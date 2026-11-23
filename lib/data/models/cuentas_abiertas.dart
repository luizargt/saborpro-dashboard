/// Las cuentas pendientes de cobro: lo que el punto de venta muestra en su
/// pestaña "Por cobrar" ("22 cuentas abiertas · Q5,010.00").
///
/// Es el ESTADO DE AHORA, no un período: no depende de la fecha que se mira en
/// el Inicio, solo de la sucursal. Y se define como la define el POS
/// (`getActiveOrders` / `readyOrdersStream` en order_service.dart): pedidos en
/// estado WEB, ENVIADO, EN_PREP o LISTO, creados en las últimas 48 horas y sin
/// cobrar. La ventana de 48 horas es del POS a propósito: deja fuera las cuentas
/// que quedaron abiertas para siempre sin que nadie las cobrara ni las cancelara.
///
/// El monto es el mismo con que el POS arranca el cobro (`montoACobrarDePedido`
/// en orders_screen.dart, probado en monto_cobrar_test.dart): el total guardado
/// nunca baja de la suma de los renglones vigentes (sin anulados ni cortesías), y
/// encima van impuesto, descuento, envío y recargo. La propina no entra: se elige
/// dentro del cobro.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'cortesias_data.dart' show valorCortesia;

/// Una cuenta pendiente de cobro, ya con lo que falta cobrar.
class CuentaAbierta {
  final String id;
  final String? locationId;

  /// En la moneda de su sucursal (sin convertir).
  final double monto;
  final DateTime? creada;

  const CuentaAbierta({
    required this.id,
    required this.locationId,
    required this.monto,
    this.creada,
  });
}

/// Cuántas cuentas hay y cuánto suman, en la moneda de la vista.
class CuentasPorCobrar {
  final int cuantas;
  final double monto;

  const CuentasPorCobrar({this.cuantas = 0, this.monto = 0});
}

class CuentasAbiertas {
  CuentasAbiertas._();

  /// Los estados con que el POS considera "activo" un pedido sin cobrar.
  static const estados = ['WEB', 'ENVIADO', 'EN_PREP', 'LISTO'];

  /// Cuánto hacia atrás mira el POS.
  static const ventana = Duration(hours: 48);

  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;

  /// Lo que falta cobrar de un pedido abierto, con los nombres de campo de
  /// Firestore. Es `montoACobrarDePedido` del POS, renglón por renglón.
  static double montoACobrar(Map<String, dynamic> pedido) {
    var calculado = 0.0;
    final items = pedido['items'];
    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;
        // Anulados y cortesías no se cobran.
        if (it['is_void'] == true || it['is_courtesy'] == true) continue;
        // La cuenta del POS: precio × cantidad más extras.
        calculado += valorCortesia(it);
      }
    }
    final guardado = _num(pedido['total_amount']);
    final total = calculado > guardado ? calculado : guardado;
    return total +
        _num(pedido['tax_amount']) -
        _num(pedido['discount_amount']) +
        _num(pedido['delivery_fee']) +
        _num(pedido['surcharge_amount']);
  }

  /// El documento como cuenta abierta, o null si no cuenta: otro estado, o ya
  /// cobrado. La consulta ya filtra por estado y ventana; esto es el cinturón.
  static CuentaAbierta? deDoc(String id, Map<String, dynamic> d) {
    if (!estados.contains(d['status'])) return null;
    if (d['payment_status'] == 'PAID') return null;
    final creada = d['created_at'];
    return CuentaAbierta(
      id: id,
      locationId: d['location_id'] as String?,
      monto: montoACobrar(d),
      creada: creada is Timestamp ? creada.toDate().toLocal() : null,
    );
  }

  /// Cuenta las de [cuentas] que [pasa] (el filtro de sucursal de la vista) y
  /// suma lo que falta cobrar, cada una pasada a la moneda de la vista con
  /// [factor]. Un factor nulo es una sucursal sin tipo de cambio: esa cuenta no
  /// se cuenta ni se suma (sumar monedas distintas daría un total que no es de
  /// nada; el Inicio ya avisa qué sucursales quedaron fuera).
  static CuentasPorCobrar resumir(
    Iterable<CuentaAbierta> cuentas, {
    required bool Function(String? locationId) pasa,
    required double? Function(String? locationId) factor,
  }) {
    var n = 0;
    var monto = 0.0;
    for (final c in cuentas) {
      if (!pasa(c.locationId)) continue;
      final f = factor(c.locationId);
      if (f == null) continue;
      n++;
      monto += c.monto * f;
    }
    return CuentasPorCobrar(cuantas: n, monto: monto);
  }
}
