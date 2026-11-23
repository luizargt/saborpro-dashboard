import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/cancellation_data.dart';
// La cuenta del POS para lo que vale un renglón (precio × cantidad + extras):
// la misma del ticket y del detalle de cortesías.
import '../../data/models/cortesias_data.dart' show valorCortesia;
import 'dashboard_provider.dart';

/// Arma el reporte "Pedidos Cancelados" (fase 4 del inventario).
///
/// Vive local a la pantalla y no en el MultiProvider de `main.dart`: nadie más
/// necesita estos datos y la consulta trae todos los movimientos del rango, así
/// que no vale la pena pagarla en cada arranque de la app.
class CancellationsProvider extends ChangeNotifier {
  final _firestore = FirestoreService();

  /// Válvula anti-OOM. Con el filtro de tipo en el servidor (ver
  /// [_fetchMovements]) solo bajan las cancelaciones, así que en la práctica
  /// esto ya no se alcanza; queda como red por si un tenant enorme mira un año
  /// entero. Si se alcanza, la consulta sale ordenada por `createdAt` ASC y lo
  /// que falta es el final del rango: la vista lo avisa en vez de mostrar un
  /// total corto como si fuera completo.
  ///
  /// No puede pasar de 10000: Firestore rechaza la consulta entera con
  /// `invalid-argument` si el límite es mayor, sin importar cuántos documentos
  /// existan de verdad. Estaba en 20000, así que este reporte fallaba siempre,
  /// para cualquier tenant y cualquier período. Se deja en 8000 para no traer
  /// al navegador el máximo teórico de un saque.
  static const int _kMovementLimit = 8000;

  CancellationsReport _report = CancellationsReport.empty;
  CancellationsReport get report => _report;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Firma del último load, para no reconsultar cuando la pantalla se
  /// reconstruye sin que hayan cambiado ni el rango ni la sucursal.
  String? _lastKey;

  static String _keyOf(DateRange r, String? locationId, String firmaMoneda) =>
      '${r.start.toIso8601String()}|${r.end.toIso8601String()}|${locationId ?? "*"}|$firmaMoneda';

  /// Número del último [load]. El que ya no es el último descarta su
  /// resultado: si el rango cambia dos veces seguidas, el más lento no debe
  /// pisar al más nuevo.
  int _seq = 0;

  /// Recarga solo si cambió el rango, la sucursal o la moneda del dashboard.
  Future<void> loadIfNeeded(DashboardProvider dp) {
    // Mientras el dashboard carga, sus pedidos están vacíos (los vacía al
    // empezar): leerlos ahora dejaría este reporte sin los pedidos cobrados y,
    // como la llave no cambia, nadie lo volvería a pedir. Al terminar el
    // dashboard avisa, la pantalla se reconstruye y entonces sí se carga.
    if (dp.loading) return Future.value();
    final key = _keyOf(dp.range, dp.selectedLocationId, dp.firmaMoneda);
    if (key == _lastKey && !_loading) return Future.value();
    return load(dp);
  }

