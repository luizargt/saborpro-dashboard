/// El detalle de un corte (rediseño 2026-11-21, `cierres-caja.html`), sin
/// widgets: qué pedidos y gastos son de la caja, el resumen, quién vendió y los
/// filtros de la tabla.
///
/// De qué caja es cada pedido NO cambió: `ordenesDeLaCaja` es el filtro que ya
/// tenía `RegisterDetailScreen` (el sello de caja del cobro, igual que el POS en
/// `CashRegisterCalculator.perteneceACaja`, y si no, el cobrador). Si se toca,
/// tiene que tocarse también allá.
library;

import 'cash_register_summary.dart';

/// Un pedido cobrado en la caja, listo para dibujar.
class PedidoCaja {
  final DateTime? pagadoA;
  final String usuario;
  final String numero;
  final double subtotal;
  final double descuento;
  final double propina;
  final double cortesia;

  /// Lo que se pagó (incluye la propina).
  final double total;

  /// El método como viene en el pedido ('cash', 'card', 'custom_x'...).
  final String metodo;
  final String metodoNombre;

  const PedidoCaja({
    required this.pagadoA,
    required this.usuario,
    required this.numero,
    required this.subtotal,
    required this.descuento,
    required this.propina,
    required this.cortesia,
    required this.total,
    required this.metodo,
    required this.metodoNombre,
  });

  /// La llave del filtro por método: 'split' y 'mixed' van juntos como "Mixto".
  String get llaveMetodo => metodo == 'split' || metodo == 'mixed' ? 'mixto' : metodo;

  factory PedidoCaja.desde(Map<String, dynamic> o, {Map<String, String> nombresMetodos = const {}}) {
    // Todo se lee sin lanzar: un pedido con un dato mal escrito (un número como
    // texto, un campo de otro tipo) no puede dejar el detalle de la caja sin pedidos.
    final total = _monto(o['payment_amount']) ?? _monto(o['total_amount']) ?? 0.0;
    final numero = o['order_no'];
    final prefijo = _texto(o['order_prefix']) ?? '';
    // Sin método, efectivo (como siempre); si trae algo que no es texto, se muestra tal cual.
    final crudo = o['payment_method'];
    final metodo = crudo == null ? 'cash' : '$crudo';
    return PedidoCaja(
      pagadoA: _fecha(o['paid_at']),
      usuario: _texto(o['paid_by_user_name']) ?? _texto(o['waiter_name']) ?? _texto(o['created_by_user_name']) ?? '—',
      numero: numero != null ? '$prefijo$numero' : '—',
      subtotal: _monto(o['subtotal']) ?? total,
      descuento: _monto(o['discount_amount']) ?? 0,
      propina: _monto(o['tip_amount']) ?? 0,
      cortesia: _cortesia(o),
      total: total,
      metodo: metodo,
      metodoNombre: etiquetaDelMetodo(metodo, nombresMetodos),
    );
  }

  static String? _texto(dynamic v) => v is String ? v : null;
}

/// "Efectivo", "Tarjeta"... Un método propio sale con su nombre (el de la caja) en
/// vez del id crudo.
String etiquetaDelMetodo(String metodo, [Map<String, String> nombres = const {}]) {
  switch (metodo) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'pedidosya':
      return 'PedidosYa';
    case 'ubereats':
      return 'Uber Eats';
    case 'split':
    case 'mixed':
      return 'Mixto';
    default:
      return nombres[metodo] ?? metodo;
  }
}

/// Lo que vendió cada usuario en la caja.
class UsuarioCaja {
  final String nombre;
  final int pedidos;
  final double total;
  final double propinas;

  const UsuarioCaja(this.nombre, this.pedidos, this.total, this.propinas);
}

/// Los totales de una lista de pedidos.
class TotalesPedidos {
  final int pedidos;
  final double subtotal;
  final double descuentos;
  final double propinas;
  final double cortesias;
  final double total;

  const TotalesPedidos({
    required this.pedidos,
    required this.subtotal,
    required this.descuentos,
    required this.propinas,
    required this.cortesias,
    required this.total,
  });

  static TotalesPedidos de(Iterable<PedidoCaja> lista) {
    var n = 0;
    double sub = 0, desc = 0, prop = 0, cort = 0, tot = 0;
    for (final p in lista) {
      n++;
      sub += p.subtotal;
      desc += p.descuento;
      prop += p.propina;
      cort += p.cortesia;
      tot += p.total;
    }
    return TotalesPedidos(pedidos: n, subtotal: sub, descuentos: desc, propinas: prop, cortesias: cort, total: tot);
  }
}

