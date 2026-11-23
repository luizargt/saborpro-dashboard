/// Los descuentos del período: cada pedido cobrado con descuento, a quién se
/// le hizo, quién lo cobró y por qué, y el resumen por platillo.
///
/// Cuenta EXACTAMENTE lo mismo que la tarjeta "Descuentos" del Inicio: un pedido
/// entra si su `discount_amount` es mayor que cero (igual que el conteo de
/// `ResumenPedidosInicio`), y el total es la suma de ese monto, la misma de
/// `PeriodMetrics.discounts`. Esta pantalla se abre tocando esa tarjeta: si las
/// dos cuentas se separan, el total de aquí deja de cuadrar con el de allá.
///
/// QUÉ GUARDA EL POS DE UN DESCUENTO, y por eso qué se puede contar: el monto
/// (`discount_amount`), el motivo (`discount_reason`, que puede faltar) y quién
/// cobró (`paid_by_user_id` / `paid_by_user_name`). NO guarda si el descuento fue
/// en porcentaje o en monto fijo, ni si fue a toda la cuenta o a un producto
/// (el cobro solo descuenta de la cuenta). Por eso el porcentaje que se muestra
/// se CALCULA: lo descontado entre lo que valía la cuenta antes del descuento.
library;

import 'cortesias_data.dart';

/// Desde qué porcentaje un descuento se marca como alto.
const double kDescuentoAlto = 30;

/// Un platillo de la cuenta, tal como se cobró.
class DescuentoRenglon {
  final String nombre;
  final double cantidad;

  /// Lo que valía la línea con sus extras, antes del descuento.
  final double monto;

  const DescuentoRenglon({required this.nombre, required this.cantidad, required this.monto});
}

/// Un pedido cobrado con descuento.
class DescuentoPedido {
  final String id;

  /// "#A123", o vacío si el pedido no tiene número.
  final String numero;

  /// Cuándo se cobró. Es la fecha con que el Inicio decide si el pedido cae en
  /// el período.
  final DateTime? fecha;

  /// "Mesa 4", "Para llevar", "A domicilio"...
  final String lugar;
  final String? cliente;
  final String? locationId;

  /// Lo que se cobró, sin lo regalado ni lo anulado.
  final List<DescuentoRenglon> renglones;

  /// Lo que valía la cuenta ANTES del descuento.
  final double cuenta;

  /// Lo que se descontó.
  final double descuento;

  /// Por qué (`discount_reason`), o null si no se escribió.
  final String? motivo;

  /// Quién cobró: su id (`paid_by_user_id`) y el nombre que el pedido guardó
  /// (`paid_by_user_name`); cualquiera de los dos puede faltar.
  final String? usuarioId;
  final String? usuarioNombre;

  const DescuentoPedido({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.lugar,
    required this.cliente,
    required this.locationId,
    required this.renglones,
    required this.cuenta,
    required this.descuento,
    required this.motivo,
    required this.usuarioId,
    required this.usuarioNombre,
  });

  bool get sinMotivo => motivo == null;

  /// Si se sabe sobre qué cuenta se descontó (con la cuenta en cero no hay
  /// porcentaje que decir).
  bool get tienePorcentaje => cuenta > 0;

  /// Lo descontado entre lo que valía la cuenta, en puntos (10 = 10%).
  double get porcentaje => tienePorcentaje ? descuento / cuenta * 100 : 0;

  /// Lo que quedó por pagar de la cuenta, sin propina ni envío.
  double get despues => (cuenta - descuento).clamp(0.0, double.infinity);

  bool get alto => porcentaje >= kDescuentoAlto;

  /// Quién cobró, como clave para agrupar: su id; si no hay, su nombre; si no
  /// hay ninguno, vacío (el POS no lo guardó).
  String get clave {
    final id = usuarioId;
    if (id != null) return id;
    final n = usuarioNombre;
    return n == null ? '' : 'nombre:$n';
  }
}

/// Un platillo sumado en todo el período, con lo que se le descontó.
class DescuentoPlatillo {
  final String nombre;
  final double cantidad;
  final double monto;

  /// En cuántos pedidos distintos se descontó.
  final int pedidos;

  const DescuentoPlatillo({
    required this.nombre,
    required this.cantidad,
    required this.monto,
    required this.pedidos,
  });
}

class DescuentosReport {
  /// Del más reciente al más viejo.
  final List<DescuentoPedido> pedidos;

  /// De más a menos descontado.
  final List<DescuentoPlatillo> platillos;

  /// Lo descontado en el período.
  final double total;

  /// Lo que valían esas cuentas antes del descuento.
  final double cuentaTotal;

  const DescuentosReport({
    required this.pedidos,
    required this.platillos,
    required this.total,
    required this.cuentaTotal,
  });

  static const empty = DescuentosReport(pedidos: [], platillos: [], total: 0, cuentaTotal: 0);

