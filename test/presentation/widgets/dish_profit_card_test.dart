import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_card.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_widgets.dart';

import '../../helpers/menu_de_prueba.dart';
import '../../helpers/texto_completo.dart';

/// La tarjeta "Utilidad por platillo" dentro de Rentabilidad, a 360dp.

Widget tarjeta(
  UtilidadMenu? datos, {
  bool cargando = false,
  String? error,
  VoidCallback? onReintentar,
  VoidCallback? onVerTodos,
}) =>
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: UtilidadPlatillosCard(
        datos: datos,
        cargando: cargando,
        error: error,
        periodo: 'Octubre 2026',
        onReintentar: onReintentar ?? () {},
        onVerTodos: onVerTodos ?? () {},
      ),
    );

RepartoGastos repartoCon(DateRange rango, {double ventas = 100000}) =>
    RepartoGastos.desde(
      datos: ProfitabilityData(
        netSales: ventas,
        cogs: 0,
        itemsSinCosto: 0,
        itemsConCosto: 0,
        expenses: const [
          ExpenseLine(
              categoryId: 'renta', label: 'Renta', amount: 60000, esFijo: true),
          ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 50000),
        ],
        payroll: 0,
        paidFromCash: 0,
        purchases: 0,
        inventoryValue: 0,
        ingredientesSinPrecio: 0,
      ),
      rango: rango,
      gastosLeidos: true,
      hoy: DateTime(2026, 11, 5),
    );

