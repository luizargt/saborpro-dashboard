// Lo que calcula el reporte "Compras vs Ventas" (compras-ventas.html): qué se
// compró, qué se vendió, cuánto se ganó con la mercadería y qué pasó con la bodega.
//
// Todo es Dart puro, sin Firestore ni providers, y NUNCA lanza ante un dato roto.
//
// QUÉ SIGNIFICA CADA NÚMERO (y de dónde sale)
//  - Vendiste: la venta neta de Rentabilidad (cobrado sin propinas ni envíos).
//  - Usaste: el costo de lo vendido, el MISMO de Rentabilidad (costo sellado al
//    vender). Por eso "Ganaste" = la utilidad bruta de Rentabilidad: un solo
//    número para las dos pantallas.
//  - Compraste: la mercadería que entró a la despensa (movimientos `entrada`).
//  - Tenías / Te queda: el valor de la bodega, de las fotos mensuales que guarda
//    el servidor (`inventorySnapshots`); en un mes que sigue abierto, "Te queda"
//    es el valor de hoy. Lo que no explican las compras ni lo usado (merma,
//    ajustes, cambios de precio) se muestra aparte, no se esconde.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

import '../../core/utils/date_range.dart';
import 'profitability_data.dart';
import 'propinas_data.dart' show PropinasReporte;
import 'rentabilidad_calculo.dart' show ParCosto;

/// Desde aquí una existencia deja de ser creíble. El mismo corte que usa la
/// función del servidor (`fotoInventario.js`) y Rentabilidad.
const double kStockImposible = 1000000;

