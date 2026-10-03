// Utilidad por platillo: lo que cuesta la receta, lo que se cobra y la parte
// de los gastos del negocio que le toca, repartida proporcional a la venta.
//
// El costo de receta replica lo que el POS sella al cobrar (cantidad × último
// precio de compra del ingrediente que resuelve en la sucursal), así que es
// el mismo número que el sistema ya usa. El reparto de gastos sale del período
// que el dueño eligió en Rentabilidad.
//
// Todo lo de este archivo es Dart puro, sin Firestore, para poder probarlo.
// Los montos van en CENTAVOS enteros: con dobles, 3 × Q0.10 contra un precio
// de Q0.30 daba una pérdida de −0.0% pintada de rojo.

import '../../core/utils/date_range.dart';
import 'profitability_data.dart';

/// Gastos que son comida comprada. Ya están en el costo de cada receta: si
/// además se repartieran como gasto, el platillo pagaría dos veces lo mismo.
const kCategoriasDeComida = {'pago_proveedor', 'insumos'};

/// Por encima de esto, casi seguro falta un ingrediente en la receta.
const double kMargenSospechoso = 95;

/// Abreviaturas de las unidades predefinidas del POS (`UnitOfMeasure`).
const _abreviaturas = {
  'kilogramos': 'kg',
  'gramos': 'g',
  'litros': 'L',
  'mililitros': 'ml',
  'unidades': 'und.',
  'rebanadas': 'reb.',
  'porciones': 'porc.',
};

// ── Datos de entrada ────────────────────────────────────────────────────────

class IngredienteCosto {
  final String id;
  final String nombre;
  final String? codigo;
  final String? sucursalId;
  final String? masterId;
  final bool activo;

  /// Nombre de la unidad tal como la guarda el POS (`kilogramos`, `gramos`…).
  /// Ausente o desconocida vale `unidades`, igual que en el POS.
  final String unidad;

  /// Id de unidad personalizada. Son por sucursal, así que no se pueden
  /// comparar entre sucursales.
  final String? unidadPersonalizada;

  /// Último precio de compra por UNA unidad.
  final double? precio;

  const IngredienteCosto({
    required this.id,
    required this.nombre,
    this.codigo,
    this.sucursalId,
    this.masterId,
    this.activo = true,
    this.unidad = 'unidades',
    this.unidadPersonalizada,
    this.precio,
  });

  /// Un precio en cero se trata igual que ninguno: un ingrediente gratis no
  /// existe y contarlo regalaría margen. (El POS sí sella Q0.00.)
  bool get tienePrecio => precio != null && precio! > 0;

  String get abreviatura =>
      unidadPersonalizada != null ? '' : (_abreviaturas[unidad] ?? '');
}

class LineaReceta {
  /// Id del documento. Desempata recetas duplicadas igual que el POS.
  final String docId;
  final String productoId;
  final String presentacionId;
  final String ingredienteId;
  final String? masterId;

  /// En la unidad del ingrediente, tal como la guarda el POS.
  final double cantidad;

  const LineaReceta({
    required this.docId,
    required this.productoId,
    required this.presentacionId,
    required this.ingredienteId,
    this.masterId,
    required this.cantidad,
  });
}

class PresentacionMenu {
  final String id;
  final String nombre;
  final double precio;

  const PresentacionMenu({
    required this.id,
    required this.nombre,
    required this.precio,
  });
}

class ProductoMenu {
  final String id;
  final String nombre;
  final List<PresentacionMenu> presentaciones;

  const ProductoMenu({
    required this.id,
    required this.nombre,
    required this.presentaciones,
  });
}

/// Todo lo que hace falta para costear el menú, ya leído y validado.
class MenuCrudo {
  final List<ProductoMenu> productos;
  final List<LineaReceta> recetas;
  final List<IngredienteCosto> ingredientes;

  /// `presentacionId|sucursalId` → precio que cobra esa sucursal.
  final Map<String, double> preciosSucursal;

  /// `productoId|sucursalId` de los productos apagados en esa sucursal.
  final Set<String> apagados;

  /// Sucursales activas que venden (sin la bodega central).
  final Set<String> sucursalesVendibles;

  /// Documentos que no se pudieron leer. Se cuentan para decirlo en pantalla
  /// en vez de esconder que algo quedó fuera.
  final int descartados;

