import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/menu_margin_data.dart';
import '../../data/models/profitability_data.dart';

// Paleta de Utilidad por platillo. Los textos con cifras van en blanco al 60%
// o más: por debajo no llegan al contraste mínimo sobre la tarjeta (4.5:1), y
// el rojo y el violeta de la marca tampoco, así que como TEXTO se usan sus
// versiones claras. Los oscuros quedan para bordes y rellenos.
const kFondo = Color(0xFF0F172A);
const kBarra = Color(0xFF0A1020);
const kTarjeta = Color(0xFF1E293B);
const kAcento = Color(0xFF7444fd);
const kAcentoTexto = Color(0xFFA78BFA);
const kVerde = Color(0xFF22C55E);
const kRojo = Color(0xFFEF4444);
const kRojoTexto = Color(0xFFF87171);
const kAmbar = Color(0xFFFBBF24);

Color colorDeBanda(Banda b) => switch (b) {
      Banda.cubreTodo => kVerde,
      Banda.noCubreFijos => kAmbar,
      Banda.pierde => kRojoTexto,
    };

/// Qué significa el color, en palabras. El ámbar dice cuánto APORTA: sin eso,
/// el dueño ve un número negativo entre "los que menos dejan" y lo quita,
/// aunque ese platillo ayude a pagar la renta.
String etiquetaDeBanda(Desglose d) => switch (d.banda) {
      Banda.cubreTodo => 'cubre sus gastos',
      Banda.noCubreFijos =>
        'aporta ${formatoQ(d.contribucion)} a los fijos, pero no toda su parte',
      Banda.pierde => 'pierde en cada venta',
    };

/// Sin reparto, el mismo semáforo que el costo de comida de Rentabilidad: un
/// margen de receta de 65% es un costo de comida de 35%, la meta de allá.
Color colorDeMargenReceta(double? pct) {
  if (pct == null) return Colors.white60;
  return switch (evaluarFoodCost(100 - pct)) {
    Salud.bien => kVerde,
    Salud.atencion => kAmbar,
    Salud.mal => kRojoTexto,
    Salud.desconocido => Colors.white60,
  };
}

String textoDeAlerta(AlertaReceta a) => switch (a) {
      AlertaReceta.cuestaMasQueElPrecio =>
        'La receta cuesta más que el precio · revisá cantidades y unidades',
      AlertaReceta.margenMuyAlto =>
        'Margen de receta muy alto · ¿falta algún ingrediente?',
      AlertaReceta.recetaDuplicada => 'Un ingrediente está dos veces en la receta',
      AlertaReceta.unidadDistinta =>
        'Un ingrediente se mide distinto en esta sucursal',
      AlertaReceta.cantidadInvalida =>
        'Una línea de la receta tiene cantidad cero o negativa',
    };

String _explicacionDeAlerta(AlertaReceta a) => switch (a) {
      AlertaReceta.cuestaMasQueElPrecio =>
        'Casi siempre es un error de unidad (gramos contra kilos): revisá la '
            'línea en rojo, su cantidad y su precio de compra. Si está bien, '
            'cada venta pierde: subí el precio.',
      AlertaReceta.margenMuyAlto =>
        'Casi todo lo que cobrás queda después de la receta. En bebidas puede '
            'ser real; en un platillo, confirmá que la receta tenga todos los '
            'ingredientes.',
      AlertaReceta.recetaDuplicada =>
        'El POS descuenta solo una de las dos líneas (y este costo también). '
            'Dejá una sola línea con la cantidad correcta.',
      AlertaReceta.unidadDistinta =>
        'En la receta va en una unidad y en esta sucursal en otra (por '
            'ejemplo gramos y kilos). El POS no convierte: si la receta dice '
            '200, descuenta 200 kilos. Corregí la cantidad o la unidad.',
      AlertaReceta.cantidadInvalida =>
        'Una cantidad en cero o negativa no descuenta nada (o devuelve '
            'inventario) y deja el costo más bajo de lo real. Corregila en la '
            'receta.',
    };

