// test/presentation/settings/leer_numero_tasa_test.dart
//
// El tipo de cambio se escribe a mano: "1,200" contra el dólar es mil
// doscientos (no 1.2), y "7,75" es siete con setenta y cinco.

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/screens/settings/moneda_settings_screen.dart';

void main() {
  test('coma de miles', () {
    expect(leerNumeroTasa('1,200'), 1200);
    expect(leerNumeroTasa('12,500'), 12500);
    expect(leerNumeroTasa('1,234,567'), 1234567);
  });

  test('coma decimal', () {
    expect(leerNumeroTasa('7,75'), 7.75);
    expect(leerNumeroTasa('0,13'), 0.13);
    expect(leerNumeroTasa('125,5'), 125.5);
  });

  test('punto decimal y los dos juntos', () {
    expect(leerNumeroTasa('118.5'), 118.5);
    expect(leerNumeroTasa('1,234.5'), 1234.5);
    expect(leerNumeroTasa(' 125 '), 125);
  });

  test('vacío o basura', () {
    expect(leerNumeroTasa(''), isNull);
    expect(leerNumeroTasa('abc'), isNull);
  });
}