/// Un filtro de la tabla de pedidos.
class FiltroPedidos {
  /// 'todos', 'descuento', 'cortesia' o la llave de un método ('cash', 'card'...).
  final String id;
  final String nombre;
  final int cuantos;

  const FiltroPedidos(this.id, this.nombre, this.cuantos);

  static const todos = 'todos';
  static const conDescuento = 'descuento';
  static const conCortesia = 'cortesia';
}

class DetalleCaja {
  /// Del más reciente al más antiguo.
  final List<PedidoCaja> pedidos;

  const DetalleCaja(this.pedidos);

  static const vacio = DetalleCaja([]);

  /// [ordenes]: los pedidos de la caja (ver [ordenesDeLaCaja]).
  factory DetalleCaja.desde(List<Map<String, dynamic>> ordenes, {Map<String, String> nombresMetodos = const {}}) =>
      DetalleCaja([for (final o in ordenes) PedidoCaja.desde(o, nombresMetodos: nombresMetodos)]);

  TotalesPedidos get totales => TotalesPedidos.de(pedidos);

  double get promedio => pedidos.isEmpty ? 0 : totales.total / pedidos.length;

  /// Las propinas como % del subtotal. Sin subtotal, 0.
  double get propinaPct {
    final t = totales;
    return t.subtotal > 0 ? t.propinas / t.subtotal * 100 : 0;
  }

  int get conDescuento => pedidos.where((p) => p.descuento > 0).length;
  int get conCortesia => pedidos.where((p) => p.cortesia > 0).length;

