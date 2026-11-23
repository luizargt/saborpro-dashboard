// Lo que el rediseño de Rentabilidad (2026-11-22, rentabilidad.html) calcula
// ENCIMA de los números de siempre ([ProfitabilityData], que no cambian):
// qué sucursales no tienen gastos fijos, el día en que se cubrió el punto de
// equilibrio, la comparación entre sucursales, y todo lo que sale de cruzar el
// menú con lo que se vendió (mapa del menú, ganancia por platillo, recetas por
// completar).
//
// Todo es Dart puro, sin Firestore ni providers, y NUNCA lanza ante un dato
// roto: los pedidos vienen de Firestore con campos que cambiaron con los años.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

import '../../core/utils/date_range.dart';
import 'menu_margin_data.dart';
import 'profitability_data.dart';
import 'rentabilidad_calculo.dart';

// ── Metas del rubro (las del diseño) ────────────────────────────────────────

/// Con qué meta se compara el costo de la receta de un platillo.
enum MetaReceta {
  comida(35, 'Comida'),
  bebida(25, 'Bebida prep.'),
  reventa(70, 'Reventa');

  /// El costo de la receta no debería pasar de este % del precio.
  final double pct;
  final String etiqueta;
  const MetaReceta(this.pct, this.etiqueta);
}

/// A qué meta pertenece un platillo.
///
/// OJO, es una regla nuestra: el menú no guarda si algo es "de reventa". Se
/// llama reventa a lo que se compra hecho y se vende tal cual: la receta es UN
/// solo ingrediente, en cantidad 1 y en unidades (una lata, una botella), y no
/// está clasificado como Comida ni Postres. Bebida preparada es lo clasificado
/// como Bebidas que no es reventa. Todo lo demás cuenta como comida.
///
/// [clasificacion] es la que ya usa el dashboard ("Comida", "Bebidas",
/// "Postres"…); null si no se conoce.
MetaReceta metaDe(MargenPlatillo p, String? clasificacion) {
  final c = clasificacion?.trim().toLowerCase();
  final esComida = c == 'comida' || c == 'postres';
  if (!esComida && p.lineas.length == 1) {
    final l = p.lineas.first;
    if ((l.cantidad - 1).abs() < 1e-9 && l.unidad == 'und.') return MetaReceta.reventa;
  }
  if (c == 'bebidas' || c == 'bebida') return MetaReceta.bebida;
  return MetaReceta.comida;
}

// ── Gastos fijos que faltan ─────────────────────────────────────────────────

/// Los nombres de las sucursales que no tienen NINGÚN gasto fijo anotado (renta,
/// sueldos, internet, seguros). Sin ellos la utilidad de esa sucursal sale más
/// alta de lo real: no son "cero de gastos", es que nadie los anotó.
///
/// [sucursales] son las que se ven, en orden. Los gastos de otra sucursal no
/// cuentan.
List<String> sucursalesSinGastosFijos({
  required List<Map<String, dynamic>> gastos,
  required List<(String id, String nombre)> sucursales,
}) {
  final conFijos = <String>{};
  for (final g in gastos) {
    final loc = g['location_id'];
    if (loc is! String) continue;
    final monto = g['amount'];
    if (monto is! num || !(monto > 0)) continue;
    if (esGastoFijo(g)) conFijos.add(loc);
  }
  return [for (final s in sucursales) if (!conFijos.contains(s.$1)) s.$2];
}

// ── El día en que se cubrió el punto de equilibrio ──────────────────────────

/// "octubre". En español si el idioma está cargado; si no (una prueba), en el
/// de por defecto en vez de lanzar.
String nombreDelMes(DateTime d) {
  try {
    return DateFormat('MMMM', 'es').format(d);
  } catch (_) {
    return DateFormat('MMMM').format(d);
  }
}

