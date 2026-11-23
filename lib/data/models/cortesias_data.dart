/// Lo que se regaló en el período: cada pedido con sus platillos de cortesía
/// o donación, y el resumen por platillo.
///
/// Cuenta EXACTAMENTE lo mismo que la tarjeta "Cortesías / Donaciones" del
/// Inicio: sobre los mismos pedidos y con las mismas dos funciones de aquí
/// abajo ([cuentaComoCortesia] y [valorCortesia]), que la tarjeta también
/// usa. Esta pantalla se abre tocando esa tarjeta: si las dos cuentas se
/// separan, el total de aquí deja de cuadrar con el de allá y se lee como un
/// descuadre.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Si un renglón del ticket cuenta como regalado: marcado como cortesía (o
/// donación) y no anulado.
bool cuentaComoCortesia(Object? item) =>
    item is Map && item['is_courtesy'] == true && item['is_void'] != true;

/// Lo que vale un renglón regalado: el precio del platillo por la cantidad,
/// más sus extras con precio (cada extra por su cantidad y por la del
/// platillo). Es la cuenta del POS (`OrderItem.originalPrice`): la que sale
/// tachada en el carrito y en el ticket ("Valor: Q146.00 -> Q0.00").
///
/// La usan la tarjeta del Inicio (y con ella los resúmenes de cada mes) y
/// este detalle: una sola cuenta, para que no puedan separarse. Hasta
/// 2026-11 la tarjeta dejaba fuera los extras.
double valorCortesia(Map<dynamic, dynamic> item) {
  final qty = _num(item['qty'], 1);
  // En el orden del POS: primero los extras sumados, después el platillo.
  var extras = 0.0;
  final mods = item['modifiers'];
  if (mods is List) {
    for (final m in mods) {
      if (m is! Map) continue;
      extras += _num(m['price'], 0) * _num(m['qty'], 1) * qty;
    }
  }
  return _num(item['unit_price'], 0) * qty + extras;
}

double _num(Object? v, double siFalta) => v is num ? v.toDouble() : siFalta;

enum TipoCortesia {
  cortesia('Cortesía'),
  donacion('Donación');

  final String etiqueta;
  const TipoCortesia(this.etiqueta);

  /// El POS escribe 'CORTESIA' o 'DONACION'. Sin tipo es cortesía, igual que
  /// en el Excel de caja.
  static TipoCortesia de(Object? v) =>
      v == 'DONACION' ? TipoCortesia.donacion : TipoCortesia.cortesia;
}

/// Un platillo regalado dentro de un pedido.
class CortesiaRenglon {
  final String nombre;
  final double cantidad;

  /// Con sus extras (ver [valorCortesia]).
  final double monto;
  final TipoCortesia tipo;
  final String? motivo;

  /// Quién la marcó en el POS (`courtesy_by_user_id`).
  final String? usuarioId;

  /// Los extras que llevaba ("Tocino", "Queso ×2"), para que se entienda el
  /// monto: 2 hamburguesas de Q55 regaladas valen Q146 si llevaban extras.
  final List<String> extras;

  const CortesiaRenglon({
    required this.nombre,
    required this.cantidad,
    required this.monto,
    required this.tipo,
    this.motivo,
    this.usuarioId,
    this.extras = const [],
  });
}

/// Un pedido con al menos un platillo regalado. Solo trae esos renglones: lo
/// que se cobró no es parte de este reporte.
class CortesiaPedido {
  final String id;

  /// "#A123", o vacío si el pedido no tiene número.
  final String numero;

  /// Cuándo se cobró. Es la fecha con que el Inicio decide si el pedido cae
  /// en el período.
  final DateTime? fecha;

  /// "Mesa 4", "Para llevar", "A domicilio"...
  final String lugar;
  final String? cliente;
  final String? locationId;
  final List<CortesiaRenglon> renglones;

  const CortesiaPedido({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.lugar,
    required this.cliente,
    required this.locationId,
    required this.renglones,
  });