  const MenuCrudo({
    this.productos = const [],
    this.recetas = const [],
    this.ingredientes = const [],
    this.preciosSucursal = const {},
    this.apagados = const {},
    this.sucursalesVendibles = const {},
    this.descartados = 0,
  });
}

// ── Resultado por presentación ──────────────────────────────────────────────

enum EstadoLinea {
  ok,

  /// El ingrediente existe en la sucursal pero no tiene precio de compra.
  sinPrecio,

  /// No existe en la sucursal: el POS tampoco lo descuenta al vender.
  noEnSucursal,
}

class LineaCosto {
  final String ingrediente;
  final double cantidad;
  final String unidad;
  final double? precio;
  final EstadoLinea estado;

  /// El ingrediente que se encontró en la sucursal se mide en otra unidad que
  /// el de la receta. El POS no convierte: aplica la cantidad tal cual.
  final bool unidadDistinta;

  const LineaCosto({
    required this.ingrediente,
    required this.cantidad,
    this.unidad = '',
    this.precio,
    this.estado = EstadoLinea.ok,
    this.unidadDistinta = false,
  });

  int? get centavos => estado == EstadoLinea.ok && precio != null
      ? (precio! * cantidad * 100).round()
      : null;
}

enum EstadoCosto {
  /// Todas las líneas tienen precio: hay costo.
  completo,

  /// Falta al menos un precio, o un ingrediente no existe en la sucursal. No
  /// hay costo: uno corto por falta de datos se ve igual que uno bajo.
  incompleto,

  /// La presentación no tiene receta.
  sinReceta,
}

/// Señales de que el costo probablemente está mal cargado.
enum AlertaReceta {
  /// Cuesta más de lo que se cobra: suele ser un error de unidad o de precio.
  cuestaMasQueElPrecio,

  /// Tan alto que casi seguro falta un ingrediente.
  margenMuyAlto,

  /// Dos líneas del mismo ingrediente. El POS usa una sola.
  recetaDuplicada,

  /// Un ingrediente se mide distinto en esta sucursal que en la receta.
  unidadDistinta,

  /// Una línea con cantidad cero o negativa: no es una receta real.
  cantidadInvalida,
}

class MargenPlatillo {
  final String productoId;
  final String presentacionId;
  final String producto;

  /// Null cuando el producto tiene una sola presentación: su nombre ("Normal",
  /// "Único") no dice nada.
  final String? presentacion;

  /// Precio que cobra la sucursal, en centavos.
  final int precio;
  final EstadoCosto estado;
  final List<LineaCosto> lineas;
  final bool duplicada;

  MargenPlatillo({
    required this.productoId,
    required this.presentacionId,
    required this.producto,
    this.presentacion,
    required this.precio,
    required this.estado,
    required this.lineas,
    this.duplicada = false,
  });

  String get clave => '$productoId|$presentacionId';

  String get nombre =>
      presentacion == null ? producto : '$producto · $presentacion';

  // Costo y alertas se calculan una vez: la lista los consulta en cada filtro,
  // en cada contador de chip y en cada comparación al ordenar.
  late final int? costo = estado == EstadoCosto.completo
      ? lineas.fold<int>(0, (a, l) => a + (l.centavos ?? 0))
      : null;

  /// Precio menos costo de receta, sin gastos.
  int? get margenReceta => costo == null ? null : precio - costo!;

  /// Sin precio de venta no hay porcentaje: devolver 0 diría "no gana nada".
  double? get margenRecetaPct =>
      margenReceta == null || precio <= 0 ? null : margenReceta! / precio * 100;

  late final Set<AlertaReceta> alertas = _alertas();

  Set<AlertaReceta> _alertas() {
    final a = <AlertaReceta>{};
    if (duplicada) a.add(AlertaReceta.recetaDuplicada);
    if (lineas.any((l) => l.unidadDistinta)) a.add(AlertaReceta.unidadDistinta);
    if (lineas.any((l) => l.cantidad <= 0)) a.add(AlertaReceta.cantidadInvalida);
    final m = margenRecetaPct;
    if (costo != null && costo! > precio) {
      a.add(AlertaReceta.cuestaMasQueElPrecio);
    } else if (m != null && m > kMargenSospechoso) {
      a.add(AlertaReceta.margenMuyAlto);
    }
    return a;
  }

  bool get porRevisar => alertas.isNotEmpty;

  /// Ingredientes sin precio, por nombre: el dueño tiene que saber CUÁLES.
  List<String> get sinPrecio => [
        for (final l in lineas)
          if (l.estado == EstadoLinea.sinPrecio) l.ingrediente
      ];