/// Chip de filtro. Mide al menos 44 de alto: es lo mínimo para tocarlo con el
/// dedo sin errar.
class ChipFiltro extends StatelessWidget {
  final String etiqueta;
  final bool activo;
  final bool deshabilitado;
  final VoidCallback onTap;

  const ChipFiltro({
    super.key,
    required this.etiqueta,
    required this.activo,
    this.deshabilitado = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? kAcento.withValues(alpha: 0.22) : kTarjeta,
      shape: StadiumBorder(
        side: BorderSide(
          color: activo ? kAcento : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: deshabilitado ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                etiqueta,
                style: GoogleFonts.inter(
                  // Deshabilitado puede ir tenue: WCAG exime a los controles
                  // inactivos del contraste mínimo.
                  color: deshabilitado
                      ? Colors.white38
                      : (activo ? Colors.white : Colors.white70),
                  fontSize: 12.5,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _plural(int n, String uno, String varios) => n == 1 ? uno : varios;

/// Lo que dice un platillo: la cifra principal, su explicación y su color.
class _Lectura {
  final String principal;
  final Color color;
  final String? secundario;

  const _Lectura(this.principal, this.color, this.secundario);

  factory _Lectura.de(FilaUtilidad f) {
    final p = f.platillo;
    final d = f.desglose;
    // Con el costo mal cargado, la banda no es un hecho: se dice.
    final revisar = p.porRevisar ? ' · dato por revisar' : '';
    switch (p.estado) {
      case EstadoCosto.completo:
        if (d != null && d.pct != null) {
          return _Lectura(
            formatoQ(d.utilidad),
            colorDeBanda(d.banda),
            'por venta · ${formatoPct(d.pct)} del precio · '
                '${etiquetaDeBanda(d)}$revisar',
          );
        }
        if (p.margenRecetaPct == null) {
          return const _Lectura('Sin precio de venta', Colors.white60, null);
        }
        // Sin reparto el color es el del costo de comida, no "pierde/cubre":
        // se dice con las palabras de Rentabilidad para no confundirlos.
        return _Lectura(
          formatoQ(p.margenReceta!),
          colorDeMargenReceta(p.margenRecetaPct),
          'por venta, tras la receta · la receta es '
              '${formatoPct(100 - p.margenRecetaPct!)} del precio '
              '(meta: menos de 35%)$revisar',
        );
      case EstadoCosto.incompleto:
        final faltan = p.sinPrecio.length + p.noEnSucursal.length;
        return _Lectura(
          'Falta costo',
          kAmbar,
          '$faltan ${_plural(faltan, 'ingrediente sin costo', 'ingredientes sin costo')}',
        );
      case EstadoCosto.sinReceta:
        return const _Lectura('Sin receta', Colors.white70, null);
    }
  }
}

/// Nombre del producto y, debajo, la presentación entera. La presentación es
/// lo que distingue dos filas ("Doble" de "Sencilla"): nunca se corta.
class _Nombre extends StatelessWidget {
  final MargenPlatillo p;
  final double tamano;
  const _Nombre({required this.p, this.tamano = 14.5});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          p.producto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: tamano,
              fontWeight: FontWeight.w600,
              height: 1.25),
        ),
        if (p.presentacion != null)
          Text(
            p.presentacion!,
            style: GoogleFonts.inter(
                color: Colors.white70, fontSize: tamano - 2, height: 1.3),
          ),
      ],
    );
  }
}

/// La cifra y su explicación. En un Wrap y sin límite de líneas: con la letra
/// del sistema al 200% bajan de renglón en vez de cortarse.
class _Cifras extends StatelessWidget {
  final _Lectura l;
  final double tamano;
  const _Cifras({required this.l, this.tamano = 16});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(l.principal,
            style: GoogleFonts.inter(
                color: l.color, fontSize: tamano, fontWeight: FontWeight.w800)),
        if (l.secundario != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 1.5),
            child: Text(l.secundario!,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Fila resumida de la tarjeta de Rentabilidad.
class FilaPlatilloCompacta extends StatelessWidget {
  final FilaUtilidad fila;
  const FilaPlatilloCompacta({super.key, required this.fila});

  @override
  Widget build(BuildContext context) {
    final l = _Lectura.de(fila);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Nombre(p: fila.platillo, tamano: 13.5),
          const SizedBox(height: 3),
          _Cifras(l: l, tamano: 14.5),
        ],
      ),
    );
  }
}