  double get monto => renglones.fold(0.0, (s, r) => s + r.monto);

  Set<TipoCortesia> get tipos => {for (final r in renglones) r.tipo};

  List<String> get motivos => {
        for (final r in renglones)
          if (r.motivo != null) r.motivo!,
      }.toList();

  List<String> get usuarios => {
        for (final r in renglones)
          if (r.usuarioId != null) r.usuarioId!,
      }.toList();
}

/// Un platillo sumado en todo el período.
class CortesiaPlatillo {
  final String nombre;
  final double cantidad;
  final double monto;

  /// En cuántos pedidos distintos se regaló.
  final int pedidos;

  const CortesiaPlatillo({
    required this.nombre,
    required this.cantidad,
    required this.monto,
    required this.pedidos,
  });
}

class CortesiasReport {
  /// Del más reciente al más viejo.
  final List<CortesiaPedido> pedidos;

  /// De más a menos monto regalado.
  final List<CortesiaPlatillo> platillos;

  final double total;
  final double totalCortesia;
  final double totalDonacion;

  /// Platillos regalados (suma de cantidades).
  final double cantidad;

  /// Cuántos renglones hay de cada tipo. Dice si HUBO, que no es lo mismo
  /// que el monto: un platillo de precio Q0 regalado suma cero y sí pasó.
  final int renglonesCortesia;
  final int renglonesDonacion;

  const CortesiasReport({
    required this.pedidos,
    required this.platillos,
    required this.total,
    required this.totalCortesia,
    required this.totalDonacion,
    required this.cantidad,
    this.renglonesCortesia = 0,
    this.renglonesDonacion = 0,
  });

  static const empty = CortesiasReport(
    pedidos: [],
    platillos: [],
    total: 0,
    totalCortesia: 0,
    totalDonacion: 0,
    cantidad: 0,
  );

  bool get vacio => pedidos.isEmpty;

  /// Los ids de quienes marcaron cortesías, para ponerles nombre.
  Set<String> get usuarios => {
        for (final p in pedidos) ...p.usuarios,
      };

