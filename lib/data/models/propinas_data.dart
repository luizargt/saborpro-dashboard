/// Las propinas de un período, desglosadas como las pide el diseño
/// (propinas.html): quién las recibe, a qué hora, por tipo de servicio, por
/// tamaño de cuenta, por zona y por método de pago.
///
/// Sale de los MISMOS pedidos con que el Inicio sumó sus tarjetas
/// (`DashboardProvider.currentOrders`: cobrados, de la sucursal que se mira y ya
/// en la moneda de la vista), y la venta de cada pedido se cuenta como el Inicio
/// cuenta su "Venta bruta" (lo cobrado, sin propina ni cobro de envío): así la
/// "propina promedio" de aquí es sobre la misma venta que se ve arriba.
///
/// Las propinas que entraron a la caja como ingreso ("Meter dinero" → Propina)
/// NO son de ningún pedido: no tienen mesero, hora, tipo ni método. No entran en
/// estos desgloses; la pantalla las suma aparte al total.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Un grupo de pedidos (un mesero, un tipo de servicio…) con lo que dejó de
/// propina.
class GrupoPropina {
  final String clave;

  /// Lo que se muestra ("Ana Cosme", "Mesa", "Terraza").
  final String nombre;
  final int pedidos;

  /// La venta de esos pedidos, sin propina ni envío.
  final double ventas;
  final double propinas;

  /// Cuántos de esos pedidos no dejaron propina.
  final int sinPropina;

  const GrupoPropina({
    required this.clave,
    required this.nombre,
    required this.pedidos,
    required this.ventas,
    required this.propinas,
    required this.sinPropina,
  });

  /// La propina sobre la venta, en porcentaje.
  double get tasa => ventas > 0 ? propinas / ventas * 100 : 0.0;
}

/// Lo que se dejó de propina en una hora del día (0 a 23).
class HoraPropina {
  final int hora;
  final double propinas;
  const HoraPropina(this.hora, this.propinas);
}

class PropinasReporte {
  /// Pedidos del período y lo que sumaron.
  final int pedidos;
  final double ventas;

  /// Propinas de los pedidos (sin las metidas a la caja).
  final double propinas;

  /// Pedidos que no dejaron propina.
  final int sinPropina;

  /// Propinas de los pedidos del período anterior. Nulo = no se sabe (no hay
  /// pedidos de entonces): no hay con qué comparar.
  final double? propinasAnterior;

  /// De más a menos propina.
  final List<GrupoPropina> meseros;

  /// Horas seguidas, de la primera a la última con pedidos.
  final List<HoraPropina> horas;
  final List<GrupoPropina> porTipo;
  final List<GrupoPropina> porTamano;

  /// Nulo = no se sabe a qué zona pertenece cada mesa (no se pudieron leer).
  final List<GrupoPropina>? porZona;
  final List<GrupoPropina> porMetodo;

  const PropinasReporte({
    this.pedidos = 0,
    this.ventas = 0,
    this.propinas = 0,
    this.sinPropina = 0,
    this.propinasAnterior,
    this.meseros = const [],
    this.horas = const [],
    this.porTipo = const [],
    this.porTamano = const [],
    this.porZona,
    this.porMetodo = const [],
  });

  static const vacio = PropinasReporte();

  bool get hayPedidos => pedidos > 0;

  /// La propina sobre la venta de todo el período, en porcentaje.
  double get tasa => ventas > 0 ? propinas / ventas * 100 : 0.0;

  double get porPedido => pedidos > 0 ? propinas / pedidos : 0.0;

  /// De cada cien pedidos, cuántos no dejaron propina.
  double get pctSinPropina => pedidos > 0 ? sinPropina / pedidos * 100 : 0.0;

  /// Cuánto subió (o bajó) la propina contra el período anterior, en
  /// porcentaje. Nulo si no hay con qué comparar o el anterior fue cero.
  double? get cambioPct {
    final a = propinasAnterior;
    if (a == null || a <= 0) return null;
    return (propinas - a) / a * 100;
  }

  /// La hora en que más se dejó (la primera si hay empate), o nulo si nadie dejó.
  HoraPropina? get horaPico {
    HoraPropina? pico;
    for (final h in horas) {
      if (h.propinas > 0 && (pico == null || h.propinas > pico.propinas)) pico = h;
    }
    return pico;
  }

  /// Desde cuántos pedidos se le puede señalar a un mesero que recibe poca
  /// propina: con uno o dos, un cliente que no dejó nada es mala suerte, no una
  /// tendencia.
  static const minPedidosParaAlerta = 5;

  /// Cuántos puntos de porcentaje por debajo del promedio para avisar.
  static const puntosParaAlerta = 1.5;

