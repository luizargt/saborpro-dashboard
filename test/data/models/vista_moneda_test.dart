// test/data/models/vista_moneda_test.dart
//
// En qué moneda se ve cada vista: una moneda sola se suma tal cual (en la
// suya si el dueño lo prefiere o si no hay tipo de cambio); varias se
// convierten siempre a la principal y la que no tiene tipo de cambio queda
// fuera, nunca sumada sin convertir.

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/location_service.dart';
import 'package:saborpro_reports/data/models/config_moneda.dart';
import 'package:saborpro_reports/data/models/vista_moneda.dart';

final _reforma = LocationModel(id: 'reforma', name: 'La Reforma', currencySymbol: 'Q');
final _zacapa = LocationModel(id: 'zacapa', name: 'Zacapa', currencySymbol: 'Q');
final _palermo =
    LocationModel(id: 'palermo', name: 'Palermo', currencySymbol: '\$', country: 'Argentina');

final _conTasa = const ConfigMoneda(principal: 'GTQ')
    .conTasa('ARS', TasaCambio(desde: DateTime(2026, 1, 1), valor: 125));

VistaMoneda _vista({
  String? seleccionada,
  ConfigMoneda config = ConfigMoneda.vacia,
  bool verEnLocal = false,
  List<LocationModel>? sucursales,
}) =>
    VistaMoneda(
      sucursales: sucursales ?? [_palermo, _reforma, _zacapa],
      seleccionada: seleccionada,
      config: config,
      verEnLocal: verEnLocal,
    );

