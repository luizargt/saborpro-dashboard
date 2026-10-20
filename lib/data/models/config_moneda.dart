/// Moneda principal del negocio y tipos de cambio, para ver en una sola moneda
/// sucursales que venden en monedas distintas (una en Guatemala y otra en
/// Argentina, por ejemplo).
///
/// Los tipos de cambio tienen FECHA DE INICIO y no se sobrescriben: cada venta
/// se convierte con el que estaba vigente el día que se cobró. Si el dueño
/// ajusta el del peso hoy, las ventas del año pasado siguen con el de entonces
/// y un reporte que ya revisó no cambia. El primero que se puso vale también
/// para todo lo anterior a él.
///
/// Se guarda en `reportingCurrency/{tenantId}`.
class TasaCambio {
  const TasaCambio({required this.desde, required this.valor});

  /// Día (hora local) desde el que vale, inclusive.
  final DateTime desde;

  /// Cuántas unidades de la moneda equivalen a 1 de la principal:
  /// "1 Q = 125 $" se guarda como 125.
  final double valor;

  static String fechaTexto(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {'from': fechaTexto(desde), 'value': valor};

  static TasaCambio? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final texto = raw['from'];
    final valor = (raw['value'] as num?)?.toDouble();
    if (texto is! String || valor == null || valor <= 0 || !valor.isFinite) return null;
    final p = texto.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return TasaCambio(desde: DateTime(y, m, d), valor: valor);
  }
}

class ConfigMoneda {
  const ConfigMoneda({this.principal, this.tasas = const {}});

  static const ConfigMoneda vacia = ConfigMoneda();

  /// Código de la moneda principal. Nulo = el dueño no la eligió todavía (se
  /// usa la que más sucursales tienen).
  final String? principal;

  /// Por código de moneda, ordenadas de la más vieja a la más nueva.
  final Map<String, List<TasaCambio>> tasas;

  bool tieneTasa(String codigo) => (tasas[codigo] ?? const []).isNotEmpty;

  /// La tasa vigente en [fecha]: la última que empezó ese día o antes. Una
  /// fecha anterior a todas usa la primera.
  TasaCambio? tasaEn(String codigo, DateTime fecha) {
    final lista = tasas[codigo];
    if (lista == null || lista.isEmpty) return null;
    var vigente = lista.first;
    for (final t in lista) {
      if (t.desde.isAfter(fecha)) break;
      vigente = t;
    }
    return vigente;
  }

  /// Por cuánto se multiplica un monto en [codigo] para pasarlo a la
  /// principal en [fecha]. Nulo si no hay tipo de cambio: ese monto no se
  /// puede sumar con los demás.
  double? factor(String codigo, String principal, DateTime fecha) {
    if (codigo == principal) return 1;
    final t = tasaEn(codigo, fecha);
    return t == null ? null : 1 / t.valor;
  }

  /// Días dentro de (desde, hasta) en que cambia la tasa de [codigo]. Entre
  /// dos cortes seguidos la tasa es una sola, y así una suma de servidor por
  /// tramo se puede convertir entera.
  List<DateTime> cortes(String codigo, DateTime desde, DateTime hasta) => [
        for (final t in tasas[codigo] ?? const <TasaCambio>[])
          if (t.desde.isAfter(desde) && t.desde.isBefore(hasta)) t.desde,
      ];

  /// Huella de lo que hace falta para convertir [codigos] entre [desde] y
  /// [hasta]: si cambia, un resumen guardado con otra huella está viejo.
  String firma(String principal, Iterable<String> codigos, DateTime desde, DateTime hasta) {
    final partes = <String>[principal];
    for (final c in ({...codigos}.toList()..sort())) {
      if (c == principal) continue;
      final usadas = <TasaCambio>[];
      final inicial = tasaEn(c, desde);
      if (inicial != null) usadas.add(inicial);
      for (final t in tasas[c] ?? const <TasaCambio>[]) {
        if (t.desde.isAfter(desde) && t.desde.isBefore(hasta)) usadas.add(t);
      }
      partes.add(usadas.isEmpty
          ? '$c=sin'
          : '$c=${usadas.map((t) => '${TasaCambio.fechaTexto(t.desde)}:${t.valor}').join(',')}');
    }
    return partes.join('|');
  }

