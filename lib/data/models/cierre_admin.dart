/// Cerrar una caja desde Sabor Manager, como administrador.
///
/// Nadie cuenta el dinero, así que el corte queda DESCUADRADO: se guarda lo que
/// debía haber por método (sacado de los pedidos de la caja, con las reglas con
/// que cierra el POS) y NO se escribe nada contado ni ninguna diferencia. No se
/// inventa un faltante: sin conteo no se sabe cuánto falta.
///
/// Sin Firebase: lo lee y lo escribe `CierreAdminService`.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'cash_register_summary.dart';
import 'detalle_caja.dart';

/// Lo vendido en una caja, por método de pago (propinas incluidas).
class VentasDeCaja {
  final double efectivo;
  final double tarjeta;
  final double transferencia;
  final double pedidosya;
  final double ubereats;

  /// Métodos propios (id → monto). 'otros' junta los métodos que no se reconocen.
  final Map<String, double> propios;

  const VentasDeCaja({
    this.efectivo = 0,
    this.tarjeta = 0,
    this.transferencia = 0,
    this.pedidosya = 0,
    this.ubereats = 0,
    this.propios = const {},
  });

  /// La misma cuenta que `CashRegisterCalculator.calculate` del POS: si se toca
  /// allá, se toca aquí. [pedidos]: solo los de la caja.
  static VentasDeCaja desde(List<Map<String, dynamic>> pedidos) {
    var efectivo = 0.0, tarjeta = 0.0, transferencia = 0.0, pedidosya = 0.0, ubereats = 0.0;
    final propios = <String, double>{};

    void suma(String metodo, double monto) {
      switch (metodo) {
        // Un pago compuesto que perdió su desglose se queda en efectivo, como en el POS.
        case 'cash' || 'split' || 'mixed':
          efectivo += monto;
        case 'card':
          tarjeta += monto;
        case 'transfer':
          transferencia += monto;
        case 'pedidosya':
          pedidosya += monto;
        case 'ubereats':
          ubereats += monto;
        default:
          // Un método desconocido no se suma al efectivo: el POS lo manda a 'otros'.
          final id = metodo.startsWith('custom_') || metodo == 'custom' ? metodo : 'otros';
          propios[id] = (propios[id] ?? 0) + monto;
      }
    }

    void partes(List<dynamic> lista, String llaveMetodo) {
      for (final p in lista) {
        if (p is! Map) continue;
        final metodo = p[llaveMetodo];
        suma(metodo is String ? metodo : 'cash', _numero(p['amount']) ?? 0);
      }
    }

    for (final o in pedidos) {
      final crudo = o['payment_method'];
      final metodo = crudo == null ? 'cash' : '$crudo';
      final divididos = o['split_payments'];
      final mixtos = o['mixed_payments'];
      if (metodo == 'split' && divididos is List) {
        partes(divididos, 'payment_method');
      } else if (metodo == 'mixed' && mixtos is List && mixtos.isNotEmpty) {
        partes(mixtos, 'method');
      } else {
        suma(metodo, _numero(o['payment_amount']) ?? _numero(o['total_amount']) ?? 0);
      }
    }

    return VentasDeCaja(
      efectivo: efectivo,
      tarjeta: tarjeta,
      transferencia: transferencia,
      pedidosya: pedidosya,
      ubereats: ubereats,
      propios: propios,
    );
  }
}

class CierreAdmin {
  CierreAdmin._();

  /// La marca en el documento de la caja.
  static const campo = 'closed_by_admin';

  /// La nota del corte. Las palabras "Cierre forzado" no se pueden quitar: con
  /// ellas el POS ya instalado le dice al cajero que la cerró un administrador
  /// sin contar, y le pide su conteo.
  static String nota(String admin) => 'Cierre forzado desde Sabor Manager: caja cerrada por administrador ($admin) '
      'sin contar el dinero. Quedó descuadrada.';