/// De dónde sale cada quetzal del platillo. Los renglones suman exacto al
/// precio: es lo que permite creerle al número, o encontrar qué línea está
/// mal cargada.
class DesglosePlatillo extends StatelessWidget {
  final FilaUtilidad fila;
  final RepartoGastos? reparto;

  const DesglosePlatillo({super.key, required this.fila, this.reparto});

  @override
  Widget build(BuildContext context) {
    final p = fila.platillo;
    final d = fila.desglose;
    final r = reparto;

    final hijos = <Widget>[
      const SizedBox(height: 10),
      Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
      const SizedBox(height: 8),
      _Renglon('Precio de venta (con IVA)', formatoQ(p.precio), fuerte: true),
    ];

    if (d != null && d.descuento > 0 && r != null) {
      hijos.add(_Renglon(
          'Descuentos (promedio del negocio, '
          '${formatoPct(r.tasaDescuento * 100)})',
          formatoQ(-d.descuento)));
    }

    if (p.lineas.isNotEmpty) {
      hijos.add(_Renglon(
        'Receta',
        p.costo == null ? 'Incompleta' : formatoQ(-p.costo!),
        colorMonto: p.costo == null ? kAmbar : null,
      ));
      for (final l in p.lineas) {
        hijos.add(_LineaIngrediente(l: l, precioPlatillo: p.precio));
      }
    }

    if (d != null && r != null) {
      hijos.addAll([
        _Renglon(
            'Gastos variables (${formatoPct(r.ratioVariables * 100)} de lo '
            'cobrado)',
            formatoQ(-d.variables)),
        _Renglon(
            'Gastos fijos (${formatoPct(r.ratioFijos * 100)} de lo cobrado)',
            formatoQ(-d.fijos)),
        const SizedBox(height: 4),
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 6),
        _Renglon('Te queda, antes de impuestos', formatoQ(d.utilidad),
            fuerte: true, colorMonto: colorDeBanda(d.banda)),
        _pie(switch (d.banda) {
          Banda.cubreTodo => 'Cubre la receta y su parte de todos los gastos.',
          Banda.noCubreFijos =>
            'No lo quités por esto: cada venta deja ${formatoQ(d.contribucion)} '
                'para la renta y los sueldos. Sin él, esos gastos siguen y los '
                'pagan los demás platillos.',
          Banda.pierde =>
            'La receta y los gastos variables ya cuestan más de lo que '
                'cobrás: cada venta te saca dinero. Subí el precio o revisá '
                'la receta.',
        }),
        if (d.precioMinimo != null && d.banda != Banda.cubreTodo)
          _pie('Cubriría todos sus gastos desde ${formatoQ(d.precioMinimo!)}.'),
      ]);
    } else if (p.estado == EstadoCosto.completo && p.margenReceta != null) {
      hijos.addAll([
        const SizedBox(height: 4),
        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
        const SizedBox(height: 6),
        _Renglon('Queda tras la receta (sin gastos)', formatoQ(p.margenReceta!),
            fuerte: true,
            colorMonto: colorDeMargenReceta(p.margenRecetaPct)),
      ]);
    }

    switch (p.estado) {
      case EstadoCosto.sinReceta:
        hijos.add(_pie('Este platillo no tiene receta. Agregásela en Sabor '
            'Suite para ver cuánto te deja.'));
      case EstadoCosto.incompleto:
        if (p.sinPrecio.isNotEmpty) {
          hijos.add(_pie('Registrá en Despensa una entrada con costo de los '
              'marcados "Sin precio" y el cálculo aparece solo.'));
        }
        if (p.noEnSucursal.isNotEmpty) {
          hijos.add(_pie('El POS no encuentra en esta sucursal los marcados '
              '"No está en la sucursal". Crealos (o activalos) en la Despensa '
              'de esta sucursal con el mismo nombre o código.'));
        }
      case EstadoCosto.completo:
        break;
    }

