import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saborpro_reports/data/models/cancellation_data.dart';
import 'package:saborpro_reports/presentation/widgets/cancellations_view.dart';

/// La pantalla de "Pedidos Cancelados" depende de providers con Firebase y no
/// se puede montar en un test; su mitad visual sí. Estas pruebas cubren lo que
/// se rompe callado: que la vista quepa en un teléfono de 360dp (y en escritorio),
/// que NUNCA muestre Q0.00 para producto que sí se perdió pero no tiene precio
/// de compra, y que los filtros dejen en la lista lo que dicen.
void main() {
  setUpAll(() async {
    // Sin red en los tests: que google_fonts use la fuente de respaldo en vez
    // de intentar bajarla y ensuciar la salida.
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es', null);
  });

  Widget wrap(CancellationsReport report, {double escala = 1.0}) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: kCancelBg,
          body: CancellationsReportBody(report: report),
        ),
      );

  void tamano(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Baja hasta el widget (la vista es una sola columna desplazable) y lo toca.
  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> bajarHasta(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  group('PartialValue', () {
    test('suma dinero y unidades sin costo por separado', () {
      const a = PartialValue(
        amount: 10,
        unpricedByUnit: {'u': 3},
        unpricedIngredientIds: {'gatorade'},
      );
      const b = PartialValue(
        amount: 5.5,
        unpricedByUnit: {'u': 2, 'lb': 1},
        unpricedIngredientIds: {'modelo'},
      );

      final sum = a + b;
      expect(sum.amount, 15.5);
      expect(sum.unpricedByUnit['u'], 5);
      expect(sum.unpricedByUnit['lb'], 1);
      expect(sum.unpricedIngredientIds, {'gatorade', 'modelo'});
    });

    test('lo que no tiene precio no vale cero: queda contado en unidades', () {
      const soloSinCosto = PartialValue(
        unpricedByUnit: {'u': 4},
        unpricedIngredientIds: {'stella'},
      );
      expect(soloSinCosto.hasMoney, isFalse);
      expect(soloSinCosto.hasUnpriced, isTrue);
      expect(soloSinCosto.isEmpty, isFalse);
      expect(soloSinCosto.unpricedLabel, '4 u');
    });

    test('vacío es distinto de "no tiene precio"', () {
      expect(PartialValue.empty.isEmpty, isTrue);
      expect(PartialValue.empty.hasUnpriced, isFalse);
    });
  });

  group('PersonCut', () {
    test('el porcentaje se mide en artículos, no en quetzales', () {
      const p = PersonCut(
        userId: 'u1',
        userName: 'Ana',
        events: 4,
        itemsCancelled: 8,
        itemsLost: 6,
        wasted: PartialValue.empty,
        returned: PartialValue.empty,
      );
      expect(p.lostRate, closeTo(0.75, 0.0001));
    });

    test('sin artículos anulados el porcentaje es 0 y no una división por cero', () {
      const p = PersonCut(
        userId: 'u2',
        userName: 'Beto',
        events: 2,
        itemsCancelled: 0,
        itemsLost: 0,
        wasted: PartialValue.empty,
        returned: PartialValue.empty,
      );
      expect(p.lostRate, 0);
    });
  });

  group('a 360dp', () {
    testWidgets('no desborda con datos completos y llega hasta el final',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      // Cualquier RenderFlex overflowed hace fallar el test por sí solo.
      expect(find.text('Producto perdido'), findsOneWidget);

      // En el teléfono todo va uno debajo del otro y las cancelaciones al final.
      await bajarHasta(tester, find.text('¿Quién declara merma?'));
      await bajarHasta(tester, find.text('¿Por qué se cancela?'));
      await bajarHasta(tester, find.text('Cancelaciones'));
      await bajarHasta(tester, find.text('Sin motivo anotado').last);
    });

    testWidgets('con letra grande tampoco desborda', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto(), escala: 1.35));
      await tester.pumpAndSettle();
      await bajarHasta(tester, find.text('Cancelaciones'));
      await bajarHasta(tester, find.text('Sin motivo anotado').last);
    });

    testWidgets('vacío dice que no hubo, no muestra listas', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(CancellationsReport.empty));
      await tester.pumpAndSettle();

      expect(find.text('Ninguna cancelación en este periodo.'), findsOneWidget);
      expect(find.text('¿Quién declara merma?'), findsNothing);
      expect(find.text('Cancelaciones'), findsNothing);
    });

    // La pantalla real mete el cuerpo en el cambio de sucursal
    // (LocationContentSwitcher), que es un AnimatedSwitcher: lo pone en un Stack
    // centrado y con restricciones sueltas. Un SingleChildScrollView mide lo que
    // mide su contenido, así que sin cancelaciones (contenido bajito) todo
    // quedaba al medio de la pantalla, con un hueco enorme entre las pestañas y
    // la tarjeta. El `wrap` de arriba no lo ve: el Scaffold da restricciones
    // firmes.
    for (final tam in const [Size(1280, 900), Size(390, 844)]) {
      testWidgets('sin datos el contenido arranca arriba, no al medio ($tam)',
          (tester) async {
        tamano(tester, tam);
        const arribaDelArea = 100.0; // el encabezado y las pestañas
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: kCancelBg,
            body: Column(
              children: [
                const SizedBox(height: arribaDelArea),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: const ValueKey('todas'),
                      child: RefreshIndicator(
                        onRefresh: () async {},
                        child: CancellationsReportBody(report: CancellationsReport.empty),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // El área desplazable llena todo el alto (jalar para actualizar tiene
        // que funcionar también sobre lo que queda debajo de las tarjetas)...
        expect(
          tester.getSize(find.byType(SingleChildScrollView)).height,
          tam.height - arribaDelArea,
        );
        // ...y la primera tarjeta arranca bajo las pestañas: 8 de relleno más
        // lo que ocupa el rótulo dentro de la tarjeta, no un hueco de cientos.
        final rotulo = tester.getTopLeft(find.text('Producto perdido')).dy;
        expect(rotulo, lessThan(arribaDelArea + 60));
      });
    }

    testWidgets('sin precio de compra muestra unidades, nunca Q0.00',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_soloSinPrecio()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Q0.00'), findsNothing);
      // En el resumen, en la persona y en la etiqueta de la cancelación.
      expect(find.text('6 u'), findsWidgets);
      expect(find.text('Merma 6 u'), findsOneWidget);
      // Y el aviso que explica por qué no es dinero.
      expect(find.textContaining('no es que valgan cero'), findsOneWidget);
    });

    testWidgets('con muchas cancelaciones se ven 20 y el resto se pide',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteConMuchas(25)));
      await tester.pumpAndSettle();

      expect(find.text('25 de 25'), findsOneWidget);
      await bajarHasta(tester, find.text('Ver las otras 5 cancelaciones'));
      expect(find.text('Mesa 19 · #19'), findsOneWidget);
      expect(find.text('Mesa 24 · #24'), findsNothing);
      await tocar(tester, find.text('Ver las otras 5 cancelaciones'));
      await bajarHasta(tester, find.text('Mesa 24 · #24'));
    });
  });

  group('el resumen', () {
    testWidgets('el titular es el precio de venta, porque incluye lo que no tiene receta',
        (tester) async {
      // El costo de ingredientes deja fuera a los productos sin receta: no
      // generan movimiento, así que un Taco de Q50 declarado basura no
      // aparecía en NINGÚN número del reporte. En septiembre de 2026 eso fue
      // 12 de 22 productos perdidos en Santa Rosalía.
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      // El número grande es el precio de venta, no el costo.
      expect(find.text('Q205.00'), findsOneWidget);
      expect(find.text('A precio de venta, lo que se declaró perdido'),
          findsOneWidget);
      // El costo sigue estando, para poder comparar.
      expect(
          find.textContaining(
              'Costo de los ingredientes de lo anulado: Q172.50, de los que se perdieron Q44.00.'),
          findsOneWidget);
      // Se dice cuánto de eso es invisible para el resto del reporte.
      expect(find.textContaining('sin receta: no bajan inventario'),
          findsOneWidget);
    });

    testWidgets('dice cuánto valía todo lo anulado y en cuántos pedidos',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      expect(find.text('Valor cancelado'), findsOneWidget);
      expect(find.text('Q645.00'), findsOneWidget);
      expect(find.text('6 pedidos a precio de venta'), findsOneWidget);
    });

    testWidgets('el porcentaje de la casa es en artículos', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      // 3 de 5 artículos con pregunta de despensa.
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('3 de 5 artículos con pregunta de despensa'), findsOneWidget);
    });

    testWidgets('sin poder leer los pedidos, el valor es un guion y no Q0.00',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_sinPedidos()));
      await tester.pumpAndSettle();

      expect(find.text('Sin el precio de esos pedidos'), findsOneWidget);
      expect(find.text('Q0.00'), findsNothing);
      // En la lista tampoco inventa un valor.
      await bajarHasta(tester, find.text('Cancelaciones'));
      expect(find.text('Venta Q0.00'), findsNothing);
    });

    testWidgets('si a alguna cancelación le falta el precio, lo avisa',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto(conUnaSinPrecio: true)));
      await tester.pumpAndSettle();

      expect(find.text('Sin precio: 1 cancelación de la lista'), findsOneWidget);
    });
  });

  group('los avisos', () {
    testWidgets('señalan a quien destaca, los pedidos sin receta y las pruebas',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      // Carlos marcó 3 de 3 artículos como perdidos; la casa, 60%.
      expect(
        find.textContaining(
            'declaró 3 de 3 artículos como perdidos en 2 cancelaciones: 100% no regresó (promedio de la casa 60%)',
            findRichText: true),
        findsOneWidget,
      );
      // El pedido de Nachos y el de las nueve cosas: 10 productos distintos.
      expect(find.textContaining('2 pedidos sin receta (10 productos)', findRichText: true),
          findsOneWidget);
      expect(
        find.textContaining('1 cancelación de prueba por Q360.00', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('quien perdió pocos artículos no sale señalado', (tester) async {
      tamano(tester, const Size(360, 640));
      // Perdió 2 de 3: son menos de tres, mala suerte y no un patrón.
      await tester.pumpWidget(wrap(_reporteCompleto(carlosPierde: 2)));
      await tester.pumpAndSettle();

      expect(find.textContaining('como perdidos en', findRichText: true), findsNothing);
      expect(find.text('Ver sus cancelaciones'), findsNothing);
    });

    testWidgets('"aprueba" no es una prueba', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto(motivoDePrueba: 'El cliente no aprueba el platillo')));
      await tester.pumpAndSettle();

      expect(find.textContaining('de prueba', findRichText: true), findsNothing);
      expect(find.textContaining('inflan este reporte', findRichText: true), findsNothing);
    });

    testWidgets('sin nada que avisar no deja huecos', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteTranquilo()));
      await tester.pumpAndSettle();

      expect(find.text('Ver cuáles'), findsNothing);
      expect(find.text('Ver sus cancelaciones'), findsNothing);
      expect(find.text('Cancelaciones'), findsOneWidget);
    });

    testWidgets('avisan cuando la consulta se quedó corta', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto(truncado: true)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hay más movimientos de los que se pueden leer'),
          findsOneWidget);
    });
  });

  group('los filtros', () {
    testWidgets('Merma deja solo lo que se declaró perdido', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('6 de 6'));
      await tocar(tester, find.widgetWithText(InkWell, 'Merma'));

      expect(find.text('2 de 6'), findsOneWidget);
    });

    testWidgets('Sin receta y No llegó a cocina son botones aparte', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await tocar(tester, find.widgetWithText(InkWell, 'Sin receta'));
      expect(find.text('2 de 6'), findsOneWidget);

      await tocar(tester, find.widgetWithText(InkWell, 'No llegó a cocina'));
      expect(find.text('1 de 6'), findsOneWidget);
    });

    testWidgets('el botón de un estado que nunca pasó no se ofrece', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteTranquilo()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InkWell, 'Merma'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Sin receta'), findsNothing);
      expect(find.widgetWithText(InkWell, 'No llegó a cocina'), findsNothing);
    });

    testWidgets('tocar a una persona deja sus cancelaciones, y se quita', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await tocar(tester, find.widgetWithText(InkWell, 'Carlos Pérez'));
      expect(find.text('2 de 6'), findsOneWidget);
      // El filtro queda a la vista, con su equis para quitarlo.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tocar(tester, find.byIcon(Icons.close_rounded));
      expect(find.text('6 de 6'), findsOneWidget);
    });

    testWidgets('"Ver sus cancelaciones" filtra por la persona señalada', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await tocar(tester, find.text('Ver sus cancelaciones'));
      expect(find.text('2 de 6'), findsOneWidget);
    });

    testWidgets('"Ver cuáles" y "Ver" filtran los pedidos sin receta y las pruebas',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await tocar(tester, find.text('Ver cuáles'));
      expect(find.text('2 de 6'), findsOneWidget);

      // Cada aviso reemplaza el filtro anterior: solo la prueba, con su equis.
      await tocar(tester, find.text('Ver'));
      expect(find.text('1 de 6'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('quien ya no está en el reporte nuevo no deja la lista vacía',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();
      await tocar(tester, find.widgetWithText(InkWell, 'Carlos Pérez'));
      expect(find.text('2 de 6'), findsOneWidget);

      // Otro período: Carlos ya no aparece.
      await tester.pumpWidget(wrap(_reporteConMuchas(3)));
      await tester.pumpAndSettle();
      expect(find.text('3 de 3'), findsOneWidget);
    });
  });

  group('las cancelaciones', () {
    testWidgets('cada una trae su mesa, quién, motivo, valor y qué pasó con el inventario',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('Mesa 2 · #E04'));
      expect(find.text('Venta Q80.00'), findsOneWidget);
      expect(find.text('Merma Q28.00'), findsOneWidget);
      expect(find.text('Cliente se fue'), findsWidgets);
      // Parte regresó y parte se perdió: las dos etiquetas.
      await bajarHasta(tester, find.text('Para llevar · #K02'));
      // En la etiqueta de la cancelación y en lo que regresó de María.
      expect(find.text('Regresó Q31.00'), findsNWidgets(2));
      expect(find.text('Sin receta'), findsWidgets);
      expect(find.text('No llegó a cocina'), findsWidgets);
    });

    testWidgets('con varios renglones, el perdido lo dice', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('Mesa 2 · #E04'));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText() == 'Hamburguesa clásica  perdido'),
        findsOneWidget,
      );
    });

    testWidgets('un pedido largo muestra tres platillos y "+ N más"', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('+ 6 más'));
      expect(find.textContaining('Pie de Limón', findRichText: true), findsNothing);

      await tocar(tester, find.text('+ 6 más'));
      expect(find.textContaining('Pie de Limón', findRichText: true), findsOneWidget);
      expect(find.text('Ver menos'), findsOneWidget);
    });

    testWidgets('sin motivo anotado lo marca', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('Sin motivo anotado').last);
      expect(find.text('Sin motivo anotado'), findsWidgets);
    });

    testWidgets('"¿Por qué se cancela?" junta el mismo motivo escrito distinto',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteConMotivosRepetidos()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('¿Por qué se cancela?'));
      // Tres escritos distinto, una sola fila (cada fila lleva su globo).
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      // En el motivo y en el "Valor cancelado" del resumen.
      expect(find.text('Q150.00'), findsNWidgets(2));
    });
  });

  group('lo que cerró la verificación', () {
    testWidgets('filtrar por quien firmó solo un renglón encuentra el pedido', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteConCoautor()));
      await tester.pumpAndSettle();

      // En la fila de Beto dice "1 cancelación"; al tocarla tiene que haber una.
      await tocar(tester, find.widgetWithText(InkWell, 'Beto'));
      expect(find.text('1 de 2'), findsOneWidget);
      expect(find.text('No hay cancelaciones con este filtro.'), findsNothing);
      // Y la fila dice que él también firmó.
      expect(find.text('Ana, Beto'), findsOneWidget);
    });

    testWidgets('"Todos" quita también a la persona y las pruebas', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await tocar(tester, find.widgetWithText(InkWell, 'Carlos Pérez'));
      expect(find.text('2 de 6'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tocar(tester, find.widgetWithText(InkWell, 'Todos'));
      expect(find.text('6 de 6'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('el porcentaje en rojo pide una muestra de al menos tres artículos',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteDeMuestras()));
      await tester.pumpAndSettle();

      Color? fondoDe(Finder pastilla) {
        final c = tester.widget<Container>(
            find.ancestor(of: pastilla, matching: find.byType(Container)).first);
        return (c.decoration as BoxDecoration).color;
      }

      final pastillas = find.text('100% perdido');
      expect(pastillas, findsNWidgets(2));
      // Carla: 3 de 3, sobre el 50% de la casa. Ana: 1 de 1, mala suerte.
      expect(fondoDe(pastillas.first), CancelColores.badTint);
      expect(fondoDe(pastillas.last), CancelColores.giftTint);
      // Y de cuántos sale cada porcentaje se ve en su fila.
      expect(find.text('3 de 3 artículos perdidos'), findsOneWidget);
      expect(find.text('1 de 1 artículo perdido'), findsOneWidget);
      expect(find.text('0 de 4 artículos perdidos'), findsOneWidget);
    });

    testWidgets('un renglón sin receta que se declaró perdido lo dice en su fila',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteConPerdidoSinReceta()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('Mesa 3 · #T1'));
      // La etiqueta de inventario sola diría "Sin receta" y esos Q50 no
      // tendrían explicación.
      expect(find.text('Declarado perdido'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == 'Taco de camarón  perdido'),
        findsOneWidget,
      );
      // El botón de merma lo incluye: es lo que se declaró perdido.
      await tocar(tester, find.widgetWithText(InkWell, 'Merma'));
      expect(find.text('1 de 2'), findsOneWidget);
    });

    testWidgets('quien declaró solo productos sin receta no aparece con un guion de merma',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_conDeclaranteSinCosto()));
      await tester.pumpAndSettle();

      // Perdió 1 de 1 pero sin costo: "—" diría que no declaró nada.
      await bajarHasta(tester, find.text('¿Quién declara merma?'));
      expect(find.text('sin costo'), findsOneWidget);
      expect(find.text('1 de 1 artículo perdido'), findsOneWidget);
      expect(find.textContaining('Q0.00'), findsNothing);
      // Y su fila dice quién la anuló y por qué.
      await bajarHasta(tester, find.text('Mesa 8 · #S1'));
      expect(find.text('Luis'), findsWidgets);
      expect(find.text('Se cayó'), findsWidgets);
      expect(find.text('Declarado perdido'), findsOneWidget);
    });

    testWidgets('las pruebas se reconocen con número o guion bajo pegado', (tester) async {
      tamano(tester, const Size(360, 640));
      for (final motivo in ['prueba_3', 'Prueba2', 'PRUEBA', '¡Prueba!']) {
        await tester.pumpWidget(wrap(_reporteCompleto(motivoDePrueba: motivo)));
        await tester.pumpAndSettle();
        expect(find.textContaining('1 cancelación de prueba', findRichText: true), findsOneWidget,
            reason: motivo);
      }
      for (final motivo in ['Se aprueba el cambio', 'Comprueba la cuenta']) {
        await tester.pumpWidget(wrap(_reporteCompleto(motivoDePrueba: motivo)));
        await tester.pumpAndSettle();
        expect(find.textContaining('de prueba', findRichText: true), findsNothing, reason: motivo);
      }
    });

    testWidgets('en la vista de año avisa que no se leyeron los pedidos cobrados',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto(sinCobrados: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining('En la vista de año no se leen los pedidos cobrados'),
          findsOneWidget);

      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();
      expect(find.textContaining('En la vista de año'), findsNothing);
    });

    testWidgets('con montos arriba y la lista vacía, no dice "ninguna cancelación" a secas',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_vacioConMontos()));
      await tester.pumpAndSettle();

      expect(find.text('Valor cancelado'), findsOneWidget);
      expect(find.text('Ninguna cancelación en este periodo.'), findsNothing);
      expect(find.textContaining('La lista no trae filas pero el resumen de arriba sí tiene montos'),
          findsOneWidget);
    });

    testWidgets('con la consulta corta y la lista vacía, dice "en lo que se pudo leer"',
        (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_vacioConMontos(truncado: true)));
      await tester.pumpAndSettle();

      expect(find.text('Ninguna cancelación en lo que se pudo leer de este periodo.'),
          findsOneWidget);
      expect(find.text('Ninguna cancelación en este periodo.'), findsNothing);
    });

    testWidgets('"+ N más" se toca con el dedo (38dp o más)', (tester) async {
      tamano(tester, const Size(360, 640));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('+ 6 más'));
      final alto = tester.getSize(find.widgetWithText(InkWell, '+ 6 más')).height;
      expect(alto, greaterThanOrEqualTo(38));
    });

    testWidgets('un monto de seis cifras con letra grande no se parte en la tabla',
        (tester) async {
      tamano(tester, const Size(1280, 900));
      await tester.pumpWidget(wrap(_conMontoGrande(), escala: 1.3));
      await tester.pumpAndSettle();

      // La última aparición es la de la tabla (la primera es el resumen).
      final monto = find.text('Q123,456.78').last;
      await bajarHasta(tester, monto);
      expect(tester.getSize(monto).height, lessThan(40),
          reason: 'una línea: partido en dos pasaría de 50');
    });
  });

  group('en pantalla ancha', () {
    testWidgets('la lista es una tabla y no desborda a 1280', (tester) async {
      tamano(tester, const Size(1280, 900));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('VALOR VENTA'));
      for (final h in ['HORA', 'MESA · PEDIDO', 'PLATILLOS', 'INVENTARIO', 'QUIÉN · MOTIVO']) {
        expect(find.text(h), findsOneWidget);
      }
      // Una fila de la tabla: sin "Venta" delante, el valor va solo en su columna.
      expect(find.text('Q80.00'), findsWidgets);
      expect(find.text('Venta Q80.00'), findsNothing);
      expect(find.text('15:02'), findsOneWidget);
      expect(find.text('19 nov'), findsWidgets);
    });

    testWidgets('en el borde de 900 tampoco desborda', (tester) async {
      tamano(tester, const Size(900, 800));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('VALOR VENTA'));
      expect(find.text('¿Quién declara merma?'), findsOneWidget);
    });

    testWidgets('una pantalla de tablet (700) usa tarjetas y cabe', (tester) async {
      tamano(tester, const Size(700, 900));
      await tester.pumpWidget(wrap(_reporteCompleto()));
      await tester.pumpAndSettle();

      await bajarHasta(tester, find.text('Mesa 2 · #E04'));
      expect(find.text('VALOR VENTA'), findsNothing);
    });
  });
}