  List<String> get noEnSucursal => [
        for (final l in lineas)
          if (l.estado == EstadoLinea.noEnSucursal) l.ingrediente
      ];
}

// ── Cálculo del costo, fiel al POS ──────────────────────────────────────────

String _norm(String s) => s.toLowerCase().trim();

class _Indices {
  final Map<String, IngredienteCosto> porId = {};
  final Map<String, IngredienteCosto> porMaster = {};
  final Map<String, IngredienteCosto> porCodigo = {};
  final Map<String, IngredienteCosto> porNombre = {};

  _Indices(List<IngredienteCosto> ingredientes) {
    // Un aparato del POS solo guarda los ingredientes activos de su sucursal,
    // y con varios candidatos gana el último indexado: el de id mayor. Por eso
    // se recorren en orden de id y se sobrescribe.
    final orden = [...ingredientes]..sort((a, b) => a.id.compareTo(b.id));
    for (final i in orden) {
      porId[i.id] = i;
      if (!i.activo || i.sucursalId == null) continue;
      final s = i.sucursalId!;
      if (i.masterId != null) porMaster['${i.masterId}|$s'] = i;
      if (i.codigo != null && i.codigo!.trim().isNotEmpty) {
        porCodigo['$s|${_norm(i.codigo!)}'] = i;
      }
      porNombre['$s|${_norm(i.nombre)}'] = i;
    }
  }

  /// El ingrediente que el POS descontaría en la sucursal [suc] al cobrar.
  ///
  /// Mismo orden que `_resolveIngredient` del POS: maestro de la receta →
  /// el propio si es de la sucursal → maestro del propio → código → nombre.
  /// Si no aparece, el POS no descuenta esa línea, y aquí no se costea.
  IngredienteCosto? resolver(LineaReceta r, String? suc) {
    final propio = porId[r.ingredienteId];
    // "Todas" con varias sucursales: no hay una sucursal donde buscar, se usa
    // el ingrediente con que se armó la receta.
    if (suc == null) return propio != null && propio.activo ? propio : null;

    if (r.masterId != null) {
      final m = porMaster['${r.masterId}|$suc'];
      if (m != null) return m;
    }
    if (propio == null) return null;
    if (propio.sucursalId == suc && propio.activo) return propio;
    if (propio.masterId != null) {
      final m = porMaster['${propio.masterId}|$suc'];
      if (m != null) return m;
    }
    if (propio.codigo != null && propio.codigo!.trim().isNotEmpty) {
      final c = porCodigo['$suc|${_norm(propio.codigo!)}'];
      if (c != null) return c;
    }
    return porNombre['$suc|${_norm(propio.nombre)}'];
  }
}

bool _unidadesDistintas(IngredienteCosto a, IngredienteCosto b) {
  final ca = a.unidadPersonalizada, cb = b.unidadPersonalizada;
  // Las personalizadas tienen un id distinto en cada sucursal: dos
  // personalizadas no se pueden comparar y no se marcan.
  if (ca != null && cb != null) return false;
  if ((ca == null) != (cb == null)) return true;
  return a.unidad != b.unidad;
}

