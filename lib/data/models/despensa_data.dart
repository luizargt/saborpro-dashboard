/// Lo que se ve en Despensa (rediseño 2026-11-21, `despensa.html` de saborpro_app
/// en su modo oscuro), sin widgets: el estado de cada ingrediente por los días que
/// alcanza, cuánto dinero hay en la despensa y en qué orden se muestra.
///
/// El estado ahora sale de los DÍAS que alcanza (como el diseño): agotado si no
/// queda nada, "pronto" si se acaba en menos de [diasPronto] días y "bien" si no.
/// Antes salía del stock mínimo (`IngredientStock.statusAt`), que sigue sirviendo
/// al Excel; esa regla colorea sin que se vea por qué, y un ingrediente sin
/// mínimo anotado nunca avisaba.
///
/// Los días son stock ÷ consumo diario promedio de los últimos 30 días (ver
/// `InventoryProvider`). Sin consumo no se pueden calcular: el ingrediente cuenta
/// como "bien" (no se acaba) y la celda dice "Sin consumo".
library;

import 'dart:math' as math;

import 'inventory_data.dart';

/// Menos de estos días de stock es "Pronto".
const diasPronto = 10;

enum EstadoDespensa { agotado, pronto, bien }

/// El estado de una existencia: [stock] nulo = el ingrediente no se maneja ahí.
EstadoDespensa? estadoPorDias(double? stock, double? dias) {
  if (stock == null) return null;
  if (stock <= 0) return EstadoDespensa.agotado;
  if (dias != null && dias < diasPronto) return EstadoDespensa.pronto;
  return EstadoDespensa.bien;
}

/// "+180 días", "<1 día", "1 día", "12 días".
String textoDias(double dias) {
  if (dias > 180) return '+180 días';
  if (dias < 1) return '<1 día';
  final n = dias.round();
  return '$n ${n == 1 ? 'día' : 'días'}';
}

/// Las cantidades sin ceros de más: "12", "0.5", "0.25".
String textoCantidad(double v) {
  if (v == 0) return '0';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
}

/// Lo que hay de un ingrediente en una sucursal.
class CeldaDespensa {
  final double stock;

  /// Cuántos días alcanza; nulo si no hubo consumo para calcularlo.
  final double? dias;
  final EstadoDespensa estado;

  const CeldaDespensa(this.stock, this.dias, this.estado);
}

/// Una fila de la tabla: un ingrediente visto en las sucursales que se muestran.
class FilaDespensa {
  final IngredientStock item;

  /// Los ids de las sucursales que se ven (todas, o la elegida).
  final List<String> sucursales;

  const FilaDespensa(this.item, this.sucursales);

  CeldaDespensa? celda(String idSucursal) {
    final stock = item.stockByLocation[idSucursal];
    if (stock == null) return null;
    final dias = item.daysRemainingByLocation[idSucursal];
    return CeldaDespensa(stock, dias, estadoPorDias(stock, dias)!);
  }

  Iterable<CeldaDespensa> get celdas sync* {
    for (final id in sucursales) {
      final c = celda(id);
      if (c != null) yield c;
    }
  }

  /// El peor estado entre las sucursales que se ven; nulo si no se maneja en ninguna.
  EstadoDespensa? get peor {
    EstadoDespensa? peor;
    for (final c in celdas) {
      if (c.estado == EstadoDespensa.agotado) return EstadoDespensa.agotado;
      if (c.estado == EstadoDespensa.pronto) peor = EstadoDespensa.pronto;
      peor ??= EstadoDespensa.bien;
    }
    return peor;
  }

  /// Lo que hay en total en las sucursales que se ven.
  double get total => celdas.fold(0.0, (a, c) => a + c.stock);

  /// Los menos días que le quedan en alguna sucursal; nulo si en ninguna se sabe.
  double? get minDias {
    double? m;
    for (final c in celdas) {
      if (c.dias != null && (m == null || c.dias! < m)) m = c.dias;
    }
    return m;
  }

  /// Cuánto vale lo que hay, a su último precio de compra. Nulo si no se sabe:
  /// hay existencia en alguna sucursal sin precio anotado (no se asume cero).
  double? get valor {
    var suma = 0.0;
    for (final id in sucursales) {
      final stock = item.stockByLocation[id];
      if (stock == null || stock <= 0) continue;
      final costo = item.costByLocation[id];
      if (costo == null) return null;
      suma += stock * costo;
    }
    return suma;
  }

  /// Cuánto vale lo que hay SOLO en una sucursal (nulo si no se sabe).
  double? valorEn(String idSucursal) {
    final stock = item.stockByLocation[idSucursal];
    if (stock == null || stock <= 0) return stock == null ? null : 0;
    final costo = item.costByLocation[idSucursal];
    return costo == null ? null : stock * costo;
  }

