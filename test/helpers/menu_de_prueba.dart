import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/utils/date_range.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/data/models/profitability_data.dart';
import 'package:saborpro_reports/presentation/widgets/dish_profit_widgets.dart';

/// Un menú con todo lo que complica la pantalla: nombres largos, montos de
/// miles, un platillo que pierde, uno con margen sospechoso, incompletos con
/// listas largas de ingredientes, sin receta, duplicados y unidades distintas.
MenuCrudo menuDificil() {
  ProductoMenu prod(String id, String nombre, Map<String, double> pres) =>
      ProductoMenu(id: id, nombre: nombre, presentaciones: [
        for (final e in pres.entries)
          PresentacionMenu(id: '$id-${e.key}', nombre: e.key, precio: e.value)
      ]);
  IngredienteCosto ing(String id, String nombre, double? precio,
          {String unidad = 'unidades', String suc = 's1'}) =>
      IngredienteCosto(
          id: id, nombre: nombre, sucursalId: suc, unidad: unidad, precio: precio);
  var n = 0;
  LineaReceta l(String prod, String pres, String ing, double q,
          {String? doc}) =>
      LineaReceta(
          docId: doc ?? 'r${n++}',
          productoId: prod,
          presentacionId: '$prod-$pres',
          ingredienteId: ing,
          cantidad: q);

  return MenuCrudo(
    productos: [
      prod('ham', 'Hamburguesa Clásica', {'Normal': 50}),
      prod('pizza', 'Pizza Familiar Especial de la Casa con Todos los Ingredientes',
          {'Mediana de ocho porciones': 120, 'Familiar de doce porciones': 1250}),
      prod('filete', 'Filete de Pechuga a la Barbacoa', {'Normal': 90}),
      prod('cafe', 'Café Americano', {'Normal': 25}),
      prod('ens', 'Ensalada César', {'Normal': 45}),
      prod('taco', 'Tacos al Pastor', {'Normal': 40}),
      prod('sopa', 'Sopa del Día', {'Normal': 30}),
      prod('licuado', 'Licuado de Fresa', {'Normal': 22}),
      prod('postre', 'Pastel de Chocolate', {'Normal': 35}),
      prod('lomo',
          'Lomito Encebollado con Arroz, Frijoles, Ensalada y Tortillas',
          {'Normal': 85}),
      prod('refresco', 'Refresco en Lata', {'Normal': 15}),
    ],
    ingredientes: [
      ing('pan', 'Pan', 3),
      ing('carne', 'Carne', 12),
      ing('masa', 'Masa', 8),
      ing('queso', 'Queso mozzarella importado de primera calidad', null),
      ing('salsa', 'Salsa de tomate artesanal de la casa', null),
      ing('pollo', 'Pollo', 648),
      ing('grano', 'Café en grano', 0.4),
      ing('lechuga', 'Lechuga', 6),
      ing('tortilla', 'Tortilla', 0.5),
      ing('cerdo', 'Cerdo', 20),
      ing('verdura', 'Verdura', 18), // Sopa: cada venta pierde
      ing('fresa', 'Fresa', 15), // Licuado: no cubre su parte de los fijos
      ing('choco', 'Chocolate', 9),
      ing('res', 'Lomito de res', 0.12, unidad: 'gramos'),
      ing('jamon', 'Jamón de pavo', 30),
    ],
    recetas: [
      l('ham', 'Normal', 'pan', 1),
      l('ham', 'Normal', 'carne', 1),
      l('pizza', 'Mediana de ocho porciones', 'masa', 1),
      l('pizza', 'Mediana de ocho porciones', 'queso', 1),
      l('pizza', 'Mediana de ocho porciones', 'salsa', 1),
      l('pizza', 'Familiar de doce porciones', 'masa', 2),
      l('pizza', 'Familiar de doce porciones', 'jamon', 10),
      l('filete', 'Normal', 'pollo', 1),
      l('cafe', 'Normal', 'grano', 1),
      l('ens', 'Normal', 'lechuga', 2, doc: 'a'),
      l('ens', 'Normal', 'lechuga', 2, doc: 'z'), // duplicada
      l('taco', 'Normal', 'tortilla', 3),
      l('taco', 'Normal', 'cerdo', 0.5),
      l('sopa', 'Normal', 'verdura', 1.5),
      l('licuado', 'Normal', 'fresa', 1),
      l('postre', 'Normal', 'choco', 1.25),
      l('lomo', 'Normal', 'res', 200),
    ],
    sucursalesVendibles: {'s1'},
  );
}

/// Octubre cerrado, con descuentos, gastos de comida que no se reparten y
/// gastos fijos y variables.
RepartoGastos repartoDeOctubre({double ventas = 100000}) => RepartoGastos.desde(
      datos: ProfitabilityData(
        netSales: ventas,
        cogs: 0,
        itemsSinCosto: 0,
        itemsConCosto: 0,
        expenses: const [
          ExpenseLine(
              categoryId: 'renta', label: 'Renta', amount: 15000, esFijo: true),
          ExpenseLine(
              categoryId: 'salarios',
              label: 'Sueldos',
              amount: 10000,
              esFijo: true),
          ExpenseLine(categoryId: 'gas', label: 'Gas', amount: 13000),
          ExpenseLine(categoryId: 'insumos', label: 'Insumos', amount: 9000),
        ],
        payroll: 10000,
        paidFromCash: 0,
        purchases: 0,
        inventoryValue: 0,
        ingredientesSinPrecio: 0,
      ),
      rango: DateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
        mode: PeriodMode.month,
      ),
      gastosLeidos: true,
      descuentos: 3000,
      hoy: DateTime(2026, 11, 5),
    );

UtilidadMenu utilidadDificil({RepartoGastos? reparto, bool conReparto = true}) =>
    UtilidadMenu.armar(
      calcularMargenes(menuDificil()),
      reparto: conReparto ? (reparto ?? repartoDeOctubre()) : null,
    );

/// Pinta [hijo] en un teléfono de [ancho] dp con la letra del sistema a
/// [escala].
Future<void> pintarEnTelefono(
  WidgetTester tester,
  Widget hijo, {
  double ancho = 360,
  double alto = 800,
  double escala = 1.0,
  bool asentar = true,
}) async {
  tester.view.physicalSize = Size(ancho, alto);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(ancho, alto),
        textScaler: TextScaler.linear(escala),
      ),
      child: Scaffold(backgroundColor: kFondo, body: hijo),
    ),
  ));
  if (asentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