// ── DATOS DE PRUEBA ──────────────────────────────────────────────────────────

const _sinDinero = PartialValue.empty;

CancellationItem _item(
  String name, {
  int qty = 1,
  double? value,
  bool lost = false,
  bool movido = false,
  PartialValue returned = _sinDinero,
  PartialValue wasted = _sinDinero,
}) =>
    CancellationItem(
      itemId: name,
      name: name,
      qty: qty,
      returned: returned,
      wasted: wasted,
      declaredLost: lost,
      value: value,
      movedInventory: movido,
    );

/// La jornada del diseño (cancelados.html), con datos de verdad: seis
/// cancelaciones, una de prueba, dos sin receta, una antes de cocina, dos con
/// merma y una que regresó.
CancellationsReport _reporteCompleto({
  bool truncado = false,
  bool conUnaSinPrecio = false,
  bool sinCobrados = false,
  int carlosPierde = 3,
  String motivoDePrueba = 'Prueba Andrea',
}) {
  final dia = DateTime(2026, 11, 19);
  final nueve = [
    'Chilaquiles con Huevos',
    'Café',
    'Avocado Toast',
    'Chocolate',
    'Panqueques o Waffles',
    'Matcha Latte',
    'Crepas Atlantis',
    'Pastel de Chocolate',
    'Pie de Limón',
  ];

  final eventos = [
    CancellationEvent(
      orderId: 'e11',
      orderLabel: '#E11',
      tableLabel: 'Mesa 4',
      at: dia.add(const Duration(hours: 15, minutes: 2)),
      userName: 'Ana Cosme',
      reason: 'Se tomó la orden en otra cuenta',
      impact: InventoryImpact.sinReceta,
      items: [_item('Nachos Mixtos', value: 55)],
      returned: _sinDinero,
      wasted: _sinDinero,
      value: 55,
    ),
    CancellationEvent(
      orderId: 'e10',
      orderLabel: '#E10',
      tableLabel: 'Mesa 7',
      at: dia.add(const Duration(hours: 14, minutes: 20)),
      userName: 'Ana Cosme',
      reason: motivoDePrueba,
      impact: InventoryImpact.sinReceta,
      items: [for (final n in nueve) _item(n, value: 40)],
      returned: _sinDinero,
      wasted: _sinDinero,
      value: 360,
    ),
    CancellationEvent(
      orderId: 'e04',
      orderLabel: '#E04',
      tableLabel: 'Mesa 2',
      at: dia.add(const Duration(hours: 13, minutes: 5)),
      userName: 'Carlos Pérez',
      reason: 'Cliente se fue',
      impact: InventoryImpact.conMovimiento,
      items: [
        _item('Hamburguesa clásica',
            value: 60, lost: true, movido: true, wasted: const PartialValue(amount: 20)),
        _item('Papas fritas',
            value: 20, lost: true, movido: true, wasted: const PartialValue(amount: 8)),
      ],
      returned: _sinDinero,
      wasted: const PartialValue(amount: 28),
      value: 80,
    ),
    CancellationEvent(
      orderId: 'k02',
      orderLabel: '#K02',
      tableLabel: 'Para llevar',
      at: dia.add(const Duration(hours: 12, minutes: 40)),
      userName: 'María López',
      reason: 'Error al tomar la orden',
      impact: InventoryImpact.conMovimiento,
      items: [
        _item('Licuado de fresa',
            value: 25, movido: true, returned: const PartialValue(amount: 12)),
        _item('Club sándwich',
            value: 50, movido: true, returned: const PartialValue(amount: 19)),
      ],
      returned: const PartialValue(amount: 31),
      wasted: _sinDinero,
      value: conUnaSinPrecio ? null : 75,
    ),
    CancellationEvent(
      orderId: 'e01',
      orderLabel: '#E01',
      tableLabel: 'Mesa 6',
      at: dia.add(const Duration(hours: 11, minutes: 15)),
      userName: 'Carlos Pérez',
      reason: 'Se quemó en cocina',
      impact: InventoryImpact.conMovimiento,
      items: [
        _item('Huevos rancheros',
            value: 45, lost: true, movido: true, wasted: const PartialValue(amount: 16)),
      ],
      returned: _sinDinero,
      wasted: const PartialValue(amount: 16),
      value: 45,
    ),
    CancellationEvent(
      orderId: 'e99',
      orderLabel: '#E99',
      tableLabel: 'Mesa 9',
      at: dia.add(const Duration(hours: 10, minutes: 30)),
      userName: 'María López',
      reason: null,
      impact: InventoryImpact.sinCocina,
      items: [_item('Jugo de naranja', value: 30)],
      returned: _sinDinero,
      wasted: _sinDinero,
      value: 30,
    ),
  ];

  return CancellationsReport(
    events: eventos,
    people: [
      PersonCut(
        userId: 'u2',
        userName: 'Carlos Pérez',
        events: 2,
        itemsCancelled: 3,
        itemsLost: carlosPierde,
        wasted: const PartialValue(amount: 44),
        returned: _sinDinero,
      ),
      const PersonCut(
        userId: 'u3',
        userName: 'María López',
        events: 2,
        itemsCancelled: 2,
        itemsLost: 0,
        wasted: _sinDinero,
        returned: PartialValue(amount: 31),
        eventsWithoutInventory: 1,
      ),
      const PersonCut(
        userId: 'u1',
        userName: 'Ana Cosme',
        events: 2,
        itemsCancelled: 0,
        itemsLost: 0,
        wasted: _sinDinero,
        returned: _sinDinero,
        eventsWithoutInventory: 2,
      ),
    ],
    totalWasted: const PartialValue(amount: 44),
    totalReturned: const PartialValue(amount: 128.5),
    itemsCancelled: 5,
    itemsLost: 3,
    cancelledBeforeKitchen: 1,
    cancelledWithoutRecipe: 2,
    unpricedIngredients: 0,
    saleWaste: const SaleValueWaste(
      amount: 205,
      items: 22,
      withoutRecipeAmount: 50,
      withoutRecipeItems: 12,
    ),
    truncated: truncado,
    // 55 + 360 + 80 + 75 + 45 + 30.
    cancelledValue: 645,
    cancelledValueOrders: 6,
    withoutPaidOrders: sinCobrados,
  );
}