  bool get vacio => pedidos.isEmpty;

  /// El descuento promedio de las cuentas, en puntos (lo descontado entre lo
  /// que valían, no el promedio de los porcentajes: una cuenta grande pesa más).
  double get porcentajePromedio => cuentaTotal > 0 ? total / cuentaTotal * 100 : 0;

  int get sinMotivo => pedidos.where((p) => p.sinMotivo).length;
  double get montoSinMotivo => pedidos.where((p) => p.sinMotivo).fold(0.0, (s, p) => s + p.descuento);

  int get altos => pedidos.where((p) => p.alto).length;

  /// El pedido con el porcentaje más alto (si empatan, el de más monto); null
  /// si no hay pedidos o ninguno tiene porcentaje.
  DescuentoPedido? get masAlto {
    DescuentoPedido? mejor;
    for (final p in pedidos) {
      if (!p.tienePorcentaje) continue;
      if (mejor == null ||
          p.porcentaje > mejor.porcentaje ||
          (p.porcentaje == mejor.porcentaje && p.descuento > mejor.descuento)) {
        mejor = p;
      }
    }
    return mejor;
  }

  /// Los ids de quienes cobraron sin que el pedido guardara su nombre, para
  /// buscárselo.
  Set<String> get usuarios => {
        for (final p in pedidos)
          if (p.usuarioId != null && p.usuarioNombre == null) p.usuarioId!,
      };

  /// Arma el reporte con los pedidos que el Inicio ya tiene en memoria (ya
  /// filtrados por sucursal, sin cancelados y en la moneda de la vista).
  factory DescuentosReport.desde(List<Map<String, dynamic>> ordenes) {
    final pedidos = <DescuentoPedido>[];
    final porPlatillo = <String, _AccPlatillo>{};
    var total = 0.0, cuentaTotal = 0.0;

    for (final o in ordenes) {
      final descuento = _num(o['discount_amount']);
      // La misma condición que el conteo de la tarjeta del Inicio.
      if (descuento == null || descuento <= 0) continue;

      final renglones = <DescuentoRenglon>[];
      final items = o['items'];
      if (items is List) {
        for (final item in items) {
          if (item is! Map) continue;
          // Solo lo que se cobró: ni lo anulado ni lo regalado valen algo en
          // la cuenta, así que ahí no hay nada que descontar.
          if (item['is_void'] == true || item['is_courtesy'] == true) continue;
          renglones.add(DescuentoRenglon(
            nombre: textoDelPedido(item['name']) ?? 'Sin nombre',
            cantidad: _num(item['qty']) ?? 1,
            monto: valorCortesia(item),
          ));
        }
      }

      // La cuenta es lo que el POS guarda como total antes del descuento; si no
      // viene, lo que suman sus platillos.
      final guardado = _num(o['total_amount']);
      final suma = renglones.fold(0.0, (s, r) => s + r.monto);
      final cuenta = guardado != null && guardado > 0 ? guardado : suma;

      final pedido = DescuentoPedido(
        id: textoDelPedido(o['_docId']) ?? textoDelPedido(o['id']) ?? '',
        numero: numeroDelPedido(o),
        fecha: fechaDelPedido(o['paid_at']),
        lugar: lugarDelPedido(o),
        cliente: textoDelPedido(o['customer_name']),
        locationId: textoDelPedido(o['location_id']),
        renglones: renglones,
        cuenta: cuenta,
        descuento: descuento,
        motivo: textoDelPedido(o['discount_reason']),
        usuarioId: _usuario(o['paid_by_user_id']),
        usuarioNombre: _usuario(o['paid_by_user_name']),
      );
      pedidos.add(pedido);
      total += descuento;
      cuentaTotal += cuenta;

      // El descuento es de la cuenta entera: se reparte entre sus platillos en
      // proporción a lo que valía cada uno.
      if (suma > 0) {
        final enEstePedido = <String>{};
        for (final r in renglones) {
          final parte = descuento * r.monto / suma;
          final acc = porPlatillo.putIfAbsent(r.nombre, () => _AccPlatillo());
          acc.cantidad += r.cantidad;
          acc.monto += parte;
          // El mismo platillo dos veces en un pedido es UN pedido.
          if (enEstePedido.add(r.nombre)) acc.pedidos++;
        }
      }
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
        DescuentoPlatillo(
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

    return DescuentosReport(pedidos: pedidos, platillos: platillos, total: total, cuentaTotal: cuentaTotal);
  }

  static double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

  /// El POS escribe 'unknown' cuando no sabe quién es.
  static String? _usuario(Object? v) {
    final t = textoDelPedido(v);
    return t == null || t == 'unknown' ? null : t;
  }
}

class _AccPlatillo {
  double cantidad = 0;
  double monto = 0;
  int pedidos = 0;
}