  /// Arma el reporte con los pedidos que el Inicio ya tiene en memoria (ya
  /// filtrados por sucursal, sin cancelados y en la moneda de la vista).
  factory CortesiasReport.desde(List<Map<String, dynamic>> ordenes) {
    final pedidos = <CortesiaPedido>[];
    final porPlatillo = <String, _AccPlatillo>{};
    var total = 0.0, totalCortesia = 0.0, totalDonacion = 0.0, cantidad = 0.0;
    var renglonesCortesia = 0, renglonesDonacion = 0;

    for (final o in ordenes) {
      final items = o['items'];
      if (items is! List) continue;

      final renglones = <CortesiaRenglon>[];
      for (final item in items) {
        // La misma condición y la misma cuenta que la tarjeta del Inicio.
        if (!cuentaComoCortesia(item)) continue;
        final renglon = item as Map;
        final qty = _num(renglon['qty'], 1);
        final monto = valorCortesia(renglon);
        // Se suma renglón por renglón y en el mismo orden que la tarjeta: con
        // otro orden, el redondeo de los decimales podría mover un centavo.
        total += monto;
        cantidad += qty;

        final tipo = TipoCortesia.de(renglon['courtesy_type']);
        if (tipo == TipoCortesia.donacion) {
          totalDonacion += monto;
          renglonesDonacion++;
        } else {
          totalCortesia += monto;
          renglonesCortesia++;
        }

        final nombre = _texto(renglon['name']) ?? 'Sin nombre';
        renglones.add(CortesiaRenglon(
          nombre: nombre,
          cantidad: qty,
          monto: monto,
          tipo: tipo,
          motivo: _texto(renglon['courtesy_reason']),
          usuarioId: _usuario(renglon['courtesy_by_user_id']),
          extras: _extras(renglon['modifiers']),
        ));
      }
      if (renglones.isEmpty) continue;

      final id = _texto(o['_docId']) ?? _texto(o['id']) ?? '';
      final enEstePedido = <String>{};
      for (final r in renglones) {
        final acc = porPlatillo.putIfAbsent(r.nombre, () => _AccPlatillo());
        acc.cantidad += r.cantidad;
        acc.monto += r.monto;
        // El mismo platillo dos veces en un pedido es UN pedido.
        if (enEstePedido.add(r.nombre)) acc.pedidos++;
      }

      pedidos.add(CortesiaPedido(
        id: id,
        numero: _numeroPedido(o),
        fecha: _fecha(o['paid_at']),
        lugar: _lugar(o),
        cliente: _texto(o['customer_name']),
        locationId: _texto(o['location_id']),
        renglones: renglones,
      ));
    }

    pedidos.sort((a, b) {
      final fa = a.fecha, fb = b.fecha;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fb.compareTo(fa);
    });

    final platillos = [
      for (final e in porPlatillo.entries)
        CortesiaPlatillo(
          nombre: e.key,
          cantidad: e.value.cantidad,
          monto: e.value.monto,
          pedidos: e.value.pedidos,
        ),
    ]..sort((a, b) {
        final m = b.monto.compareTo(a.monto);
        if (m != 0) return m;
        final c = b.cantidad.compareTo(a.cantidad);
        if (c != 0) return c;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

    return CortesiasReport(
      pedidos: pedidos,
      platillos: platillos,
      total: total,
      totalCortesia: totalCortesia,
      totalDonacion: totalDonacion,
      cantidad: cantidad,
      renglonesCortesia: renglonesCortesia,
      renglonesDonacion: renglonesDonacion,
    );
  }

  /// "Tocino", "Queso ×2". Los que no tienen nombre no se pueden mostrar,
  /// pero su precio igual entra en el monto.
  static List<String> _extras(Object? mods) {
    if (mods is! List) return const [];
    return [
      for (final m in mods)
        if (m is Map && _texto(m['name']) != null)
          _num(m['qty'], 1) > 1
              ? '${_texto(m['name'])} ×${_num(m['qty'], 1).toStringAsFixed(0)}'
              : _texto(m['name'])!,
    ];
  }

  static String? _texto(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// El cobro como cortesía escribe 'unknown' cuando no sabe quién es.
  static String? _usuario(Object? v) {
    final t = _texto(v);
    return t == null || t == 'unknown' ? null : t;
  }

  static String _numeroPedido(Map<String, dynamic> o) {
    final no = o['order_no'];
    if (no == null || '$no'.trim().isEmpty) return '';
    return '#${_texto(o['order_prefix']) ?? ''}$no';
  }

  static String _lugar(Map<String, dynamic> o) {
    final mesa = _texto(o['table_name']);
    switch (o['type']) {
      case 'takeout':
      case 'pickup':
        return 'Para llevar';
      case 'delivery':
        return 'A domicilio';
      case 'quick_sale':
        return 'Entrega inmediata';
      case 'room_service':
        return mesa ?? 'Hospedaje';
      default:
        return mesa ?? 'Consumir aquí';
    }
  }

  static DateTime? _fecha(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

class _AccPlatillo {
  double cantidad = 0;
  double monto = 0;
  int pedidos = 0;
}

// Lo que Cortesías comparte con otros detalles del Inicio (Descuentos): una sola
// forma de decir "Mesa 4", "#A123" y de leer una fecha, para que no se separen.

/// "#A123", o vacío si el pedido no tiene número.
String numeroDelPedido(Map<String, dynamic> o) => CortesiasReport._numeroPedido(o);

/// "Mesa 4", "Para llevar", "A domicilio"...
String lugarDelPedido(Map<String, dynamic> o) => CortesiasReport._lugar(o);

/// La fecha de un pedido (Timestamp, DateTime o texto ISO), en hora local.
DateTime? fechaDelPedido(Object? v) => CortesiasReport._fecha(v);

/// Un texto sin espacios de más, o null si está vacío.
String? textoDelPedido(Object? v) => CortesiasReport._texto(v);