  /// El mesero que recibe claramente menos propina que el promedio (el de la
  /// tasa más baja), o nulo si no hay ninguno.
  GrupoPropina? get meseroConPocaPropina {
    if (tasa <= 0) return null;
    GrupoPropina? peor;
    for (final m in meseros) {
      if (m.pedidos < minPedidosParaAlerta) continue;
      if (m.tasa >= tasa - puntosParaAlerta) continue;
      if (peor == null || m.tasa < peor.tasa) peor = m;
    }
    return peor;
  }

  /// Los menores de esto son "cuenta chica"; los mayores de [limiteCuentaGrande],
  /// "cuenta grande". Los de la pantalla de diseño, en la moneda de la vista.
  static const limiteCuentaChica = 100.0;
  static const limiteCuentaGrande = 300.0;

  static const _sinRegistrar = 'Sin registrar';

  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;

  static DateTime? _fecha(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  /// La venta de un pedido como la cuenta el Inicio en su "Venta bruta": lo
  /// cobrado (`payment_amount`, con fallback a `total_amount`) sin la propina ni
  /// el cobro de envío.
  static double ventaDe(Map<String, dynamic> o) {
    final pagado = o['payment_amount'] is num ? _num(o['payment_amount']) : _num(o['total_amount']);
    return pagado - _num(o['tip_amount']) - _num(o['delivery_fee']);
  }

  static String _texto(Object? v) => v is String ? v.trim() : '';

  /// Quién creó el pedido (el mesero): el id, o el nombre si no hay id.
  static String _claveMesero(Map<String, dynamic> o) {
    final id = _texto(o['created_by_user_id']);
    if (id.isNotEmpty) return id;
    final n = _texto(o['created_by_user_name']);
    return n.isNotEmpty ? 'n:$n' : '';
  }

  /// Los ids de quienes crearon pedidos sin dejar su nombre en el pedido, para
  /// que la pantalla los pregunte a `users`.
  static Set<String> idsSinNombre(List<Map<String, dynamic>> pedidos) => {
        for (final o in pedidos)
          if (_texto(o['created_by_user_id']).isNotEmpty && _texto(o['created_by_user_name']).isEmpty)
            _texto(o['created_by_user_id']),
      };

  static String etiquetaTipo(String tipo) => switch (tipo) {
        'dine_in' => 'Mesa',
        'takeout' || 'pickup' => 'Para llevar',
        'delivery' => 'Domicilio',
        'quick_sale' => 'Venta rápida',
        'room_service' => 'Habitación',
        '' => 'Otros',
        _ => tipo[0].toUpperCase() + tipo.substring(1),
      };

  static String etiquetaMetodo(String? metodo) => switch (metodo) {
        'card' => 'Tarjeta',
        'cash' => 'Efectivo',
        _ => 'Otros',
      };

  /// [pedidos]: los del período. [anteriores]: los del período anterior (solo
  /// para saber cuánto se dejó entonces). [nombresUsuario]: id → nombre, para los
  /// pedidos que no traen el nombre de quien los creó. [zonaDeMesa]: id de mesa →
  /// zona; nulo si no se pudo leer. [signo]: el de la moneda de la vista, para
  /// rotular los tamaños de cuenta.
  factory PropinasReporte.desde(
    List<Map<String, dynamic>> pedidos, {
    List<Map<String, dynamic>> anteriores = const [],
    Map<String, String> nombresUsuario = const {},
    Map<String, String>? zonaDeMesa,
    String signo = 'Q',
  }) {
    final meseros = <String, _Acc>{};
    final tipos = <String, _Acc>{};
    final metodos = <String, _Acc>{};
    final zonas = <String, _Acc>{};
    final tamanos = <String, _Acc>{};
    final porHora = <int, double>{};
    int? minHora, maxHora;

    var ventas = 0.0, propinas = 0.0;
    var sin = 0;

    final chica = '$signo${limiteCuentaChica.toStringAsFixed(0)}';
    final grande = '$signo${limiteCuentaGrande.toStringAsFixed(0)}';
    final etiquetasTamano = {
      'chica': 'Menos de $chica',
      'media': '$chica a $grande',
      'grande': 'Más de $grande',
    };

    for (final o in pedidos) {
      final tip = _num(o['tip_amount']);
      final venta = ventaDe(o);
      final sinTip = tip <= 0;
      ventas += venta;
      propinas += tip > 0 ? tip : 0;
      if (sinTip) sin++;

      // Mesero.
      final clave = _claveMesero(o);
      final nombreEnPedido = _texto(o['created_by_user_name']);
      final m = meseros.putIfAbsent(clave, () => _Acc(''));
      if (m.nombre.isEmpty && nombreEnPedido.isNotEmpty) m.nombre = nombreEnPedido;
      m.suma(venta, tip, sinTip);

      // Hora.
      final fecha = _fecha(o['paid_at']);
      if (fecha != null) {
        final t = tip > 0 ? tip : 0.0;
        porHora.update(fecha.hour, (v) => v + t, ifAbsent: () => t);
        if (minHora == null || fecha.hour < minHora) minHora = fecha.hour;
        if (maxHora == null || fecha.hour > maxHora) maxHora = fecha.hour;
      }

      // Tipo de servicio.
      final tipo = etiquetaTipo(_texto(o['type']));
      tipos.putIfAbsent(tipo, () => _Acc(tipo)).suma(venta, tip, sinTip);

      // Tamaño de la cuenta.
      final grupoTamano = venta < limiteCuentaChica ? 'chica' : (venta <= limiteCuentaGrande ? 'media' : 'grande');
      tamanos.putIfAbsent(grupoTamano, () => _Acc(etiquetasTamano[grupoTamano]!)).suma(venta, tip, sinTip);

      // Método de pago.
      final metodo = etiquetaMetodo(_texto(o['payment_method']).isEmpty ? null : _texto(o['payment_method']));
      metodos.putIfAbsent(metodo, () => _Acc(metodo)).suma(venta, tip, sinTip);

      // Zona: solo pedidos en mesa, y solo si se sabe la zona de las mesas.
      if (zonaDeMesa != null && _texto(o['type']) == 'dine_in') {
        final zona = zonaDeMesa[_texto(o['table_id'])] ?? 'Sin zona';
        zonas.putIfAbsent(zona, () => _Acc(zona)).suma(venta, tip, sinTip);
      }
    }

    GrupoPropina grupo(String clave, _Acc a, {String? nombre}) => GrupoPropina(
          clave: clave,
          nombre: nombre ?? a.nombre,
          pedidos: a.pedidos,
          ventas: a.ventas,
          propinas: a.propinas,
          sinPropina: a.sin,
        );

    List<GrupoPropina> enOrden(Map<String, _Acc> mapa, List<String> orden) => [
          for (final k in orden)
            if (mapa.containsKey(k)) grupo(k, mapa[k]!),
          // Lo que no estaba en la lista conocida, al final y por nombre.
          for (final k in (mapa.keys.where((k) => !orden.contains(k)).toList()..sort())) grupo(k, mapa[k]!),
        ];

    final listaMeseros = [
      for (final e in meseros.entries)
        grupo(
          e.key,
          e.value,
          nombre: e.value.nombre.isNotEmpty
              ? e.value.nombre
              : (nombresUsuario[e.key]?.trim().isNotEmpty == true ? nombresUsuario[e.key]!.trim() : _sinRegistrar),
        ),
    ]..sort((a, b) => b.propinas.compareTo(a.propinas));

    final horas = <HoraPropina>[
      if (minHora != null && maxHora != null)
        for (var h = minHora; h <= maxHora; h++) HoraPropina(h, porHora[h] ?? 0),
    ];

    // Lo que se dejó en el período anterior, solo si hubo pedidos entonces.
    double? anterior;
    if (anteriores.isNotEmpty) {
      anterior = 0;
      for (final o in anteriores) {
        final t = _num(o['tip_amount']);
        if (t > 0) anterior = anterior! + t;
      }
    }

    return PropinasReporte(
      pedidos: pedidos.length,
      ventas: ventas,
      propinas: propinas,
      sinPropina: sin,
      propinasAnterior: anterior,
      meseros: listaMeseros,
      horas: horas,
      porTipo: enOrden(tipos, const ['Mesa', 'Para llevar', 'Domicilio', 'Venta rápida', 'Habitación']),
      porTamano: [
        for (final k in const ['chica', 'media', 'grande'])
          if (tamanos.containsKey(k)) grupo(k, tamanos[k]!),
      ],
      porZona: zonaDeMesa == null
          ? null
          : (zonas.entries.map((e) => grupo(e.key, e.value)).toList()
            ..sort((a, b) => b.propinas.compareTo(a.propinas))),
      porMetodo: enOrden(metodos, const ['Tarjeta', 'Efectivo', 'Otros']),
    );
  }
}

class _Acc {
  String nombre;
  int pedidos = 0;
  double ventas = 0;
  double propinas = 0;
  int sin = 0;

  _Acc(this.nombre);

  void suma(double venta, double tip, bool sinTip) {
    pedidos++;
    ventas += venta;
    if (tip > 0) propinas += tip;
    if (sinTip) sin++;
  }
}