  /// Los pedidos que cuentan en [caja] hasta [hasta]. Es la regla con que el POS
  /// cierra (`CashRegisterCalculator.perteneceACaja`): si se toca allá, se toca
  /// aquí. Es más estricta que la lista de "Ver pedidos y gastos": un cobro sin
  /// cobrador (apps de reparto) no entra en ningún corte. [pedidos] puede traer
  /// de más.
  static List<Map<String, dynamic>> pedidosDeLaCaja(
    List<Map<String, dynamic>> pedidos,
    CashRegisterSummary caja, {
    required DateTime hasta,
  }) {
    final desde = caja.openedAt.subtract(const Duration(seconds: 1));
    final tope = hasta.add(const Duration(seconds: 1));
    return pedidos.where((o) {
      if (o['payment_status'] != 'PAID') return false;
      if (o['status'] == 'CANCELLED' || o['cancelled_at'] != null) return false;
      if (o['location_id'] != caja.locationId) return false;
      final pagado = _fecha(o['paid_at']);
      if (pagado == null) return false;
      // Como `effectivePaidAt` del POS: con el reloj del aparato atrasado la hora
      // de pago queda antes de la de creación, y vale la de creación.
      final creado = _fecha(o['created_at']);
      final efectivo = creado != null && pagado.isBefore(creado) ? creado : pagado;
      if (!efectivo.isAfter(desde) || !efectivo.isBefore(tope)) return false;
      // La venta que dice en qué caja se cobró cuenta solo en esa; si no, la
      // responde quien la cobró.
      final sello = cajaDelCobro(o);
      if (sello != null) return sello == caja.id;
      return o['paid_by_user_id'] == caja.userId;
    }).toList();
  }

  /// Lo que cambia en la caja cada vez que se cobra en ella (los acumulados del
  /// POS). Si cambia mientras se hace la cuenta, la cuenta ya no sirve.
  static String huellaDeCobros(Map<String, dynamic> caja) {
    final propios = caja['expectedCustomMethods'];
    return [
      for (final m in const ['Cash', 'Card', 'Transfer', 'Pedidosya', 'Ubereats']) '${caja['expected$m']}',
      if (propios is Map)
        for (final id in propios.keys.map((k) => '$k').toList()..sort()) '$id=${propios[id]}',
    ].join('|');
  }

  /// El `updatedAt` del cierre: nunca anterior al que ya tiene la caja. Otro
  /// aparato que guarde una copia "más nueva" que el cierre la seguiría viendo
  /// abierta (en "Cajero único" nadie más podría abrir), y el reloj de quien
  /// cierra puede ir atrasado.
  static DateTime horaDeActualizacion(Map<String, dynamic> caja, DateTime ahora) {
    final anterior = _fecha(caja['updatedAt']);
    if (anterior == null) return ahora;
    final siguiente = anterior.add(const Duration(seconds: 1));
    return siguiente.isAfter(ahora) ? siguiente : ahora;
  }

  /// Lo que se escribe sobre la caja abierta al cerrarla. La hora del cierre
  /// (`closedAt`) la pone el servidor al escribir.
  static Map<String, dynamic> datos({
    required CashRegisterSummary caja,
    required VentasDeCaja ventas,
    required DateTime actualizada,
    required String adminId,
    required String adminNombre,
  }) {
    return {
      'status': 'closed',
      'updatedAt': Timestamp.fromDate(actualizada),
      // Como en el cierre del POS: el fondo de apertura va incluido.
      'expectedCash': caja.initialCash + ventas.efectivo,
      'expectedCard': caja.initialCard + ventas.tarjeta,
      'expectedTransfer': caja.initialTransfer + ventas.transferencia,
      'expectedPedidosya': caja.initialPedidosya + ventas.pedidosya,
      'expectedUbereats': caja.initialUbereats + ventas.ubereats,
      'expectedCustomMethods': ventas.propios,
      // Nadie contó.
      'actualCash': null,
      'actualCard': null,
      'actualTransfer': null,
      'actualPedidosya': null,
      'actualUbereats': null,
      'actualCustomMethods': <String, double>{},
      'differenceCash': null,
      'differenceCard': null,
      'differenceTransfer': null,
      'differencePedidosya': null,
      'differenceUbereats': null,
      'differenceCustomMethods': <String, double>{},
      'closingNotes': nota(adminNombre),
      // Solo textos: el POS guarda el documento en su disco y ahí una fecha de
      // Firestore dentro de un campo que no conoce no se puede escribir.
      campo: {'user_id': adminId, 'user_name': adminNombre, 'app': 'sabor_manager'},
    };
  }
}

double? _numero(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _fecha(dynamic v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}