/// El costo de receta de cada presentación del menú en una sucursal.
///
/// [sucursalId] null es "Todas". Si el negocio tiene una sola sucursal que
/// vende, "Todas" es esa: se costea con sus precios.
List<MargenPlatillo> calcularMargenes(
  MenuCrudo menu, {
  String? sucursalId,

  /// Sucursales que el usuario puede ver. Vacío = todas. Nada de una sucursal
  /// fuera de este conjunto se usa, ni el precio ni el costo.
  Set<String> sucursalesPermitidas = const {},
}) {
  bool permitida(String? s) =>
      sucursalesPermitidas.isEmpty ||
      (s != null && sucursalesPermitidas.contains(s));

  // Con una sola sucursal vendible el POS ignora los productos apagados: no
  // hay nada que repartir entre sucursales.
  final unica = menu.sucursalesVendibles.length == 1
      ? menu.sucursalesVendibles.first
      : null;
  final suc = sucursalId ?? unica;

  final indices = _Indices(menu.ingredientes);

  // Duplicados: el POS se queda con una línea por (producto, presentación,
  // ingrediente de la receta) — la de id mayor, que es la que sobrevive en
  // todos los aparatos tras sincronizar.
  final elegidas = <String, LineaReceta>{};
  final duplicadas = <String>{};
  for (final r in menu.recetas) {
    final k = '${r.productoId}|${r.presentacionId}|${r.ingredienteId}';
    final previa = elegidas[k];
    if (previa == null) {
      elegidas[k] = r;
      continue;
    }
    duplicadas.add('${r.productoId}|${r.presentacionId}');
    if (r.docId.compareTo(previa.docId) > 0) elegidas[k] = r;
  }
  final porPresentacion = <String, List<LineaReceta>>{};
  for (final r in elegidas.values) {
    porPresentacion
        .putIfAbsent('${r.productoId}|${r.presentacionId}', () => [])
        .add(r);
  }

  LineaCosto costear(LineaReceta r) {
    final propio = indices.porId[r.ingredienteId];
    final encontrado = indices.resolver(r, suc);
    final nombre = encontrado?.nombre ?? propio?.nombre ?? 'Ingrediente eliminado';

    if (encontrado == null || !permitida(encontrado.sucursalId)) {
      return LineaCosto(
        ingrediente: nombre,
        cantidad: r.cantidad,
        unidad: propio?.abreviatura ?? '',
        estado: EstadoLinea.noEnSucursal,
      );
    }
    return LineaCosto(
      ingrediente: nombre,
      cantidad: r.cantidad,
      unidad: encontrado.abreviatura,
      precio: encontrado.tienePrecio ? encontrado.precio : null,
      estado: encontrado.tienePrecio ? EstadoLinea.ok : EstadoLinea.sinPrecio,
      unidadDistinta: propio != null &&
          !identical(propio, encontrado) &&
          _unidadesDistintas(propio, encontrado),
    );
  }

  final salida = <MargenPlatillo>[];
  for (final p in menu.productos) {
    if (suc != null && unica == null && menu.apagados.contains('${p.id}|$suc')) {
      continue;
    }
    final varias = p.presentaciones.length > 1;
    for (final pr in p.presentaciones) {
      // El POS cobra el precio de la sucursal si existe; si no, el base.
      final precio = (suc != null && permitida(suc)
              ? menu.preciosSucursal['${pr.id}|$suc']
              : null) ??
          pr.precio;

      final lineas = [
        for (final r in porPresentacion['${p.id}|${pr.id}'] ?? const <LineaReceta>[])
          costear(r)
      ];

      final EstadoCosto estado;
      if (lineas.isEmpty) {
        estado = EstadoCosto.sinReceta;
      } else if (lineas.any((l) => l.estado != EstadoLinea.ok)) {
        estado = EstadoCosto.incompleto;
      } else {
        estado = EstadoCosto.completo;
      }

      salida.add(MargenPlatillo(
        productoId: p.id,
        presentacionId: pr.id,
        producto: p.nombre,
        presentacion: varias ? pr.nombre : null,
        precio: (precio * 100).round(),
        estado: estado,
        lineas: lineas,
        duplicada: duplicadas.contains('${p.id}|${pr.id}'),
      ));
    }
  }
  return salida;
}

// ── Reparto de los gastos del período ───────────────────────────────────────

enum EstadoReparto {
  listo,

  /// Ni Mes ni Año. La renta y los sueldos se registran una vez al mes: en un
  /// día, una semana o un rango libre no caen completos (o caen dos veces).
  periodoCorto,
  sinVentas,

  /// No hay ningún gasto en el período. Repartir cero pintaría todo de verde.
  sinGastos,

  /// Falló la consulta de gastos o la de cajas (retiros): repartir con una
  /// parte sería decir que se gastó menos.
  gastosNoLeidos,

  /// El período tiene más órdenes de las que el dashboard trae de una vez: la
  /// venta neta sale corta y los gastos parecerían más pesados.
  ventasIncompletas,

  /// Los gastos superan las ventas: ningún precio los cubre.
  gastosSuperanVentas,
}

class RepartoGastos {
  final double ventasNetas;
  final double gastosFijos;
  final double gastosVariables;

  /// Insumos y pagos a proveedores: no se reparten (ya están en la receta),
  /// pero se dice cuánto quedó fuera.
  final double gastosDeComida;

  /// Descuentos dados en el período, para pasar del precio de lista a lo que
  /// de verdad se cobra.
  final double descuentos;

  /// False en la vista de año mientras no llega el detalle de los meses: los
  /// descuentos se toman en cero y hay que decirlo.
  final bool descuentoConocido;
  final EstadoReparto estado;