/// El día del mes en que las ventas cubrieron el punto de equilibrio, SOLO con
/// un mes elegido y si ya se cubrió. Es una estimación: reparte lo vendido en
/// partes iguales entre los días que van (los del mes entero si ya terminó).
/// Null cuando no aplica o no se puede decir.
int? diaDeEquilibrio(ProfitabilityData d, DateRange rango, DateTime ahora) {
  if (rango.mode != PeriodMode.month) return null;
  final be = d.breakEven;
  if (be == null || !be.isFinite || be <= 0) return null;
  if (!d.netSales.isFinite || d.netSales < be) return null;

  final diasDelMes = DateUtils.getDaysInMonth(rango.start.year, rango.start.month);
  // En UTC: restar fechas locales pierde una hora en el mes del cambio de horario
  // y `inDays` trunca un día de menos.
  final inicio = DateTime.utc(rango.start.year, rango.start.month, rango.start.day);
  final hoy = DateTime.utc(ahora.year, ahora.month, ahora.day);
  final corridos = hoy.isBefore(inicio)
      ? 0
      : math.min(diasDelMes, hoy.difference(inicio).inDays + 1);
  if (corridos <= 0) return null;

  // Se cubre cuando (días × lo vendido por día) llega al equilibrio. Se despeja el
  // día con una sola división: be ÷ (ventas ÷ días) daba 7.000000000000001 donde
  // la cuenta exacta es 7, y el día salía uno de más. El 1e-9 absorbe ese ruido.
  final dia = (be * corridos / d.netSales - 1e-9).ceil();
  return dia.clamp(1, corridos);
}

// ── Comparación entre sucursales ────────────────────────────────────────────

/// Los números de una sucursal para compararla con las demás.
class SucursalRentabilidad {
  final String id;
  final String nombre;
  final ProfitabilityData datos;

  const SucursalRentabilidad(this.id, this.nombre, this.datos);

  double get ventas => datos.netSales;
  double? get costoPct => datos.foodCostPct;

  /// Todo lo que se gastó (no solo lo fijo): es lo que resta la utilidad.
  double get gastos => datos.totalExpenses;
  double get utilidad => datos.operatingProfit;
  double? get margen => datos.marginPct;

  /// Con gastos fijos anotados: sin ellos la utilidad no es real y no se
  /// compara.
  bool get conGastosFijos => !datos.sinCostosFijos;

  /// Con casi todo lo vendido valorizado a su costo del momento. Una sucursal sin
  /// costo de comida cargado parece ganar muchísimo, pero es que nadie anotó lo
  /// que le costó.
  bool get costoConfiable => datos.costoConfiable;

  bool get sinMovimiento => datos.sinDatos;
}

class ComparacionSucursales {
  final List<SucursalRentabilidad> filas;

  /// La de más margen entre las que se pueden comparar (con gastos fijos y con su
  /// costo de comida cargado); solo cuando hay al menos dos (con una sola,
  /// "ganar" no dice nada).
  final SucursalRentabilidad? mejor;

  /// Lo vendido que entra en "Todas" pero no en estas tarjetas: sucursales
  /// ocultas o bodegas, y pedidos sin sucursal. Para decirlo en pantalla en vez
  /// de dejar un total que no se puede cuadrar con las tarjetas.
  final double ventasFuera;

  const ComparacionSucursales(this.filas, this.mejor, {this.ventasFuera = 0});

  static const vacia = ComparacionSucursales([], null);

  bool get hayQueComparar => filas.length >= 2;

  /// [porSucursal] sale del provider (la misma cuenta que el total);
  /// [sucursales] son las que se ven, en el orden de las pestañas.
  /// [ventasTotales] son las ventas netas de "Todas", para saber cuánto no está
  /// en ninguna tarjeta.
  factory ComparacionSucursales.armar({
    required Map<String, ProfitabilityData> porSucursal,
    required List<(String id, String nombre)> sucursales,
    double? ventasTotales,
  }) {
    final filas = [
      for (final s in sucursales)
        if (porSucursal[s.$1] != null) SucursalRentabilidad(s.$1, s.$2, porSucursal[s.$1]!),
    ];
    final comparables = [
      for (final f in filas)
        if (f.conGastosFijos && f.costoConfiable && f.ventas > 0 && f.margen != null) f,
    ];
    SucursalRentabilidad? mejor;
    if (comparables.length >= 2) {
      mejor = comparables.reduce((a, b) => b.margen! > a.margen! ? b : a);
    }
    final fuera = ventasTotales == null ? 0.0 : ventasTotales - filas.fold<double>(0, (a, f) => a + f.ventas);
    return ComparacionSucursales(filas, mejor, ventasFuera: fuera.isFinite ? fuera : 0);
  }
}