/// Dos cancelaciones que abrió Ana; en la primera, Beto firmó un renglón. En
/// el corte por persona Beto tiene 1 cancelación.
CancellationsReport _reporteConCoautor() {
  CancellationEvent ev(String id, List<String> autores) => CancellationEvent(
        orderId: id,
        orderLabel: '#$id',
        tableLabel: 'Mesa $id',
        at: DateTime(2026, 11, 19, 12),
        userName: 'Ana',
        authors: autores,
        reason: 'Error',
        impact: InventoryImpact.conMovimiento,
        items: [
          _item('Café', value: 22, movido: true, returned: const PartialValue(amount: 5)),
        ],
        returned: const PartialValue(amount: 5),
        wasted: _sinDinero,
        value: 22,
      );

  return CancellationsReport(
    events: [ev('1', ['Ana', 'Beto']), ev('2', ['Ana'])],
    people: const [
      PersonCut(
        userId: 'u1',
        userName: 'Ana',
        events: 2,
        itemsCancelled: 1,
        itemsLost: 0,
        wasted: _sinDinero,
        returned: PartialValue(amount: 5),
      ),
      PersonCut(
        userId: 'u2',
        userName: 'Beto',
        events: 1,
        itemsCancelled: 1,
        itemsLost: 0,
        wasted: _sinDinero,
        returned: PartialValue(amount: 5),
      ),
    ],
    totalWasted: _sinDinero,
    totalReturned: const PartialValue(amount: 10),
    itemsCancelled: 2,
    itemsLost: 0,
    cancelledBeforeKitchen: 0,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 0,
    saleWaste: SaleValueWaste.empty,
    truncated: false,
    cancelledValue: 44,
    cancelledValueOrders: 2,
  );
}

