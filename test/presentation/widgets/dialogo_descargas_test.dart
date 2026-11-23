import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saborpro_reports/core/theme/tema_manager.dart';
import 'package:saborpro_reports/presentation/controllers/descargas_controller.dart';
import 'package:saborpro_reports/presentation/widgets/dialogo_descargas.dart';

/// "Descargar reportes": el mes y la sucursal, el buscador y cada Excel.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => TemaManager.instancia.ponerSinGuardar(ThemeMode.light));

  Finder boton(String etiqueta) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == etiqueta);

  const items = [
    ItemDescarga('caja', Icons.point_of_sale_rounded, 'Reporte de caja', 'Ventas y cortesías'),
    ItemDescarga('metodos', Icons.credit_card_rounded, 'Ventas por método de pago', 'Efectivo y tarjeta'),
    ItemDescarga('platillos', Icons.restaurant_menu_rounded, 'Platillos vendidos', 'Cuántos de cada uno'),
    ItemDescarga('inventario', Icons.inventory_2_outlined, 'Inventario', 'Lo que hay en bodega'),
  ];
  const seis = [
    ...items,
    ItemDescarga('sar_a', Icons.receipt_long_rounded, 'Documentos no utilizados (SAR)', 'Facturas sin usar'),
    ItemDescarga('sar_b', Icons.summarize_outlined, 'Resumen de ventas por ISV (SAR)', 'El impuesto de cada tasa'),
  ];
  const sucursales = <OpcionSucursal>[(id: null, nombre: 'Todas'), (id: 'a', nombre: 'Centro'), (id: 'b', nombre: 'Norte')];

  Future<void> montar(
    WidgetTester t,
    DescargasController c, {
    List<OpcionSucursal> sucs = sucursales,
    String? elegida,
    ValueChanged<String?>? onSucursal,
    VoidCallback? onCerrar,
    bool telefono = false,
    double ancho = 800,
    double escala = 1,
  }) async {
    t.view.physicalSize = Size(ancho, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(ancho, 1400), textScaler: TextScaler.linear(escala)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ContenidoDescargas(
              controlador: c,
              selectorPeriodo: const Text('Noviembre 2026'),
              sucursales: sucs,
              sucursalElegida: elegida,
              onSucursal: onSucursal ?? (_) {},
              onCerrar: onCerrar ?? () {},
              telefono: telefono,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('título, mes, sucursales y un renglón por reporte', (t) async {
    final c = DescargasController(items: items, ejecutar: (_) async {});
    await montar(t, c);
    expect(find.text('Descargar reportes'), findsOneWidget);
    expect(find.text('Noviembre 2026'), findsOneWidget);
    for (final s in ['Todas', 'Centro', 'Norte']) {
      expect(find.text(s), findsOneWidget);
    }
    for (final i in items) {
      expect(find.text(i.nombre), findsOneWidget);
      expect(find.text(i.descripcion), findsOneWidget);
    }
    expect(find.text('Descargar'), findsNWidgets(items.length));
    expect(find.text('Excel'), findsNWidgets(items.length));
    c.dispose();
  });

  testWidgets('con una sola sucursal no hay chips', (t) async {
    final c = DescargasController(items: items, ejecutar: (_) async {});
    await montar(t, c, sucs: const [(id: null, nombre: 'Todas')]);
    expect(find.text('Todas'), findsNothing);
    c.dispose();
  });

  testWidgets('elegir sucursal avisa cuál (null es todas)', (t) async {
    final c = DescargasController(items: items, ejecutar: (_) async {});
    final elegidas = <String?>[];
    await montar(t, c, onSucursal: elegidas.add);
    await t.tap(find.text('Norte'));
    await t.tap(find.text('Todas'));
    expect(elegidas, ['b', null]);
    c.dispose();
  });

  testWidgets('el buscador solo aparece con más de 5 reportes, y filtra sin tildes', (t) async {
    final pocos = DescargasController(items: items, ejecutar: (_) async {});
    await montar(t, pocos);
    expect(find.byKey(const Key('descargas-buscar')), findsNothing);
    pocos.dispose();

    final muchos = DescargasController(items: seis, ejecutar: (_) async {});
    await montar(t, muchos);
    expect(find.byKey(const Key('descargas-buscar')), findsOneWidget);
    await t.enterText(find.byKey(const Key('descargas-buscar')), 'METODO');
    await t.pump();
    expect(find.text('Ventas por método de pago'), findsOneWidget);
    expect(find.text('Inventario'), findsNothing);
    await t.enterText(find.byKey(const Key('descargas-buscar')), 'zzz');
    await t.pump();
    expect(find.text('No hay reportes con "zzz"'), findsOneWidget);
    muchos.dispose();
  });

  testWidgets('descargar genera ese reporte y queda "Listo"', (t) async {
    final salieron = <String>[];
    final c = DescargasController(items: items, ejecutar: (i) async => salieron.add(i.id));
    await montar(t, c);
    await t.tap(boton('Descargar Inventario'));
    await t.pumpAndSettle();
    expect(salieron, ['inventario']);
    expect(find.text('Listo'), findsOneWidget);
    c.dispose();
  });

  testWidgets('mientras se genera uno, ese muestra el círculo y los demás se apagan', (t) async {
    final puerta = Completer<void>();
    final c = DescargasController(items: items, ejecutar: (_) => puerta.future);
    await montar(t, c);
    await t.tap(boton('Descargar Reporte de caja'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    puerta.complete();
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    c.dispose();
  });

  testWidgets('el error del último intento se ve', (t) async {
    final c = DescargasController(items: items, ejecutar: (_) async => throw StateError('x'));
    await montar(t, c);
    await t.tap(boton('Descargar Platillos vendidos'));
    await t.pumpAndSettle();
    expect(find.text('No se pudo generar "Platillos vendidos". Intenta de nuevo.'), findsOneWidget);
    c.dispose();
  });

  testWidgets('cerrar avisa', (t) async {
    var cerro = 0;
    final c = DescargasController(items: items, ejecutar: (_) async {});
    await montar(t, c, onCerrar: () => cerro++);
    await t.tap(find.byTooltip('Cerrar'));
    expect(cerro, 1);
    c.dispose();
  });

  testWidgets('en el teléfono el botón es solo el ícono y no hay etiqueta "Excel"', (t) async {
    final c = DescargasController(items: items, ejecutar: (_) async {});
    await montar(t, c, telefono: true, ancho: 360);
    expect(find.text('Descargar'), findsNothing);
    expect(find.text('Excel'), findsNothing);
    expect(boton('Descargar Inventario'), findsOneWidget);
    c.dispose();
  });

  for (final ancho in [320.0, 360.0, 800.0]) {
    testWidgets('cabe a $ancho con letra grande', (t) async {
      final c = DescargasController(items: seis, ejecutar: (_) async {});
      await montar(t, c, telefono: ancho <= 760, ancho: ancho, escala: 1.4);
      expect(t.takeException(), isNull);
      c.dispose();
    });
  }
}