  /// Hay existencia sin precio anotado.
  bool get sinPrecio {
    for (final id in sucursales) {
      final stock = item.stockByLocation[id];
      if (stock != null && stock > 0 && item.costByLocation[id] == null) return true;
    }
    return false;
  }

  double consumo7(List<String> dias) => item.totalConsumptionLast7Days(dias, sucursales);
  double consumoDia(String dia) => item.consumptionOnDay(dia, sucursales);
}

/// Los conteos y el dinero de la despensa.
class ResumenDespensa {
  final int agotados;
  final int pronto;
  final int bien;

  /// Lo que vale lo que hay, por sucursal (solo donde se sabe de todos los
  /// ingredientes con existencia: ver [sinPrecio]).
  final Map<String, double> valorPorSucursal;

  /// Cuántos ingredientes tienen existencia sin precio de compra anotado: el
  /// dinero de arriba no los incluye.
  final int sinPrecio;

  const ResumenDespensa({
    required this.agotados,
    required this.pronto,
    required this.bien,
    required this.valorPorSucursal,
    required this.sinPrecio,
  });

  int get total => agotados + pronto + bien;

  int cuantos(EstadoDespensa e) => switch (e) {
        EstadoDespensa.agotado => agotados,
        EstadoDespensa.pronto => pronto,
        EstadoDespensa.bien => bien,
      };

  /// [filas]: las filas de las sucursales que se ven. El valor de cada sucursal
  /// suma lo que hay ahí con precio conocido.
  static ResumenDespensa de(List<FilaDespensa> filas, List<String> sucursales) {
    var a = 0, p = 0, b = 0, sin = 0;
    final valor = {for (final id in sucursales) id: 0.0};
    for (final f in filas) {
      switch (f.peor) {
        case EstadoDespensa.agotado:
          a++;
        case EstadoDespensa.pronto:
          p++;
        case EstadoDespensa.bien:
          b++;
        case null:
          break;
      }
      if (f.sinPrecio) sin++;
      for (final id in sucursales) {
        final v = f.valorEn(id);
        if (v != null) valor[id] = valor[id]! + v;
      }
    }
    return ResumenDespensa(agotados: a, pronto: p, bien: b, valorPorSucursal: valor, sinPrecio: sin);
  }
}

class Despensa {
  Despensa._();

  /// Las filas de [items] en las sucursales [sucursales]: solo los ingredientes
  /// que se manejan en alguna de ellas.
  static List<FilaDespensa> filas(List<IngredientStock> items, List<String> sucursales) => [
        for (final i in items)
          if (sucursales.any(i.stockByLocation.containsKey)) FilaDespensa(i, sucursales),
      ];

  static bool _coincide(FilaDespensa f, String consulta) {
    final q = consulta.trim().toLowerCase();
    return q.isEmpty || f.item.name.toLowerCase().contains(q);
  }

  /// "Días que alcanza": lo que coincide con la búsqueda y el estado, lo más
  /// urgente primero (agotados, después los que se acaban pronto, después los
  /// demás; dentro de cada grupo, los que menos días tienen, y por nombre).
  static List<FilaDespensa> porUrgencia(List<FilaDespensa> filas, {String consulta = '', EstadoDespensa? estado}) {
    int rango(FilaDespensa f) => f.peor?.index ?? 3;
    return filas.where((f) => _coincide(f, consulta) && (estado == null || f.peor == estado)).toList()
      ..sort((a, b) {
        final r = rango(a).compareTo(rango(b));
        if (r != 0) return r;
        final da = a.minDias, db = b.minDias;
        if (da != db) {
          if (da == null) return 1;
          if (db == null) return -1;
          final d = da.compareTo(db);
          if (d != 0) return d;
        }
        return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
      });
  }

  /// "Consumo 7 días": solo lo que se consumió, de más a menos (y, si se pide, solo
  /// lo de ese estado: el filtro es el mismo en los dos modos).
  static List<FilaDespensa> porConsumo(List<FilaDespensa> filas, List<String> dias, {String consulta = '', EstadoDespensa? estado}) {
    return filas.where((f) => _coincide(f, consulta) && (estado == null || f.peor == estado) && f.consumo7(dias) > 0).toList()
      ..sort((a, b) => b.consumo7(dias).compareTo(a.consumo7(dias)));
  }

  /// Qué tan oscura va una celda del consumo: de 8% a 50% del color de acento,
  /// según qué tanto se consumió contra lo máximo de la tabla.
  static double intensidad(double cantidad, double maximo) =>
      maximo <= 0 ? 0.08 : (8 + cantidad / maximo * 42) / 100;

  /// El mayor consumo de un día en una sola celda (para la intensidad).
  static double maximoDiario(List<FilaDespensa> filas, List<String> dias) {
    var m = 0.0;
    for (final f in filas) {
      for (final d in dias) {
        m = math.max(m, f.consumoDia(d));
      }
    }
    return m;
  }
}