  /// El mes elegido es el actual: faltan ventas y quizá gastos.
  final bool mesEnCurso;

  const RepartoGastos({
    required this.ventasNetas,
    required this.gastosFijos,
    required this.gastosVariables,
    this.gastosDeComida = 0,
    this.descuentos = 0,
    this.descuentoConocido = true,
    required this.estado,
    this.mesEnCurso = false,
  });

  /// Arma el reparto con los números de Rentabilidad.
  ///
  /// La venta neta es la de la cascada: lo cobrado sin propina ni envío, ya
  /// con los descuentos restados. Los gastos son los mismos de la cascada,
  /// menos los de comida (ver [kCategoriasDeComida]).
  ///
  /// Solo se reparte con Mes o Año: la renta y los sueldos se registran una
  /// vez al mes, y en un rango libre de 32 días entran dos rentas o en uno de
  /// 28 ninguna. Además el dashboard corta las órdenes de un rango largo y la
  /// venta saldría a medias.
  factory RepartoGastos.desde({
    required ProfitabilityData datos,
    required DateRange rango,
    required bool gastosLeidos,
    bool ventasCompletas = true,
    double? descuentos = 0,
    DateTime? hoy,
  }) {
    var fijos = 0.0, variables = 0.0, comida = 0.0;
    for (final e in datos.expenses) {
      if (kCategoriasDeComida.contains(e.categoryId)) {
        comida += e.amount;
      } else if (e.esFijo) {
        fijos += e.amount;
      } else {
        variables += e.amount;
      }
    }
    // Un total negativo es una corrección mal cargada, no un ingreso: restarlo
    // bajaría el gasto y regalaría utilidad a todos los platillos.
    if (fijos < 0) fijos = 0;
    if (variables < 0) variables = 0;
    if (comida < 0) comida = 0;

    final ahora = hoy ?? DateTime.now();
    final mensualOAnual =
        rango.mode == PeriodMode.month || rango.mode == PeriodMode.year;
    final mesEnCurso = rango.mode == PeriodMode.month &&
        !ahora.isBefore(rango.start) &&
        !ahora.isAfter(rango.end);

    final ventas = datos.netSales;
    final EstadoReparto estado;
    if (!gastosLeidos) {
      estado = EstadoReparto.gastosNoLeidos;
    } else if (!mensualOAnual) {
      estado = EstadoReparto.periodoCorto;
    } else if (!ventasCompletas) {
      estado = EstadoReparto.ventasIncompletas;
    } else if (ventas <= 0) {
      estado = EstadoReparto.sinVentas;
    } else if (fijos + variables <= 0) {
      estado = EstadoReparto.sinGastos;
    } else if ((fijos + variables) / ventas >= 1) {
      estado = EstadoReparto.gastosSuperanVentas;
    } else {
      estado = EstadoReparto.listo;
    }

    return RepartoGastos(
      ventasNetas: ventas,
      gastosFijos: fijos,
      gastosVariables: variables,
      gastosDeComida: comida,
      descuentos: descuentos == null || descuentos < 0 ? 0 : descuentos,
      descuentoConocido: descuentos != null,
      estado: estado,
      mesEnCurso: mesEnCurso,
    );
  }

  bool get listo => estado == EstadoReparto.listo;

  double get ratioFijos => ventasNetas > 0 ? gastosFijos / ventasNetas : 0;
  double get ratioVariables =>
      ventasNetas > 0 ? gastosVariables / ventasNetas : 0;
  double get ratio => ratioFijos + ratioVariables;

  /// Qué parte del precio de lista se fue en descuentos, en promedio.
  double get tasaDescuento {
    final lista = ventasNetas + descuentos;
    return lista > 0 ? descuentos / lista : 0;
  }

  bool get sinGastosFijos => gastosFijos <= 0;

  /// "De cada Q100, Qx en gastos": el total redondeado, y los fijos y los
  /// variables repartidos de forma que SUMEN ese total. Redondeados por
  /// separado, 12.5% + 12.5% decía "Q13 y Q13" bajo un titular de Q25.
  ({int total, int fijos, int variables}) get cada100 {
    final total = (ratio * 100).round();
    final f = (ratioFijos * 100).round().clamp(0, total);
    return (total: total, fijos: f, variables: total - f);
  }
}

