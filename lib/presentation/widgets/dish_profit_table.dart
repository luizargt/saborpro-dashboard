import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/menu_margin_data.dart';
import '../../data/models/profitability_data.dart';
import 'dish_profit_widgets.dart';

/// Columnas por las que se puede ordenar la tabla.
enum ColumnaOrden { producto, costo, gasto, precio, ganancia, pct }

/// Lo que dice cada celda de una fila, ya formateado y con su color.
class CeldasFila {
  final String costo;
  final Color colorCosto;
  final String gasto;
  final String precio;
  final String ganancia;
  final String pct;
  final Color colorGanancia;

  /// Qué significa el color, para el lector de pantalla.
  final String? significado;

  /// Hay algo que leer en el desglose: un dato por revisar, un platillo que
  /// pierde, que no cubre sus fijos o con costo de comida alto, o uno al que
  /// le falta costo o receta.
  final bool conConsejo;
  final bool grave;

  const CeldasFila({
    required this.costo,
    required this.colorCosto,
    required this.gasto,
    required this.precio,
    required this.ganancia,
    required this.pct,
    required this.colorGanancia,
    this.significado,
    required this.conConsejo,
    required this.grave,
  });

  factory CeldasFila.de(FilaUtilidad f) {
    final p = f.platillo;
    final d = f.desglose;

    final String costo;
    Color colorCosto = Colors.white70;
    switch (p.estado) {
      case EstadoCosto.completo:
        costo = formatoQ(p.costo!);
      case EstadoCosto.incompleto:
        costo = 'Falta';
        colorCosto = kAmbar;
      case EstadoCosto.sinReceta:
        costo = 'Sin receta';
        colorCosto = Colors.white60;
    }

    String ganancia;
    String pct;
    Color color;
    String? significado;
    var costoComidaAlto = false;
    if (p.porRevisar && p.estado == EstadoCosto.completo) {
      // Con el costo mal cargado, la cifra es basura ("−620%"): en la tabla
      // dice "Revisar" y el número queda en el desglose, con su explicación.
      ganancia = 'Revisar';
      pct = '—';
      color = kAmbar;
      significado = 'dato por revisar';
    } else if (d != null && d.pct != null) {
      ganancia = formatoQ(d.utilidad);
      pct = formatoPct(d.pct);
      color = colorDeBanda(d.banda);
      significado = etiquetaDeBanda(d);
    } else if (p.margenReceta != null && p.margenRecetaPct != null) {
      ganancia = formatoQ(p.margenReceta!);
      pct = formatoPct(p.margenRecetaPct);
      color = colorDeMargenReceta(p.margenRecetaPct);
      final salud = evaluarFoodCost(100 - p.margenRecetaPct!);
      costoComidaAlto = salud == Salud.atencion || salud == Salud.mal;
      significado = costoComidaAlto
          ? 'la receta pasa la meta de costo de comida'
          : 'la receta está dentro de la meta';
    } else {
      ganancia = '—';
      pct = '—';
      color = Colors.white60;
    }

    final banda = d?.banda;
    return CeldasFila(
      costo: costo,
      colorCosto: colorCosto,
      gasto: d == null ? '—' : formatoQ(d.descuento + d.variables + d.fijos),
      precio: formatoQ(p.precio),
      ganancia: ganancia,
      pct: pct,
      colorGanancia: color,
      significado: significado,
      conConsejo: p.porRevisar ||
          p.estado != EstadoCosto.completo ||
          costoComidaAlto ||
          (banda != null && banda != Banda.cubreTodo),
      grave: p.alertas.contains(AlertaReceta.cuestaMasQueElPrecio) ||
          banda == Banda.pierde,
    );
  }
}

// Las filas se recrean solo cuando cambian los datos, no al escribir en el
// buscador ni al ordenar: se calculan sus celdas una vez.
final _memoCeldas = Expando<CeldasFila>();
CeldasFila celdasDe(FilaUtilidad f) => _memoCeldas[f] ??= CeldasFila.de(f);

bool _esCifra(String v) => RegExp(r'^−?Q?[\d,.]+%?$').hasMatch(v);