/// "2026-10-14".
final _esDia = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _diaDe(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// El día ("2026-10-14") de una fecha, para unir con las llaves por día.
String llaveDeDia(DateTime d) => _diaDe(d);

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _texto(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Para unir categorías de distintas sucursales (son una copia por sucursal, con
/// otro id): el nombre, sin mayúsculas ni tildes.
/// Cada letra sin marca y las que se le parecen con marca.
const _letrasConMarca = {
  'a': 'áàäâãåā',
  'e': 'éèëêē',
  'i': 'íìïîī',
  'o': 'óòöôõō',
  'u': 'úùüûū',
  'n': 'ñ',
  'c': 'ç',
  's': 'š',
  'z': 'ž',
  'y': 'ýÿ',
};

final _sinMarca = {
  for (final e in _letrasConMarca.entries)
    for (final c in e.value.split('')) c: e.key,
};

String claveDeCategoria(String nombre) {
  // Las marcas combinantes ("e" + U+0301 = "é" escrito en dos piezas) se quitan
  // primero; luego las letras con marca más comunes. La función del servidor usa
  // la descomposición de Unicode, que quita TODA marca: para las letras que no
  // están aquí la clave puede diferir, y solo cambia cómo se juntan dos
  // categorías, nunca un total.
  final b = StringBuffer();
  for (final c in nombre.replaceAll(RegExp('[\\u0300-\\u036f]'), '').toLowerCase().trim().split('')) {
    b.write(_sinMarca[c] ?? c);
  }
  return b.toString();
}

// ── Las fotos de la bodega ──────────────────────────────────────────────────

class CategoriaValor {
  final String nombre;
  final double valor;
  const CategoriaValor(this.nombre, this.valor);
}

/// El valor de la bodega de UNA sucursal en una fecha, en la moneda de esa sucursal.
class SucursalFoto {
  final double total;

  /// Es la bodega central: no vende, no entra en el reporte.
  final bool central;

  /// Con existencia pero sin precio de compra: no suman al total.
  final int sinPrecio;

  /// Con una existencia irreal (≥ 1,000,000): no suman al total.
  final List<String> imposibles;
  final List<CategoriaValor> porCategoria;

  const SucursalFoto({
    required this.total,
    this.central = false,
    this.sinPrecio = 0,
    this.imposibles = const [],
    this.porCategoria = const [],
  });

  /// Lee una sucursal tal como la guarda `inventorySnapshots`. Null si no sirve.
  static SucursalFoto? desde(Object? v) {
    if (v is! Map) return null;
    final total = _num(v['total']);
    if (total == null) return null;
    final cats = <CategoriaValor>[];
    final crudas = v['por_categoria'];
    if (crudas is List) {
      for (final c in crudas) {
        if (c is! Map) continue;
        final n = _texto(c['nombre']);
        final x = _num(c['valor']);
        if (n != null && x != null) cats.add(CategoriaValor(n, x));
      }
    }
    final imp = v['imposibles'];
    return SucursalFoto(
      total: total,
      central: v['central'] == true,
      sinPrecio: (_num(v['sin_precio']) ?? 0).toInt(),
      imposibles: imp is List ? [for (final n in imp) if (n is String) n] : const [],
      porCategoria: cats,
    );
  }
}

/// La foto del valor de la bodega de un negocio en una fecha.
class FotoBodega {
  /// "2026-11-01".
  final String fecha;

  /// id de sucursal → su valor.
  final Map<String, SucursalFoto> sucursales;

  /// Cuándo se tomó de verdad; null si no se sabe (o si es la de hoy, en vivo).
  final DateTime? tomadaEn;

  const FotoBodega(this.fecha, this.sucursales, {this.tomadaEn});

  DateTime get dia => DateTime.parse(fecha);

  /// Se tomó bastante después del día que dice ("1 de octubre" tomada el 22 de
  /// noviembre con el script): el stock que valora es el de ESE momento, no el del
  /// día 1, así que sirve para orientarse pero no es exacta. La automática se toma
  /// a las 00:00 del día 1, minutos después.
  bool get esAproximada => tomadaEn != null && tomadaEn!.difference(dia).inHours > 36;

  /// Lee un documento de `inventorySnapshots`. Null si no trae fecha válida.
  static FotoBodega? desde(Map<String, dynamic> d) {
    final f = _texto(d['fecha']);
    if (f == null || !_esDia.hasMatch(f)) return null;
    final s = d['sucursales'];
    final r = <String, SucursalFoto>{};
    if (s is Map) {
      for (final e in s.entries) {
        if (e.key is! String) continue;
        final x = SucursalFoto.desde(e.value);
        if (x != null) r[e.key as String] = x;
      }
    }
    final cuando = d['tomada_en'];
    final tomada = cuando is Timestamp
        ? cuando.toDate()
        : (cuando is String ? DateTime.tryParse(cuando) : null);
    return FotoBodega(f, r, tomadaEn: tomada?.toLocal());
  }
}

/// Un ingrediente de la despensa, como lo guarda `ingredients`.
class IngredienteVivo {
  final String id;
  final String sucursal;
  final String? categoriaId;
  final String nombre;
  final double stock;
  final double? precio;
  final bool activo;

  const IngredienteVivo({
    required this.id,
    required this.sucursal,
    required this.nombre,
    required this.stock,
    this.categoriaId,
    this.precio,
    this.activo = true,
  });

  /// Null si no se puede ligar a una sucursal.
  static IngredienteVivo? desde(String id, Map<String, dynamic> d) {
    final loc = _texto(d['location_id']);
    if (loc == null) return null;
    return IngredienteVivo(
      id: id,
      sucursal: loc,
      categoriaId: _texto(d['categoryId']),
      nombre: _texto(d['name']) ?? '(sin nombre)',
      stock: _num(d['currentStock']) ?? 0,
      precio: _num(d['lastPurchasePrice']),
      activo: d['active'] != false,
    );
  }
}

/// El valor de la bodega de ahora, con las MISMAS reglas que la función del
/// servidor (`fotoInventario.js`, `valorarIngredientes`): así lo de hoy y lo de
/// las fotos se pueden comparar.
///
/// Un ingrediente inactivo, sin existencia, con existencia irreal (≥ 1,000,000) o
/// sin precio de compra no suma (los dos últimos se cuentan aparte).
FotoBodega valorarBodega({
  required List<IngredienteVivo> ingredientes,
  required Map<String, String> nombreDeCategoria,
  required Map<String, bool> centrales,
  required DateTime hoy,
}) {
  final tot = <String, double>{};
  final sinPrecio = <String, int>{};
  final imposibles = <String, List<String>>{};
  final cats = <String, Map<String, CategoriaValor>>{};
  final vistas = <String>{};

  for (final i in ingredientes) {
    if (!i.activo) continue;
    vistas.add(i.sucursal);
    if (!i.stock.isFinite || i.stock <= 0) continue;
    if (i.stock >= kStockImposible) {
      final l = imposibles.putIfAbsent(i.sucursal, () => []);
      if (l.length < 20) l.add(i.nombre);
      continue;
    }
    final p = i.precio;
    if (p == null || !p.isFinite || p <= 0) {
      sinPrecio.update(i.sucursal, (v) => v + 1, ifAbsent: () => 1);
      continue;
    }
    final v = i.stock * p;
    tot.update(i.sucursal, (x) => x + v, ifAbsent: () => v);
    final nombre = _texto(nombreDeCategoria[i.categoriaId]) ?? 'Sin categoría';
    final mapa = cats.putIfAbsent(i.sucursal, () => {});
    final k = claveDeCategoria(nombre);
    final previa = mapa[k];
    mapa[k] = CategoriaValor(previa?.nombre ?? nombre, (previa?.valor ?? 0) + v);
  }

  return FotoBodega(_diaDe(hoy), {
    for (final loc in vistas)
      loc: SucursalFoto(
        total: tot[loc] ?? 0,
        central: centrales[loc] == true,
        sinPrecio: sinPrecio[loc] ?? 0,
        imposibles: imposibles[loc] ?? const [],
        porCategoria: (cats[loc]?.values.toList() ?? [])..sort((a, b) => b.valor.compareTo(a.valor)),
      ),
  });
}

// ── La bodega del período ───────────────────────────────────────────────────

/// Cuánto valía la bodega al empezar y al terminar el período, de las sucursales
/// que se ven y en la moneda de la vista.
class BodegaPeriodo {
  /// Null si no hay foto del inicio.
  final double? inicio;

  /// Null si no hay con qué decir cuánto quedó al terminar.
  final double? fin;

  /// "Te queda" es el valor de HOY (el período todavía no termina).
  final bool finEsHoy;

  final Map<String, double> inicioPorSucursal;
  final Map<String, double> finPorSucursal;

  /// Lo que queda al terminar, por categoría (llave → nombre y valor).
  final Map<String, CategoriaValor> finPorCategoria;

  /// Sucursales (a la vista) con existencias que no se pudieron valorar.
  final int sinPrecio;
  final List<String> imposibles;

  /// Alguna de las fotos se tomó mucho después del día que dice: no es exacta.
  final bool aproximada;

  const BodegaPeriodo({
    this.inicio,
    this.fin,
    this.finEsHoy = false,
    this.inicioPorSucursal = const {},
    this.finPorSucursal = const {},
    this.finPorCategoria = const {},
    this.sinPrecio = 0,
    this.imposibles = const [],
    this.aproximada = false,
  });

  static const vacia = BodegaPeriodo();

  bool get completa => inicio != null && fin != null;

  /// [sucursales]: las que se ven (sin la bodega central, aunque venga en la foto).
  /// [factor] pasa un valor de la moneda de la sucursal a la de la vista, a la fecha
  /// de la foto; null = esa moneda no tiene tipo de cambio y no se suma.
  factory BodegaPeriodo.armar({
    required FotoBodega? inicio,
    required FotoBodega? fin,
    required bool finEsHoy,
    required Set<String> sucursales,
    required double? Function(String sucursal, DateTime fecha) factor,
  }) {
    Map<String, double> sumar(FotoBodega? f) {
      final r = <String, double>{};
      if (f == null) return r;
      final dia = f.dia;
      for (final e in f.sucursales.entries) {
        if (!sucursales.contains(e.key) || e.value.central) continue;
        final k = factor(e.key, dia);
        if (k == null || !k.isFinite) continue;
        r[e.key] = e.value.total * k;
      }
      return r;
    }

    final ini = sumar(inicio);
    final fi = sumar(fin);

    final cats = <String, CategoriaValor>{};
    var sinPrecio = 0;
    final imposibles = <String>[];
    if (fin != null) {
      final dia = fin.dia;
      for (final e in fin.sucursales.entries) {
        if (!sucursales.contains(e.key) || e.value.central) continue;
        final k = factor(e.key, dia);
        if (k == null || !k.isFinite) continue;
        sinPrecio += e.value.sinPrecio;
        imposibles.addAll(e.value.imposibles);
        for (final c in e.value.porCategoria) {
          final llave = claveDeCategoria(c.nombre);
          final previa = cats[llave];
          cats[llave] = CategoriaValor(previa?.nombre ?? c.nombre, (previa?.valor ?? 0) + c.valor * k);
        }
      }
    }

    // Sin ninguna sucursal que aporte (a la vista no hay ninguna, o la elegida no
    // está en la foto) no se sabe: un cero diría que la bodega estaba vacía.
    double? total(FotoBodega? f, Map<String, double> m) => f == null || m.isEmpty ? null : m.values.fold<double>(0, (a, b) => a + b);
    return BodegaPeriodo(
      inicio: total(inicio, ini),
      fin: total(fin, fi),
      finEsHoy: finEsHoy,
      inicioPorSucursal: ini,
      finPorSucursal: fi,
      finPorCategoria: cats,
      sinPrecio: sinPrecio,
      imposibles: imposibles,
      aproximada: (inicio?.esAproximada ?? false) || (fin?.esAproximada ?? false),
    );
  }
}

/// Qué pasó con la bodega.
enum EstadoBodega { igual, crecio, bajo }

/// "Igual" si cambió menos del 3% de lo que se compró; si no, creció o bajó.
EstadoBodega estadoDeBodega({required double inicio, required double fin, required double compraste}) {
  final dif = fin - inicio;
  if (dif.abs() <= compraste.abs() * 0.03) return EstadoBodega.igual;
  return dif > 0 ? EstadoBodega.crecio : EstadoBodega.bajo;
}

/// La cuenta de la bodega: lo que tenías, lo que compraste, lo que usaste, lo que
/// no se explica y lo que te queda.
class EcuacionBodega {
  final double tenias;
  final double compraste;
  final double usaste;
  final double teQueda;

  const EcuacionBodega({required this.tenias, required this.compraste, required this.usaste, required this.teQueda});

  /// Lo que la cuenta no explica: merma, ajustes de inventario y cambios de
  /// precio (la foto valora a los precios de ese día, lo usado al costo de la
  /// venta). Positivo = salió más de lo que se vendió.
  double get otros => tenias + compraste - usaste - teQueda;

  /// Pasa de las monedas: menos de Q1 no se muestra, es ruido de redondeo.
  bool get hayOtros => otros.abs() >= 1;

  EstadoBodega get estado => estadoDeBodega(inicio: tenias, fin: teQueda, compraste: compraste);
}

// ── Lo que se vendió, por día ───────────────────────────────────────────────

DateTime? fechaDePedido(Object? v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// La venta neta de cada día ("2026-10-14" → monto), de los pedidos cobrados: la
/// misma venta de Rentabilidad (cobrado sin propina ni envío). [sucursal] acota a
/// una sucursal. Un pedido sin fecha de cobro no entra.
Map<String, double> ventasPorDia(List<Map<String, dynamic>> pedidos, {String? sucursal}) {
  final r = <String, double>{};
  for (final o in pedidos) {
    if (sucursal != null && o['location_id'] != sucursal) continue;
    final f = fechaDePedido(o['paid_at']);
    if (f == null) continue;
    final v = PropinasReporte.ventaDe(o);
    if (!v.isFinite) continue;
    r.update(_diaDe(f), (x) => x + v, ifAbsent: () => v);
  }
  return r;
}

// ── Semana por semana ───────────────────────────────────────────────────────

String _mesCorto(DateTime d) {
  try {
    return DateFormat('MMM', 'es').format(d).replaceAll('.', '');
  } catch (_) {
    return DateFormat('MMM').format(d);
  }
}

class SemanaCV {
  final int numero;
  final DateTime desde;
  final DateTime hasta;
  final double vendiste;
  final double compraste;
  final double usaste;

  const SemanaCV({
    required this.numero,
    required this.desde,
    required this.hasta,
    required this.vendiste,
    required this.compraste,
    required this.usaste,
  });

  double get ganaste => vendiste - usaste;
  String get nombre => 'Semana $numero';

  /// "1 – 4 oct".
  String get rango => desde.day == hasta.day ? '${desde.day} ${_mesCorto(desde)}' : '${desde.day} – ${hasta.day} ${_mesCorto(hasta)}';
}

/// Las semanas de un mes (de lunes a domingo; la primera y la última, recortadas al
/// mes) con lo vendido, lo comprado y lo usado en cada una. Solo con un mes elegido.
List<SemanaCV> semanasDelMes({
  required DateRange rango,
  required Map<String, double> ventas,
  required Map<String, ParCosto> porDia,
}) {
  if (rango.mode != PeriodMode.month) return const [];
  final anio = rango.start.year;
  final mes = rango.start.month;
  final dias = DateUtils.getDaysInMonth(anio, mes);

  final semanas = <SemanaCV>[];
  var desde = 1;
  void cierra(int hasta) {
    var v = 0.0, c = 0.0, u = 0.0;
    for (var d = desde; d <= hasta; d++) {
      final k = _diaDe(DateTime(anio, mes, d));
      v += ventas[k] ?? 0;
      c += porDia[k]?.comprado ?? 0;
      u += porDia[k]?.costo ?? 0;
    }
    semanas.add(SemanaCV(
      numero: semanas.length + 1,
      desde: DateTime(anio, mes, desde),
      hasta: DateTime(anio, mes, hasta),
      vendiste: v,
      compraste: c,
      usaste: u,
    ));
    desde = hasta + 1;
  }

  for (var d = 1; d <= dias; d++) {
    final domingo = DateTime(anio, mes, d).weekday == DateTime.sunday;
    if (domingo || d == dias) cierra(d);
  }
  return semanas;
}

// ── Por categoría ───────────────────────────────────────────────────────────

class FilaCategoria {
  final String nombre;
  final double compraste;

  /// Lo que queda en bodega; null si no se sabe.
  final double? teQueda;

  /// Lo que se vendió de esa categoría directo (reventa); null si va en platillos.
  final double? vendiste;
  final double usaste;

  const FilaCategoria({required this.nombre, required this.compraste, required this.teQueda, required this.vendiste, required this.usaste});

  bool get esReventa => vendiste != null;
  double? get ganaste => vendiste == null ? null : vendiste! - usaste;

  /// "Por cada Q1 vendiste Qx".
  double? get porCadaQ => vendiste != null && usaste > 0 ? vendiste! / usaste : null;
}

class CategoriasCV {
  /// Lo que se revende tal cual (cerveza, gaseosas), de más a menos vendido.
  final List<FilaCategoria> reventa;

  /// Los insumos que se cocinan, cada categoría con su compra y lo que queda.
  final List<FilaCategoria> insumos;

  /// Todos los insumos juntos: sus ventas son lo que no es reventa.
  final FilaCategoria? platillos;

  const CategoriasCV({this.reventa = const [], this.insumos = const [], this.platillos});

  static const vacia = CategoriasCV();

  bool get hayAlgo => reventa.isNotEmpty || insumos.isNotEmpty;

  /// [porIngrediente]: costo y compras por ingrediente (id).
  /// [categoriaDe]: id de ingrediente → nombre de su categoría.
  /// [reventaPorIngrediente]: id de ingrediente → lo vendido de los productos de
  /// reventa cuyo único ingrediente es ese.
  /// [bodegaPorCategoria]: lo que queda, por llave de categoría; null si no se sabe.
  /// [ventasTotales]: la venta neta; lo que no es reventa va a "Platillos".
  factory CategoriasCV.armar({
    required Map<String, ParCosto> porIngrediente,
    required Map<String, String> categoriaDe,
    required Map<String, double> reventaPorIngrediente,
    required Map<String, CategoriaValor>? bodegaPorCategoria,
    required double ventasTotales,
  }) {
    // Por categoría (llave): nombre, compras, costo y reventa.
    final nombres = <String, String>{};
    final compras = <String, double>{};
    final costo = <String, double>{};
    final reventa = <String, double>{};

    String llaveDe(String? ingId) {
      final n = ingId == null ? null : _texto(categoriaDe[ingId]);
      final nombre = n ?? 'Sin categoría';
      final k = claveDeCategoria(nombre);
      nombres.putIfAbsent(k, () => nombre);
      return k;
    }

    for (final e in porIngrediente.entries) {
      final k = llaveDe(e.key);
      compras.update(k, (x) => x + e.value.comprado, ifAbsent: () => e.value.comprado);
      costo.update(k, (x) => x + e.value.costo, ifAbsent: () => e.value.costo);
    }
    for (final e in reventaPorIngrediente.entries) {
      if (!(e.value > 0) || !e.value.isFinite) continue;
      final k = llaveDe(e.key);
      reventa.update(k, (x) => x + e.value, ifAbsent: () => e.value);
    }
    // Una categoría con algo en bodega aunque no se haya movido en el período.
    if (bodegaPorCategoria != null) {
      for (final e in bodegaPorCategoria.entries) {
        nombres.putIfAbsent(e.key, () => e.value.nombre);
      }
    }

    FilaCategoria fila(String k, {double? vendiste}) => FilaCategoria(
          nombre: nombres[k]!,
          compraste: compras[k] ?? 0,
          teQueda: bodegaPorCategoria == null ? null : (bodegaPorCategoria[k]?.valor ?? 0),
          vendiste: vendiste,
          usaste: costo[k] ?? 0,
        );

    final conReventa = [for (final k in reventa.keys) fila(k, vendiste: reventa[k])]
      ..sort((a, b) => b.vendiste!.compareTo(a.vendiste!));
    final resto = [for (final k in nombres.keys) if (!reventa.containsKey(k)) fila(k)]
      ..sort((a, b) {
        final c = b.compraste.compareTo(a.compraste);
        return c != 0 ? c : a.nombre.compareTo(b.nombre);
      });

    FilaCategoria? platillos;
    final vendidoDirecto = conReventa.fold<double>(0, (a, f) => a + f.vendiste!);
    final restoVendido = ventasTotales - vendidoDirecto;
    // Con insumos de cocina, o con ventas que no son reventa y ningún insumo
    // (vendido sin costo cargado): así las filas siempre suman el total.
    if (resto.isNotEmpty || (restoVendido.isFinite && restoVendido >= 0.5)) {
      final v = restoVendido;
      platillos = FilaCategoria(
        nombre: 'Platillos',
        compraste: resto.fold<double>(0, (a, f) => a + f.compraste),
        teQueda: bodegaPorCategoria == null ? null : resto.fold<double>(0, (a, f) => a + (f.teQueda ?? 0)),
        vendiste: v.isFinite && v > 0 ? v : 0,
        usaste: resto.fold<double>(0, (a, f) => a + f.usaste),
      );
    }
    return CategoriasCV(reventa: conReventa, insumos: resto, platillos: platillos);
  }
}

// ── Por sucursal ────────────────────────────────────────────────────────────

class FilaSucursalCV {
  final String id;
  final String nombre;
  final double compro;
  final double vendio;
  final double usaste;

  /// Lo que le queda en bodega; null si no se sabe.
  final double? leQueda;

  /// Qué pasó con su bodega; null si no se sabe.
  final EstadoBodega? estado;

  /// Cuánto cambió su bodega (fin − inicio); null si no se sabe.
  final double? cambio;

  const FilaSucursalCV({
    required this.id,
    required this.nombre,
    required this.compro,
    required this.vendio,
    required this.usaste,
    this.leQueda,
    this.estado,
    this.cambio,
  });

  double get gano => vendio - usaste;

  /// [porSucursal] sale de Rentabilidad (la misma cuenta que el total).
  static List<FilaSucursalCV> armar({
    required Map<String, ProfitabilityData> porSucursal,
    required List<(String id, String nombre)> sucursales,
    required BodegaPeriodo bodega,
  }) {
    return [
      for (final s in sucursales)
        if (porSucursal[s.$1] != null)
          () {
            final d = porSucursal[s.$1]!;
            final ini = bodega.inicioPorSucursal[s.$1];
            final fin = bodega.finPorSucursal[s.$1];
            final ambos = ini != null && fin != null;
            return FilaSucursalCV(
              id: s.$1,
              nombre: s.$2,
              compro: d.purchases,
              vendio: d.netSales,
              usaste: d.cogs,
              leQueda: fin,
              estado: ambos ? estadoDeBodega(inicio: ini, fin: fin, compraste: d.purchases) : null,
              cambio: ambos ? fin - ini : null,
            );
          }(),
    ];
  }
}