  /// Toma el rango y la sucursal del [DashboardProvider] para que este reporte
  /// obedezca exactamente a la misma barra de filtros que el resto de la app.
  Future<void> load(DashboardProvider dp) async {
    final tenantId = dp.tenantId ?? AuthService().tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final seq = ++_seq;
    // Lo que se lee del dashboard se fija ANTES de esperar nada: si el rango
    // cambia durante una espera, este reporte no puede armarse con datos de uno
    // y el filtro de otro (la carga nueva lo reemplaza).
    final range = dp.range;
    final sinPedidos = dp.sinOrdenesEnMemoria;
    _lastKey = _keyOf(range, dp.selectedLocationId, dp.firmaMoneda);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchMovements(tenantId, range),
        _fetchIngredientCosts(tenantId, dp.factorDe),
        dp.fetchCancelledOrders(),
      ]);
      // Otra carga tomó el relevo mientras esperaba: la que manda es esa.
      if (seq != _seq) return;

      final raw = results[0] as _RawMovements;
      final costs = results[1] as Map<String, IngredientCost>;
      final cancelledOrders = results[2] as List<Map<String, dynamic>>;

      // Sucursales permitidas del usuario (vacío = todas), igual que el resto
      // de providers. `fetchCancelledOrders` ya viene filtrada por el
      // dashboard; los movimientos hay que filtrarlos aquí.
      final allowed = AuthService().assignedLocationIds.toSet();
      final selected = dp.selectedLocationId;
      bool passesLocation(String locationId) {
        // Sin sucursal en el movimiento no se descarta: el ingrediente puede
        // haberse creado sin `location_id` (pasa en tenants de una sola
        // sucursal) y esconderlo dejaría el reporte COMPLETAMENTE vacío, que se
        // lee igual que "nadie canceló nada" — la conclusión equivocada más
        // peligrosa justo en el reporte que existe para ver lo que se pierde.
        // Solo se oculta cuando se está mirando una sucursal en concreto.
        if (locationId.isEmpty) return selected == null || selected.isEmpty;
        // Una sucursal cuya moneda no tiene tipo de cambio no se suma con las
        // demás (la pantalla lo avisa).
        if (dp.factorDe(locationId, null) == null) return false;
        if (selected != null && selected.isNotEmpty) {
          return locationId == selected;
        }
        if (allowed.isNotEmpty) return allowed.contains(locationId);
        return true;
      }

      final movements =
          raw.movements.where((m) => passesLocation(m.locationId)).toList();

      // En la vista de año esto viene vacío: el dashboard no baja las órdenes,
      // le pide los totales a Firestore. Se pierden los metadatos de pedido
      // (mesa, motivo, quién lo hizo) de las órdenes que se cobraron igual tras
      // anular un ítem, y con ellos lo que valían: los montos a precio de venta
      // (lo perdido y lo anulado) quedan cortos. Las cantidades y los costos
      // salen de inventoryMovements y no cambian. [withoutPaidOrders] hace que
      // la vista lo avise.
      final paidOrders = dp.currentOrders;

      // Quién anuló: el POS del panel (cancelar una comanda) guarda solo el id
      // de quien anula, no su nombre. Los ids que no traen nombre en ningún
      // registro se resuelven desde `users`, para poder decir quién fue.
      final faltan = _idsSinNombre(movements, [...paidOrders, ...cancelledOrders]);
      final userNames = faltan.isEmpty
          ? const <String, String>{}
          : await dp.fetchUserNamesById(faltan.toList());
      if (seq != _seq) return;

      // Renglones anulados fuera de este período (la víspera; un bar pasada la
      // medianoche) en pedidos que salen aquí. Sin receta no tienen movimiento
      // en ningún lado y esta es la única vez que pueden salir; con receta ya
      // salieron en su período por sus movimientos. Se averigua preguntando por
      // los movimientos de esos pedidos; si no se puede, no se listan (null).
      final candidatos = _pedidosAnuladosFuera(range, [...paidOrders, ...cancelledOrders]);
      final movidosFuera =
          candidatos.isEmpty ? const <String>{} : await _fetchMovidosDe(tenantId, candidatos);
      if (seq != _seq) return;

      _report = _build(
        movements: movements,
        costs: costs,
        cancelledOrders: cancelledOrders,
        paidOrders: paidOrders,
        withoutPaidOrders: sinPedidos,
        truncated: raw.truncated,
        userNames: userNames,
        range: range,
        movidosFuera: movidosFuera,
      );
    } catch (e) {
      if (seq != _seq) return;
      _error = 'No se pudo cargar el reporte de cancelaciones: $e';
      _report = CancellationsReport.empty;
    }

    _loading = false;
    notifyListeners();
  }

  /// Ids de usuario que aparecen sin nombre en algún movimiento o pedido y en
  /// ninguno con él.
  static Set<String> _idsSinNombre(
    List<CancellationMovement> movements,
    List<Map<String, dynamic>> orders,
  ) {
    final con = <String>{};
    final sin = <String>{};
    void ver(Object? rawId, Object? rawName) {
      final id = rawId is String ? rawId.trim() : '';
      // El POS escribe 'unknown' cuando no sabe quién es el usuario.
      if (id.isEmpty || id == 'unknown') return;
      final nombre = rawName is String ? rawName.trim() : '';
      (nombre.isNotEmpty ? con : sin).add(id);
    }

    for (final m in movements) {
      ver(m.userId, m.userName);
    }
    for (final o in orders) {
      ver(o['cancelled_by_user_id'], o['cancelled_by_user_name']);
      final items = o['items'];
      if (items is List) {
        for (final i in items) {
          if (i is Map) ver(i['voided_by_user_id'], i['voided_by_user_name']);
        }
      }
    }
    return sin.difference(con);
  }

  /// Ids de los pedidos con algún renglón anulado (con decisión de despensa)
  /// fuera de [range].
  static Set<String> _pedidosAnuladosFuera(
    DateRange range,
    List<Map<String, dynamic>> orders,
  ) {
    final out = <String>{};
    for (final o in orders) {
      final m = _OrderMeta.from(o);
      final lineas = m.lines;
      if (lineas == null) continue;
      if (lineas.any((l) => l.isVoid && l.decided && !l.dentroDe(range))) {
        out.addAll(m.ids);
      }
    }
    return out;
  }

  /// Ids de renglón con algún movimiento de cancelación, en cualquier fecha,
  /// entre los pedidos [orderIds]. null si no se pudo averiguar.
  Future<Set<String>?> _fetchMovidosDe(String tenantId, Set<String> orderIds) async {
    final ids = orderIds.toList();
    final out = <String>{};
    try {
      for (var i = 0; i < ids.length; i += 30) {
        final lote = ids.sublist(i, (i + 30).clamp(0, ids.length));
        final snap = await _firestore.instance
            .collection('inventoryMovements')
            .where('tenantId', isEqualTo: tenantId)
            .where('orderId', whereIn: lote)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (!_kTipos.contains(data['type'])) continue;
          final itemId = _pick(data, ['orderItemId', 'itemId', 'order_item_id']);
          if (itemId.isNotEmpty) out.add(itemId);
        }
      }
      return out;
    } catch (e) {
      debugPrint('CancellationsProvider: no se pudieron leer los movimientos de '
          'pedidos fuera del período: $e');
      return null;
    }
  }

  // ── FIRESTORE ──────────────────────────────────────────────────────────────

  /// Los dos tipos que este reporte lee. Son los `type.name` exactos que
  /// escribe el POS.
  static const List<String> _kTipos = [
    'devolucionCancelacion',
    'mermaCancelacion',
  ];

  /// Trae los movimientos del rango.
  ///
  /// FILTRA POR TIPO EN EL SERVIDOR. La primera versión traía TODOS los
  /// movimientos del tenant en el rango y descartaba en Dart, apoyándose en el
  /// índice que ya usa Despensa (tenantId ASC, createdAt ASC). Con 17 sucursales
  /// sellando una ronda por envío y un movimiento por ingrediente eso son del
  /// orden de decenas de miles de documentos por DÍA: el tope de 20.000 se
  /// agotaba enseguida y —al salir la consulta ordenada por `createdAt` ASC— lo
  /// que se cortaba era la parte MÁS RECIENTE del rango, justo lo que el dueño
  /// quiere mirar. Además eran hasta 20.000 lecturas por cada apertura de la
  /// vista.
  ///
  /// Con el filtro en el servidor solo bajan las cancelaciones, que son unas
  /// pocas por día, y el tope deja de ser alcanzable en la práctica.
  ///
  /// EL ÍNDICE. Esto necesita el compuesto (tenantId ASC, type ASC, createdAt
  /// ASC), declarado en `firestore.indexes.json` del POS. Mientras no esté
  /// desplegado, Firestore rechaza la consulta entera con `failed-precondition`,
  /// así que hay un camino de respaldo con la consulta vieja: es preferible un
  /// reporte caro a un reporte que no abre. El respaldo se cae solo el día que
  /// el índice existe.
  ///
  /// `createdAt` se guarda como String ISO en hora LOCAL (sin designador de
  /// zona), así que el rango lexicográfico coincide con el cronológico.
  Future<_RawMovements> _fetchMovements(String tenantId, DateRange range) async {
    final startIso = range.start.toIso8601String();
    final endIso = range.end.toIso8601String();

    Query<Map<String, dynamic>> base() => _firestore.instance
        .collection('inventoryMovements')
        .where('tenantId', isEqualTo: tenantId)
        .where('createdAt', isGreaterThanOrEqualTo: startIso)
        .where('createdAt', isLessThanOrEqualTo: endIso);

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await base()
          .where('type', whereIn: _kTipos)
          .limit(_kMovementLimit)
          .get();
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      // Índice todavía no desplegado: se cae a traer el rango completo y
      // descartar en Dart, que es lo que hacía antes. Caro, pero abre.
      debugPrint(
        'CancellationsProvider: falta el índice (tenantId, type, createdAt); '
        'usando la consulta completa. Desplegá firestore.indexes.json.',
      );
      snap = await base().limit(_kMovementLimit).get();
    }

    final out = <CancellationMovement>[];
    for (final doc in snap.docs) {
      final m = _parseMovement(doc.id, doc.data(), range);
      if (m != null) out.add(m);
    }
    return _RawMovements(out, snap.docs.length >= _kMovementLimit);
  }

  /// Nombre, unidad y precio de compra de cada ingrediente del tenant.
  ///
  /// Ojo con el nombre del campo: `ingredients` filtra por `tenant_id` en
  /// snake_case mientras que `inventoryMovements` usa `tenantId`. No es un
  /// error de tipeo, son dos convenciones que conviven en la base.
  /// El precio de cada ingrediente en la moneda de la vista: el de hoy, con
  /// el tipo de cambio de hoy (el reporte ya valoriza la merma a precio
  /// actual).
  Future<Map<String, IngredientCost>> _fetchIngredientCosts(
    String tenantId,
    double? Function(String? locationId, DateTime? fecha) factorDe,
  ) async {
    final snap = await _firestore.instance
        .collection('ingredients')
        .where('tenant_id', isEqualTo: tenantId)
        .get();

    final out = <String, IngredientCost>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final price = data['lastPurchasePrice'];
      final factor = factorDe(data['location_id'] as String?, null);
      out[doc.id] = IngredientCost(
        name: (data['name'] as String? ?? '').trim(),
        unit: (data['unit'] as String? ?? 'u').trim().isEmpty
            ? 'u'
            : (data['unit'] as String).trim(),
        price: price is num && factor != null ? price.toDouble() * factor : null,
      );
    }
    return out;
  }

  // ── PARSEO ─────────────────────────────────────────────────────────────────

  /// Primer valor no vacío entre varias llaves posibles.
  ///
  /// Los movimientos de cancelación los escribe el POS (otro grupo). El
  /// contrato acordado es `orderItemId` / `orderItemName` / `orderTableName`,
  /// pero se aceptan los alias obvios para que el reporte no salga en blanco si
  /// el nombre final difiere: es preferible una fila con el dato que una fila
  /// vacía sin explicación.
  static String _pick(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  /// Primer entero utilizable entre varias llaves. Tolera que el campo llegue
  /// como String: no todo lo que escribe el POS pasa por un modelo tipado.
  static int _num(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  CancellationMovement? _parseMovement(
      String docId, Map<String, dynamic> data, DateRange range) {
    final type = data['type'] as String? ?? '';
    final CancellationKind kind;
    if (type == 'devolucionCancelacion') {
      kind = CancellationKind.devolucion;
    } else if (type == 'mermaCancelacion') {
      kind = CancellationKind.merma;
    } else {
      return null;
    }

    // Revalidar la fecha en Dart: el filtro del servidor es sobre un String y
    // un movimiento viejo con formato distinto podría colarse en el rango.
    final createdAt = _toDateTime(data['createdAt']);
    if (createdAt == null) return null;
    if (createdAt.isBefore(range.start) || createdAt.isAfter(range.end)) {
      return null;
    }

    final qty = (data['quantity'] as num? ?? 0).toDouble().abs();
    final ingredientId = data['ingredientId'] as String? ?? '';
    final locationId = data['locationId'] as String? ?? '';
    // Solo el ingrediente y la cantidad justifican tirar una fila: sin ellos no
    // hay nada que contar. La sucursal vacía se resuelve en el filtro de
    // arriba, que la deja pasar cuando no se está mirando una en concreto.
    if (ingredientId.isEmpty || qty <= 0) return null;

    final orderId = _pick(data, ['orderId', 'order_id']);
    final reason = _pick(data, ['reason', 'comment']);
    // Sin itemId no se pueden separar dos líneas del mismo pedido; se cae al id
    // del documento para que al menos no se fundan entre sí.
    final itemId = _pick(data, ['orderItemId', 'itemId', 'order_item_id']);

    return CancellationMovement(
      id: docId,
      kind: kind,
      ingredientId: ingredientId,
      locationId: locationId,
      orderId: orderId,
      orderItemId: itemId.isNotEmpty ? itemId : docId,
      itemName: _pick(data, [
        'orderItemName',
        'itemName',
        'productName',
        'product_name',
      ]),
      itemQty: _num(data, ['orderItemQty', 'itemQty', 'qty']),
      quantity: qty,
      reason: reason.isEmpty ? null : reason,
      userId: data['createdByUserId'] as String? ?? '',
      userName: _pick(data, ['createdByUserName', 'userName']),
      createdAt: createdAt,
    );
  }

  // ── AGREGACIÓN ─────────────────────────────────────────────────────────────

  /// Puertas para los tests: la agregación es pura (no toca Firestore ni el
  /// AuthService), pero vive en métodos privados. Sin esto, la única forma de
  /// verificar que el par devolución+merma se lee como UNA fila sería levantar
  /// Firebase.
  @visibleForTesting
  CancellationMovement? parseMovementForTest(
    String docId,
    Map<String, dynamic> data,
    DateRange range,
  ) =>
      _parseMovement(docId, data, range);

  @visibleForTesting
  CancellationsReport buildForTest({
    required List<CancellationMovement> movements,
    Map<String, IngredientCost> costs = const {},
    List<Map<String, dynamic>> cancelledOrders = const [],
    List<Map<String, dynamic>> paidOrders = const [],
    bool truncated = false,
    bool withoutPaidOrders = false,
    Map<String, String> userNames = const {},
    DateRange? range,
    Set<String>? movidosFuera,
  }) =>
      _build(
        movements: movements,
        costs: costs,
        cancelledOrders: cancelledOrders,
        paidOrders: paidOrders,
        truncated: truncated,
        withoutPaidOrders: withoutPaidOrders,
        userNames: userNames,
        range: range,
        movidosFuera: movidosFuera,
      );

  CancellationsReport _build({
    required List<CancellationMovement> movements,
    required Map<String, IngredientCost> costs,
    required List<Map<String, dynamic>> cancelledOrders,
    required List<Map<String, dynamic>> paidOrders,
    required bool truncated,
    bool withoutPaidOrders = false,

    /// id de usuario → nombre, de `users`, para quienes ningún registro trae su
    /// nombre (el POS del panel guarda solo el id de quien anula).
    Map<String, String> userNames = const {},

    /// El período del reporte: sirve para no listar como "de hoy" un renglón
    /// anulado en otro período (ver [_OrderMeta.listedLines]). null = sin filtro.
    DateRange? range,

    /// Ids de renglón que tienen movimiento de cancelación en otro período.
    /// null = no se pudo averiguar: los anulados fuera del período no se listan.
    Set<String>? movidosFuera,
  }) {
    // Metadatos de pedido (mesa, quién canceló, motivo). Salen de los pedidos
    // que el dashboard ya trajo: los cancelados y los cobrados. Los cobrados
    // importan porque anular UN item no cancela el pedido — ese pedido se cobra
    // igual y solo aparece en la lista de cobrados.
    final meta = <String, _OrderMeta>{};
    void indexar(Map<String, dynamic> o, {required bool cancelada}) {
      final m = _OrderMeta.from(o, cancelada: cancelada);
      for (final id in m.ids) {
        meta[id] = m;
      }
    }

    // Primero los cobrados y después los cancelados: si un pedido viene en las
    // dos listas, manda la versión cancelada.
    for (final o in paidOrders) {
      indexar(o, cancelada: false);
    }
    for (final o in cancelledOrders) {
      indexar(o, cancelada: true);
    }

    // orderId → itemId → cantidades por ingrediente
    final byOrder = <String, Map<String, _ItemAcc>>{};
    for (final mv in movements) {
      final items = byOrder.putIfAbsent(mv.orderId, () => {});
      final acc = items.putIfAbsent(mv.orderItemId, () => _ItemAcc());
      acc.absorb(mv);
    }

    final unpriced = <String>{};
    final events = <CancellationEvent>[];
    final people = <String, _PersonAcc>{};

    /// Ids de renglón que dejaron algún movimiento de cancelación.
    final conMovimiento = movements.map((m) => m.orderItemId).toSet();

    // El nombre de cada usuario por su id, de donde aparezca. El mismo usuario
    // sale con nombre en unos registros y sin él en otros (el POS del panel
    // guarda solo el id), y la persona del corte tiene que llevar el mismo
    // rótulo sea cual sea el registro que se lea primero. Lo que resolvió
    // `users` entra primero: solo se pidió para ids sin nombre en ninguno.
    final nombres = <String, String>{...userNames};
    void aprender(String id, String nombre) {
      if (id.isNotEmpty && id != 'unknown' && nombre.isNotEmpty) {
        nombres.putIfAbsent(id, () => nombre);
      }
    }

    for (final mv in movements) {
      aprender(mv.userId, mv.userName);
    }
    for (final m in meta.values) {
      aprender(m.cancelledByUserId, m.cancelledByName);
      for (final l in m.lines ?? const <_OrderLine>[]) {
        aprender(l.voidedById, l.voidedByName);
      }
    }

    /// Cómo se llama quien firmó: por su id si se conoce su nombre, si no el
    /// que trae el registro, y si no "Sin identificar".
    String nombreDe(String id, String name) {
      final conocido = id.isNotEmpty ? nombres[id] : null;
      if (conocido != null) return conocido;
      return name.isNotEmpty && name != 'Sin identificar' ? name : 'Sin identificar';
    }

    /// La persona del corte, por su id (o su nombre si no hay id). A quien no se
    /// puede nombrar —sin nombre en ningún registro ni en `users`, o sin id, o
    /// el id "unknown" del POS— se le junta en UNA tarjeta "Sin identificar":
    /// varias con la misma cara no dejarían aislar a ninguna.
    _PersonAcc persona(String rawId, String name) {
      final id = rawId == 'unknown' ? '' : rawId;
      final label = nombreDe(id, name);
      final key = label == 'Sin identificar' ? '—' : (id.isNotEmpty ? id : label);
      return people.putIfAbsent(key, () => _PersonAcc(userId: id, userName: label));
    }

    /// Renglones sin receta ya listados en alguna fila: con ids de pedido
    /// distintos para los movimientos de un mismo pedido salen varias filas, y
    /// el renglón sin movimiento no debe repetirse en cada una.
    final extrasListados = <String>{};

    byOrder.forEach((orderId, items) {
      final om = meta[orderId];
      var eventReturned = PartialValue.empty;
      var eventWasted = PartialValue.empty;
      final built = <CancellationItem>[];
      DateTime? at;
      String userName = '';
      String userNameId = '';
      String userId = '';
      String? reason;

      // Los renglones del pedido por id, para ponerle precio de venta a cada
      // item que tuvo movimiento.
      final porId = <String, _OrderLine>{
        for (final l in om?.lines ?? const <_OrderLine>[])
          if (l.id.isNotEmpty) l.id: l,
      };

      // Quiénes firmaron los renglones (cada renglón cuenta para su firmante en
      // el corte por persona): el evento los guarda para poder filtrar por
      // cualquiera de ellos.
      final authors = <String>{};

      items.forEach((itemId, acc) {
        // Lo que regresó de verdad a la despensa es la devolución MENOS la
        // merma: cuando el producto no regresa se escriben los dos movimientos
        // (el neto sobre el stock es cero) y sumar solo la devolución diría que
        // volvió algo que nadie volvió a ver.
        final netReturn = <String, double>{};
        for (final e in acc.returnedQty.entries) {
          final net = e.value - (acc.wastedQty[e.key] ?? 0);
          if (net > 0.000001) netReturn[e.key] = net;
        }

        final returned = _value(netReturn, costs, unpriced);
        final wasted = _value(acc.wastedQty, costs, unpriced);
        final declaredLost = acc.wastedQty.isNotEmpty;

        final linea = porId[itemId];
        built.add(CancellationItem(
          itemId: itemId,
          name: acc.name.isNotEmpty ? acc.name : (linea?.name ?? 'Producto'),
          qty: acc.qty > 0 ? acc.qty : (linea?.qty ?? 0),
          returned: returned,
          wasted: wasted,
          declaredLost: declaredLost,
          value: linea?.value,
        ));

        eventReturned = eventReturned + returned;
        eventWasted = eventWasted + wasted;

        if (at == null || acc.at!.isAfter(at!)) at = acc.at;
        if (userName.isEmpty && acc.userName.isNotEmpty) {
          userName = acc.userName;
          userNameId = acc.userId;
        }
        if (userId.isEmpty) userId = acc.userId;
        reason ??= acc.reason;

        // Corte por persona: se atribuye a quien FIRMÓ el movimiento, que es
        // quien apretó "no regresa", no necesariamente quien abrió la mesa. El
        // evento guarda el mismo rótulo que lleva la persona: así filtrar por
        // ella encuentra todas las filas que su tarjeta cuenta.
        final p = persona(acc.userId, acc.userName);
        authors.add(p.userName);
        p.itemsCancelled++;
        if (declaredLost) p.itemsLost++;
        p.wasted = p.wasted + wasted;
        p.returned = p.returned + returned;
        p.orders.add(orderId);
      });

      // El pedido completo: además de lo que tuvo movimiento, los renglones
      // anulados sin receta. Solo si TODOS los items con movimiento se
      // encuentran en el pedido por id: los movimientos viejos (sin
      // orderItemId) caen al id del documento y ahí el cruce no es confiable,
      // así que no se agrega nada. Un renglón con movimiento en CUALQUIER fila
      // no se agrega (ya está en la suya): con ids de pedido distintos para
      // los movimientos de un mismo pedido, se contaría dos veces.
      final lines = om?.lines;
      if (om != null &&
          lines != null &&
          items.keys.every(porId.containsKey)) {
        for (final l in om.listedLines(
            rango: range, conMovimiento: conMovimiento, movidosFuera: movidosFuera)) {
          if (items.containsKey(l.id)) continue;
          if (l.id.isNotEmpty && !extrasListados.add(l.id)) continue;
          built.add(l.asItem());
          // Pasó por la pregunta de despensa sin dejar movimiento (sin
          // receta): su respuesta cuenta para quien la dio. Quien anuló el
          // renglón; si no consta, quien canceló el pedido o, en último caso,
          // quien firmó el resto de esta cancelación.
          if (l.decided) {
            final p = l.voidedById.isNotEmpty || l.voidedByName.isNotEmpty
                ? persona(l.voidedById, l.voidedByName)
                : (om.wasCancelled
                    ? persona(om.cancelledByUserId, om.cancelledByName)
                    // No consta quién lo anuló: a nadie en concreto. Acreditarlo
                    // a quien firmó otro renglón sería acusar a quien no fue.
                    : persona('', ''));
            p.itemsCancelled++;
            if (l.lost) p.itemsLost++;
            p.orders.add(orderId);
            authors.add(p.userName);
          }
        }
      }

      built.sort((a, b) => a.name.compareTo(b.name));

      events.add(CancellationEvent(
        orderId: orderId,
        orderLabel: om?.orderLabel ?? _shortId(orderId),
        tableLabel: om?.tableLabel ?? '—',
        at: at ?? DateTime.now(),
        // Con el mismo rótulo que la tarjeta de esa persona: un usuario con dos
        // nombres en dos registros no puede salir con uno aquí y otro allá.
        userName: userName.isNotEmpty
            ? nombreDe(userNameId, userName)
            : (userId.isNotEmpty && nombres[userId] != null
                ? nombres[userId]!
                : (om != null
                    ? nombreDe(om.cancelledByUserId, om.cancelledByName)
                    : 'Sin identificar')),
        reason: reason ?? om?.reason,
        impact: InventoryImpact.conMovimiento,
        items: built,
        returned: eventReturned,
        wasted: eventWasted,
        value: _valueOf(built),
        authors: authors.toList(),
      ));
    });

    // Cancelaciones que NO movieron inventario. No son ruido: dicen cuántos
    // pedidos se toman y se deshacen, que es otro síntoma que el dueño pidió
    // ver. Se separan en dos porque no significan lo mismo.
    var beforeKitchen = 0;
    var withoutRecipe = 0;
    for (final o in cancelledOrders) {
      final om = _OrderMeta.from(o, cancelada: true);
      if (om.ids.any(byOrder.containsKey)) continue;

      final impact = om.reachedKitchen
          ? InventoryImpact.sinReceta
          : InventoryImpact.sinCocina;
      if (impact == InventoryImpact.sinCocina) {
        beforeKitchen++;
      } else {
        withoutRecipe++;
      }

      final p = persona(om.cancelledByUserId, om.cancelledByName);
      p.orders.add(om.ids.first);
      p.withoutInventory.add(om.ids.first);

      // Los renglones a los que se les preguntó qué regresaba cuentan para
      // quien contestó: quien anuló el renglón si consta, y si no, quien
      // canceló el pedido.
      final authors = <String>{p.userName};
      final listados = om.listedLines(
          rango: range, conMovimiento: conMovimiento, movidosFuera: movidosFuera);
      for (final l in listados) {
        if (!l.decided) continue;
        final q = l.voidedById.isNotEmpty || l.voidedByName.isNotEmpty
            ? persona(l.voidedById, l.voidedByName)
            : p;
        q.itemsCancelled++;
        if (l.lost) q.itemsLost++;
        if (!identical(q, p)) {
          q.orders.add(om.ids.first);
          q.withoutInventory.add(om.ids.first);
          authors.add(q.userName);
        }
      }

      events.add(CancellationEvent(
        orderId: om.ids.first,
        orderLabel: om.orderLabel,
        tableLabel: om.tableLabel,
        at: om.at ?? DateTime.now(),
        userName: p.userName,
        reason: om.reason,
        impact: impact,
        // El pedido entero, con cantidad y precio de cada renglón.
        items: [for (final l in listados) l.asItem()],
        returned: PartialValue.empty,
        wasted: PartialValue.empty,
        value: om.cancelledValue(),
        authors: authors.toList(),
      ));
    }

    // Pedidos COBRADOS con productos anulados que pasaron por la pregunta de
    // despensa y no dejaron movimiento (sin receta). Hasta ahora solo contaban
    // en los montos —en lo perdido, a precio de venta—, sin fila ni persona, y
    // el dueño no podía saber quién los declaró. El renglón guarda quién lo
    // anuló, por qué y cuándo (`voided_by_user_*`, `void_reason`, `voided_at`).
    //
    // Un pedido que ya es una fila (porque dejó movimientos o se canceló
    // entero) no se repite: sus renglones sin receta ya salen ahí.
    //
    // Solo renglones anulados de verdad (`is_void`) y de este período: uno que
    // se anuló en otro (la víspera y se cobró hoy, un bar pasada la medianoche)
    // ya salió en el suyo —por sus movimientos, si tiene receta—, y salir otra
    // vez como "sin receta" sería falso. Un renglón con decisión de despensa y
    // sin `is_void` es de un pedido cancelado y reactivado: se vendió, no tiene
    // quién ni cuándo, y no se lista (sí cuenta en los montos, como lo perdido).
    final yaListados = <String>{
      ...byOrder.keys,
      for (final o in cancelledOrders) ..._OrderMeta.from(o, cancelada: true).ids,
    };
    for (final o in paidOrders) {
      final om = _OrderMeta.from(o);
      if (om.ids.isEmpty || om.ids.any(yaListados.contains)) continue;
      final lineas = om.listedLines(
          rango: range, conMovimiento: conMovimiento, movidosFuera: movidosFuera);
      if (lineas.isEmpty) continue;
      yaListados.addAll(om.ids);

      final orderId = om.ids.first;
      final autores = <String>{};
      DateTime? cuando;
      String? motivo;
      for (final l in lineas) {
        final p = persona(l.voidedById, l.voidedByName);
        if (l.decided) {
          p.itemsCancelled++;
          if (l.lost) p.itemsLost++;
        }
        p.orders.add(orderId);
        p.withoutInventory.add(orderId);
        autores.add(p.userName);
        motivo ??= l.voidReason;
        final t = l.voidedAt;
        if (t != null && (cuando == null || t.isAfter(cuando))) cuando = t;
      }
      withoutRecipe++;

      final items = [for (final l in lineas) l.asItem()];
      events.add(CancellationEvent(
        orderId: orderId,
        orderLabel: om.orderLabel,
        tableLabel: om.tableLabel,
        at: cuando ?? om.at ?? DateTime.now(),
        userName: autores.first,
        reason: motivo,
        impact: InventoryImpact.sinReceta,
        items: items,
        returned: PartialValue.empty,
        wasted: PartialValue.empty,
        value: _valueOf(items),
        authors: autores.toList(),
      ));
    }

    events.sort((a, b) => b.at.compareTo(a.at));

    var totalWasted = PartialValue.empty;
    var totalReturned = PartialValue.empty;
    var itemsCancelled = 0;
    var itemsLost = 0;
    for (final e in events) {
      totalWasted = totalWasted + e.wasted;
      totalReturned = totalReturned + e.returned;
      // Cuentan los renglones a los que se les preguntó qué regresaba: los que
      // dejaron movimiento y los sin receta que pasaron por la misma pregunta
      // (su respuesta vale igual: es la declaración que se revisa). Un renglón
      // que nunca se mandó a cocina no se preguntó y no cuenta.
      final contados = e.items.where((i) => i.counts);
      itemsCancelled += contados.length;
      itemsLost += contados.where((i) => i.declaredLost).length;
    }

    final cut = people.values
        .map((p) => PersonCut(
              userId: p.userId,
              userName: p.userName,
              events: p.orders.length,
              itemsCancelled: p.itemsCancelled,
              itemsLost: p.itemsLost,
              wasted: p.wasted,
              returned: p.returned,
              eventsWithoutInventory: p.withoutInventory.length,
            ))
        .toList()
      // Ordenar por porcentaje de merma y no por monto: el que hay que ver
      // primero es el que MÁS marca "no regresa", tenga o no precio lo que
      // marcó.
      ..sort((a, b) {
        final byRate = b.lostRate.compareTo(a.lostRate);
        if (byRate != 0) return byRate;
        return b.itemsLost.compareTo(a.itemsLost);
      });

    // Lo perdido a PRECIO DE VENTA, sacado de los propios items del pedido.
    // No necesita receta ni precios de compra: la decisión y el precio ya
    // viajan ahí. Es lo único que ve los productos sin receta, que no generan
    // ningún movimiento y hasta ahora quedaban fuera del reporte entero.
    final saleWaste = _saleValueWaste(
      [...paidOrders, ...cancelledOrders],
      conMovimiento: conMovimiento,
    );

    // Todo lo anulado a precio de venta, de los mismos pedidos que saleWaste.
    final anulado = _cancelledValue(cancelledOrders, paidOrders, conMovimiento);

    return CancellationsReport(
      events: events,
      people: cut,
      totalWasted: totalWasted,
      totalReturned: totalReturned,
      itemsCancelled: itemsCancelled,
      itemsLost: itemsLost,
      cancelledBeforeKitchen: beforeKitchen,
      cancelledWithoutRecipe: withoutRecipe,
      unpricedIngredients: unpriced.length,
      saleWaste: saleWaste,
      truncated: truncated,
      cancelledValue: anulado.amount,
      cancelledValueOrders: anulado.orders,
      withoutPaidOrders: withoutPaidOrders,
    );
  }

  /// Lo que valía lo anulado de un pedido: la suma de sus renglones a precio
  /// de venta. Es null en cuanto un renglón no tiene valor conocido (o no hay
  /// renglones que mirar): una suma a medias se leería como el total.
  static double? _valueOf(List<CancellationItem> items) {
    if (items.isEmpty) return null;
    var total = 0.0;
    for (final i in items) {
      final v = i.value;
      if (v == null) return null;
      total += v;
    }
    return total;
  }

  /// Todo lo anulado a precio de venta en el período, y en cuántos pedidos.
  ///
  /// Sale de los pedidos y no de la lista de cancelaciones, con el mismo
  /// criterio que [_saleValueWaste]. Si se canceló el pedido entero cuenta
  /// todo; si el pedido se cobró, los renglones anulados y también los que
  /// tienen una decisión de inventario o un movimiento de cancelación (un
  /// pedido reactivado y cobrado conserva esas marcas, y lo perdido ya los
  /// cuenta: si aquí no estuvieran, lo perdido podría pasar de lo anulado).
  /// Un pedido que viene en las dos listas cuenta una vez, y como cancelado.
  static ({double amount, int orders}) _cancelledValue(
    List<Map<String, dynamic>> cancelledOrders,
    List<Map<String, dynamic>> paidOrders,
    Set<String> conMovimiento,
  ) {
    final vistos = <String>{};
    var amount = 0.0;
    var orders = 0;

    void sumar(Map<String, dynamic> o, {required bool cancelada}) {
      final m = _OrderMeta.from(o, cancelada: cancelada);
      // Sin id no se puede saber si ya se contó.
      if (m.ids.isEmpty || m.ids.any(vistos.contains)) return;
      vistos.addAll(m.ids);
      if (m.cancelledLines(conMovimiento).isEmpty) return;
      orders++;
      amount += m.cancelledValue(conMovimiento) ?? 0;
    }

    for (final o in cancelledOrders) {
      sumar(o, cancelada: true);
    }
    for (final o in paidOrders) {
      sumar(o, cancelada: false);
    }
    return (amount: amount, orders: orders);
  }

  /// Suma lo declarado desperdicio, valorado al precio de venta del producto.
  ///
  /// Lee `inventory_returned_qty` del item: null significa que nunca se
  /// preguntó (pedido viejo, o item que no selló ronda), y eso NO es lo mismo
  /// que cero —cero es "se decidió que no regresa nada"—, así que los null se
  /// saltan en vez de contarse como desperdicio total.
  ///
  /// Un mismo pedido puede venir en las dos listas (cobrados y cancelados),
  /// así que se deduplica por id o nada se contaría dos veces.
  static SaleValueWaste _saleValueWaste(
    List<Map<String, dynamic>> orders, {
    required Set<String> conMovimiento,
  }) {
    final vistos = <String>{};
    double total = 0;
    int items = 0;
    double sinReceta = 0;
    int sinRecetaItems = 0;

    for (final o in orders) {
      final id = (o['_docId'] as String? ?? o['id'] as String? ?? '');
      if (id.isEmpty || !vistos.add(id)) continue;

      final raw = o['items'];
      if (raw is! List) continue;
      for (final i in raw.whereType<Map>()) {
        final regresa = (i['inventory_returned_qty'] as num?)?.toInt();
        if (regresa == null) continue; // no se preguntó: no se inventa nada
        final qty = (i['qty'] as num?)?.toInt() ?? 0;
        final tirado = qty - regresa;
        if (tirado <= 0) continue;

        final precio = (i['unit_price'] as num?)?.toDouble() ?? 0;
        final monto = tirado * precio;
        total += monto;
        items++;

        // Sin movimiento de inventario = sin receta: es la plata que hoy no se
        // ve por ningún otro lado.
        final itemId = i['id'] as String? ?? '';
        if (!conMovimiento.contains(itemId)) {
          sinReceta += monto;
          sinRecetaItems++;
        }
      }
    }

    return SaleValueWaste(
      amount: total,
      items: items,
      withoutRecipeAmount: sinReceta,
      withoutRecipeItems: sinRecetaItems,
    );
  }

  /// Convierte cantidades por ingrediente en dinero, dejando fuera —y
  /// contabilizado aparte— lo que no tiene precio de compra.
  static PartialValue _value(
    Map<String, double> qtyByIngredient,
    Map<String, IngredientCost> costs,
    Set<String> unpricedOut,
  ) {
    if (qtyByIngredient.isEmpty) return PartialValue.empty;

    double amount = 0;
    final byUnit = <String, double>{};
    final ids = <String>{};

    for (final e in qtyByIngredient.entries) {
      final cost = costs[e.key];
      if (cost != null && cost.hasPrice) {
        amount += e.value * cost.price!;
      } else {
        final unit = cost?.unit ?? 'u';
        byUnit[unit] = (byUnit[unit] ?? 0) + e.value;
        ids.add(e.key);
        unpricedOut.add(e.key);
      }
    }

    return PartialValue(
      amount: amount,
      unpricedByUnit: byUnit,
      unpricedIngredientIds: ids,
    );
  }

  static String _shortId(String id) =>
      id.length <= 6 ? id : '…${id.substring(id.length - 5)}';
}

class _RawMovements {
  final List<CancellationMovement> movements;
  final bool truncated;
  const _RawMovements(this.movements, this.truncated);
}

/// Acumulador de un item anulado.
class _ItemAcc {
  final returnedQty = <String, double>{};
  final wastedQty = <String, double>{};
  String name = '';
  int qty = 0;
  String userName = '';
  String userId = '';
  String? reason;
  DateTime? at;

  void absorb(CancellationMovement m) {
    final target =
        m.kind == CancellationKind.devolucion ? returnedQty : wastedQty;
    target[m.ingredientId] = (target[m.ingredientId] ?? 0) + m.quantity;

    if (name.isEmpty) name = m.itemName;
    if (qty == 0) qty = m.itemQty;
    if (userName.isEmpty) userName = m.userName;
    if (userId.isEmpty) userId = m.userId;
    reason ??= m.reason;
    if (at == null || m.createdAt.isAfter(at!)) at = m.createdAt;
  }
}

class _PersonAcc {
  final String userId;
  final String userName;
  final orders = <String>{};

  /// De esos pedidos, los que no tocaron inventario.
  final withoutInventory = <String>{};
  int itemsCancelled = 0;
  int itemsLost = 0;
  PartialValue wasted = PartialValue.empty;
  PartialValue returned = PartialValue.empty;

  _PersonAcc({required this.userId, required this.userName});
}

/// Lo que se puede saber de un pedido a partir del documento de `orders`.
class _OrderMeta {
  /// Un mismo pedido se referencia por el id del documento y por su campo
  /// `id`, y no siempre coinciden. Se indexa por los dos para que el movimiento
  /// encuentre su pedido sin importar cuál guardó.
  final List<String> ids;
  final String orderLabel;
  final String tableLabel;
  final String cancelledBy;

  /// El nombre tal cual lo trae el pedido: vacío si el POS no lo guardó
  /// (distinto de [cancelledBy], que en ese caso dice "Sin identificar").
  final String cancelledByName;
  final String cancelledByUserId;
  final String? reason;
  final DateTime? at;
  final bool reachedKitchen;

  /// Los renglones del pedido; null si el documento no trae lista de items.
  final List<_OrderLine>? lines;

  /// Se canceló el pedido entero (y no solo se anuló algún producto).
  final bool wasCancelled;

  const _OrderMeta({
    required this.ids,
    required this.orderLabel,
    required this.tableLabel,
    required this.cancelledBy,
    required this.cancelledByName,
    required this.cancelledByUserId,
    required this.reason,
    required this.at,
    required this.reachedKitchen,
    required this.lines,
    required this.wasCancelled,
  });

  /// Los renglones que cuentan en los MONTOS como anulados: todos si se canceló
  /// el pedido entero; si el pedido se cobró, los que pasaron por la pregunta
  /// de despensa (`inventory_returned_qty`, que es lo que deja una anulación)
  /// o tienen un movimiento de cancelación ([conMovimiento], ids de renglón).
  /// Un pedido reactivado y cobrado sigue teniendo esas marcas aunque ya no
  /// esté anulado, y lo perdido (`saleWaste`) las cuenta: por eso aquí también.
  ///
  /// Un renglón anulado al que no se le preguntó nada no entra: no se había
  /// mandado a cocina, o se canceló la comanda desde Cuentas ("Cancelar orden
  /// de cocina"), que no pregunta qué regresa. No deja decisión ni movimiento,
  /// y sin ellos el reporte no tiene de dónde sacarlo.
  List<_OrderLine> cancelledLines([Set<String> conMovimiento = const {}]) {
    final todos = lines;
    if (todos == null) return const [];
    return [
      for (final l in todos)
        if (wasCancelled || l.decided || conMovimiento.contains(l.id)) l,
    ];
  }

  /// Los renglones que se LISTAN en la fila de un pedido, además de los que
  /// dejaron movimiento: son los que de verdad se anularon.
  ///
  /// - Pedido cancelado entero: todos, salvo los que se anularon antes, por
  ///   separado, en otro período (ver abajo).
  /// - Pedido cobrado: los anulados (`is_void`) con decisión de despensa y de
  ///   este período. Un renglón con decisión pero sin `is_void` es de un pedido
  ///   cancelado y reactivado: se vendió y no tiene quién ni cuándo.
  ///
  /// "De este período" = su anulación (`voided_at`) cae en [rango] (sin fecha,
  /// entra), o cae fuera pero no dejó NINGÚN movimiento en ninguna fecha
  /// ([movidosFuera]): sin receta no sale en el reporte de otro período, y
  /// esta es su única oportunidad. Uno anulado en otro período que sí dejó
  /// movimiento ya salió en el suyo: listarlo aquí como "sin receta" sería
  /// falso. Si [movidosFuera] es null (no se pudo averiguar), no se listan.
  ///
  /// Un renglón con movimiento en CUALQUIER fila ([conMovimiento]) no se lista
  /// aquí: ya está en la suya.
  List<_OrderLine> listedLines({
    DateRange? rango,
    Set<String> conMovimiento = const {},
    Set<String>? movidosFuera,
  }) {
    final todos = lines;
    if (todos == null) return const [];
    bool deEstePeriodo(_OrderLine l) =>
        l.dentroDe(rango) || (movidosFuera != null && !movidosFuera.contains(l.id));
    return [
      for (final l in todos)
        if (!conMovimiento.contains(l.id) &&
            (wasCancelled
                ? (!l.isVoid || deEstePeriodo(l))
                : (l.isVoid && l.decided && deEstePeriodo(l))))
          l,
    ];
  }

  /// Lo que valía lo anulado a precio de venta; null si el pedido no trae
  /// renglones que leer.
  double? cancelledValue([Set<String> conMovimiento = const {}]) {
    if (lines == null) return null;
    var total = 0.0;
    for (final l in cancelledLines(conMovimiento)) {
      total += l.value;
    }
    return total;
  }

  /// [cancelada] = el pedido viene de la lista de cancelados: se canceló
  /// entero aunque el documento no lo diga.
  factory _OrderMeta.from(Map<String, dynamic> o, {bool cancelada = false}) {
    final ids = <String>{
      (o['_docId'] as String? ?? ''),
      (o['id'] as String? ?? ''),
    }..removeWhere((e) => e.isEmpty);

    final rawItems = o['items'];
    final items = rawItems is List ? rawItems.whereType<Map>().toList() : const [];

    // Un pedido "llegó a cocina" si algún item alcanzó a llevar comanda. Es más
    // confiable que el estado al cancelar: el estado puede quedar viejo, el
    // número de comanda solo lo escribe el envío.
    final reached = items.any((i) => i['kitchen_order_no'] != null) ||
        ((o['kitchen_items_affected'] as num? ?? 0) > 0);

    final number = o['order_number'] ?? o['order_prefix'];
    final table = (o['table_name'] as String? ?? '').trim();

    return _OrderMeta(
      ids: ids.toList(),
      orderLabel: number != null && '$number'.trim().isNotEmpty
          ? '#$number'
          : (ids.isEmpty ? '—' : CancellationsProvider._shortId(ids.first)),
      tableLabel: table.isNotEmpty ? table : 'Sin mesa',
      cancelledBy: (o['cancelled_by_user_name'] as String? ?? '').trim().isEmpty
          ? 'Sin identificar'
          : (o['cancelled_by_user_name'] as String).trim(),
      cancelledByName: (o['cancelled_by_user_name'] as String? ?? '').trim(),
      cancelledByUserId: o['cancelled_by_user_id'] as String? ?? '',
      reason: (o['cancellation_reason'] as String? ?? '').trim().isEmpty
          ? null
          : (o['cancellation_reason'] as String).trim(),
      at: _toDateTime(o['cancelled_at'] ?? o['updated_at'] ?? o['created_at']),
      reachedKitchen: reached,
      lines: rawItems is List ? [for (final i in items) _OrderLine.from(i)] : null,
      wasCancelled: cancelada || o['status'] == 'CANCELLED',
    );
  }
}

/// Un renglón del pedido, tal como se guardó.
class _OrderLine {
  /// El `id` del renglón: es el mismo que lleva el movimiento de inventario
  /// (`orderItemId`), y por eso sirve para cruzarlos.
  final String id;
  final String name;
  final int qty;

  /// Precio × cantidad, más los extras con precio (ver [valorCortesia]).
  final double value;
  final bool isVoid;

  /// Pasó por la pregunta de inventario al anularse (`inventory_returned_qty`
  /// no es null). Null = nunca se preguntó (pedido viejo): no es lo mismo que
  /// cero.
  final bool decided;

  /// Se declaró desperdicio de este renglón: `inventory_returned_qty` es
  /// menor que la cantidad. Es lo único que dice algo de un renglón sin receta.
  final bool lost;

  /// Quién anuló el renglón (`voided_by_user_id` / `voided_by_user_name`), el
  /// motivo y cuándo. Vacíos si el renglón nunca se anuló por separado (se
  /// canceló el pedido entero) o el POS no supo quién era.
  final String voidedById;
  final String voidedByName;
  final String? voidReason;
  final DateTime? voidedAt;

  const _OrderLine({
    required this.id,
    required this.name,
    required this.qty,
    required this.value,
    required this.isVoid,
    required this.decided,
    required this.lost,
    this.voidedById = '',
    this.voidedByName = '',
    this.voidReason,
    this.voidedAt,
  });

  factory _OrderLine.from(Map i) {
    final rawId = i['id'];
    final rawName = i['name'];
    final rawQty = i['qty'];
    final rawReturned = i['inventory_returned_qty'];
    final qty = rawQty is num ? rawQty.toInt() : 1;

    String texto(Object? v) => v is String ? v.trim() : '';
    // El POS escribe 'unknown' cuando no sabe quién es el usuario.
    final porId = texto(i['voided_by_user_id']);
    final motivo = texto(i['void_reason']);

    return _OrderLine(
      id: rawId is String ? rawId.trim() : '',
      name: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : 'Producto',
      qty: qty,
      value: valorCortesia(i),
      isVoid: i['is_void'] == true,
      decided: rawReturned is num,
      lost: rawReturned is num && qty - rawReturned.toInt() > 0,
      voidedById: porId == 'unknown' ? '' : porId,
      voidedByName: texto(i['voided_by_user_name']),
      voidReason: motivo.isEmpty ? null : motivo,
      voidedAt: _toDateTime(i['voided_at']),
    );
  }

  /// ¿Se anuló dentro de [rango]? Sin fecha o sin rango no se puede saber y se
  /// toma como que sí.
  bool dentroDe(DateRange? rango) {
    final t = voidedAt;
    if (rango == null || t == null) return true;
    // El fin del período es 23:59:59 sin milisegundos: se le dan los 999 que
    // faltan para no dejar fuera el último segundo del día.
    return !t.isBefore(rango.start) &&
        !t.isAfter(rango.end.add(const Duration(milliseconds: 999)));
  }

  /// El renglón como item de una cancelación que no movió inventario. Si pasó
  /// por la pregunta de despensa ([decided]), su respuesta cuenta.
  CancellationItem asItem() => CancellationItem(
        itemId: id.isNotEmpty ? id : name,
        name: name,
        qty: qty,
        returned: PartialValue.empty,
        wasted: PartialValue.empty,
        declaredLost: lost,
        value: value,
        movedInventory: false,
        asked: decided,
      );
}

DateTime? _toDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is DateTime) return v.toLocal();
  return null;
}