/// Los valores que hay que medir para saber el ancho de una columna.
///
/// Las cifras van con dígitos de ancho fijo, así que de ellas basta la más
/// larga (y la negativa más larga, porque el "−" no mide lo que un dígito).
/// Los textos ("Falta", "Sin receta", "Revisar") se miden todos: contar letras
/// no sirve entre textos y cifras, y elegía "Sin receta" por tener más letras
/// aunque "Q1,250.00" fuera más ancho.
@visibleForTesting
List<String> candidatosParaMedir(Iterable<String> valores) {
  String? positivo, negativo;
  final textos = <String>{};
  for (final v in valores) {
    if (!_esCifra(v)) {
      textos.add(v);
    } else if (v.startsWith('−')) {
      if (negativo == null || v.length > negativo.length) negativo = v;
    } else {
      if (positivo == null || v.length > positivo.length) positivo = v;
    }
  }
  return [
    if (positivo != null) positivo,
    if (negativo != null) negativo,
    ...textos,
  ];
}

enum _Tipo { costo, gasto, precio, ganancia, pct }

class _Col {
  final _Tipo tipo;
  final double ancho;
  const _Col(this.tipo, this.ancho);

  ColumnaOrden get orden => switch (tipo) {
        _Tipo.costo => ColumnaOrden.costo,
        _Tipo.gasto => ColumnaOrden.gasto,
        _Tipo.precio => ColumnaOrden.precio,
        _Tipo.ganancia => ColumnaOrden.ganancia,
        _Tipo.pct => ColumnaOrden.pct,
      };

  String get titulo => switch (tipo) {
        _Tipo.costo => 'Costo',
        _Tipo.gasto => 'Gasto',
        _Tipo.precio => 'Precio',
        _Tipo.ganancia => 'Ganancia',
        _Tipo.pct => '%',
      };

  static String valor(_Tipo t, CeldasFila c) => switch (t) {
        _Tipo.costo => c.costo,
        _Tipo.gasto => c.gasto,
        _Tipo.precio => c.precio,
        _Tipo.ganancia => c.ganancia,
        _Tipo.pct => c.pct,
      };

  Color color(CeldasFila c) => switch (tipo) {
        _Tipo.costo => c.colorCosto,
        _Tipo.gasto => Colors.white70,
        _Tipo.precio => Colors.white,
        _Tipo.ganancia || _Tipo.pct => c.colorGanancia,
      };

  bool get fuerte => tipo == _Tipo.ganancia;
}