  /// Agrega o reemplaza (mismo día) un tipo de cambio.
  ConfigMoneda conTasa(String codigo, TasaCambio tasa) {
    final lista = [
      for (final t in tasas[codigo] ?? const <TasaCambio>[])
        if (TasaCambio.fechaTexto(t.desde) != TasaCambio.fechaTexto(tasa.desde)) t,
      tasa,
    ]..sort((a, b) => a.desde.compareTo(b.desde));
    return ConfigMoneda(principal: principal, tasas: {...tasas, codigo: lista});
  }

  ConfigMoneda sinTasa(String codigo, DateTime desde) {
    final lista = [
      for (final t in tasas[codigo] ?? const <TasaCambio>[])
        if (TasaCambio.fechaTexto(t.desde) != TasaCambio.fechaTexto(desde)) t,
    ];
    return ConfigMoneda(principal: principal, tasas: {...tasas, codigo: lista});
  }

  /// Cambiar la principal borra los tipos de cambio: estaban escritos contra
  /// la anterior ("1 Q = 125 $") y con otra principal ya no dicen nada.
  ConfigMoneda conPrincipal(String codigo) =>
      codigo == principal ? this : ConfigMoneda(principal: codigo);

  Map<String, dynamic> toMap() => {
        'principal_currency': principal,
        'rates': {
          for (final e in tasas.entries)
            if (e.value.isNotEmpty) e.key: [for (final t in e.value) t.toMap()],
        },
      };

  factory ConfigMoneda.fromMap(Map<String, dynamic>? d) {
    if (d == null) return vacia;
    final principal = d['principal_currency'];
    final tasas = <String, List<TasaCambio>>{};
    final raw = d['rates'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is! String || e.value is! List) continue;
        final lista = [
          for (final t in e.value as List) TasaCambio.fromMap(t),
        ].whereType<TasaCambio>().toList()
          ..sort((a, b) => a.desde.compareTo(b.desde));
        if (lista.isNotEmpty) tasas[e.key as String] = lista;
      }
    }
    return ConfigMoneda(
      principal: principal is String && principal.isNotEmpty ? principal : null,
      tasas: tasas,
    );
  }
}

/// Las llaves de dinero de una orden, un gasto o una compra. Se multiplican
/// a cualquier profundidad (renglones, modificadores, pagos divididos); lo
/// demás (cantidades, fechas, ids) no se toca.
const Set<String> kLlavesDeDinero = {
  'payment_amount',
  'total_amount',
  'subtotal',
  'discount_amount',
  'tax_amount',
  'tip_amount',
  'delivery_fee',
  'unit_price',
  'price',
  'amount',
  'total',
  'modifiers_price',
  'unit_cost',
  'cost',
  'total_cost',
  'change_amount',
  'surcharge_amount',
};

/// Copia de [fila] con cada monto multiplicado por [factor]. Con factor 1
/// devuelve la misma fila, sin copiar: es el caso de casi todas.
Map<String, dynamic> convertirFila(Map<String, dynamic> fila, double factor) {
  if (factor == 1) return fila;
  return _convertirMapa(fila, factor);
}

Map<String, dynamic> _convertirMapa(Map<dynamic, dynamic> m, double factor) {
  final r = <String, dynamic>{};
  m.forEach((k, v) {
    final key = k.toString();
    r[key] = (v is num && kLlavesDeDinero.contains(key)) ? v * factor : _convertirValor(v, factor);
  });
  return r;
}

dynamic _convertirValor(dynamic v, double factor) {
  if (v is Map) return _convertirMapa(v, factor);
  if (v is List) return [for (final x in v) _convertirValor(x, factor)];
  return v;
}