    for (final a in p.alertas) {
      hijos.add(_pie(_explicacionDeAlerta(a)));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos);
  }

  Widget _pie(String texto) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(texto,
            style: GoogleFonts.inter(
                color: Colors.white60, fontSize: 11.5, height: 1.45)),
      );
}

/// Una etiqueta a la izquierda y un monto a la derecha. Si con la letra del
/// sistema agrandada no caben en una fila sin partir una palabra, el monto
/// baja a su propio renglón, alineado a la derecha: cortar o encimar el monto
/// es lo único que no puede pasar.
class _EtiquetaYMonto extends StatefulWidget {
  /// Los textos de la izquierda, para medir su palabra más larga.
  final List<(String, TextStyle)> textos;
  final Widget izquierda;
  final String monto;
  final TextStyle estiloMonto;

  const _EtiquetaYMonto({
    required this.textos,
    required this.izquierda,
    required this.monto,
    required this.estiloMonto,
  });

  @override
  State<_EtiquetaYMonto> createState() => _EtiquetaYMontoState();
}

class _EtiquetaYMontoState extends State<_EtiquetaYMonto> {
  // La decisión fila/columna se toma midiendo con la tipografía que haya. Si
  // Inter llega después del primer cuadro (GoogleFonts la baja la primera
  // vez), hay que volver a medir: con la medida vieja una palabra se partía.
  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_volverAMedir);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_volverAMedir);
    super.dispose();
  }

  void _volverAMedir() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textos = widget.textos;
    final izquierda = widget.izquierda;
    final monto = widget.monto;
    final estiloMonto = widget.estiloMonto;
    final escala = MediaQuery.textScalerOf(context);
    final direccion = Directionality.of(context);
    // Text mezcla su estilo con el del tema (que trae espaciado entre letras):
    // hay que medir con la misma mezcla o la medida sale corta.
    final base = DefaultTextStyle.of(context).style;

    double medir(String texto, TextStyle estilo, {required bool palabra}) {
      final tp = TextPainter(
        text: TextSpan(text: texto, style: base.merge(estilo)),
        textDirection: direccion,
        textScaler: escala,
      )..layout();
      final ancho = palabra ? tp.minIntrinsicWidth : tp.maxIntrinsicWidth;
      tp.dispose();
      // El texto pintado redondea su ancho hacia arriba; medido sin redondear
      // quedaba un píxel corto y la palabra se salía.
      return ancho.ceilToDouble() + 1;
    }

    final textoMonto =
        Text(monto, textAlign: TextAlign.right, style: estiloMonto);

    return LayoutBuilder(builder: (context, c) {
      final anchoMonto = medir(monto, estiloMonto, palabra: false);
      final palabraMasLarga = textos.fold<double>(
          0, (a, t) => math.max(a, medir(t.$1, t.$2, palabra: true)));
      if (palabraMasLarga + 10 + anchoMonto <= c.maxWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: izquierda),
            const SizedBox(width: 10),
            textoMonto,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [izquierda, textoMonto],
      );
    });
  }
}

class _Renglon extends StatelessWidget {
  final String etiqueta;
  final String monto;
  final bool fuerte;
  final Color? colorMonto;

  const _Renglon(this.etiqueta, this.monto,
      {this.fuerte = false, this.colorMonto});