void main() {
  test('una sola moneda: nada cambia respecto de antes', () {
    final v = _vista(sucursales: [_reforma, _zacapa]);
    expect(v.principal, 'GTQ');
    expect(v.hayOtraMoneda, isFalse);
    expect(v.convierte, isFalse);
    expect(v.factorDe('reforma', DateTime(2026, 5, 1)), 1);
    expect(v.firma, 'local');
    expect(v.firmaMes(2026, 5), '', reason: 'los resúmenes de siempre, sin firma');
    expect(v.enMoneda, isNull);
  });

  test('sin elegir, la principal es la que más sucursales usan', () {
    expect(_vista().principal, 'GTQ');
  });

  test('"Todas" con tipo de cambio: convierte cada venta a la principal', () {
    final v = _vista(config: _conTasa);
    expect(v.convierte, isTrue);
    expect(v.codigoVista, 'GTQ');
    expect(v.sinTasa, isEmpty);
    expect(v.factorDe('palermo', DateTime(2026, 5, 1)), closeTo(1 / 125, 1e-12));
    expect(v.factorDe('reforma', DateTime(2026, 5, 1)), 1);
  });

  test('"Todas" sin tipo de cambio: la sucursal en otra moneda queda fuera', () {
    final v = _vista();
    expect(v.convierte, isTrue);
    expect(v.sinTasa.map((l) => l.name), ['Palermo']);
    expect(v.factorDe('palermo', DateTime(2026, 5, 1)), isNull);
    expect(v.factorDe('reforma', DateTime(2026, 5, 1)), 1);
  });

  test('"Todas" no se ve en local aunque se prefiera: no se pueden sumar monedas', () {
    final v = _vista(config: _conTasa, verEnLocal: true);
    expect(v.convierte, isTrue);
    expect(v.puedeVerEnLocal, isFalse);
  });

  test('una sucursal en otra moneda: en la principal o en la suya', () {
    final principal = _vista(seleccionada: 'palermo', config: _conTasa);
    expect(principal.convierte, isTrue);
    expect(principal.codigoVista, 'GTQ');
    expect(principal.puedeVerEnLocal, isTrue);

    final local = _vista(seleccionada: 'palermo', config: _conTasa, verEnLocal: true);
    expect(local.convierte, isFalse);
    expect(local.codigoVista, 'ARS');
    expect(local.factorDe('palermo', DateTime(2026, 5, 1)), 1);
    expect(local.simboloDe(local.codigoVista), '\$');
    expect(local.firma, isNot(principal.firma));
  });

  test('una sucursal sin tipo de cambio se ve en la suya y se avisa', () {
    final v = _vista(seleccionada: 'palermo');
    expect(v.convierte, isFalse);
    expect(v.codigoVista, 'ARS');
    expect(v.faltaTasaEnVista, isTrue);
    expect(v.sinTasa, isEmpty);
  });

  test('una sucursal de la principal no ofrece cambiar de moneda', () {
    final v = _vista(seleccionada: 'reforma', config: _conTasa);
    expect(v.convierte, isFalse);
    expect(v.puedeVerEnLocal, isFalse);
    expect(v.faltaTasaEnVista, isFalse);
  });

  test('una sucursal desconocida se toma como de la principal', () {
    final v = _vista(config: _conTasa);
    expect(v.factorDe('cerrada', DateTime(2026, 5, 1)), 1);
  });

  test('una inactiva en otra moneda se convierte en "Todas" aunque no tenga pestaña', () {
    final cerrada = LocationModel(
        id: 'cordoba', name: 'Córdoba', currencySymbol: '\$', country: 'Argentina', active: false);
    final soloGt = [_reforma, _zacapa];
    final v = VistaMoneda(
        sucursales: soloGt, ocultas: [cerrada], seleccionada: null, config: _conTasa, verEnLocal: false);
    expect(v.hayOtraMoneda, isTrue);
    expect(v.convierte, isTrue);
    expect(v.factorDe('cordoba', DateTime(2026, 5, 1)), closeTo(1 / 125, 1e-12));
    // Sin tipo de cambio queda fuera y se avisa con su nombre.
    final sin = VistaMoneda(
        sucursales: soloGt, ocultas: [cerrada], seleccionada: null, config: ConfigMoneda.vacia, verEnLocal: false);
    expect(sin.sinTasa.map((l) => l.name), ['Córdoba']);
    expect(sin.factorDe('cordoba', DateTime(2026, 5, 1)), isNull);
  });

  test('la firma del mes cambia si una sucursal cambia de moneda aunque el conjunto sea igual', () {
    final ar2Mal = LocationModel(id: 'ar2', name: 'Belgrano', currencySymbol: 'Q', country: 'Argentina');
    final ar2Bien = LocationModel(id: 'ar2', name: 'Belgrano', currencySymbol: '\$', country: 'Argentina');
    final antes = _vista(config: _conTasa, sucursales: [_palermo, _reforma, ar2Mal]);
    final despues = _vista(config: _conTasa, sucursales: [_palermo, _reforma, ar2Bien]);
    expect(antes.codigosEnVista, despues.codigosEnVista);
    expect(antes.firmaMes(2026, 5), isNot(despues.firmaMes(2026, 5)));
  });

  test('ver en local cambia solo el signo: no obliga a recalcular', () {
    final local = _vista(seleccionada: 'palermo', config: _conTasa, verEnLocal: true);
    final gt = _vista(seleccionada: 'reforma', config: _conTasa);
    expect(local.firma, gt.firma);
    expect(local.codigoVista, isNot(gt.codigoVista));
  });

  test('la firma cambia con el tipo de cambio', () {
    final otra = _conTasa.conTasa('ARS', TasaCambio(desde: DateTime(2026, 6, 1), valor: 140));
    expect(_vista(config: otra).firma, isNot(_vista(config: _conTasa).firma));
  });

  test('una principal que ninguna sucursal usa se pinta con su signo de siempre', () {
    final v = _vista(config: const ConfigMoneda(principal: 'USD'));
    expect(v.simboloDe('USD'), 'US\$');
    expect(v.simboloDe('GTQ'), 'Q');
    expect(v.sinTasa.length, 3);
  });

  test('una bodega con otra moneda no vuelve "mixto" a un negocio de una sola', () {
    // Negocio de Honduras con una bodega que el POS creó en "Q".
    final sps = LocationModel(id: 'sps', name: 'San Pedro Sula', currencySymbol: 'L', country: 'Honduras');
    final bodega = LocationModel(
        id: 'bod', name: 'Bodega Central', currencySymbol: 'Q', centralWarehouse: true);
    final v = VistaMoneda(
        sucursales: [sps], bodegas: [bodega], seleccionada: null, config: ConfigMoneda.vacia, verEnLocal: false);
    expect(v.hayOtraMoneda, isFalse);
    expect(v.convierte, isFalse);
    expect(v.sinTasa, isEmpty);
    expect(v.factorDe('bod', DateTime(2026, 5, 1)), 1);
  });

  test('con la vista ya convirtiendo, el inventario de la bodega se pasa con su moneda', () {
    final bodegaAr = LocationModel(
        id: 'bodAr', name: 'Depósito', currencySymbol: '\$', country: 'Argentina', centralWarehouse: true);
    final v = VistaMoneda(
        sucursales: [_palermo, _reforma], bodegas: [bodegaAr], seleccionada: null, config: _conTasa, verEnLocal: false);
    expect(v.factorDe('bodAr', DateTime(2026, 5, 1)), closeTo(1 / 125, 1e-12));
  });

  test('una sucursal asignada que está inactiva se puede ver sola y se convierte', () {
    final cerrada = LocationModel(
        id: 'cordoba', name: 'Córdoba', currencySymbol: '\$', country: 'Argentina', active: false);
    final v = VistaMoneda(
        sucursales: [_reforma], ocultas: [cerrada], seleccionada: 'cordoba', config: _conTasa, verEnLocal: false);
    expect(v.enVista.map((l) => l.id), ['cordoba']);
    expect(v.convierte, isTrue);
    expect(v.enMoneda, 'GTQ');
    expect(v.factorDe('cordoba', DateTime(2026, 5, 1)), closeTo(1 / 125, 1e-12));
  });

  test('el orden de las sucursales no cambia la firma', () {
    final a = _vista(config: _conTasa, sucursales: [_palermo, _reforma, _zacapa]);
    final b = _vista(config: _conTasa, sucursales: [_zacapa, _reforma, _palermo]);
    expect(a.firma, b.firma);
    expect(a.firmaMes(2026, 5), b.firmaMes(2026, 5));
  });

  test('con la vista convirtiendo, una bodega sin tipo de cambio queda fuera CON aviso', () {
    // Negocio de Honduras (principal L) con una sucursal en dólares que sí
    // tiene tasa, y una bodega creada con "Q" que no.
    final teg = LocationModel(id: 'teg', name: 'Tegucigalpa', currencySymbol: 'L', country: 'Honduras');
    final sv = LocationModel(id: 'sv', name: 'San Salvador', currencySymbol: '\$', country: 'El Salvador');
    final bod = LocationModel(id: 'bod', name: 'Bodega central', currencySymbol: 'Q', centralWarehouse: true);
    final cfg = const ConfigMoneda(principal: 'HNL')
        .conTasa('USD', TasaCambio(desde: DateTime(2026, 1, 1), valor: 0.04));
    final v = VistaMoneda(
        sucursales: [teg, sv], bodegas: [bod], seleccionada: null, config: cfg, verEnLocal: false);
    expect(v.convierte, isTrue);
    expect(v.sinTasa.map((l) => l.name), ['Bodega central']);
    expect(v.factorDe('bod', DateTime(2026, 5, 1)), isNull);
    expect(v.enVista.map((l) => l.id), containsAll(['teg', 'sv', 'bod']),
        reason: 'el año la excluye igual que el mes');
  });
}