// ── Lo vendido por platillo ─────────────────────────────────────────────────

class VentaDePlatillo {
  final int cantidad;

  /// Lo cobrado por esas unidades al precio de la línea (sin extras ni
  /// descuentos).
  final double ventas;
  const VentaDePlatillo(this.cantidad, this.ventas);
}

/// Cuántas unidades de cada presentación del menú se vendieron en los pedidos.
class UnidadesVendidas {
  /// 'productoId|presentacionId' (la `clave` de [MargenPlatillo]) → lo vendido.
  final Map<String, VentaDePlatillo> porClave;

  /// Unidades de pedidos que no se pudieron ligar a un platillo del menú
  /// (borrado, o sin presentación en un producto que tiene varias).
  final int sinIdentificar;

  const UnidadesVendidas(this.porClave, this.sinIdentificar);

  static const vacio = UnidadesVendidas({}, 0);

  int cantidadDe(String clave) => porClave[clave]?.cantidad ?? 0;

  /// Cuenta lo vendido en [ordenes] (los pedidos cobrados del período), de la
  /// sucursal [sucursal] o de todas si es null. No cuentan las líneas anuladas
  /// ni las de cortesía —no se vendieron—, ni los pedidos de devolución.
  ///
  /// [soloSucursales] acota además a esas sucursales (en "Todas" con sucursales
  /// de otra moneda, el menú se costea solo con las de una).
  factory UnidadesVendidas.desde(
    List<Map<String, dynamic>> ordenes,
    List<MargenPlatillo> platillos, {
    String? sucursal,
    Set<String>? soloSucursales,
  }) {
    final claves = {for (final p in platillos) p.clave};
    final porProducto = <String, List<String>>{};
    for (final p in platillos) {
      porProducto.putIfAbsent(p.productoId, () => []).add(p.clave);
    }

    final cantidades = <String, int>{};
    final ventas = <String, double>{};
    var sinIdentificar = 0;

    for (final o in ordenes) {
      if (sucursal != null && o['location_id'] != sucursal) continue;
      if (soloSucursales != null && !soloSucursales.contains(o['location_id'])) continue;
      if (o['is_refund'] == true) continue;
      final items = o['items'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        if (item['is_void'] == true || item['is_courtesy'] == true) continue;

        final qtyCruda = item['qty'] ?? item['quantity'] ?? 1;
        final qty = qtyCruda is num && qtyCruda.isFinite ? qtyCruda.round() : 0;
        if (qty <= 0) continue;

        final prod = item['product_id']?.toString() ?? '';
        final pres = item['presentation_id']?.toString() ?? '';

        String? clave;
        if (pres.isNotEmpty) {
          final k = '$prod|$pres';
          if (claves.contains(k)) clave = k;
        } else {
          // Sin presentación: solo se sabe cuál es si el producto tiene una.
          final candidatas = porProducto[prod];
          if (candidatas != null && candidatas.length == 1) clave = candidatas.single;
        }
        if (clave == null) {
          sinIdentificar += qty;
          continue;
        }

        final precioCrudo = item['unit_price'] ?? item['price'] ?? 0;
        final precio = precioCrudo is num && precioCrudo.isFinite ? precioCrudo.toDouble() : 0.0;
        cantidades[clave] = (cantidades[clave] ?? 0) + qty;
        ventas[clave] = (ventas[clave] ?? 0) + precio * qty;
      }
    }

    return UnidadesVendidas({
      for (final e in cantidades.entries) e.key: VentaDePlatillo(e.value, ventas[e.key] ?? 0),
    }, sinIdentificar);
  }
}

