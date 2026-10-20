// test/core/utils/monedas_test.dart
//
// El código de moneda sale del símbolo y del país. "$" solo no dice qué
// moneda es: en Argentina es el peso, en México el peso mexicano y en
// Guatemala o El Salvador el dólar. Sabor Manager agrupa y convierte con este
// código (el mismo cálculo vive en saborpro_app, donde se elige la moneda).

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/location_service.dart';
import 'package:saborpro_reports/core/utils/monedas.dart';

void main() {
  test('el signo de pesos depende del país', () {
    expect(codigoDeMoneda('\$', 'Argentina'), 'ARS');
    expect(codigoDeMoneda('\$', 'México'), 'MXN');
    expect(codigoDeMoneda('\$', 'Colombia'), 'COP');
    expect(codigoDeMoneda('\$', 'Chile'), 'CLP');
    expect(codigoDeMoneda('\$', 'El Salvador'), 'USD');
    expect(codigoDeMoneda('\$', 'Estados Unidos'), 'USD');
    expect(codigoDeMoneda('\$', 'Guatemala'), 'USD');
    expect(codigoDeMoneda('\$', null), 'USD');
  });

  test('los símbolos propios no dependen del país', () {
    expect(codigoDeMoneda('Q', 'Guatemala'), 'GTQ');
    expect(codigoDeMoneda('Q', 'Argentina'), 'GTQ');
    expect(codigoDeMoneda('US\$', 'México'), 'USD');
    expect(codigoDeMoneda('\$AR', 'Guatemala'), 'ARS');
    expect(codigoDeMoneda('L', 'Honduras'), 'HNL');
    expect(codigoDeMoneda('C\$', 'Nicaragua'), 'NIO');
    expect(codigoDeMoneda('CLP', 'Chile'), 'CLP');
  });

  test('las variantes escritas a mano no parten un negocio en dos monedas', () {
    expect(codigoDeMoneda('Q.', 'Guatemala'), 'GTQ');
    expect(codigoDeMoneda('q', 'Guatemala'), 'GTQ');
    expect(codigoDeMoneda(' Q ', 'Guatemala'), 'GTQ');
    expect(codigoDeMoneda('L.', 'Honduras'), 'HNL');
    expect(codigoDeMoneda('Lps', 'Honduras'), 'HNL');
    expect(codigoDeMoneda('Lps.', 'Honduras'), 'HNL');
    expect(codigoDeMoneda('US \$', 'México'), 'USD');
    expect(codigoDeMoneda('\$.', 'Argentina'), 'ARS');
    expect(codigoDeMoneda('usd', 'Guatemala'), 'USD');
    expect(codigoDeMoneda('S/', 'Perú'), 'PEN');
  });

  test('sin símbolo es quetzal, como en el POS; uno escrito a mano es su propia moneda', () {
    expect(codigoDeMoneda(null, null), 'GTQ');
    expect(codigoDeMoneda('  ', 'Guatemala'), 'GTQ');
    expect(codigoDeMoneda('MXN', 'Guatemala'), 'MXN');
    // Un signo que no se conoce es su propia moneda, sin importar mayúsculas
    // ni el punto final.
    expect(codigoDeMoneda('Bs', 'Otro'), 'BS');
    expect(codigoDeMoneda('bs.', 'Otro'), 'BS');
  });

  test('el signo de pesos también es local en República Dominicana y Belice', () {
    expect(codigoDeMoneda('\$', 'República Dominicana'), 'DOP');
    expect(codigoDeMoneda('\$', 'Belice'), 'BZD');
    expect(codigoDeMoneda('\$', 'Panamá'), 'USD');
  });

  test('el balboa escrito de varias formas es uno solo', () {
    expect(codigoDeMoneda('B/.', 'Panamá'), 'PAB');
    expect(codigoDeMoneda('B/', 'Panamá'), 'PAB');
    expect(codigoDeMoneda('b/.', 'Panamá'), 'PAB');
  });

  test('la moneda que se propone para cada país es la local', () {
    const esperado = {
      'Guatemala': 'GTQ',
      'México': 'MXN',
      'El Salvador': 'USD',
      'Honduras': 'HNL',
      'Nicaragua': 'NIO',
      'Costa Rica': 'CRC',
      'Panamá': 'PAB',
      'Belice': 'BZD',
      'República Dominicana': 'DOP',
      'Estados Unidos': 'USD',
      'Colombia': 'COP',
      'Perú': 'PEN',
      'Argentina': 'ARS',
      'Chile': 'CLP',
      'España': 'EUR',
    };
    for (final e in simboloDelPais.entries) {
      expect(codigoDeMoneda(e.value, e.key), esperado[e.key], reason: e.key);
    }
    expect(simboloDelPais.keys.toSet(), esperado.keys.toSet());
  });

  test('todo símbolo ofrecido tiene nombre', () {
    for (final s in simbolosDeMoneda) {
      expect(nombreDeMoneda[codigoDeMoneda(s, 'Guatemala')], isNotNull, reason: s);
    }
  });

  test('la sucursal expone su código', () {
    final ar = LocationModel(id: 'a', name: 'Palermo', currencySymbol: '\$', country: 'Argentina');
    expect(ar.currencyCode, 'ARS');
    expect(LocationModel(id: 'g', name: 'Zona 10').currencyCode, 'GTQ');
    expect(describirMoneda(ar.currencyCode), 'Peso argentino (ARS)');
  });

  test('cada código elegible tiene nombre y signo', () {
    for (final c in codigosDeMoneda) {
      expect(nombreDeMoneda[c], isNotNull, reason: c);
      expect(simboloDeCodigo(c), isNot(c), reason: c);
    }
  });
}