TextStyle _estiloNumero(Color color, {bool fuerte = false}) => GoogleFonts.inter(
      color: color,
      fontSize: 13,
      fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
      // Cifras de ancho fijo: las columnas quedan alineadas como en Excel.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

final _estiloTitulo = GoogleFonts.inter(
    color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700);
final _estiloNombre = GoogleFonts.inter(
    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600);
final _estiloPresentacion =
    GoogleFonts.inter(color: Colors.white70, fontSize: 11.5);

const _cebraClara = Color(0xFF243247);

/// La tabla tipo hoja de cálculo.
///
/// En pantalla ancha caben todas las columnas, en el orden en que se lee la
/// cuenta (costo, gasto, precio, ganancia). En teléfono la de Producto queda
/// fija a la izquierda (con la presentación debajo), Ganancia y % van primero
/// para verse sin deslizar, y el resto se desliza de lado: como "inmovilizar
/// columna" en Excel.
///
/// El ancho de cada columna numérica se MIDE con la letra del sistema: un
/// monto nunca se corta, a lo sumo la tabla se desliza.
class TablaUtilidad extends StatefulWidget {
  /// Las filas que se ven.
  final List<FilaUtilidad> filas;

  /// Todas las filas del menú: los anchos se miden con ellas para que las
  /// columnas no salten mientras se escribe en el buscador.
  final List<FilaUtilidad> todas;
  final ColumnaOrden columna;
  final bool ascendente;
  final ValueChanged<ColumnaOrden> onOrdenar;
  final ValueChanged<FilaUtilidad> onAbrir;
  final Future<void> Function()? onRefresh;

  const TablaUtilidad({
    super.key,
    required this.filas,
    required this.todas,
    required this.columna,
    required this.ascendente,
    required this.onOrdenar,
    required this.onAbrir,
    this.onRefresh,
  });

  /// Desde este ancho Producto y Presentación van en columnas separadas.
  static const anchoMinimoSeparado = 720.0;

  @override
  State<TablaUtilidad> createState() => _TablaUtilidadState();
}

class _TablaUtilidadState extends State<TablaUtilidad> {
  final _horizontal = ScrollController();

  // Los anchos se miden con la tipografía que haya. Si Inter llega después
  // del primer cuadro, hay que volver a medir o los montos quedan cortos.
  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_volverAMedir);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_volverAMedir);
    _horizontal.dispose();
    super.dispose();
  }

  void _volverAMedir() {
    if (mounted) setState(() {});
  }

  TextPainter _pintor(BuildContext context, String texto, TextStyle estilo) =>
      TextPainter(
        text: TextSpan(
            text: texto,
            style: DefaultTextStyle.of(context).style.merge(estilo)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();

  double _ancho(BuildContext context, String texto, TextStyle estilo) {
    final tp = _pintor(context, texto, estilo);
    final ancho = tp.maxIntrinsicWidth.ceilToDouble() + 1;
    tp.dispose();
    return ancho;
  }

  double _alto(BuildContext context, TextStyle estilo) {
    final tp = _pintor(context, 'Ág', estilo);
    final alto = tp.height.ceilToDouble();
    tp.dispose();
    return alto;
  }

  double _anchoColumna(
      BuildContext context, _Tipo tipo, List<CeldasFila> celdas) {
    final estilo = _estiloNumero(Colors.white, fuerte: tipo == _Tipo.ganancia);
    final escala = MediaQuery.textScalerOf(context);
    var ancho = _ancho(context, _Col(tipo, 0).titulo, _estiloTitulo) +
        escala.scale(16); // la flecha de orden
    for (final v in candidatosParaMedir(celdas.map((c) => _Col.valor(tipo, c)))) {
      ancho = math.max(ancho, _ancho(context, v, estilo));
    }
    return ancho + 20;
  }

  @override
  Widget build(BuildContext context) {
    final celdas = [for (final f in widget.filas) celdasDe(f)];
    final celdasTodas = [for (final f in widget.todas) celdasDe(f)];
    final escala = MediaQuery.textScalerOf(context);

    return LayoutBuilder(builder: (context, c) {
      final separado = c.maxWidth >= TablaUtilidad.anchoMinimoSeparado;
      final tipos = separado
          ? const [_Tipo.costo, _Tipo.gasto, _Tipo.precio, _Tipo.ganancia, _Tipo.pct]
          : const [_Tipo.ganancia, _Tipo.pct, _Tipo.precio, _Tipo.costo, _Tipo.gasto];
      final numeros = [
        for (final t in tipos) _Col(t, _anchoColumna(context, t, celdasTodas))
      ];
      final anchoIdea = math.max(48.0, escala.scale(40));
      final sumaNumeros =
          numeros.fold<double>(0, (a, col) => a + col.ancho) + anchoIdea;

      final libre = c.maxWidth - sumaNumeros;
      final conPresentacion = separado && libre >= 300;

      final double anchoProducto;
      final double anchoPresentacion;
      if (conPresentacion) {
        anchoProducto = libre * 0.55;
        anchoPresentacion = libre - anchoProducto;
      } else {
        // Fija a la izquierda: lo bastante ancha para reconocer el platillo,
        // sin comerse la pantalla de un teléfono.
        anchoProducto = (c.maxWidth * 0.45).clamp(130.0, 240.0);
        anchoPresentacion = 0;
      }

      final total = anchoProducto + anchoPresentacion + sumaNumeros;
      final desliza = total > c.maxWidth + 0.5;
      final anchoTabla = desliza ? total : c.maxWidth;
      final productoFinal =
          desliza ? anchoProducto : anchoProducto + (c.maxWidth - total);

      // Alturas medidas con la letra real del sistema (la escala de Android 14
      // no es lineal: multiplicar una altura fija se quedaba corto).
      final altoFila = math.max(
          48.0,
          (conPresentacion
                  ? math.max(_alto(context, _estiloNombre),
                      _alto(context, _estiloNumero(Colors.white)))
                  : _alto(context, _estiloNombre) +
                      _alto(context, _estiloPresentacion)) +
              16);
      final altoTitulo = math.max(44.0, _alto(context, _estiloTitulo) + 16);
      final controlador = desliza ? _horizontal : null;

      final lista = ListView.builder(
        key: const PageStorageKey('utilidad-vertical'),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding:
            EdgeInsets.only(bottom: 28 + MediaQuery.paddingOf(context).bottom),
        itemCount: widget.filas.length,
        itemBuilder: (context, i) => _FilaDatos(
          key: ValueKey(widget.filas[i].platillo.clave),
          fila: widget.filas[i],
          celdas: celdas[i],
          par: i.isEven,
          altura: altoFila,
          anchoProducto: productoFinal,
          anchoPresentacion: anchoPresentacion,
          numeros: numeros,
          anchoIdea: anchoIdea,
          horizontal: controlador,
          onAbrir: widget.onAbrir,
        ),
      );

      Widget tabla = SizedBox(
        width: anchoTabla,
        height: c.maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilaTitulo(
              altura: altoTitulo,
              anchoProducto: productoFinal,
              anchoPresentacion: anchoPresentacion,
              numeros: numeros,
              anchoIdea: anchoIdea,
              horizontal: controlador,
              columna: widget.columna,
              ascendente: widget.ascendente,
              onOrdenar: widget.onOrdenar,
            ),
            Expanded(child: lista),
          ],
        ),
      );

      if (desliza) {
        tabla = Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            // Recuerda cuánto se deslizó al cambiar de sucursal: comparar un
            // platillo entre sucursales no puede costar volver a buscar la
            // columna.
            key: const PageStorageKey('utilidad-horizontal'),
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: tabla,
          ),
        );
      }

      if (widget.onRefresh != null) {
        tabla = RefreshIndicator(
          color: kAcento,
          backgroundColor: kTarjeta,
          onRefresh: widget.onRefresh!,
          // La lista va dentro del desplazamiento horizontal: sin esto el
          // gesto de deslizar hacia abajo no llegaba al indicador.
          notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
          child: tabla,
        );
      }
      return tabla;
    });
  }
}