// ── El menú cruzado con lo vendido ──────────────────────────────────────────

/// Un platillo con lo que se vendió de él.
class PlatilloVendido {
  final MargenPlatillo platillo;
  final int cantidad;
  final double ventas;
  final MetaReceta meta;

  const PlatilloVendido(this.platillo, this.cantidad, this.ventas, this.meta);

  String get nombre => platillo.producto;
  String? get presentacion => platillo.presentacion;

  /// Lo que deja cada venta: precio menos costo de receta. Solo con costo
  /// completo ([AnalisisMenu] solo pone aquí lo confiable).
  double get gananciaPorVenta => (platillo.margenReceta ?? 0) / 100;
  double get gananciaTotal => gananciaPorVenta * cantidad;

  /// Qué parte del precio se va en la receta.
  double get recetaPct =>
      platillo.precio > 0 && platillo.costo != null ? platillo.costo! / platillo.precio * 100 : 0;

  /// Cuánto pasa (positivo) o queda por debajo (negativo) de la meta de su tipo.
  double get sobreLaMeta => recetaPct - meta.pct;
}

/// Los cuatro cuadrantes del mapa del menú.
enum Cuadrante {
  /// Gana mucho y se vende mucho.
  estrella,

  /// Gana poco y se vende mucho.
  caballo,

  /// Gana mucho y se vende poco.
  rompecabezas,

  /// Gana poco y se vende poco.
  perro,
}

class AnalisisMenu {
  /// Los platillos vendidos con costo completo y sin señales de dato mal
  /// cargado: los únicos que se pueden poner en el mapa y en el ranking.
  final List<PlatilloVendido> analizados;

  /// Lo vendido que NO entra por falta de costo confiable (sin receta, con
  /// ingredientes sin precio o con la receta por revisar).
  final int sinCostoConfiable;

  /// Lo que más se vende sin receta, de más a menos vendido en plata. Mientras
  /// no tengan receta, su costo cuenta como cero.
  final List<PlatilloVendido> sinReceta;

  /// Vendidos con receta pero a los que les falta el precio de algún
  /// ingrediente (o un ingrediente no existe en la sucursal).
  final int incompletos;

  /// Unidades vendidas que no se pudieron ligar a un platillo.
  final int sinIdentificar;

  const AnalisisMenu({
    this.analizados = const [],
    this.sinCostoConfiable = 0,
    this.sinReceta = const [],
    this.incompletos = 0,
    this.sinIdentificar = 0,
  });

  static const vacio = AnalisisMenu();

  bool get hayAlgo => analizados.isNotEmpty || sinReceta.isNotEmpty || incompletos > 0;

  /// [clasificacion] es productoId → "Comida"/"Bebidas"/… (la del dashboard).
  factory AnalisisMenu.armar({
    required List<MargenPlatillo> platillos,
    required UnidadesVendidas vendidas,
    Map<String, String> clasificacion = const {},
  }) {
    final analizados = <PlatilloVendido>[];
    final sinReceta = <PlatilloVendido>[];
    var sinCosto = 0;
    var incompletos = 0;

    for (final p in platillos) {
      final v = vendidas.porClave[p.clave];
      if (v == null || v.cantidad <= 0) continue;
      final pv = PlatilloVendido(p, v.cantidad, v.ventas, metaDe(p, clasificacion[p.productoId]));

      if (p.estado == EstadoCosto.sinReceta) {
        sinReceta.add(pv);
        sinCosto++;
      } else if (p.estado == EstadoCosto.incompleto) {
        incompletos++;
        sinCosto++;
      } else if (p.porRevisar || p.precio <= 0) {
        sinCosto++;
      } else {
        analizados.add(pv);
      }
    }

    sinReceta.sort((a, b) {
      final c = b.ventas.compareTo(a.ventas);
      return c != 0 ? c : a.platillo.nombre.compareTo(b.platillo.nombre);
    });

    return AnalisisMenu(
      analizados: analizados,
      sinCostoConfiable: sinCosto,
      sinReceta: sinReceta,
      incompletos: incompletos,
      sinIdentificar: vendidas.sinIdentificar,
    );
  }