/// Tres personas con muestras muy distintas: Carla perdió 3 de 3, Ana 1 de 1 y
/// Beto 0 de 4. La casa: 4 de 8 (50%).
CancellationsReport _reporteDeMuestras() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 'x',
          orderLabel: '#x',
          tableLabel: 'Mesa 1',
          at: DateTime(2026, 11, 19, 12),
          userName: 'Carla',
          reason: 'Error',
          impact: InventoryImpact.conMovimiento,
          items: [
            _item('Café', value: 22, lost: true, movido: true, wasted: const PartialValue(amount: 5)),
          ],
          returned: _sinDinero,
          wasted: const PartialValue(amount: 5),
          value: 22,
        ),
      ],
      people: const [
        PersonCut(
          userId: 'c',
          userName: 'Carla',
          events: 3,
          itemsCancelled: 3,
          itemsLost: 3,
          wasted: PartialValue(amount: 15),
          returned: _sinDinero,
        ),
        PersonCut(
          userId: 'a',
          userName: 'Ana',
          events: 1,
          itemsCancelled: 1,
          itemsLost: 1,
          wasted: PartialValue(amount: 5),
          returned: _sinDinero,
        ),
        PersonCut(
          userId: 'b',
          userName: 'Beto',
          events: 2,
          itemsCancelled: 4,
          itemsLost: 0,
          wasted: _sinDinero,
          returned: PartialValue(amount: 20),
        ),
      ],
      totalWasted: const PartialValue(amount: 20),
      totalReturned: const PartialValue(amount: 20),
      itemsCancelled: 8,
      itemsLost: 4,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: const SaleValueWaste(
        amount: 88,
        items: 4,
        withoutRecipeAmount: 0,
        withoutRecipeItems: 0,
      ),
      truncated: false,
      cancelledValue: 200,
      cancelledValueOrders: 6,
    );