void main() {
  for (final escala in [1.0, 1.5, 2.0]) {
    testWidgets('a 360dp con letra al ${(escala * 100).round()}%: nada se '
        'desborda ni se corta, y todo se lee', (tester) async {
      await pintarEnTelefono(tester, tarjeta(utilidadDificil()),
          escala: escala, alto: 2400);
      expect(tester.takeException(), isNull);
      expectCifrasCompletas(tester);
      expectContrasteDeCifras(tester, fondo: kTarjeta);
    });
  }

  testWidgets('en el teléfono más angosto (320dp) tampoco', (tester) async {
    await pintarEnTelefono(tester, tarjeta(utilidadDificil()),
        ancho: 320, alto: 2400);
    expect(tester.takeException(), isNull);
    expectCifrasCompletas(tester);
  });

  testWidgets('explica el reparto: cuánto de cada Q100 se va en gastos',
      (tester) async {
    await pintarEnTelefono(tester, tarjeta(utilidadDificil()), alto: 2400);
    expect(find.text('De cada Q100 que cobrás, Q38 se van en gastos'),
        findsOneWidget);
    expect(find.textContaining('Q25 en fijos (renta, sueldos) y Q13 en variables'),
        findsOneWidget);
    // En la tarjeta no: espera a "Ver todos" para no alargarla.
    expect(find.textContaining('de insumos'), findsNothing);
  });

  testWidgets('menos y más dejan, sin repetir y sin los sospechosos',
      (tester) async {
    await pintarEnTelefono(tester, tarjeta(utilidadDificil()), alto: 2400);
    expect(find.text('MENOR GANANCIA (% DEL PRECIO)'), findsOneWidget);
    expect(find.text('MAYOR GANANCIA (% DEL PRECIO)'), findsOneWidget);
    expect(find.text('Por cada venta: no cuenta cuántos vendés.'),
        findsOneWidget);
    // La sopa pierde en cada venta: es el que menos deja.
    expect(find.text('Sopa del Día'), findsOneWidget);
    expect(find.textContaining('pierde en cada venta'), findsOneWidget);
    // El filete (receta mayor que el precio) y el café (99%) no entran al
    // ranking: tienen el costo mal cargado.
    expect(find.text('Filete de Pechuga a la Barbacoa'), findsNothing);
    expect(find.text('Café Americano'), findsNothing);
  });

  testWidgets('dice cuántos tienen costo y qué precio cargar primero',
      (tester) async {
    await pintarEnTelefono(tester, tarjeta(utilidadDificil()), alto: 2400);
    expect(
        find.textContaining('Con costo completo: 10 de 12 platillos · 3 por '
            'revisar'),
        findsOneWidget);
    expect(
        find.textContaining('Queso mozzarella importado de primera calidad '
            '(en 1 platillo)'),
        findsOneWidget);
  });

  testWidgets('con pocos platillos confiables va una sola lista',
      (tester) async {
    final datos = UtilidadMenu.armar(
      calcularMargenes(MenuCrudo(
        productos: const [
          ProductoMenu(id: 'a', nombre: 'Único', presentaciones: [
            PresentacionMenu(id: 'a1', nombre: 'N', precio: 50),
          ]),
        ],
        recetas: const [
          LineaReceta(
              docId: 'r',
              productoId: 'a',
              presentacionId: 'a1',
              ingredienteId: 'i',
              cantidad: 1),
        ],
        ingredientes: const [IngredienteCosto(id: 'i', nombre: 'I', precio: 10)],
      )),
      reparto: repartoDeOctubre(),
    );
    await pintarEnTelefono(tester, tarjeta(datos));
    expect(find.text('TUS PLATILLOS CON COSTO (% DEL PRECIO)'), findsOneWidget);
    expect(find.text('MAYOR GANANCIA (% DEL PRECIO)'), findsNothing);
  });

  testWidgets('con un día elegido pide Mes o Año y muestra la receta',
      (tester) async {
    final datos = UtilidadMenu.armar(calcularMargenes(menuDificil()),
        reparto: repartoCon(DateRange.today()));
    await pintarEnTelefono(tester, tarjeta(datos), alto: 2400);
    expect(find.textContaining('elegí Mes o Año'), findsOneWidget);
    expect(find.textContaining('tras la receta'), findsWidgets);
    expect(find.textContaining('cubre sus gastos'), findsNothing);
    expect(find.textContaining('pierde en cada venta'), findsNothing);
  });

  testWidgets('si los gastos superan la venta lo dice en vez de pintar todo '
      'de rojo', (tester) async {
    final octubre = DateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
        mode: PeriodMode.month);
    final datos = UtilidadMenu.armar(calcularMargenes(menuDificil()),
        reparto: repartoCon(octubre));
    await pintarEnTelefono(tester, tarjeta(datos), alto: 2400);
    expect(find.textContaining('superan lo que cobraste'), findsOneWidget);
    expect(find.textContaining('pierde en cada venta'), findsNothing);
  });

  testWidgets('sin gastos cargados no pinta todo de verde', (tester) async {
    final octubre = DateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
        mode: PeriodMode.month);
    final sinGastos = RepartoGastos.desde(
      datos: const ProfitabilityData(
        netSales: 100000,
        cogs: 0,
        itemsSinCosto: 0,
        itemsConCosto: 0,
        expenses: [],
        payroll: 0,
        paidFromCash: 0,
        purchases: 0,
        inventoryValue: 0,
        ingredientesSinPrecio: 0,
      ),
      rango: octubre,
      gastosLeidos: true,
      hoy: DateTime(2026, 11, 5),
    );
    await pintarEnTelefono(
        tester,
        tarjeta(UtilidadMenu.armar(calcularMargenes(menuDificil()),
            reparto: sinGastos)),
        alto: 2400);
    expect(find.textContaining('No hay gastos cargados'), findsOneWidget);
    expect(find.textContaining('cubre sus gastos'), findsNothing);
  });

  testWidgets('a inicio de mes no alarma: explica y manda al mes pasado',
      (tester) async {
    final octubre = DateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
        mode: PeriodMode.month);
    final r = RepartoGastos.desde(
      datos: const ProfitabilityData(
        netSales: 4000,
        cogs: 0,
        itemsSinCosto: 0,
        itemsConCosto: 0,
        expenses: [
          ExpenseLine(
              categoryId: 'renta', label: 'Renta', amount: 15000, esFijo: true),
        ],
        payroll: 0,
        paidFromCash: 0,
        purchases: 0,
        inventoryValue: 0,
        ingredientesSinPrecio: 0,
      ),
      rango: octubre,
      gastosLeidos: true,
      hoy: DateTime(2026, 10, 3),
    );
    await pintarEnTelefono(
        tester,
        tarjeta(UtilidadMenu.armar(calcularMargenes(menuDificil()), reparto: r)),
        alto: 2400);
    expect(find.textContaining('Apenas va el mes'), findsOneWidget);
    expect(find.textContaining('superan lo que cobraste'), findsNothing);
  });

  testWidgets('el ámbar dice cuánto aporta, no solo que no cubre',
      (tester) async {
    await pintarEnTelefono(tester, tarjeta(utilidadDificil()), alto: 2400);
    // El licuado no cubre su parte de los fijos pero sí aporta a la renta.
    expect(find.textContaining('aporta Q'), findsOneWidget);
    expect(find.textContaining('a los fijos, pero no toda su parte'),
        findsOneWidget);
  });

  testWidgets('mientras baja el menú, un spinner; si falla, Reintentar',
      (tester) async {
    await pintarEnTelefono(tester, tarjeta(null, cargando: true),
        asentar: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    var reintentos = 0;
    await pintarEnTelefono(
        tester,
        tarjeta(null,
            error: 'Sin conexión con el servidor.',
            onReintentar: () => reintentos++));
    expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
    final boton = find.ancestor(
        of: find.text('Reintentar'), matching: find.byType(InkWell));
    expect(tester.getSize(boton).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Reintentar'));
    expect(reintentos, 1);
  });

  testWidgets('"Ver todos" mide 44 y abre la lista', (tester) async {
    var abierto = 0;
    await pintarEnTelefono(
        tester, tarjeta(utilidadDificil(), onVerTodos: () => abierto++),
        alto: 2400);
    final boton = find.ancestor(
        of: find.text('Ver todos los platillos (12)'),
        matching: find.byType(InkWell));
    expect(tester.getSize(boton).height, greaterThanOrEqualTo(44));
    await tester.tap(boton);
    expect(abierto, 1);
  });

  testWidgets('menú vacío: lo explica y no ofrece "Ver todos"', (tester) async {
    await pintarEnTelefono(tester, tarjeta(const UtilidadMenu([])));
    expect(find.textContaining('todavía no tiene platillos'), findsOneWidget);
    expect(find.textContaining('Ver todos'), findsNothing);
  });
}

