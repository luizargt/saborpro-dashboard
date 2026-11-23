import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/cuentas_abiertas.dart';

/// Las cuentas pendientes de cobro, como las define el POS. Los casos de
/// `montoACobrar` son LOS MISMOS de saborpro_app/test/presentation/screens/
/// ordenes/monto_cobrar_test.dart (con los nombres de campo de Firestore y los
/// mismos resultados): si el Manager dijera otra cifra que el POS, dos pantallas
/// del mismo negocio se contradirían.
void main() {
  Map<String, dynamic> item(
    double precio, {
    int qty = 1,
    bool anulado = false,
    bool cortesia = false,
    List<Map<String, dynamic>> extras = const [],
  }) =>
      {
        'name': 'Producto',
        'unit_price': precio,
        'qty': qty,
        'is_void': anulado,
        'is_courtesy': cortesia,
        if (extras.isNotEmpty) 'modifiers': extras,
      };

  Map<String, dynamic> pedido({
    required double total,
    List<Map<String, dynamic>> items = const [],
    double impuesto = 0,
    double descuento = 0,
    double? envio,
    double? recargo,
    double? propina,
  }) =>
      {
        'total_amount': total,
        'tax_amount': impuesto,
        'discount_amount': descuento,
        if (envio != null) 'delivery_fee': envio,
        if (recargo != null) 'surcharge_amount': recargo,
        if (propina != null) 'tip_amount': propina,
        'items': items,
      };

  group('monto a cobrar (los casos del POS)', () {
    test('con el total al día, es el total del pedido', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 50, items: [item(20), item(30)])), 50);
    });

    test('si el total guardado quedó corto, manda la suma de los ítems', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 20, items: [item(20), item(30)])), 50);
    });

    test('si el total guardado es mayor, nunca baja', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 80, items: [item(20), item(30)])), 80);
    });

    test('un total en cero con ítems cobra los ítems', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 0, items: [item(12.5, qty: 2)])), 25);
    });

    test('los ítems anulados y las cortesías no cuentan', () {
      final o = pedido(total: 0, items: [item(40), item(99, anulado: true), item(99, cortesia: true)]);
      expect(CuentasAbiertas.montoACobrar(o), 40);
    });

    test('suma impuesto, envío y recargo, y resta el descuento', () {
      final o = pedido(total: 100, items: [item(100)], impuesto: 12, descuento: 10, envio: 15, recargo: 5);
      expect(CuentasAbiertas.montoACobrar(o), 122);
    });

    test('la propina no entra: se elige dentro del cobro', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 100, items: [item(100)], propina: 10)), 100);
    });

    test('un pedido vacío es cero', () {
      expect(CuentasAbiertas.montoACobrar(pedido(total: 0)), 0);
    });
  });

  group('monto a cobrar: lo que el POS cuenta y aquí podría fallar', () {
    test('los extras van por su cantidad y por la del platillo', () {
      // 2 platillos de 30 con un extra de 5 (×1) cada uno: 2×30 + 5×1×2 = 70.
      final o = pedido(total: 0, items: [
        item(30, qty: 2, extras: [
          {'price': 5, 'qty': 1},
        ]),
      ]);
      expect(CuentasAbiertas.montoACobrar(o), 70);
    });

    test('datos a medias no rompen: campos nulos, ítems que no son mapas, total como texto', () {
      expect(CuentasAbiertas.montoACobrar({'items': 'no es lista', 'total_amount': '100'}), 0);
      expect(
        CuentasAbiertas.montoACobrar({
          'items': [null, 'x', 7, item(10)],
          'total_amount': null,
          'tax_amount': null,
        }),
        10,
      );
      expect(CuentasAbiertas.montoACobrar(const {}), 0);
    });
  });

  group('qué cuenta como cuenta abierta', () {
    Map<String, dynamic> doc(String status, {String? pago, String? loc = 'L1', Object? creada}) => {
          ...pedido(total: 40),
          'status': status,
          if (pago != null) 'payment_status': pago,
          'location_id': loc,
          'created_at': creada ?? Timestamp.fromDate(DateTime(2026, 11, 20, 12)),
        };

    test('los cuatro estados activos del POS, y solo ésos', () {
      expect(CuentasAbiertas.estados, ['WEB', 'ENVIADO', 'EN_PREP', 'LISTO']);
      for (final e in CuentasAbiertas.estados) {
        expect(CuentasAbiertas.deDoc('a', doc(e)), isNotNull, reason: e);
      }
      for (final e in ['DRAFT', 'ENTREGADO', 'COBRADO', 'CERRADO', 'CANCELLED', 'raro']) {
        expect(CuentasAbiertas.deDoc('a', doc(e)), isNull, reason: e);
      }
      expect(CuentasAbiertas.deDoc('a', {...pedido(total: 40)}), isNull, reason: 'sin estado');
    });

    test('la ventana es la del POS: 48 horas', () {
      expect(CuentasAbiertas.ventana, const Duration(hours: 48));
    });

    test('una ya cobrada no es por cobrar, aunque su estado siga activo', () {
      expect(CuentasAbiertas.deDoc('a', doc('LISTO', pago: 'PAID')), isNull);
      expect(CuentasAbiertas.deDoc('a', doc('LISTO', pago: 'PENDING')), isNotNull);
    });

    test('guarda su sucursal, lo que falta cobrar y cuándo se creó', () {
      final c = CuentasAbiertas.deDoc('p1', doc('ENVIADO', loc: 'L2'))!;
      expect(c.id, 'p1');
      expect(c.locationId, 'L2');
      expect(c.monto, 40);
      expect(c.creada, DateTime(2026, 11, 20, 12));
      // Sin fecha legible no se inventa una.
      expect(CuentasAbiertas.deDoc('p2', doc('ENVIADO', creada: 'ayer'))!.creada, isNull);
    });
  });

  group('resumir', () {
    CuentaAbierta c(String loc, double monto) => CuentaAbierta(id: '$loc$monto', locationId: loc, monto: monto);

    final todas = [c('A', 100), c('A', 50.5), c('B', 200), c('C', 80)];

    test('todas las sucursales: cuántas y cuánto', () {
      final r = CuentasAbiertas.resumir(todas, pasa: (_) => true, factor: (_) => 1.0);
      expect(r.cuantas, 4);
      expect(r.monto, 430.5);
    });

    test('una sucursal: solo las suyas', () {
      final r = CuentasAbiertas.resumir(todas, pasa: (l) => l == 'A', factor: (_) => 1.0);
      expect(r.cuantas, 2);
      expect(r.monto, 150.5);
    });

    test('con conversión: cada una a su tipo de cambio', () {
      // B vende en otra moneda: 1 de B = 0.5 de la principal.
      final r = CuentasAbiertas.resumir(todas, pasa: (_) => true, factor: (l) => l == 'B' ? 0.5 : 1.0);
      expect(r.cuantas, 4);
      expect(r.monto, 100 + 50.5 + 100 + 80);
    });

    test('una sucursal sin tipo de cambio queda FUERA, tanto de la cuenta como de la suma', () {
      final r = CuentasAbiertas.resumir(todas, pasa: (_) => true, factor: (l) => l == 'C' ? null : 1.0);
      expect(r.cuantas, 3);
      expect(r.monto, 350.5);
    });

    test('sin cuentas, ceros', () {
      final r = CuentasAbiertas.resumir(const [], pasa: (_) => true, factor: (_) => 1.0);
      expect(r.cuantas, 0);
      expect(r.monto, 0);
    });
  });
}