  @override
  Widget build(BuildContext context) {
    final estiloEtiqueta = GoogleFonts.inter(
      color: fuerte ? Colors.white : Colors.white70,
      fontSize: 13,
      fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
      height: 1.3,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: _EtiquetaYMonto(
        textos: [(etiqueta, estiloEtiqueta)],
        izquierda: Text(etiqueta, style: estiloEtiqueta),
        monto: monto,
        estiloMonto: GoogleFonts.inter(
          color: colorMonto ?? (fuerte ? Colors.white : Colors.white70),
          fontSize: fuerte ? 13.5 : 13,
          fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _LineaIngrediente extends StatelessWidget {
  final LineaCosto l;
  final int precioPlatillo;
  const _LineaIngrediente({required this.l, required this.precioPlatillo});

  @override
  Widget build(BuildContext context) {
    final cantidad =
        '${formatoCantidad(l.cantidad)}${l.unidad.isEmpty ? '' : ' ${l.unidad}'}';
    final String detalle;
    final String monto;
    Color colorMonto = Colors.white70;
    switch (l.estado) {
      case EstadoLinea.ok:
        detalle = '$cantidad × ${_precioUnitario(l.precio!)}';
        monto = formatoQ(l.centavos!);
        // Una sola línea que cuesta más que todo el platillo es casi siempre
        // un error de unidad: se marca para que se vea cuál corregir.
        if (precioPlatillo > 0 && l.centavos! > precioPlatillo) {
          colorMonto = kRojoTexto;
        }
      case EstadoLinea.sinPrecio:
        detalle = cantidad;
        monto = 'Sin precio';
        colorMonto = kAmbar;
      case EstadoLinea.noEnSucursal:
        detalle = cantidad;
        monto = 'No está en la sucursal';
        colorMonto = kAmbar;
    }

    final estiloNombre =
        GoogleFonts.inter(color: Colors.white70, fontSize: 12.5, height: 1.3);
    final textoDetalle =
        l.unidadDistinta ? '$detalle · unidad distinta' : detalle;
    final estiloDetalle = GoogleFonts.inter(
        color: l.unidadDistinta ? kAmbar : Colors.white60,
        fontSize: 11,
        height: 1.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 0, 3),
      child: _EtiquetaYMonto(
        textos: [(l.ingrediente, estiloNombre), (textoDetalle, estiloDetalle)],
        izquierda: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.ingrediente, style: estiloNombre),
            Text(textoDetalle, style: estiloDetalle),
          ],
        ),
        monto: monto,
        estiloMonto: GoogleFonts.inter(
            color: colorMonto, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// El precio por unidad puede ser una fracción de centavo (Q0.0125 el gramo):
/// redondearlo a centavos haría que la línea no cuadre al auditarla.
String _precioUnitario(double precio) {
  final centavos = precio * 100;
  if ((centavos - centavos.round()).abs() < 1e-9) {
    return formatoQ(centavos.round());
  }
  return 'Q${formatoCantidad(precio)}';
}

/// Cómo se repartieron los gastos del período, o por qué no se pudo.
///
/// Es lo primero que hay que leer: sin esto, "te queda Q8.40" no dice de qué
/// período ni con qué gastos sale. Muestra a lo sumo dos avisos, los más
/// importantes: con todos juntos eran 19 líneas antes del primer platillo.
class ResumenReparto extends StatelessWidget {
  final RepartoGastos? reparto;
  final String periodo;
  final bool calculando;

  /// Rentabilidad falló: no hay gastos con qué repartir y hay que decirlo.
  final bool errorGastos;

  /// "Todas" con varias sucursales: el número es aproximado y hay que decirlo.
  final bool vistaTodas;

  /// En la tarjeta de Rentabilidad: deja fuera lo que puede esperar a "Ver
  /// todos".
  final bool compacto;

  /// Cuántos avisos ámbar caben. En la guía, que está para leerse, todos.
  final int maxAvisos;

  const ResumenReparto({
    super.key,
    required this.reparto,
    required this.periodo,
    this.calculando = false,
    this.errorGastos = false,
    this.vistaTodas = false,
    this.compacto = false,
    this.maxAvisos = 2,
  });

  static const _soloReceta = 'Por ahora ves solo el precio menos la receta.';

  @override
  Widget build(BuildContext context) {
    final r = reparto;
    final hijos = <Widget>[];

    if (r == null) {
      if (errorGastos) {
        hijos.add(_nota(
            'No se pudieron calcular los gastos. $_soloReceta Deslizá hacia '
            'abajo para reintentar.',
            kAmbar));
      } else if (calculando) {
        hijos.add(_nota('Calculando los gastos de $periodo…', Colors.white60));
      }
    } else {
      switch (r.estado) {
        case EstadoReparto.listo:
          final c = r.cada100;
          hijos.addAll([
            Text(
              'De cada Q100 que cobrás, Q${c.total} se van en gastos',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3),
            ),
            const SizedBox(height: 3),
            Text(
              'Aparte de la receta: Q${c.fijos} en fijos (renta, sueldos) y '
              'Q${c.variables} en variables (luz, gas…). Gastos de $periodo; '
              'precios y recetas de hoy.',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 12.5, height: 1.4),
            ),
          ]);
          final avisos = <String>[
            if (r.mesEnCurso)
              'El mes va a medias: faltan ventas y quizá gastos. Para decidir, '
                  'elegí el mes pasado.',
            if (r.sinGastosFijos)
              'Faltan tus gastos fijos (renta, sueldos), así que todo sale más '
                  'verde de lo que es. Cargalos en Gastos de Sabor Suite.',
            if (!r.descuentoConocido)
              'Todavía no está el detalle de descuentos del año: la utilidad '
                  'puede salir un poco más alta.',
            if (r.ratio >= 0.8)
              'Es mucho: por eso casi todo sale ámbar o rojo. Revisá en Gastos '
                  'que no haya pagos de otros meses cargados en este período.',
          ];
          for (final a in avisos.take(maxAvisos)) {
            hijos.add(_nota(a, kAmbar));
          }
          if (!compacto && r.gastosDeComida > 0) {
            hijos.add(_nota(
                'Sin contar ${formatoQ((r.gastosDeComida * 100).round())} de '
                'insumos y pagos a proveedores: se asume que es la comida de '
                'las recetas. Si incluye desechables o limpieza, ganás un poco '
                'menos de lo que dice.',
                Colors.white60));
          }
        case EstadoReparto.periodoCorto:
          hijos.add(_nota(
              'Para restar tus gastos, tocá la fecha de arriba y elegí Mes o '
              'Año. $_soloReceta',
              kAmbar));
        case EstadoReparto.sinVentas:
          hijos.add(_nota(
              'Sin ventas en $periodo no hay con qué repartir los gastos. '
              'Elegí un período con ventas. $_soloReceta',
              Colors.white70));
        case EstadoReparto.sinGastos:
          hijos.addAll([
            Text('No hay gastos cargados en $periodo',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3)),
            _nota(
                'Ves solo el precio menos la receta: todo sale mejor de lo que '
                'es. Cargá renta, sueldos y servicios en Gastos de Sabor Suite.',
                kAmbar),
          ]);
        case EstadoReparto.gastosNoLeidos:
          hijos.add(_nota(
              'No se pudieron leer todos los gastos del período (gastos o '
              'retiros de caja). $_soloReceta Deslizá hacia abajo para '
              'reintentar.',
              kAmbar));
        case EstadoReparto.ventasIncompletas:
          hijos.add(_nota(
              'Este período tiene más ventas de las que se pueden traer de una '
              'vez: con una parte, los gastos parecerían más pesados de lo que '
              'son. Probá la vista de Año, que suma todas. $_soloReceta',
              kAmbar));
        case EstadoReparto.gastosSuperanVentas:
          final gastos =
              formatoQ(((r.gastosFijos + r.gastosVariables) * 100).round());
          final ventas = formatoQ((r.ventasNetas * 100).round());
          hijos.add(_nota(
              r.mesEnCurso
                  ? 'Apenas va el mes: ya hay $gastos de gastos y $ventas de '
                      'ventas. Es normal al inicio. Para decidir, elegí el mes '
                      'pasado. $_soloReceta'
                  : 'Tus gastos ($gastos) superan lo que cobraste ($ventas): '
                      'ningún platillo puede cubrir su parte. Es tema de ventas '
                      'o de gastos, no de un platillo: no quités platillos por '
                      'esto. Revisá que no haya gastos repetidos o de otros '
                      'meses. $_soloReceta',
              r.mesEnCurso ? kAmbar : kRojoTexto));
      }
    }

    if (vistaTodas) {
      hijos.add(_nota(
          'En "Todas" se usa el precio base y el costo de la sucursal donde se '
          'armó cada receta. Elegí una sucursal para verlo con sus precios.',
          Colors.white60));
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos);
  }

  Widget _nota(String texto, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(texto,
            style: GoogleFonts.inter(color: color, fontSize: 12, height: 1.45)),
      );
}

/// Una sola línea con lo que no puede esconderse detrás del ícono: de qué
/// período salen los gastos, o por qué la columna Gasto está vacía. El resto
/// vive en la guía.
({String texto, Color color})? resumenCorto(
  RepartoGastos? r, {
  bool calculando = false,
  bool errorGastos = false,
}) {
  if (r == null) {
    if (errorGastos) {
      return (texto: 'No se pudieron calcular los gastos', color: kAmbar);
    }
    if (calculando) {
      return (texto: 'Calculando los gastos…', color: Colors.white60);
    }
    return null;
  }
  // Los avisos que cambian la lectura de TODA la tabla no pueden quedar
  // detrás de un punto de 9 px: se suman a la línea y la pintan de ámbar.
  final aviso = r.mesEnCurso
      ? 'el mes va a medias'
      : r.sinGastosFijos
          ? 'faltan tus gastos fijos'
          : r.ratio >= 0.8
              ? 'gastos muy altos, revisalos'
              : null;
  return switch (r.estado) {
    EstadoReparto.listo => (
        texto: 'De cada Q100 que cobrás, Q${r.cada100.total} se van en gastos'
            '${aviso == null ? '' : ' · $aviso'}',
        color: aviso == null ? Colors.white : kAmbar,
      ),
    EstadoReparto.periodoCorto =>
      (texto: 'Gasto vacío: elegí Mes o Año en la fecha', color: kAmbar),
    EstadoReparto.sinVentas =>
      (texto: 'Sin ventas en el período: no se reparten gastos', color: kAmbar),
    EstadoReparto.sinGastos => (
        texto: 'No hay gastos cargados: la ganancia sale más alta',
        color: kAmbar,
      ),
    EstadoReparto.gastosNoLeidos =>
      (texto: 'No se pudieron leer todos los gastos', color: kAmbar),
    EstadoReparto.ventasIncompletas =>
      (texto: 'Demasiadas ventas para repartir: probá Año', color: kAmbar),
    EstadoReparto.gastosSuperanVentas => r.mesEnCurso
        ? (texto: 'El mes recién empieza: elegí el mes pasado', color: kAmbar)
        : (texto: 'Tus gastos superan tus ventas', color: kRojoTexto),
  };
}

/// Hay avisos que conviene leer en la guía: el ícono se enciende.
bool hayAvisos(RepartoGastos? r,
    {bool errorGastos = false, bool vistaTodas = false}) {
  // En "Todas" los números son aproximados (precio base): se avisa.
  if (errorGastos || vistaTodas) return true;
  if (r == null) return false;
  if (!r.listo) return true;
  return r.mesEnCurso ||
      r.sinGastosFijos ||
      !r.descuentoConocido ||
      r.ratio >= 0.8;
}

Widget _tituloSeccion(String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(t,
          style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );

Widget _parrafo(String t, {Color color = Colors.white70}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t,
          style: GoogleFonts.inter(color: color, fontSize: 12.5, height: 1.45)),
    );

/// La guía que abre el ícono de idea: todo lo que antes iba en texto encima de
/// la lista. Está para leerse con calma, así que muestra todos los avisos.
class GuiaUtilidad extends StatelessWidget {
  final RepartoGastos? reparto;
  final String periodo;
  final bool calculando;
  final bool errorGastos;
  final bool vistaTodas;
  final int descartados;
  final String? errorMenu;

  const GuiaUtilidad({
    super.key,
    required this.reparto,
    required this.periodo,
    this.calculando = false,
    this.errorGastos = false,
    this.vistaTodas = false,
    this.descartados = 0,
    this.errorMenu,
  });

  @override
  Widget build(BuildContext context) {
    Widget color(Color c, String nombre, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '$nombre: ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: texto),
                  ]),
                  style: GoogleFonts.inter(
                      color: Colors.white70, fontSize: 12.5, height: 1.45),
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tituloSeccion('TUS GASTOS DE ${periodo.toUpperCase()}'),
        ResumenReparto(
          reparto: reparto,
          periodo: periodo,
          calculando: calculando,
          errorGastos: errorGastos,
          vistaTodas: vistaTodas,
          maxAvisos: 99,
        ),
        _tituloSeccion('QUÉ DICE CADA COLUMNA'),
        _parrafo('Costo: lo que pide la receta al último precio de compra de '
            'cada ingrediente en la sucursal, como lo descuenta el POS (sin '
            'merma, extras ni desechables).'),
        _parrafo('Gasto: la parte de tus gastos fijos y variables que le toca '
            'al platillo según su precio, más el descuento promedio. Solo con '
            'Mes o Año.'),
        _parrafo('Precio: el que cobra la sucursal, con IVA.'),
        _parrafo('Ganancia: precio menos costo menos gasto, por venta y antes '
            'de impuestos. Sin gastos repartidos es precio menos costo.'),
        _parrafo('%: la ganancia sobre el precio. Sirve para comparar un '
            'platillo caro con uno barato.'),
        _tituloSeccion('QUÉ DICE CADA COLOR'),
        color(kVerde, 'Verde', 'cubre la receta y su parte de todos los gastos.'),
        color(kAmbar, 'Ámbar',
            'cubre la receta y los gastos variables, pero no toda su parte de '
                'la renta y los sueldos. Aporta: no lo quités por esto, revisá '
                'el precio.'),
        color(kRojoTexto, 'Rojo',
            'la receta y los gastos variables ya cuestan más de lo que '
                'cobrás: cada venta pierde. Primero revisá que la receta esté '
                'bien cargada.'),
        _parrafo('Cuando no se reparten gastos (día, semana, un rango libre o '
            'si faltan datos), el color sigue la meta de costo de comida de '
            'Rentabilidad: la receta en menos de 35% del precio.'),
        _parrafo('"Revisar" en Ganancia: el costo parece mal cargado y la '
            'cifra no sería confiable. Tocá el platillo para ver por qué.'),
        _tituloSeccion('CONSEJOS'),
        _parrafo('Tocá cualquier platillo (o su ícono de idea) para ver el desglose línea '
            'por línea y qué hacer con él. La idea encendida marca los que '
            'tienen algo que revisar.'),
        _parrafo('Los que tienen datos sospechosos (receta más cara que el '
            'precio, un ingrediente repetido, unidades distintas) están en el '
            'filtro "Por revisar". Casi siempre es un error de unidad: gramos '
            'contra kilos.'),
        _parrafo('A los que les falta costo, registrales en Despensa una '
            'entrada con costo de los ingredientes sin precio.'),
        if (descartados > 0) _parrafo(textoDescartadosMenu(descartados)),
        if (errorMenu != null)
          _parrafo(
              'No se pudo actualizar el menú: se muestran los datos '
              'anteriores. Deslizá hacia abajo para reintentar.',
              color: kAmbar),
      ],
    );
  }
}

String textoDescartadosMenu(int n) => n == 1
    ? '1 producto o receta con datos dañados no aparece. Si falta un platillo, '
        'avisá a soporte.'
    : '$n productos o recetas con datos dañados no aparecen. Si falta un '
        'platillo, avisá a soporte.';

/// Lo que abre un platillo: su nombre completo, qué revisar y el desglose
/// línea por línea con sus consejos.
class ConsejosPlatillo extends StatelessWidget {
  final FilaUtilidad fila;
  final RepartoGastos? reparto;

  const ConsejosPlatillo({super.key, required this.fila, this.reparto});

  @override
  Widget build(BuildContext context) {
    final p = fila.platillo;
    final l = _Lectura.de(fila);
    final alertas = p.alertas.toList()..sort((a, b) => a.index - b.index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Nombre(p: p, tamano: 16),
        const SizedBox(height: 8),
        _Cifras(l: l),
        for (final a in alertas)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              textoDeAlerta(a),
              style: GoogleFonts.inter(
                color: a == AlertaReceta.cuestaMasQueElPrecio
                    ? kRojoTexto
                    : kAmbar,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        DesglosePlatillo(fila: fila, reparto: reparto),
      ],
    );
  }
}
