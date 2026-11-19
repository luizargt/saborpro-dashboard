import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/core/services/export_service.dart';
import 'package:saborpro_reports/data/models/cortesias_data.dart';

/// El Excel "Reporte de Caja": la columna "Cortesía / Donación" vale con
/// extras (igual que la tarjeta del Inicio y el ticket), y la hoja
/// "Cortesías" trae solo lo regalado, con el resumen por platillo, y suma lo
/// mismo que esa columna.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es', null);
  });

  String txt(Data? d) => d?.value?.toString() ?? '';
  double numero(Data? d) {
    final v = d?.value;
    if (v is DoubleCellValue) return v.value;
    if (v is IntCellValue) return v.value.toDouble();
    return double.nan;
  }

  List<List<Data?>> filas(Excel e, String hoja) => e.tables[hoja]!.rows;
  int col(List<Data?> encabezado, String nombre) =>
      encabezado.indexWhere((d) => txt(d) == nombre);

  Map<String, dynamic> item(
    String name, {
    num qty = 1,
    num price = 10,
    bool courtesy = true,
    bool voided = false,
    String type = 'CORTESIA',
    String? reason,
    String? by,
    List<Map<String, dynamic>>? mods,
  }) =>
      {
        'name': name,
        'qty': qty,
        'unit_price': price,
        'is_courtesy': courtesy,
        'is_void': voided,
        if (courtesy) 'courtesy_type': type,
        if (reason != null) 'courtesy_reason': reason,
        if (by != null) 'courtesy_by_user_id': by,
        if (mods != null) 'modifiers': mods,
      };

  Map<String, dynamic> orden(String id, List<Object?> items,
          {DateTime? paid, String? location, int? no, String? table}) =>
      {
        '_docId': id,
        'items': items,
        'paid_at': Timestamp.fromDate(paid ?? DateTime(2026, 11, 5, 13)),
        'type': 'dine_in',
        if (table != null) 'table_name': table,
        if (no != null) 'order_no': no,
        'order_prefix': 'A',
        if (location != null) 'location_id': location,
        'payment_amount': 50,
        'total_amount': 50,
      };

  final hamburguesa = item('Hamburguesa', qty: 2, price: 55, by: 'u1',
      reason: 'Cumpleaños', mods: [
        {'name': 'Tocino', 'price': 10, 'qty': 1},
        {'name': 'Queso', 'price': 8, 'qty': 1},
      ]);

  List<Map<String, dynamic>> pedidos() => [
        orden('a', [
          hamburguesa,
          item('Limonada', price: 15, courtesy: false),
          // Anulada: no cuenta.
          item('Papas', price: 20, voided: true),
        ], no: 7, table: 'Mesa 4', paid: DateTime(2026, 11, 5, 20)),
        orden('b', [
          item('Postre', price: 25, type: 'DONACION'),
          item('Hamburguesa', price: 55),
        ], no: 3, paid: DateTime(2026, 11, 2, 12)),
        orden('c', [item('Café', price: 12, courtesy: false)], no: 9),
      ];

  test('la columna de caja vale con extras, como la tarjeta y el ticket', () {
    final e = ExportService.armarCajaReport(pedidos(), {}, const {});
    final caja = filas(e, 'Reporte de Caja');
    final c = col(caja.first, 'Cortesía / Donación (Q)');
    expect(c, isNonNegative);
    // Pedido a: 2 × (55 + 10 + 8) = 146; la anulada no entra.
    expect(numero(caja[1][c]), 146);
    expect(numero(caja[2][c]), 80);
    expect(numero(caja[3][c]), 0);
  });

  test('la hoja Cortesías trae solo lo regalado, en orden de fecha', () {
    final e = ExportService.armarCajaReport(
        pedidos(), {}, const {'u1': 'Ana'});
    final h = filas(e, 'Cortesías');
    final enc = h.first;
    expect(enc.map(txt).toList(), [
      'Fecha y hora',
      'Nº Ticket',
      'Mesa / Lugar',
      'Cliente',
      'Platillo',
      'Extras',
      'Cantidad',
      'Monto (Q)',
      'Tipo',
      'Motivo',
      'Registró',
    ]);

    // 3 renglones regalados: los 2 del pedido b (más viejo) y la hamburguesa
    // del a. Ni la limonada cobrada ni las papas anuladas.
    final detalle = h.sublist(1, 4);
    expect(detalle.map((f) => txt(f[col(enc, 'Platillo')])).toList(),
        ['Postre', 'Hamburguesa', 'Hamburguesa']);
    final ultima = detalle.last;
    expect(txt(ultima[col(enc, 'Nº Ticket')]), 'A7');
    expect(txt(ultima[col(enc, 'Mesa / Lugar')]), 'Mesa 4');
    expect(txt(ultima[col(enc, 'Extras')]), 'Tocino · Queso');
    expect(numero(ultima[col(enc, 'Cantidad')]), 2);
    expect(numero(ultima[col(enc, 'Monto (Q)')]), 146);
    expect(txt(ultima[col(enc, 'Tipo')]), 'Cortesía');
    expect(txt(ultima[col(enc, 'Motivo')]), 'Cumpleaños');
    expect(txt(ultima[col(enc, 'Registró')]), 'Ana');
    expect(txt(detalle.first[col(enc, 'Tipo')]), 'Donación');
  });

  test('la hoja Cortesías suma lo mismo que la columna de caja y la tarjeta',
      () {
    final ordenes = pedidos();
    final e = ExportService.armarCajaReport(ordenes, {}, const {});
    final caja = filas(e, 'Reporte de Caja');
    final cCaja = col(caja.first, 'Cortesía / Donación (Q)');
    final sumaCaja =
        caja.skip(1).fold<double>(0, (s, f) => s + numero(f[cCaja]));

    final h = filas(e, 'Cortesías');
    final cMonto = col(h.first, 'Monto (Q)');
    final detalle = h.skip(1).takeWhile((f) => txt(f.first).isNotEmpty);
    final sumaHoja = detalle.fold<double>(0, (s, f) => s + numero(f[cMonto]));

    expect(sumaHoja, sumaCaja);
    expect(sumaHoja, CortesiasReport.desde(ordenes).total);
    expect(sumaHoja, 226);
  });

  test('debajo va el resumen por platillo, con el total de pedidos distintos',
      () {
    final e = ExportService.armarCajaReport(pedidos(), {}, const {});
    final h = filas(e, 'Cortesías');
    final i = h.indexWhere((f) => txt(f.first) == 'Resumen por platillo');
    expect(i, greaterThan(0));
    // La tabla rellena cada fila hasta su ancho: se miran las 4 primeras.
    expect(h[i + 1].take(4).map(txt).toList(),
        ['Platillo', 'Cantidad', 'Monto (Q)', 'Pedidos']);
    // Hamburguesa: 2 con extras (146) + 1 sola (55), en 2 pedidos.
    expect(txt(h[i + 2][0]), 'Hamburguesa');
    expect(numero(h[i + 2][1]), 3);
    expect(numero(h[i + 2][2]), 201);
    expect(numero(h[i + 2][3]), 2);
    expect(txt(h[i + 3][0]), 'Postre');
    final total = h[i + 4];
    expect(txt(total[0]), 'Total');
    expect(numero(total[1]), 4);
    expect(numero(total[2]), 226);
    // Bajo "Pedidos" no va nada: no sería la suma de la columna.
    expect(txt(total[3]), '');
    // Dos pedidos, aunque la columna sume 3: el b tiene dos platillos. Va en
    // su propia fila, rotulada.
    expect(txt(h[i + 5][0]), 'Pedidos con cortesía');
    expect(numero(h[i + 5][1]), 2);
  });

  test('con dos monedas: columna Moneda y un resumen por cada una', () {
    final e = ExportService.armarCajaReport(
      [
        orden('gt', [item('Taco', price: 20)], location: 'gt1'),
        orden('ar', [item('Empanada', price: 1500)], location: 'ar1'),
      ],
      {},
      const {},
      simbolos: const {'gt1': 'Q', 'ar1': r'$'},
    );
    final h = filas(e, 'Cortesías');
    expect(col(h.first, 'Moneda'), isNonNegative);
    expect(col(h.first, 'Monto'), isNonNegative);
    final titulos = h
        .map((f) => txt(f.first))
        .where((t) => t.startsWith('Resumen por platillo'))
        .toList();
    expect(titulos, [r'Resumen por platillo ($)', 'Resumen por platillo (Q)']);
    // Ningún total junta quetzales con pesos.
    final totales = h.where((f) => txt(f.first) == 'Total').toList();
    expect(totales.map((f) => numero(f[2])).toSet(), {1500.0, 20.0});
  });

  test('la sucursal sale solo si hay cortesías de más de una', () {
    final nombres = {'s1': 'Centro', 's2': 'Zona 10'};
    final dos = ExportService.armarCajaReport(
      [
        orden('a', [item('Taco')], location: 's1'),
        orden('b', [item('Taco')], location: 's2'),
      ],
      {},
      const {},
      nombresSucursal: nombres,
    );
    final h = filas(dos, 'Cortesías');
    final c = col(h.first, 'Sucursal');
    expect(c, isNonNegative);
    expect({txt(h[1][c]), txt(h[2][c])}, {'Centro', 'Zona 10'});

    final una = ExportService.armarCajaReport(
      [orden('a', [item('Taco')], location: 's1')],
      {},
      const {},
      nombresSucursal: nombres,
    );
    expect(col(filas(una, 'Cortesías').first, 'Sucursal'), -1);
  });

  test('sin cortesías la hoja lo dice', () {
    final e = ExportService.armarCajaReport(
        [orden('c', [item('Café', courtesy: false)])], {}, const {});
    final h = filas(e, 'Cortesías');
    expect(txt(h[1].first), 'No hubo cortesías ni donaciones en este período.');
  });
}