/// Un taco sin receta que se declaró perdido (no hay costo que poner) y otra
/// cancelación que sí regresó.
CancellationsReport _reporteConPerdidoSinReceta() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 't1',
          orderLabel: '#T1',
          tableLabel: 'Mesa 3',
          at: DateTime(2026, 11, 19, 13),
          userName: 'Ana',
          reason: 'Se cayó',
          impact: InventoryImpact.sinReceta,
          items: [_item('Taco de camarón', value: 50, lost: true)],
          returned: _sinDinero,
          wasted: _sinDinero,
          value: 50,
        ),
        CancellationEvent(
          orderId: 't2',
          orderLabel: '#T2',
          tableLabel: 'Mesa 4',
          at: DateTime(2026, 11, 19, 12),
          userName: 'Ana',
          reason: 'Error',
          impact: InventoryImpact.conMovimiento,
          items: [
            _item('Café', value: 22, movido: true, returned: const PartialValue(amount: 5)),
          ],
          returned: const PartialValue(amount: 5),
          wasted: _sinDinero,
          value: 22,
        ),
      ],
      people: const [
        PersonCut(
          userId: 'u1',
          userName: 'Ana',
          events: 2,
          itemsCancelled: 1,
          itemsLost: 0,
          wasted: _sinDinero,
          returned: PartialValue(amount: 5),
          eventsWithoutInventory: 1,
        ),
      ],
      totalWasted: _sinDinero,
      totalReturned: const PartialValue(amount: 5),
      itemsCancelled: 1,
      itemsLost: 0,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 1,
      unpricedIngredients: 0,
      saleWaste: const SaleValueWaste(
        amount: 50,
        items: 1,
        withoutRecipeAmount: 50,
        withoutRecipeItems: 1,
      ),
      truncated: false,
      cancelledValue: 72,
      cancelledValueOrders: 2,
    );