/// Fila con la columna de Producto fija: las demás celdas van en una Row que
/// se desliza con la tabla, y Producto se pinta ENCIMA, corrido lo mismo que
/// se deslizó, para que quede quieto a la izquierda.
///
/// Solo esa celda escucha el desplazamiento: reconstruir la lista entera en
/// cada cuadro del deslizamiento costaba unos mil elementos por cuadro.
class _ConProductoFijo extends StatelessWidget {
  final double altura;
  final double anchoProducto;
  final ScrollController? horizontal;
  final Color fondo;
  final Widget producto;
  final List<Widget> resto;

  const _ConProductoFijo({
    required this.altura,
    required this.anchoProducto,
    required this.horizontal,
    required this.fondo,
    required this.producto,
    required this.resto,
  });

  Widget _posicionada(double desplazamiento, Widget hijo) => Positioned(
        left: desplazamiento,
        top: 0,
        bottom: 0,
        width: anchoProducto,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: desplazamiento > 0
                ? const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 6,
                        offset: Offset(2, 0)),
                  ]
                : null,
          ),
          // Material propio: el toque se ve también sobre la celda fija.
          child: Material(color: fondo, child: hijo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final h = horizontal;
    return SizedBox(
      height: altura,
      child: Stack(
        children: [
          Row(children: [SizedBox(width: anchoProducto), ...resto]),
          if (h == null)
            _posicionada(0, producto)
          else
            AnimatedBuilder(
              animation: h,
              child: producto,
              // Nunca menos de cero: en el rebote de iOS el desplazamiento se
              // vuelve negativo y la celda fija quedaba recortada, con una
              // franja vacía a la izquierda. Así la tabla rebota entera.
              builder: (context, hijo) => _posicionada(
                  h.hasClients ? math.max(0.0, h.offset) : 0, hijo!),
            ),
        ],
      ),
    );
  }
}

class _FilaTitulo extends StatelessWidget {
  final double altura;
  final double anchoProducto;
  final double anchoPresentacion;
  final List<_Col> numeros;
  final double anchoIdea;
  final ScrollController? horizontal;
  final ColumnaOrden columna;
  final bool ascendente;
  final ValueChanged<ColumnaOrden> onOrdenar;

  const _FilaTitulo({
    required this.altura,
    required this.anchoProducto,
    required this.anchoPresentacion,
    required this.numeros,
    required this.anchoIdea,
    required this.horizontal,
    required this.columna,
    required this.ascendente,
    required this.onOrdenar,
  });