/// Semáforo de un platillo una vez repartidos los gastos.
enum Banda {
  /// Cubre su receta, sus gastos variables y su parte de los fijos.
  cubreTodo,

  /// Cubre la receta y los variables, pero no su parte completa de los fijos.
  /// Aporta: quitarlo no hace desaparecer la renta.
  noCubreFijos,

  /// Ni siquiera cubre la receta y los variables: cada venta pierde.
  pierde,
}

/// Lo que pasa con cada quetzal que se cobra por un platillo, en centavos.
/// Los renglones suman exacto al precio.
class Desglose {
  final int precio;
  final int descuento;
  final int costo;
  final int variables;
  final int fijos;

  /// Precio desde el cual el platillo cubre todo. Null si los gastos ya se
  /// comen el 100% de la venta.
  final int? precioMinimo;

  const Desglose({
    required this.precio,
    required this.descuento,
    required this.costo,
    required this.variables,
    required this.fijos,
    this.precioMinimo,
  });

  factory Desglose.de(MargenPlatillo p, RepartoGastos r) {
    final d = _calcular(p.precio, p.costo!, r);
    return Desglose(
      precio: d.precio,
      descuento: d.descuento,
      costo: d.costo,
      variables: d.variables,
      fijos: d.fijos,
      precioMinimo: _precioMinimo(d.costo, r),
    );
  }

  static Desglose _calcular(int precio, int costo, RepartoGastos r) {
    final descuento = (precio * r.tasaDescuento).round();
    final cobrado = precio - descuento;
    return Desglose(
      precio: precio,
      descuento: descuento,
      costo: costo,
      variables: (cobrado * r.ratioVariables).round(),
      fijos: (cobrado * r.ratioFijos).round(),
    );
  }

  /// El primer precio con el que el platillo cubre todo, con el MISMO
  /// redondeo por renglón que el desglose. La fórmula sola
  /// (costo ÷ ((1 − d)(1 − r))) a veces quedaba un centavo corta, y el
  /// desglose decía "cubre desde Q70.34" junto a "te queda −Q0.01".
  static int? _precioMinimo(int costo, RepartoGastos r) {
    final factor = (1 - r.tasaDescuento) * (1 - r.ratio);
    if (factor <= 0) return null;
    var precio = (costo / factor).ceil();
    for (var i = 0; i < 100; i++) {
      if (_calcular(precio, costo, r).utilidad >= 0) return precio;
      precio++;
    }
    return precio;
  }

  int get utilidad => precio - descuento - costo - variables - fijos;

  /// Lo que queda para pagar los fijos.
  int get contribucion => precio - descuento - costo - variables;

  double? get pct => precio > 0 ? utilidad / precio * 100 : null;

  Banda get banda {
    if (contribucion < 0) return Banda.pierde;
    if (utilidad < 0) return Banda.noCubreFijos;
    return Banda.cubreTodo;
  }
}

class FilaUtilidad {
  final MargenPlatillo platillo;

  /// Solo con reparto listo y costo completo.
  final Desglose? desglose;

  const FilaUtilidad(this.platillo, this.desglose);

  /// Utilidad en % del precio: después de gastos si hay reparto, si no el
  /// margen de receta.
  double? get pct => desglose?.pct ?? platillo.margenRecetaPct;

  /// Utilidad en centavos, con el mismo criterio que [pct].
  int? get utilidad => desglose?.utilidad ?? platillo.margenReceta;

  /// Con costo y sin señales de dato mal cargado: entra en el ranking.
  /// Sin precio de venta no hay porcentaje con qué ordenarlo: un platillo de
  /// Q0 encabezaba "los que menos dejan".
  bool get confiable =>
      platillo.estado == EstadoCosto.completo &&
      !platillo.porRevisar &&
      platillo.precio > 0;
}

/// Ingrediente cuyo precio falta, y en cuántos platillos.
class Faltante {
  final String ingrediente;
  final int platillos;
  const Faltante(this.ingrediente, this.platillos);
}

class UtilidadMenu {
  final List<FilaUtilidad> filas;
  final RepartoGastos? reparto;
  final int descartados;

  const UtilidadMenu(this.filas, {this.reparto, this.descartados = 0});

  factory UtilidadMenu.armar(
    List<MargenPlatillo> platillos, {
    RepartoGastos? reparto,
    int descartados = 0,
  }) {
    final listo = reparto != null && reparto.listo;
    return UtilidadMenu(
      [
        for (final p in platillos)
          FilaUtilidad(
            p,
            listo && p.estado == EstadoCosto.completo
                ? Desglose.de(p, reparto)
                : null,
          ),
      ],
      reparto: reparto,
      descartados: descartados,
    );
  }