  /// Quién vendió, de más a menos. Los usuarios se agrupan por nombre.
  List<UsuarioCaja> get usuarios {
    final por = <String, List<PedidoCaja>>{};
    for (final p in pedidos) {
      por.putIfAbsent(p.usuario, () => []).add(p);
    }
    return [
      for (final e in por.entries)
        UsuarioCaja(
          e.key,
          e.value.length,
          e.value.fold(0.0, (s, p) => s + p.total),
          e.value.fold(0.0, (s, p) => s + p.propina),
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Los filtros que tienen algo: "Todos", un método por cada uno que se usó y
  /// "Con descuento" / "Con cortesía" si hubo.
  List<FiltroPedidos> get filtros {
    final metodos = <String, (String, int)>{};
    for (final p in pedidos) {
      final k = p.llaveMetodo;
      final nombre = k == 'mixto' ? 'Mixto' : p.metodoNombre;
      final actual = metodos[k];
      metodos[k] = (nombre, (actual?.$2 ?? 0) + 1);
    }
    return [
      FiltroPedidos(FiltroPedidos.todos, 'Todos', pedidos.length),
      for (final e in metodos.entries) FiltroPedidos(e.key, e.value.$1, e.value.$2),
      if (conDescuento > 0) FiltroPedidos(FiltroPedidos.conDescuento, 'Con descuento', conDescuento),
      if (conCortesia > 0) FiltroPedidos(FiltroPedidos.conCortesia, 'Con cortesía', conCortesia),
    ];
  }

  /// Los pedidos que pasan el filtro y, si se pide, son de [usuario].
  List<PedidoCaja> filtrar(String filtro, {String? usuario}) {
    bool pasa(PedidoCaja p) {
      if (usuario != null && p.usuario != usuario) return false;
      switch (filtro) {
        case FiltroPedidos.todos:
          return true;
        case FiltroPedidos.conDescuento:
          return p.descuento > 0;
        case FiltroPedidos.conCortesia:
          return p.cortesia > 0;
        default:
          return p.llaveMetodo == filtro;
      }
    }

    return pedidos.where(pasa).toList();
  }

  /// Los pedidos de la caja entre todos los que se cobraron en su ventana de
  /// tiempo. Es el filtro de siempre de `RegisterDetailScreen`:
  /// - sin canceladas, y solo de la sucursal de la caja;
  /// - si el cobro trae el sello de esta caja (vigente), cuenta aquí y en
  ///   ninguna otra; si trae el de otra, no cuenta;
  /// - sin sello vigente: por quien cobró (`paid_by_user_id`) y, en pedidos muy
  ///   viejos sin ese campo, por el nombre;
  /// - del más reciente al más antiguo.
  static List<Map<String, dynamic>> ordenesDeLaCaja(List<Map<String, dynamic>> todas, CashRegisterSummary reg) {
    final sucursal = reg.locationId ?? '';
    return todas.where((o) {
      final status = o['status'] as String? ?? '';
      if (status == 'CANCELLED') return false;

      if (sucursal.isNotEmpty && o['location_id'] != sucursal) return false;

      // Las ventas nuevas dicen en qué caja se cobraron y cuentan solo en esa:
      // con dos cajas del cajero abiertas a la vez, antes salían en las dos.
      final caja = _cajaDelCobro(o);
      if (caja != null) return caja == reg.id;

      final cobradoPor = o['paid_by_user_id'] as String? ?? '';
      // El mismo respaldo de nombre que la columna "Usuario".
      final nombre = o['paid_by_user_name'] as String? ??
          o['waiter_name'] as String? ??
          o['created_by_user_name'] as String? ??
          '';
      if (cobradoPor.isNotEmpty) {
        if (cobradoPor != reg.userId) return false;
      } else if (nombre.isNotEmpty && reg.userName.isNotEmpty) {
        if (nombre != reg.userName) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = _fecha(a['paid_at']);
        final db = _fecha(b['paid_at']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
  }
}

/// Un gasto hecho con el dinero de la caja.
class GastoCaja {
  final DateTime? fecha;
  final String concepto;
  final String categoria;
  final String? usuario;
  final double monto;

  const GastoCaja({
    required this.fecha,
    required this.concepto,
    required this.categoria,
    required this.usuario,
    required this.monto,
  });

  /// Los gastos de la caja [idCaja], del más reciente al más antiguo.
  static List<GastoCaja> deLaCaja(List<Map<String, dynamic>> items, String idCaja) {
    final propios = items.where((e) => e['source'] == 'cashRegister' && e['register_id'] == idCaja).toList()
      ..sort((a, b) => (b['date'] is String ? b['date'] as String : '').compareTo(a['date'] is String ? a['date'] as String : ''));
    String? texto(dynamic v) => v is String ? v : null;
    return [
      for (final e in propios)
        GastoCaja(
          fecha: _fecha(e['date']),
          concepto: (texto(e['description'])?.isNotEmpty ?? false)
              ? texto(e['description'])!
              : (texto(e['category_name']) ?? 'Sin categoría'),
          categoria: texto(e['category_name']) ?? 'Sin categoría',
          usuario: (texto(e['registered_by'])?.isNotEmpty ?? false) ? texto(e['registered_by']) : null,
          monto: _monto(e['amount']) ?? 0,
        ),
    ];
  }
}

// ── Utilidades ────────────────────────────────────────────────────────────────

double _cortesia(Map<String, dynamic> order) {
  final items = order['items'];
  if (items is! List) return 0;
  double total = 0;
  for (final item in items) {
    if (item is! Map) continue;
    if (item['is_courtesy'] != true) continue;
    final qty = _monto(item['qty']) ?? _monto(item['quantity']) ?? 1;
    final price = _monto(item['unit_price']) ?? _monto(item['price']) ?? 0;
    total += qty * price;
  }
  return total;
}

double? _monto(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _fecha(dynamic ts) {
  if (ts is DateTime) return ts.toLocal();
  if (ts is String) return DateTime.tryParse(ts)?.toLocal();
  try {
    return (ts as dynamic).toDate().toLocal() as DateTime;
  } catch (_) {}
  return null;
}

/// La caja en que se cobró la venta, si el sello es del cobro vigente: se selló
/// con la misma hora de pago que tiene ahora (un minuto de margen: las copias de
/// un mismo cobro difieren en segundos). Si se volvió a cobrar después con una
/// versión anterior del POS, el sello quedó viejo: vale el criterio de siempre. Y
/// si lo volvió a cobrar otro usuario (cambió quién cobró respecto de quien selló
/// esa caja, `cash_register_paid_by`, que solo vale para la caja con la que
/// viene), también, aunque la hora quede dentro del margen. Igual que
/// Order.cajaDelCobro en el POS.
String? _cajaDelCobro(Map<String, dynamic> o) {
  final caja = o['cash_register_id'];
  if (caja is! String || caja.isEmpty) return null;
  final sello = o['cash_register_paid_by'];
  final selladaPor = sello is Map && sello['cash_register_id'] == caja ? sello['user_id'] : null;
  final cobrador = o['paid_by_user_id'];
  if (selladaPor is String &&
      selladaPor.isNotEmpty &&
      cobrador is String &&
      cobrador.isNotEmpty &&
      selladaPor != cobrador) {
    return null;
  }
  final selladaA = _fecha(o['cash_register_paid_at']);
  final pagada = _fecha(o['paid_at']);
  if (selladaA == null || pagada == null) return null;
  return selladaA.difference(pagada).abs() < const Duration(minutes: 1) ? caja : null;
}
