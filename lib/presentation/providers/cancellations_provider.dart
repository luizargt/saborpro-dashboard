import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/utils/date_range.dart';
import '../../data/models/cancellation_data.dart';
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

  static String _keyOf(DateRange r, String? locationId) =>
      '${r.start.toIso8601String()}|${r.end.toIso8601String()}|${locationId ?? "*"}';

  /// Recarga solo si cambió el rango o la sucursal del dashboard.
  Future<void> loadIfNeeded(DashboardProvider dp) {
    final key = _keyOf(dp.range, dp.selectedLocationId);
    if (key == _lastKey && !_loading) return Future.value();
    return load(dp);
  }

  /// Toma el rango y la sucursal del [DashboardProvider] para que este reporte
  /// obedezca exactamente a la misma barra de filtros que el resto de la app.
  Future<void> load(DashboardProvider dp) async {
    final tenantId = dp.tenantId ?? AuthService().tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    _lastKey = _keyOf(dp.range, dp.selectedLocationId);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchMovements(tenantId, dp.range),
        _fetchIngredientCosts(tenantId),
        dp.fetchCancelledOrders(),
      ]);

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
        if (selected != null && selected.isNotEmpty) {
          return locationId == selected;
        }
        if (allowed.isNotEmpty) return allowed.contains(locationId);
        return true;
      }

      final movements =
          raw.movements.where((m) => passesLocation(m.locationId)).toList();

      _report = _build(
        movements: movements,
        costs: costs,
        cancelledOrders: cancelledOrders,
        paidOrders: dp.currentOrders,
        truncated: raw.truncated,
      );
    } catch (e) {
      _error = 'No se pudo cargar el reporte de cancelaciones: $e';
      _report = CancellationsReport.empty;
    }

    _loading = false;
    notifyListeners();
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
  Future<Map<String, IngredientCost>> _fetchIngredientCosts(String tenantId) async {
    final snap = await _firestore.instance
        .collection('ingredients')
        .where('tenant_id', isEqualTo: tenantId)
        .get();

    final out = <String, IngredientCost>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final price = data['lastPurchasePrice'];
      out[doc.id] = IngredientCost(
        name: (data['name'] as String? ?? '').trim(),
        unit: (data['unit'] as String? ?? 'u').trim().isEmpty
            ? 'u'
            : (data['unit'] as String).trim(),
        price: price is num ? price.toDouble() : null,
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
  }) =>
      _build(
        movements: movements,
        costs: costs,
        cancelledOrders: cancelledOrders,
        paidOrders: paidOrders,
        truncated: truncated,
      );

  CancellationsReport _build({
    required List<CancellationMovement> movements,
    required Map<String, IngredientCost> costs,
    required List<Map<String, dynamic>> cancelledOrders,
    required List<Map<String, dynamic>> paidOrders,
    required bool truncated,
  }) {
    // Metadatos de pedido (mesa, quién canceló, motivo). Salen de los pedidos
    // que el dashboard ya trajo: los cancelados y los cobrados. Los cobrados
    // importan porque anular UN item no cancela el pedido — ese pedido se cobra
    // igual y solo aparece en la lista de cobrados.
    final meta = <String, _OrderMeta>{};
    for (final o in [...paidOrders, ...cancelledOrders]) {
      final m = _OrderMeta.from(o);
      for (final id in m.ids) {
        meta[id] = m;
      }
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

    byOrder.forEach((orderId, items) {
      final om = meta[orderId];
      var eventReturned = PartialValue.empty;
      var eventWasted = PartialValue.empty;
      final built = <CancellationItem>[];
      DateTime? at;
      String userName = '';
      String userId = '';
      String? reason;

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

        built.add(CancellationItem(
          itemId: itemId,
          name: acc.name.isNotEmpty ? acc.name : 'Producto',
          qty: acc.qty,
          returned: returned,
          wasted: wasted,
          declaredLost: declaredLost,
        ));

        eventReturned = eventReturned + returned;
        eventWasted = eventWasted + wasted;

        if (at == null || acc.at!.isAfter(at!)) at = acc.at;
        if (userName.isEmpty) userName = acc.userName;
        if (userId.isEmpty) userId = acc.userId;
        reason ??= acc.reason;

        // Corte por persona: se atribuye a quien FIRMÓ el movimiento, que es
        // quien apretó "no regresa", no necesariamente quien abrió la mesa.
        final key = acc.userId.isNotEmpty ? acc.userId : acc.userName;
        final p = people.putIfAbsent(
          key.isEmpty ? '—' : key,
          () => _PersonAcc(
            userId: acc.userId,
            userName: acc.userName.isNotEmpty ? acc.userName : 'Sin identificar',
          ),
        );
        p.itemsCancelled++;
        if (declaredLost) p.itemsLost++;
        p.wasted = p.wasted + wasted;
        p.returned = p.returned + returned;
        p.orders.add(orderId);
      });

      built.sort((a, b) => a.name.compareTo(b.name));

      events.add(CancellationEvent(
        orderId: orderId,
        orderLabel: om?.orderLabel ?? _shortId(orderId),
        tableLabel: om?.tableLabel ?? '—',
        at: at ?? DateTime.now(),
        userName: userName.isNotEmpty
            ? userName
            : (om?.cancelledBy ?? 'Sin identificar'),
        reason: reason ?? om?.reason,
        impact: InventoryImpact.conMovimiento,
        items: built,
        returned: eventReturned,
        wasted: eventWasted,
      ));
    });

    // Cancelaciones que NO movieron inventario. No son ruido: dicen cuántos
    // pedidos se toman y se deshacen, que es otro síntoma que el dueño pidió
    // ver. Se separan en dos porque no significan lo mismo.
    var beforeKitchen = 0;
    var withoutRecipe = 0;
    for (final o in cancelledOrders) {
      final om = _OrderMeta.from(o);
      if (om.ids.any(byOrder.containsKey)) continue;

      final impact = om.reachedKitchen
          ? InventoryImpact.sinReceta
          : InventoryImpact.sinCocina;
      if (impact == InventoryImpact.sinCocina) {
        beforeKitchen++;
      } else {
        withoutRecipe++;
      }

      final p = people.putIfAbsent(
        om.cancelledByUserId.isNotEmpty ? om.cancelledByUserId : om.cancelledBy,
        () => _PersonAcc(
          userId: om.cancelledByUserId,
          userName: om.cancelledBy,
        ),
      );
      p.orders.add(om.ids.first);

      events.add(CancellationEvent(
        orderId: om.ids.first,
        orderLabel: om.orderLabel,
        tableLabel: om.tableLabel,
        at: om.at ?? DateTime.now(),
        userName: om.cancelledBy,
        reason: om.reason,
        impact: impact,
        items: om.itemNames
            .map((n) => CancellationItem(
                  itemId: n,
                  name: n,
                  qty: 0,
                  returned: PartialValue.empty,
                  wasted: PartialValue.empty,
                  declaredLost: false,
                ))
            .toList(),
        returned: PartialValue.empty,
        wasted: PartialValue.empty,
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
      if (!e.movedInventory) continue;
      itemsCancelled += e.items.length;
      itemsLost += e.items.where((i) => i.declaredLost).length;
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
      truncated: truncated,
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
  final String cancelledByUserId;
  final String? reason;
  final DateTime? at;
  final bool reachedKitchen;
  final List<String> itemNames;

  const _OrderMeta({
    required this.ids,
    required this.orderLabel,
    required this.tableLabel,
    required this.cancelledBy,
    required this.cancelledByUserId,
    required this.reason,
    required this.at,
    required this.reachedKitchen,
    required this.itemNames,
  });

  factory _OrderMeta.from(Map<String, dynamic> o) {
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
      cancelledByUserId: o['cancelled_by_user_id'] as String? ?? '',
      reason: (o['cancellation_reason'] as String? ?? '').trim().isEmpty
          ? null
          : (o['cancellation_reason'] as String).trim(),
      at: _toDateTime(o['cancelled_at'] ?? o['updated_at'] ?? o['created_at']),
      reachedKitchen: reached,
      itemNames: items
          .map((i) => (i['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList(),
    );
  }
}

DateTime? _toDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is DateTime) return v.toLocal();
  return null;
}