  /// Cuánto se vende de un platillo "normal" (el promedio de unidades) y cuánto
  /// gana, de media, cada venta (ponderada por lo vendido).
  @visibleForTesting
  ({double unidades, double ganancia}) get promedios {
    if (analizados.isEmpty) return (unidades: 0, ganancia: 0);
    final unidades = analizados.fold<int>(0, (a, p) => a + p.cantidad);
    final ganancia = analizados.fold<double>(0, (a, p) => a + p.gananciaPorVenta * p.cantidad);
    return (unidades: unidades / analizados.length, ganancia: ganancia / unidades);
  }

  /// Cada platillo en su cuadrante. "Se vende mucho" = al menos el 70% de lo que
  /// vende un platillo promedio; "gana mucho" = deja algo y al menos lo que deja,
  /// en promedio, una venta. Dentro de cada cuadrante, los más vendidos primero.
  ///
  /// Las comparaciones van con enteros (centavos y unidades), sin dividir: con
  /// promedios en decimales, un platillo que ES el promedio quedaba 1 ulp por
  /// debajo y salía "gana poco" (un solo platillo, o varios con la misma
  /// ganancia).
  Map<Cuadrante, List<PlatilloVendido>> get mapa {
    final r = {for (final c in Cuadrante.values) c: <PlatilloVendido>[]};
    final n = analizados.length;
    if (n == 0) return r;

    var unidades = 0;
    var ponderado = 0; // centavos × unidades
    for (final p in analizados) {
      unidades += p.cantidad;
      ponderado += (p.platillo.margenReceta ?? 0) * p.cantidad;
    }

    for (final p in analizados) {
      // cantidad ≥ 0.7 × (unidades ÷ n)
      final vendeMucho = p.cantidad * n * 10 >= unidades * 7;
      final m = p.platillo.margenReceta ?? 0;
      // m ≥ ponderado ÷ unidades
      final ganaMucho = m > 0 && m * unidades >= ponderado;
      final c = ganaMucho
          ? (vendeMucho ? Cuadrante.estrella : Cuadrante.rompecabezas)
          : (vendeMucho ? Cuadrante.caballo : Cuadrante.perro);
      r[c]!.add(p);
    }
    for (final l in r.values) {
      l.sort((a, b) {
        final c = b.cantidad.compareTo(a.cantidad);
        return c != 0 ? c : a.platillo.nombre.compareTo(b.platillo.nombre);
      });
    }
    return r;
  }

  /// Los que más dejan en total (ganancia por venta × lo vendido).
  List<PlatilloVendido> masGanancia(int n) {
    final l = [...analizados]..sort((a, b) {
        final c = b.gananciaTotal.compareTo(a.gananciaTotal);
        return c != 0 ? c : a.platillo.nombre.compareTo(b.platillo.nombre);
      });
    return l.take(n).toList();
  }

  /// "Revisa su precio": los que más se pasan de la meta de su tipo. "Más
  /// ganancia": los que más por debajo de su meta están. Ninguno aparece en las
  /// dos listas, y solo entran los que de verdad pasan o quedan por debajo.
  ({List<PlatilloVendido> revisa, List<PlatilloVendido> mas}) porVenta({int n = 5}) {
    int orden(PlatilloVendido a, PlatilloVendido b) {
      final c = b.sobreLaMeta.compareTo(a.sobreLaMeta);
      return c != 0 ? c : a.platillo.nombre.compareTo(b.platillo.nombre);
    }

    final l = [...analizados]..sort(orden);
    final revisa = [for (final p in l) if (p.sobreLaMeta > 0) p].take(n).toList();
    final mas = [for (final p in l.reversed) if (p.sobreLaMeta <= 0) p].take(n).toList();
    return (revisa: revisa, mas: mas);
  }
}