/// Nada en la lista, pero el resumen trae montos: un producto sin receta
/// anulado en un pedido ya cobrado no tiene fila.
CancellationsReport _vacioConMontos({bool truncado = false}) => CancellationsReport(
      events: const [],
      people: const [],
      totalWasted: _sinDinero,
      totalReturned: _sinDinero,
      itemsCancelled: 0,
      itemsLost: 0,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: const SaleValueWaste(
        amount: 50,
        items: 1,
        withoutRecipeAmount: 50,
        withoutRecipeItems: 1,
      ),
      truncated: truncado,
      cancelledValue: 50,
      cancelledValueOrders: 1,
    );

/// Un producto sin receta que Luis anuló en un pedido ya cobrado y declaró
/// perdido: no hay costo que poner, pero la fila y la persona sí existen.
CancellationsReport _conDeclaranteSinCosto() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 's1',
          orderLabel: '#S1',
          tableLabel: 'Mesa 8',
          at: DateTime(2026, 11, 19, 14),
          userName: 'Luis',
          authors: const ['Luis'],
          reason: 'Se cayó',
          impact: InventoryImpact.sinReceta,
          items: [
            const CancellationItem(
              itemId: 't1',
              name: 'Taco de camarón',
              qty: 1,
              returned: PartialValue.empty,
              wasted: PartialValue.empty,
              declaredLost: true,
              value: 50,
              movedInventory: false,
              asked: true,
            ),
          ],
          returned: _sinDinero,
          wasted: _sinDinero,
          value: 50,
        ),
      ],
      people: const [
        PersonCut(
          userId: 'u7',
          userName: 'Luis',
          events: 1,
          itemsCancelled: 1,
          itemsLost: 1,
          wasted: _sinDinero,
          returned: _sinDinero,
          eventsWithoutInventory: 1,
        ),
      ],
      totalWasted: _sinDinero,
      totalReturned: _sinDinero,
      itemsCancelled: 1,
      itemsLost: 1,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 1,
      unpricedIngredients: 0,
      saleWaste: const SaleValueWaste(
        amount: 50,
        items: 1,
        withoutRecipeAmount: 50,
        withoutRecipeItems: 1,
      ),
      truncated: false,
      cancelledValue: 50,
      cancelledValueOrders: 1,
    );

