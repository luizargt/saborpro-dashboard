import 'package:intl/intl.dart';

// Mismo patrón que el resto de la app: coma para los miles, punto para los
// decimales y la Q adelante.
final _q = NumberFormat('#,##0.00', 'en_US');

/// Centavos → "Q1,234.50". El signo de resta es "−" (no "-") y el cero nunca
/// lleva signo: "−Q0.00" se lee como una pérdida que no existe.
String formatoQ(int centavos) {
  if (centavos == 0) return 'Q0.00';
  final texto = 'Q${_q.format(centavos.abs() / 100)}';
  return centavos < 0 ? '−$texto' : texto;
}

/// "12.5%", "−3.0%". Lo que redondea a cero sale "0.0%", sin signo.
String formatoPct(double? v) {
  if (v == null) return '—';
  final redondo = double.parse(v.toStringAsFixed(1));
  if (redondo == 0) return '0.0%';
  final texto = '${redondo.abs().toStringAsFixed(1)}%';
  return redondo < 0 ? '−$texto' : texto;
}

/// 2 en vez de 2.000, y 0.0125 sin perder decimales: el desglose tiene que
/// poder auditarse, y "0.013 × Q40.00" no da lo que dice la línea.
String formatoCantidad(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