  bool get conReparto => reparto != null && reparto!.listo;
  bool get sinPlatillos => filas.isEmpty;

  int get total => filas.length;
  int get completos =>
      filas.where((f) => f.platillo.estado == EstadoCosto.completo).length;
  int get incompletos =>
      filas.where((f) => f.platillo.estado == EstadoCosto.incompleto).length;
  int get sinReceta =>
      filas.where((f) => f.platillo.estado == EstadoCosto.sinReceta).length;
  int get porRevisar => filas.where((f) => f.platillo.porRevisar).length;

  List<FilaUtilidad> get confiables =>
      filas.where((f) => f.confiable).toList();

  static int _porPct(FilaUtilidad a, FilaUtilidad b) {
    final c = (a.pct ?? 0).compareTo(b.pct ?? 0);
    return c != 0 ? c : a.platillo.nombre.compareTo(b.platillo.nombre);
  }

  /// Los [n] que menos dejan, solo entre los confiables: los que tienen el
  /// costo mal cargado se cuentan aparte en vez de copar el ranking.
  List<FilaUtilidad> menosDejan(int n) =>
      (confiables..sort(_porPct)).take(n).toList();

  /// Los [n] que más dejan, sin repetir los de [menosDejan].
  List<FilaUtilidad> masDejan(int n) {
    final orden = confiables..sort(_porPct);
    final abajo = orden.take(n).toSet();
    return orden.reversed.where((f) => !abajo.contains(f)).take(n).toList();
  }

  /// Ingredientes cuyo precio falta, ordenados por en cuántos platillos.
  List<Faltante> faltantes(int n) {
    final cuenta = <String, int>{};
    for (final f in filas) {
      for (final nombre in f.platillo.sinPrecio.toSet()) {
        cuenta[nombre] = (cuenta[nombre] ?? 0) + 1;
      }
    }
    final lista = [
      for (final e in cuenta.entries) Faltante(e.key, e.value)
    ]..sort((a, b) {
        final c = b.platillos.compareTo(a.platillos);
        return c != 0 ? c : a.ingrediente.compareTo(b.ingrediente);
      });
    return lista.take(n).toList();
  }
}

// ── Lectura de los documentos de Firestore ──────────────────────────────────
//
// Cada lector devuelve null ante un documento que no sirve, y lanza solo si
// el documento está roto de una forma inesperada: quien lee un lote cuenta
// esos como descartados en vez de tumbar el menú entero.

/// Un número que se pueda usar. NaN o infinito (un dato roto) cuentan como
/// ausentes: si pasaran, `round()` reventaba la lista entera.
double? _num(dynamic v) => v is num && v.isFinite ? v.toDouble() : null;

/// Texto no vacío, o null. Acepta números (un código "1001" guardado como
/// número), como hace el POS al leer.
String? _str(dynamic v) {
  if (v is String) return v.trim().isEmpty ? null : v;
  if (v is num) return v.toString();
  return null;
}

IngredienteCosto? leerIngrediente(String id, Map<String, dynamic> d) {
  // Sin nombre el POS lo sigue usando (lo muestra como "Sin nombre"); si aquí
  // se descartara, su línea saldría como ingrediente eliminado.
  final nombre = _str(d['name']) ?? 'Sin nombre';
  final precio = _num(d['lastPurchasePrice']);
  final unidad = _str(d['unit']);
  return IngredienteCosto(
    id: id,
    nombre: nombre,
    codigo: _str(d['code']),
    sucursalId: _str(d['location_id']) ?? _str(d['locationId']),
    masterId: _str(d['masterIngredientId']),
    activo: d['active'] is bool ? d['active'] as bool : true,
    unidad: unidad != null && _abreviaturas.containsKey(unidad)
        ? unidad
        : 'unidades',
    unidadPersonalizada: _str(d['customUnitId']),
    precio: precio,
  );
}