  Widget _titulo(String texto, ColumnaOrden? orden, double ancho,
      {bool derecha = true}) {
    final activo = orden != null && orden == columna;
    final contenido = Row(
      mainAxisAlignment:
          derecha ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: activo
                  ? _estiloTitulo.copyWith(color: Colors.white)
                  : _estiloTitulo),
        ),
        if (activo)
          Icon(
            ascendente
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
            color: kAcentoTexto,
          ),
      ],
    );
    final relleno = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: derecha ? Alignment.centerRight : Alignment.centerLeft,
        child: contenido,
      ),
    );
    if (orden == null) return SizedBox(width: ancho, child: relleno);
    return SizedBox(
      width: ancho,
      child: Semantics(
        button: true,
        label: 'Ordenar por ${texto == '%' ? 'porcentaje' : texto}',
        value: activo
            ? (ascendente ? 'de menor a mayor' : 'de mayor a menor')
            : null,
        excludeSemantics: true,
        onTap: () => onOrdenar(orden),
        child: InkWell(onTap: () => onOrdenar(orden), child: relleno),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kFondo,
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
      child: _ConProductoFijo(
        altura: altura,
        anchoProducto: anchoProducto,
        horizontal: horizontal,
        fondo: kFondo,
        producto: _titulo('Producto', ColumnaOrden.producto, anchoProducto,
            derecha: false),
        resto: [
          if (anchoPresentacion > 0)
            _titulo('Presentación', null, anchoPresentacion, derecha: false),
          for (final col in numeros) _titulo(col.titulo, col.orden, col.ancho),
          SizedBox(width: anchoIdea),
        ],
      ),
    );
  }
}

class _FilaDatos extends StatelessWidget {
  final FilaUtilidad fila;
  final CeldasFila celdas;
  final bool par;
  final double altura;
  final double anchoProducto;
  final double anchoPresentacion;
  final List<_Col> numeros;
  final double anchoIdea;
  final ScrollController? horizontal;
  final ValueChanged<FilaUtilidad> onAbrir;

  const _FilaDatos({
    super.key,
    required this.fila,
    required this.celdas,
    required this.par,
    required this.altura,
    required this.anchoProducto,
    required this.anchoPresentacion,
    required this.numeros,
    required this.anchoIdea,
    required this.horizontal,
    required this.onAbrir,
  });

  /// Lo que lee el lector de pantalla: primero el platillo, después cada cifra
  /// con el nombre de su columna y al final qué significa el color.
  String _etiqueta() {
    final p = fila.platillo;
    final c = celdas;
    String leer(String v) => v == '—' ? 'sin dato' : v;
    return [
      p.presentacion == null ? p.producto : '${p.producto}, ${p.presentacion}',
      'Costo ${leer(c.costo)}',
      'Gasto ${leer(c.gasto)}',
      'Precio ${leer(c.precio)}',
      'Ganancia ${leer(c.ganancia)}',
      if (c.pct != '—') '${c.pct} del precio',
      if (c.significado != null) c.significado!,
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final p = fila.platillo;
    final fondo = par ? kTarjeta : _cebraClara;
    final c = celdas;
    final conPresentacion = anchoPresentacion > 0;

    final producto = InkWell(
      onTap: () => onAbrir(fila),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.producto,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _estiloNombre),
            if (!conPresentacion && p.presentacion != null)
              Text(p.presentacion!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _estiloPresentacion),
          ],
        ),
      ),
    );

    final colorIdea =
        !c.conConsejo ? Colors.white54 : (c.grave ? kRojoTexto : kAmbar);

    return Semantics(
      container: true,
      button: true,
      label: _etiqueta(),
      hint: 'Abre el desglose y los consejos',
      excludeSemantics: true,
      onTap: () => onAbrir(fila),
      child: Material(
        color: fondo,
        child: InkWell(
          onTap: () => onAbrir(fila),
          child: _ConProductoFijo(
            altura: altura,
            anchoProducto: anchoProducto,
            horizontal: horizontal,
            fondo: fondo,
            producto: producto,
            resto: [
              if (conPresentacion)
                SizedBox(
                  width: anchoPresentacion,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(p.presentacion ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                ),
              for (final col in numeros)
                SizedBox(
                  width: col.ancho,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(_Col.valor(col.tipo, c),
                          maxLines: 1,
                          softWrap: false,
                          style: _estiloNumero(col.color(c),
                              fuerte: col.fuerte)),
                    ),
                  ),
                ),
              SizedBox(
                width: anchoIdea,
                child: IconButton(
                  // 44 como mínimo: el de Material mide 40 y se erra con el
                  // dedo.
                  style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                  tooltip: c.conConsejo
                      ? 'Ver desglose y consejos'
                      : 'Ver desglose',
                  icon: Icon(
                    c.conConsejo
                        ? Icons.lightbulb_rounded
                        : Icons.lightbulb_outline_rounded,
                    color: colorIdea,
                    size: 20,
                  ),
                  onPressed: () => onAbrir(fila),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