/// Un monto de seis cifras y letra grande: no debe partirse en dos líneas.
CancellationsReport _conMontoGrande() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 'g1',
          orderLabel: '#G1',
          tableLabel: 'Mesa 1',
          at: DateTime(2026, 11, 19, 12),
          userName: 'Ana',
          reason: 'Evento',
          impact: InventoryImpact.conMovimiento,
          items: [
            _item('Banquete', value: 123456.78, movido: true, returned: const PartialValue(amount: 5)),
          ],
          returned: const PartialValue(amount: 5),
          wasted: _sinDinero,
          value: 123456.78,
        ),
      ],
      people: const [
        PersonCut(
          userId: 'u1',
          userName: 'Ana',
          events: 1,
          itemsCancelled: 1,
          itemsLost: 0,
          wasted: _sinDinero,
          returned: PartialValue(amount: 5),
        ),
      ],
      totalWasted: _sinDinero,
      totalReturned: const PartialValue(amount: 5),
      itemsCancelled: 1,
      itemsLost: 0,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: SaleValueWaste.empty,
      truncated: false,
      cancelledValue: 123456.78,
      cancelledValueOrders: 1,
    );

/// Una jornada sin nada raro: una sola cancelación que regresó.
CancellationsReport _reporteTranquilo() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 'a1',
          orderLabel: '#1',
          tableLabel: 'Mesa 1',
          at: DateTime(2026, 11, 19, 9, 30),
          userName: 'María López',
          reason: 'Error al tomar la orden',
          impact: InventoryImpact.conMovimiento,
          items: [
            _item('Licuado de fresa',
                value: 25, movido: true, returned: const PartialValue(amount: 12)),
          ],
          returned: const PartialValue(amount: 12),
          wasted: _sinDinero,
          value: 25,
        ),
      ],
      people: const [
        PersonCut(
          userId: 'u3',
          userName: 'María López',
          events: 1,
          itemsCancelled: 1,
          itemsLost: 0,
          wasted: _sinDinero,
          returned: PartialValue(amount: 12),
        ),
      ],
      totalWasted: _sinDinero,
      totalReturned: const PartialValue(amount: 12),
      itemsCancelled: 1,
      itemsLost: 0,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: SaleValueWaste.empty,
      truncated: false,
      cancelledValue: 25,
      cancelledValueOrders: 1,
    );