/// Null para las recetas de modificador (extras): se costea el platillo base.
LineaReceta? leerLineaReceta(String docId, Map<String, dynamic> d) {
  // El POS trata como receta de modificador todo `modifierId` no nulo.
  if (d['modifierId'] != null) return null;
  final producto = _str(d['productId']);
  final presentacion = _str(d['presentationId']);
  final ingrediente = _str(d['ingredientId']);
  final cantidad = _num(d['quantity']);
  if (producto == null ||
      presentacion == null ||
      ingrediente == null ||
      cantidad == null) {
    return null;
  }
  return LineaReceta(
    docId: docId,
    productoId: producto,
    presentacionId: presentacion,
    ingredienteId: ingrediente,
    masterId: _str(d['masterIngredientId']),
    cantidad: cantidad,
  );
}

/// Null si el producto está borrado, apagado o sin presentaciones vigentes.
ProductoMenu? leerProducto(String id, Map<String, dynamic> d) {
  final nombre = _str(d['name']);
  if (nombre == null) return null;
  if (d['deleted'] == true || d['active'] == false) return null;

  final presentaciones = <PresentacionMenu>[];
  final crudas = d['presentations'];
  if (crudas is List) {
    for (final c in crudas) {
      if (c is! Map) continue;
      if (c['deleted'] == true) continue;
      final pid = _str(c['id']);
      final precio = _num(c['price']);
      if (pid == null || precio == null) continue;
      presentaciones.add(PresentacionMenu(
        id: pid,
        nombre: _str(c['name']) ?? '',
        precio: precio,
      ));
    }
  }
  if (presentaciones.isEmpty) return null;
  return ProductoMenu(id: id, nombre: nombre, presentaciones: presentaciones);
}

/// Un documento crudo: su id y sus campos.
class DocCrudo {
  final String id;
  final Map<String, dynamic> datos;
  const DocCrudo(this.id, this.datos);
}

/// Lo que devuelve Firestore, sin interpretar.
class MenuDescargado {
  final List<DocCrudo> productos;
  final List<DocCrudo> recetas;
  final List<DocCrudo> ingredientes;

  /// `presentation_locations`: precio por sucursal.
  final List<DocCrudo> preciosSucursal;

  /// `productLocations`: productos apagados por sucursal.
  final List<DocCrudo> disponibilidad;
  final List<DocCrudo> sucursales;

  const MenuDescargado({
    this.productos = const [],
    this.recetas = const [],
    this.ingredientes = const [],
    this.preciosSucursal = const [],
    this.disponibilidad = const [],
    this.sucursales = const [],
  });
}

/// Interpreta la descarga. Un documento roto se cuenta y se salta: no puede
/// tumbar el reporte de todo el menú.
MenuCrudo interpretarMenu(MenuDescargado d) {
  var descartados = 0;

  List<T> leer<T>(List<DocCrudo> docs, T? Function(DocCrudo) f) {
    final salida = <T>[];
    for (final doc in docs) {
      try {
        final v = f(doc);
        if (v != null) salida.add(v);
      } catch (_) {
        descartados++;
      }
    }
    return salida;
  }

  final productos = leer(d.productos, (x) => leerProducto(x.id, x.datos));
  final recetas = leer(d.recetas, (x) => leerLineaReceta(x.id, x.datos));
  final ingredientes =
      leer(d.ingredientes, (x) => leerIngrediente(x.id, x.datos));

  final precios = <String, double>{};
  for (final doc in d.preciosSucursal) {
    try {
      final pres = _str(doc.datos['presentation_id']);
      final suc = _str(doc.datos['location_id']);
      // El POS cobra el precio de sucursal si no es nulo, sin mirar `enabled`.
      final precio = _num(doc.datos['price_override']);
      if (pres != null && suc != null && precio != null) {
        precios['$pres|$suc'] = precio;
      }
    } catch (_) {
      descartados++;
    }
  }

  final apagados = <String>{};
  for (final doc in d.disponibilidad) {
    try {
      // `enabled` ausente vale true, como en el POS.
      if (doc.datos['enabled'] != false) continue;
      final prod = _str(doc.datos['product_id']);
      final suc = _str(doc.datos['location_id']);
      if (prod != null && suc != null) apagados.add('$prod|$suc');
    } catch (_) {
      descartados++;
    }
  }

  final vendibles = <String>{};
  for (final doc in d.sucursales) {
    if (doc.datos['active'] == false) continue;
    if (doc.datos['is_central_warehouse'] == true) continue;
    vendibles.add(doc.id);
  }

  return MenuCrudo(
    productos: productos,
    recetas: recetas,
    ingredientes: ingredientes,
    preciosSucursal: precios,
    apagados: apagados,
    sucursalesVendibles: vendibles,
    descartados: descartados,
  );
}
