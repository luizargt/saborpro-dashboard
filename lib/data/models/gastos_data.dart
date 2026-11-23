/// Lo que se ve en Gastos (rediseño 2026-11-22, `gastos.html` de saborpro_app en
/// su modo oscuro), sin widgets: las compras de insumos, los gastos operacionales
/// y los retiros de caja del período, y los análisis que el diseño pide (cuánto se
/// va en compras contra lo vendido, a quién se le compra más, qué subió de
/// precio y dónde sale más barato el mismo insumo).
///
/// Todo se lee SIN lanzar: un renglón con un dato mal escrito (un número como
/// texto, un campo de otro tipo) no puede dejar sin pantalla a todos los demás.
///
/// Lo que no se sabe no se inventa: sin ventas no hay "de cada Q100", sin el
/// período anterior no hay comparación, y un insumo sin precio no entra a las
/// comparaciones de precio.
library;

import 'cierres_caja.dart' show fechaCorta;
import 'despensa_data.dart' show textoCantidad;

String? _texto(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _fecha(dynamic v) {
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  try {
    return (v as dynamic).toDate().toLocal() as DateTime;
  } catch (_) {}
  return null;
}

const _acentos = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n',
};

/// Un nombre para comparar: sin acentos, sin mayúsculas ni espacios de más.
String claveDe(String t) {
  final b = StringBuffer();
  for (final c in t.trim().toLowerCase().split('')) {
    b.write(_acentos[c] ?? c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// El % de cambio de [actual] contra [anterior], redondeado; nulo si no hay con
/// qué comparar (anterior en cero).
int? cambioPct(double actual, double? anterior) {
  if (anterior == null || anterior <= 0) return null;
  return ((actual - anterior) / anterior * 100).round();
}

/// Un insumo de una compra.
class LineaCompra {
  final String insumo;

  /// Cuánto se recibió (nulo si no se sabe) y en qué unidad ("u", "lb").
  final double? cantidad;
  final String unidad;

  /// Cuánto costó esta línea.
  final double costo;

  /// Lo que costó cada unidad; nulo si no se puede saber.
  final double? precio;

  const LineaCompra({
    required this.insumo,
    required this.cantidad,
    required this.unidad,
    required this.costo,
    required this.precio,
  });

  /// "25 u". Sin cantidad, la unidad sola o nada.
  String get cantidadTexto {
    final c = cantidad;
    if (c == null || c <= 0) return unidad;
    return unidad.isEmpty ? textoCantidad(c) : '${textoCantidad(c)} $unidad';
  }

  /// Una línea de una orden de compra; nula si no se compró nada (no se consiguió).
  static LineaCompra? desde(dynamic crudo) {
    if (crudo is! Map) return null;
    if (crudo['no_conseguido'] == true) return null;
    final nombre = _texto(crudo['ingredient_name']) ?? _texto(crudo['name']);
    if (nombre == null) return null;
    final recibida = _num(crudo['received_quantity']);
    final pedida = _num(crudo['requested_quantity']);
    final cantidad = (recibida != null && recibida > 0) ? recibida : (pedida != null && pedida > 0 ? pedida : null);
    final unitario = (_num(crudo['actual_unit_price']) ?? 0) > 0 ? _num(crudo['actual_unit_price']) : _num(crudo['unit_price']);
    final pagado = _num(crudo['total_pagado']);
    final costo = pagado ?? ((cantidad ?? 0) * (unitario != null && unitario > 0 ? unitario : 0));
    if (costo <= 0 && (cantidad == null)) return null;
    final precio = (unitario != null && unitario > 0)
        ? unitario
        : (pagado != null && cantidad != null ? pagado / cantidad : null);
    return LineaCompra(
      insumo: nombre,
      cantidad: cantidad,
      unidad: _texto(crudo['unit_abbreviation']) ?? _texto(crudo['unit']) ?? '',
      costo: costo,
      precio: precio,
    );
  }
}

/// Una compra de insumos (orden de compra recibida).
class Compra {
  final int? numero;
  final String? proveedor;
  final DateTime? fecha;
  final String? sucursal;
  final double total;
  final String? notas;
  final List<LineaCompra> lineas;

  /// Una llave que no se repite entre sucursales ni entre compras sin número.
  final String llave;

  const Compra({
    required this.numero,
    required this.proveedor,
    required this.fecha,
    required this.sucursal,
    required this.total,
    required this.notas,
    required this.lineas,
    required this.llave,
  });

  String get nombre => proveedor ?? 'Sin proveedor';

  static Compra desde(Map<String, dynamic> o, int posicion) {
    final num = o['order_number'];
    final numero = num is int ? num : (num is double ? num.toInt() : int.tryParse('$num'));
    final lineas = <LineaCompra>[];
    final crudas = o['items'];
    if (crudas is List) {
      for (final l in crudas) {
        final x = LineaCompra.desde(l);
        if (x != null) lineas.add(x);
      }
    }
    return Compra(
      numero: numero,
      proveedor: _texto(o['supplier_name']),
      fecha: _fecha(o['received_at']),
      sucursal: _texto(o['location_id']),
      total: _num(o['total']) ?? 0,
      notas: _texto(o['notes']),
      lineas: lineas,
      llave: 'c-${_texto(o['location_id']) ?? ''}-${numero ?? 'x'}-$posicion',
    );
  }
}

/// Un gasto operacional o un retiro de caja.
class GastoLinea {
  final String concepto;
  final String categoria;
  final String? usuario;
  final DateTime? fecha;
  final double monto;
  final String? sucursal;

  /// Un retiro de caja: de qué cajero y a qué hora.
  final bool esRetiro;
  final String? idCaja;
  final String? cajero;
  final String llave;

  const GastoLinea({
    required this.concepto,
    required this.categoria,
    required this.usuario,
    required this.fecha,
    required this.monto,
    required this.sucursal,
    required this.esRetiro,
    required this.idCaja,
    required this.cajero,
    required this.llave,
  });

  static GastoLinea desde(Map<String, dynamic> e, int posicion) {
    final retiro = e['source'] == 'cashRegister';
    final categoria = _texto(e['category_name']) ?? 'Sin categoría';
    return GastoLinea(
      concepto: _texto(e['description']) ?? categoria,
      categoria: categoria,
      usuario: _texto(e['registered_by']),
      fecha: _fecha(e['date']),
      monto: _num(e['amount']) ?? 0,
      sucursal: _texto(e['location_id']),
      esRetiro: retiro,
      idCaja: retiro ? (_texto(e['register_id']) ?? 'desconocida') : null,
      cajero: retiro ? _texto(e['register_user']) : null,
      llave: 'g-${retiro ? 'r' : 'm'}-$posicion',
    );
  }
}

/// Las compras y los gastos de un período.
class GastosPeriodo {
  final List<Compra> compras;
  final List<GastoLinea> manuales;
  final List<GastoLinea> retiros;

  const GastosPeriodo({this.compras = const [], this.manuales = const [], this.retiros = const []});

  static const vacio = GastosPeriodo();

  /// [compras]: las órdenes de compra recibidas. [gastos]: los gastos manuales y
  /// los retiros de caja juntos (como los entrega el provider). Del más reciente
  /// al más antiguo.
  factory GastosPeriodo.desde(List<Map<String, dynamic>> compras, List<Map<String, dynamic>> gastos) {
    int porFecha(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    final cs = [for (var i = 0; i < compras.length; i++) Compra.desde(compras[i], i)]..sort((a, b) => porFecha(a.fecha, b.fecha));
    final gs = [for (var i = 0; i < gastos.length; i++) GastoLinea.desde(gastos[i], i)];
    return GastosPeriodo(
      compras: cs,
      manuales: gs.where((g) => !g.esRetiro).toList()..sort((a, b) => porFecha(a.fecha, b.fecha)),
      retiros: gs.where((g) => g.esRetiro).toList()..sort((a, b) => porFecha(a.fecha, b.fecha)),
    );
  }

  double get totalCompras => compras.fold(0.0, (s, c) => s + c.total);
  double get totalManuales => manuales.fold(0.0, (s, g) => s + g.monto);
  double get totalRetiros => retiros.fold(0.0, (s, g) => s + g.monto);

  /// Todo lo que se gastó: compras, gastos y retiros. Es la cifra de siempre
  /// ("Total gastos del período").
  double get total => totalCompras + totalManuales + totalRetiros;

  bool get hayAlgo => compras.isNotEmpty || manuales.isNotEmpty || retiros.isNotEmpty;

  int get cuantos => compras.length + manuales.length + retiros.length;

  /// Lo gastado en una sucursal.
  double totalEn(String? sucursal) =>
      compras.where((c) => c.sucursal == sucursal).fold(0.0, (s, c) => s + c.total) +
      manuales.where((g) => g.sucursal == sucursal).fold(0.0, (s, g) => s + g.monto) +
      retiros.where((g) => g.sucursal == sucursal).fold(0.0, (s, g) => s + g.monto);
}

/// Un insumo que subió de precio contra la compra anterior.
class SubidaPrecio {
  final String insumo;
  final String proveedor;
  final String unidad;
  final double anterior;
  final double nuevo;

  const SubidaPrecio(this.insumo, this.proveedor, this.unidad, this.anterior, this.nuevo);

  int get pct => cambioPct(nuevo, anterior) ?? 0;
}

/// El mismo insumo, a dos precios según con quién se compre.
class ComparaPrecio {
  final String insumo;
  final String mejor;
  final double precioMejor;
  final String otro;
  final double precioOtro;

  /// La cantidad con que se compró al más caro y cuánto se ahorraba comprándola con el mejor.
  final String cantidad;
  final double ahorro;

  const ComparaPrecio({
    required this.insumo,
    required this.mejor,
    required this.precioMejor,
    required this.otro,
    required this.precioOtro,
    required this.cantidad,
    required this.ahorro,
  });
}

/// Una compra que coincide con la búsqueda y, si se buscó un insumo, cuáles.
class CoincideCompra {
  final Compra compra;
  final List<LineaCompra>? lineas;
  const CoincideCompra(this.compra, this.lineas);
}

class AnalisisGastos {
  AnalisisGastos._();

  /// Cuántos quetzales de cada 100 vendidos se fueron en gastos; nulo sin ventas.
  static int? deCada100(double gastos, double? ventas) {
    if (ventas == null || ventas <= 0) return null;
    return (gastos / ventas * 100).round();
  }

  /// Las compras sin proveedor: cuántas y cuánto suman.
  static (int, double) sinProveedor(List<Compra> compras) {
    final sin = compras.where((c) => c.proveedor == null).toList();
    return (sin.length, sin.fold(0.0, (s, c) => s + c.total));
  }

  /// En qué insumos se fue más dinero, de mayor a menor (nombre como se escribió
  /// la primera vez).
  static List<(String, double)> topInsumos(List<Compra> compras, {int n = 5}) {
    final nombres = <String, String>{};
    final suma = <String, double>{};
    for (final c in compras) {
      for (final l in c.lineas) {
        final k = claveDe(l.insumo);
        nombres.putIfAbsent(k, () => l.insumo);
        suma[k] = (suma[k] ?? 0) + l.costo;
      }
    }
    final orden = suma.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in orden.take(n)) (nombres[e.key]!, e.value)];
  }

  /// A quién se le compra más, de mayor a menor ("Sin proveedor" también cuenta).
  static List<(String, double)> topProveedores(List<Compra> compras, {int n = 4}) {
    final nombres = <String, String>{};
    final suma = <String, double>{};
    for (final c in compras) {
      final k = claveDe(c.nombre);
      nombres.putIfAbsent(k, () => c.nombre);
      suma[k] = (suma[k] ?? 0) + c.total;
    }
    final orden = suma.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in orden.take(n)) (nombres[e.key]!, e.value)];
  }

  /// Los precios que se pagaron: por cada (insumo, proveedor), en orden de fecha.
  static Map<String, List<_Punto>> _precios(List<Compra> compras, {required bool actual}) {
    final out = <String, List<_Punto>>{};
    for (final c in compras) {
      for (final l in c.lineas) {
        final p = l.precio;
        if (p == null || p <= 0) continue;
        final k = '${claveDe(l.insumo)}|${claveDe(c.nombre)}';
        (out[k] ??= []).add(_Punto(l.insumo, c.nombre, l.unidad, p, c.fecha, l.cantidad, actual));
      }
    }
    return out;
  }

  /// Lo que subió de precio: la compra más reciente del período contra la
  /// anterior del mismo insumo y proveedor (en este período o en el pasado), de lo
  /// que más subió a lo que menos. Sin historial no hay con qué comparar.
  static List<SubidaPrecio> subieron(List<Compra> actuales, List<Compra> anteriores, {int n = 5}) {
    final todos = <String, List<_Punto>>{};
    for (final e in _precios(anteriores, actual: false).entries) {
      todos[e.key] = [...e.value];
    }
    for (final e in _precios(actuales, actual: true).entries) {
      (todos[e.key] ??= []).addAll(e.value);
    }
    final out = <SubidaPrecio>[];
    for (final puntos in todos.values) {
      if (puntos.length < 2) continue;
      puntos.sort((a, b) {
        final fa = a.fecha, fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return -1;
        if (fb == null) return 1;
        return fa.compareTo(fb);
      });
      final ultimo = puntos.last;
      if (!ultimo.actual) continue;
      final previo = puntos[puntos.length - 2];
      if ((cambioPct(ultimo.precio, previo.precio) ?? 0) >= 1) {
        out.add(SubidaPrecio(ultimo.insumo, ultimo.proveedor, ultimo.unidad, previo.precio, ultimo.precio));
      }
    }
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out.take(n).toList();
  }

  /// Insumos comprados a más de un proveedor en el período a precios distintos:
  /// con quién sale más barato y cuánto se ahorraba con la cantidad que se compró
  /// al más caro. De mayor a menor ahorro.
  static List<ComparaPrecio> comparar(List<Compra> compras, {int n = 3}) {
    final porInsumo = <String, Map<String, _Punto>>{};
    final ordenadas = [...compras]..sort((a, b) {
        final fa = a.fecha, fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return -1;
        if (fb == null) return 1;
        return fa.compareTo(fb);
      });
    for (final c in ordenadas) {
      for (final l in c.lineas) {
        final p = l.precio;
        if (p == null || p <= 0) continue;
        // El último precio que pagó a cada proveedor.
        (porInsumo[claveDe(l.insumo)] ??= {})[claveDe(c.nombre)] = _Punto(l.insumo, c.nombre, l.unidad, p, c.fecha, l.cantidad, true);
      }
    }
    final out = <ComparaPrecio>[];
    for (final proveedores in porInsumo.values) {
      if (proveedores.length < 2) continue;
      final o = proveedores.values.toList()..sort((a, b) => a.precio.compareTo(b.precio));
      final mejor = o.first, otro = o[1];
      if (otro.precio - mejor.precio < 0.005) continue;
      final cant = otro.cantidad;
      final q = (cant == null || cant <= 0) ? 1.0 : cant;
      out.add(ComparaPrecio(
        insumo: mejor.insumo,
        mejor: mejor.proveedor,
        precioMejor: mejor.precio,
        otro: otro.proveedor,
        precioOtro: otro.precio,
        cantidad: otro.unidad.isEmpty ? textoCantidad(q) : '${textoCantidad(q)} ${otro.unidad}',
        ahorro: (otro.precio - mejor.precio) * q,
      ));
    }
    out.sort((a, b) => b.ahorro.compareTo(a.ahorro));
    return out.take(n).toList();
  }

  /// Las compras que coinciden con [consulta]: por proveedor, por número (con o
  /// sin "#") o por algún insumo (entonces trae cuáles). Sin acentos ni mayúsculas.
  static List<CoincideCompra> buscar(List<Compra> compras, String consulta) {
    final q = claveDe(consulta).replaceFirst(RegExp(r'^#'), '');
    if (q.isEmpty) return [for (final c in compras) CoincideCompra(c, null)];
    final out = <CoincideCompra>[];
    for (final c in compras) {
      if (claveDe(c.nombre).contains(q) || (c.numero?.toString().contains(q) ?? false)) {
        out.add(CoincideCompra(c, null));
        continue;
      }
      final hit = c.lineas.where((l) => claveDe(l.insumo).contains(q)).toList();
      if (hit.isNotEmpty) out.add(CoincideCompra(c, hit));
    }
    return out;
  }

  /// Los gastos (manuales o retiros) que coinciden con [consulta]: por concepto,
  /// categoría o quién los registró.
  static List<GastoLinea> buscarGastos(List<GastoLinea> gastos, String consulta) {
    final q = claveDe(consulta);
    if (q.isEmpty) return gastos;
    return [
      for (final g in gastos)
        if (claveDe(g.concepto).contains(q) ||
            claveDe(g.categoria).contains(q) ||
            claveDe(g.usuario ?? '').contains(q) ||
            claveDe(g.cajero ?? '').contains(q))
          g,
    ];
  }

  /// "31 oct" para el listado.
  static String fechaLista(DateTime? f) => f == null ? '' : fechaCorta(f);
}

class _Punto {
  final String insumo;
  final String proveedor;
  final String unidad;
  final double precio;
  final DateTime? fecha;
  final double? cantidad;

  /// Es de las compras del período que se mira (no de las anteriores).
  final bool actual;

  const _Punto(this.insumo, this.proveedor, this.unidad, this.precio, this.fecha, this.cantidad, this.actual);
}
