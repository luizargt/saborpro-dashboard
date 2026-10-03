import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/menu_margin_data.dart';
import 'package:saborpro_reports/presentation/providers/menu_margin_provider.dart';

/// El provider de Utilidad por platillo, sin Firebase.
///
/// Lo frágil de un reporte así no es la cuenta, es la carga: sin red decía
/// "no hay platillos", y salir de la pantalla a media descarga avisaba a un
/// provider ya liberado.

/// Una fuente que responde cuando la prueba quiere.
class FuenteFalsa implements FuenteMenu {
  final pedidos = <String>[];
  final _pendientes = <Completer<MenuDescargado>>[];

  @override
  Future<MenuDescargado> descargar(String tenantId) {
    pedidos.add(tenantId);
    final c = Completer<MenuDescargado>();
    _pendientes.add(c);
    return c.future;
  }

  void responder(MenuDescargado m, {int indice = 0}) =>
      _pendientes[indice].complete(m);

  void fallar(Object e, {int indice = 0}) =>
      _pendientes[indice].completeError(e);
}

MenuDescargado menuDe(String nombre, {String sucursal = 's1'}) =>
    MenuDescargado(
      productos: [
        DocCrudo('p1', {
          'name': nombre,
          'presentations': [
            {'id': 'pr1', 'name': 'Normal', 'price': 50},
          ],
        }),
      ],
      recetas: const [
        DocCrudo('r1', {
          'productId': 'p1',
          'presentationId': 'pr1',
          'ingredientId': 'a1',
          'masterIngredientId': 'M',
          'quantity': 1,
        }),
      ],
      ingredientes: [
        const DocCrudo('a1', {
          'name': 'Pollo',
          'location_id': 's1',
          'masterIngredientId': 'M',
          'lastPurchasePrice': 10,
        }),
        const DocCrudo('a2', {
          'name': 'Pollo',
          'location_id': 's2',
          'masterIngredientId': 'M',
          'lastPurchasePrice': 14,
        }),
      ],
      sucursales: [
        DocCrudo(sucursal, const {}),
        const DocCrudo('s2', {}),
      ],
    );

Future<void> vaciarMicrotareas() => Future<void>.delayed(Duration.zero);

void main() {
  test('dos llamadas seguidas hacen UNA descarga', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    p.cargarSiHaceFalta('t1');
    expect(f.pedidos, ['t1']);
    expect(p.cargando, isTrue);
    expect(p.listo, isFalse);

    f.responder(menuDe('Hamburguesa'));
    await vaciarMicrotareas();
    expect(p.listo, isTrue);
    expect(p.cargando, isFalse);
    p.cargarSiHaceFalta('t1');
    expect(f.pedidos, ['t1'], reason: 'ya está cargado: no se vuelve a pedir');
  });

  test('cambiar de sucursal recalcula en memoria, sin descargar', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    f.responder(menuDe('Hamburguesa'));
    await vaciarMicrotareas();

    expect(p.platillosPara('s1')!.single.costo, 1000);
    expect(p.platillosPara('s2')!.single.costo, 1400);
    expect(f.pedidos, hasLength(1));
  });

  test('sin red dice "sin conexión", nunca "no hay platillos"', () async {
    for (final e in [
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      TimeoutException('lento'),
    ]) {
      final f = FuenteFalsa();
      final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
      p.cargarSiHaceFalta('t1');
      f.fallar(e);
      await vaciarMicrotareas();
      expect(p.listo, isFalse);
      expect(p.platillosPara(null), isNull,
          reason: 'sin menú no hay lista vacía que mostrar');
      expect(p.error, contains('Sin conexión'));
    }
  });

  test('sin permiso lo dice con sus palabras', () {
    expect(
        mensajeDeError(FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied')),
        contains('permiso'));
  });

  test('tras un fallo no reintenta solo; "Reintentar" sí', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    f.fallar(StateError('x'));
    await vaciarMicrotareas();

    p.cargarSiHaceFalta('t1'); // lo que haría cada reconstrucción
    expect(f.pedidos, hasLength(1), reason: 'sin esto entraría en bucle');

    p.recargar();
    expect(f.pedidos, hasLength(2));
    expect(p.error, isNull);
    f.responder(menuDe('Hamburguesa'), indice: 1);
    await vaciarMicrotareas();
    expect(p.listo, isTrue);
  });

  test('recargar deja la lista anterior a la vista mientras llega la nueva',
      () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    f.responder(menuDe('Vieja'));
    await vaciarMicrotareas();

    p.recargar();
    expect(p.refrescando, isTrue);
    expect(p.listo, isTrue);
    expect(p.platillosPara(null)!.single.producto, 'Vieja');

    f.responder(menuDe('Nueva'), indice: 1);
    await vaciarMicrotareas();
    expect(p.refrescando, isFalse);
    expect(p.platillosPara(null)!.single.producto, 'Nueva');
  });

  test('si recargar falla, se queda con lo anterior y avisa', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    f.responder(menuDe('Vieja'));
    await vaciarMicrotareas();

    p.recargar();
    f.fallar(TimeoutException('x'), indice: 1);
    await vaciarMicrotareas();
    expect(p.listo, isTrue);
    expect(p.platillosPara(null)!.single.producto, 'Vieja');
    expect(p.error, isNotNull);
  });

  test('salir de la pantalla con la descarga en vuelo no revienta', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    p.dispose();
    f.responder(menuDe('Hamburguesa'));
    await vaciarMicrotareas(); // en debug, avisar tras dispose lanza
  });

  test('otro negocio a media descarga no mezcla los datos', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('negocioA');
    p.cargarSiHaceFalta('negocioB');
    expect(f.pedidos, ['negocioA', 'negocioB']);

    f.responder(menuDe('De B'), indice: 1);
    await vaciarMicrotareas();
    f.responder(menuDe('De A'), indice: 0); // llega tarde
    await vaciarMicrotareas();
    expect(p.platillosPara(null)!.single.producto, 'De B');
  });

  test('respeta las sucursales asignadas al usuario', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {'s2'});
    p.cargarSiHaceFalta('t1');
    f.responder(menuDe('Hamburguesa'));
    await vaciarMicrotareas();
    // En "Todas", el ingrediente de la receta es de s1, que no ve.
    expect(p.platillosPara(null)!.single.estado, EstadoCosto.incompleto);
    expect(p.platillosPara('s2')!.single.costo, 1400);
  });

  test('un precio de sucursal sin monto no cuenta como ilegible', () async {
    final f = FuenteFalsa();
    final p = MenuMarginProvider(fuente: f, sucursalesPermitidas: () => {});
    p.cargarSiHaceFalta('t1');
    f.responder(const MenuDescargado(
      preciosSucursal: [DocCrudo('x', {'presentation_id': 'a', 'location_id': 's'})],
    ));
    await vaciarMicrotareas();
    expect(p.descartados, 0, reason: 'un precio vacío no es un error');
  });
}
