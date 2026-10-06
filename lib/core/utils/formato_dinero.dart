import 'package:intl/intl.dart';

// Mismo patrón que el resto de la app: coma para los miles, punto para los
// decimales y el signo de moneda adelante.
final _q = NumberFormat('#,##0.00', 'en_US');

String _moneda = 'Q';

/// Lo que va delante de cada monto: el signo de moneda de la sucursal que se
/// está mirando, tal como se configuró en Sabor Suite. Lo fija el
/// DashboardProvider al cargar las sucursales y al cambiar de pestaña.
///
/// Antes la Q estaba escrita a mano en cada pantalla, así que una sucursal que
/// vende en dólares veía sus ventas en quetzales.
String get moneda => _moneda;

void fijarMoneda(String simbolo) {
  final s = simbolo.trim();
  if (s.isEmpty) {
    _moneda = 'Q';
    return;
  }
  // "Q1,250.00" y "\$1,250.00" se leen bien pegados, pero "USD1,250.00" no:
  // un código de letras necesita su espacio.
  final terminaEnLetra = RegExp(r'[A-Za-z]$').hasMatch(s);
  _moneda = s.length > 1 && terminaEnLetra ? '$s ' : s;
}

/// La moneda de un grupo de sucursales: la que más de ellas usan. En empate,
/// la primera que aparece; sin sucursales, "Q".
String monedaMasUsada(Iterable<String> simbolos) {
  final cuantas = <String, int>{};
  for (final s in simbolos) {
    cuantas[s] = (cuantas[s] ?? 0) + 1;
  }
  var ganadora = 'Q';
  var max = 0;
  for (final e in cuantas.entries) {
    if (e.value > max) {
      ganadora = e.key;
      max = e.value;
    }
  }
  return ganadora;
}

/// Centavos → "Q1,234.50". El signo de resta es "−" (no "-") y el cero nunca
/// lleva signo: "−Q0.00" se lee como una pérdida que no existe.
String formatoDinero(int centavos) {
  if (centavos == 0) return '${moneda}0.00';
  final texto = '$moneda${_q.format(centavos.abs() / 100)}';
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
