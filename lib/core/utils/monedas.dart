// Monedas de las sucursales.
//
// Cada sucursal guarda solo su símbolo (`settings.currency_symbol`), que es lo
// que se imprime. La identidad de la moneda es el código ISO 4217 (GTQ, ARS,
// USD…): con él Sabor Manager agrupa sucursales y convierte con el tipo de
// cambio. El código NO se guarda: sale del símbolo y del país, así no puede
// quedar desfasado cuando alguien cambia uno de los dos. "$" solo no dice
// qué moneda es (dólar, peso mexicano, peso argentino…): lo decide el país.
//
// El mismo cálculo vive en saborpro_app (lib/core/utils/monedas.dart), que es
// donde se elige la moneda de cada sucursal. Si cambias uno, cambia el otro.

/// Símbolos que se ofrecen al elegir la moneda de una sucursal.
const List<String> simbolosDeMoneda = [
  'Q', // Guatemala (Quetzal)
  '\$', // Dólar o peso, según el país
  'US\$', // Dólar estadounidense en cualquier país
  '€', // Euro
  'L', // Honduras (Lempira)
  'C\$', // Nicaragua (Córdoba)
  '₡', // Costa Rica (Colón)
  'B/.', // Panamá (Balboa)
  'BZ\$', // Belice (Dólar beliceño)
  'RD\$', // República Dominicana (Peso)
  'S/.', // Perú (Sol)
  '\$AR', // Argentina (Peso argentino)
  'CLP', // Chile (Peso chileno)
];

/// La moneda que se propone al elegir el país. "Otro" no propone nada.
const Map<String, String> simboloDelPais = {
  'Guatemala': 'Q',
  'México': '\$',
  'El Salvador': '\$',
  'Honduras': 'L',
  'Nicaragua': 'C\$',
  'Costa Rica': '₡',
  'Panamá': 'B/.',
  'Belice': 'BZ\$',
  'República Dominicana': 'RD\$',
  'Estados Unidos': '\$',
  'Colombia': '\$',
  'Perú': 'S/.',
  'Argentina': '\$',
  'Chile': '\$',
  'España': '€',
};

/// Los países donde "$" es la moneda local y no el dólar.
const Map<String, String> _pesoConSigno = {
  'México': 'MXN',
  'Colombia': 'COP',
  'Argentina': 'ARS',
  'Chile': 'CLP',
  'República Dominicana': 'DOP',
  'Belice': 'BZD',
};

const Map<String, String> _codigoDelSimbolo = {
  'Q': 'GTQ',
  'US\$': 'USD',
  '€': 'EUR',
  'L': 'HNL',
  'C\$': 'NIO',
  '₡': 'CRC',
  'B/.': 'PAB',
  'B/': 'PAB',
  'BZ\$': 'BZD',
  'RD\$': 'DOP',
  'S/.': 'PEN',
  'S/': 'PEN',
  '\$AR': 'ARS',
  'CLP': 'CLP',
};

/// Nombre para mostrar de cada código.
const Map<String, String> nombreDeMoneda = {
  'GTQ': 'Quetzal',
  'USD': 'Dólar estadounidense',
  'EUR': 'Euro',
  'HNL': 'Lempira',
  'NIO': 'Córdoba',
  'CRC': 'Colón',
  'PAB': 'Balboa',
  'BZD': 'Dólar beliceño',
  'DOP': 'Peso dominicano',
  'PEN': 'Sol',
  'ARS': 'Peso argentino',
  'CLP': 'Peso chileno',
  'MXN': 'Peso mexicano',
  'COP': 'Peso colombiano',
};

/// Código ISO de la moneda de una sucursal. Un símbolo desconocido (escrito a
/// mano) es su propia moneda: devuelve el símbolo tal cual, para que nunca se
/// junte con otra.
String codigoDeMoneda(String? simbolo, String? pais) {
  final s = (simbolo ?? '').trim();
  if (s.isEmpty) return 'GTQ'; // Igual que el POS: sin símbolo es "Q".
  if (s == '\$') return _pesoConSigno[(pais ?? '').trim()] ?? 'USD';
  final conocido = _codigoDelSimbolo[s];
  if (conocido != null) return conocido;
  // Variantes escritas a mano ("Q.", "q", "L.", "Lps", "US \$"): sin esto un
  // negocio de una sola moneda se partía en dos y "Todas" dejaba fuera una
  // sucursal por "falta de tipo de cambio".
  final limpio = s.replaceAll(' ', '').replaceAll(RegExp(r'\.+$'), '');
  if (limpio == '\$') return _pesoConSigno[(pais ?? '').trim()] ?? 'USD';
  final variante = _codigoDelSimbolo[limpio] ??
      _codigoDelSimbolo[limpio.toUpperCase()] ??
      _alias[limpio.toUpperCase()];
  if (variante != null) return variante;
  // Alguien escribió el código directamente ("USD", "mxn"), o un signo que no
  // se conoce ("Bs"): se compara sin mayúsculas ni punto final, para que
  // "Bs" y "bs." no queden como dos monedas.
  return limpio.toUpperCase();
}

/// Otras formas comunes de escribir las monedas a mano.
const Map<String, String> _alias = {
  'LPS': 'HNL',
  'QTZ': 'GTQ',
  'US\$': 'USD',
  'U\$S': 'USD',
  'MX\$': 'MXN',
  'COL\$': 'COP',
  'CLP\$': 'CLP',
};

/// "Peso argentino (ARS)", o solo el código si no tiene nombre.
String describirMoneda(String codigo) {
  final nombre = nombreDeMoneda[codigo];
  return nombre == null ? codigo : '$nombre ($codigo)';
}

/// El signo con que se pinta una moneda cuando ninguna sucursal la usa (por
/// ejemplo, un dueño que quiere ver todo en dólares). Si alguna la usa, manda
/// el signo de esa sucursal.
const Map<String, String> _simboloDelCodigo = {
  'GTQ': 'Q',
  'USD': 'US\$',
  'EUR': '€',
  'HNL': 'L',
  'NIO': 'C\$',
  'CRC': '₡',
  'PAB': 'B/.',
  'BZD': 'BZ\$',
  'DOP': 'RD\$',
  'PEN': 'S/.',
  'ARS': '\$',
  'CLP': '\$',
  'MXN': '\$',
  'COP': '\$',
};

String simboloDeCodigo(String codigo) => _simboloDelCodigo[codigo] ?? codigo;

/// Las monedas que se pueden elegir como principal.
const List<String> codigosDeMoneda = [
  'GTQ',
  'USD',
  'HNL',
  'NIO',
  'CRC',
  'PAB',
  'BZD',
  'DOP',
  'MXN',
  'COP',
  'PEN',
  'ARS',
  'CLP',
  'EUR',
];