/// El caso real de Santa Rosalía: lo que más se devuelve (bebidas) es justo lo
/// que no tiene precio de compra.
CancellationsReport _soloSinPrecio() {
  const wasted = PartialValue(
    unpricedByUnit: {'u': 6},
    unpricedIngredientIds: {'gatorade', 'stella'},
  );

  return CancellationsReport(
    events: [
      CancellationEvent(
        orderId: 'o9',
        orderLabel: '#900',
        tableLabel: 'Mesa 2',
        at: DateTime(2026, 8, 30, 12),
        userName: 'Carla',
        reason: 'Se equivocaron de mesa',
        impact: InventoryImpact.conMovimiento,
        items: [
          _item('Gatorade', qty: 6, value: 84, lost: true, movido: true, wasted: wasted),
        ],
        returned: _sinDinero,
        wasted: wasted,
        value: 84,
      ),
    ],
    people: const [
      PersonCut(
        userId: 'u3',
        userName: 'Carla',
        events: 1,
        itemsCancelled: 1,
        itemsLost: 1,
        wasted: wasted,
        returned: _sinDinero,
      ),
    ],
    totalWasted: wasted,
    totalReturned: _sinDinero,
    itemsCancelled: 1,
    itemsLost: 1,
    cancelledBeforeKitchen: 0,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 2,
    // Aunque NINGÚN ingrediente tenga precio de compra, el precio de venta sí
    // viaja en el pedido: por eso este reporte igual puede decir cuánto dinero
    // se perdió. Es justamente el agujero que la valoración a precio de venta
    // vino a tapar.
    saleWaste: const SaleValueWaste(
      amount: 84,
      items: 2,
      withoutRecipeAmount: 0,
      withoutRecipeItems: 0,
    ),
    truncated: false,
    cancelledValue: 84,
    cancelledValueOrders: 1,
  );
}

/// Vista de año: hay cancelaciones pero no se pudo leer ningún pedido, así que
/// no se sabe cuánto valían.
CancellationsReport _sinPedidos() => CancellationsReport(
      events: [
        CancellationEvent(
          orderId: 'zz9',
          orderLabel: '…zz9ab',
          tableLabel: '—',
          at: DateTime(2026, 3, 2, 18, 0),
          userName: 'Carla',
          reason: 'Se equivocaron de mesa',
          impact: InventoryImpact.conMovimiento,
          items: [
            _item('Gatorade',
                qty: 2, lost: true, movido: true, wasted: const PartialValue(amount: 10)),
          ],
          returned: _sinDinero,
          wasted: const PartialValue(amount: 10),
        ),
      ],
      people: const [
        PersonCut(
          userId: 'u3',
          userName: 'Carla',
          events: 1,
          itemsCancelled: 1,
          itemsLost: 1,
          wasted: PartialValue(amount: 10),
          returned: _sinDinero,
        ),
      ],
      totalWasted: const PartialValue(amount: 10),
      totalReturned: _sinDinero,
      itemsCancelled: 1,
      itemsLost: 1,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: SaleValueWaste.empty,
      truncated: false,
    );

/// [n] cancelaciones de Ana, de la más reciente a la más vieja.
CancellationsReport _reporteConMuchas(int n) => CancellationsReport(
      events: [
        for (var i = 0; i < n; i++)
          CancellationEvent(
            orderId: 'm$i',
            orderLabel: '#$i',
            tableLabel: 'Mesa $i',
            at: DateTime(2026, 11, 19, 20).subtract(Duration(minutes: 10 * i)),
            userName: 'Ana',
            reason: 'Error $i',
            impact: InventoryImpact.conMovimiento,
            items: [
              _item('Café', value: 22, movido: true, returned: const PartialValue(amount: 5)),
            ],
            returned: const PartialValue(amount: 5),
            wasted: _sinDinero,
            value: 22,
          ),
      ],
      people: [
        PersonCut(
          userId: 'u1',
          userName: 'Ana',
          events: n,
          itemsCancelled: n,
          itemsLost: 0,
          wasted: _sinDinero,
          returned: const PartialValue(amount: 5),
        ),
      ],
      totalWasted: _sinDinero,
      totalReturned: PartialValue(amount: 5.0 * n),
      itemsCancelled: n,
      itemsLost: 0,
      cancelledBeforeKitchen: 0,
      cancelledWithoutRecipe: 0,
      unpricedIngredients: 0,
      saleWaste: SaleValueWaste.empty,
      truncated: false,
      cancelledValue: 22.0 * n,
      cancelledValueOrders: n,
    );

/// El mismo motivo escrito de tres maneras ("Cliente se fue", "cliente se fue ",
/// "CLIENTE  SE FUE"): es uno solo.
CancellationsReport _reporteConMotivosRepetidos() {
  CancellationEvent ev(String id, String motivo) => CancellationEvent(
        orderId: id,
        orderLabel: '#$id',
        tableLabel: 'Mesa 1',
        at: DateTime(2026, 11, 19, 12),
        userName: 'Ana',
        reason: motivo,
        impact: InventoryImpact.conMovimiento,
        items: [
          _item('Café', value: 50, movido: true, returned: const PartialValue(amount: 5)),
        ],
        returned: const PartialValue(amount: 5),
        wasted: _sinDinero,
        value: 50,
      );

  return CancellationsReport(
    events: [
      ev('a', 'Cliente se fue'),
      ev('b', 'cliente se fue '),
      ev('c', 'CLIENTE  SE FUE'),
    ],
    people: const [
      PersonCut(
        userId: 'u1',
        userName: 'Ana',
        events: 3,
        itemsCancelled: 3,
        itemsLost: 0,
        wasted: _sinDinero,
        returned: PartialValue(amount: 15),
      ),
    ],
    totalWasted: _sinDinero,
    totalReturned: const PartialValue(amount: 15),
    itemsCancelled: 3,
    itemsLost: 0,
    cancelledBeforeKitchen: 0,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 0,
    saleWaste: SaleValueWaste.empty,
    truncated: false,
    cancelledValue: 150,
    cancelledValueOrders: 3,
  );
}
