/// Rentabilidad. Rediseño 2026-11-22 (`rentabilidad.html` de saborpro_app, en su
/// modo oscuro): si se ganó o se perdió y cuánto hay que vender para no perder, los
/// tres indicadores del rubro, el estado de resultados, qué sucursal gana más, qué
/// recetas faltan, el mapa del menú y cuánto deja cada platillo.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa los números
/// ya armados ([ProfitabilityData], [ComparacionSucursales], [AnalisisMenu]). Se prueba
/// a 360dp en test/presentation/widgets/rentabilidad_view_test.dart.
///
/// OJO: los pares de tarjetas y el héroe van en un `IntrinsicHeight` (misma altura):
/// nada de lo que llevan dentro puede usar `LayoutBuilder`. Las marcas de las barras
/// (la meta, el punto de equilibrio) se colocan con un `CustomSingleChildLayout`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_range.dart';
import '../../data/models/cierres_caja.dart' show formatoMonto;
import '../../data/models/profitability_data.dart';
import '../../data/models/rentabilidad_data.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El color de "gasto" del diseño (`--exp`).
Color get _exp => _C.exp;

final _entero = NumberFormat('#,##0', 'en_US');

String _p(double? v) {
  if (v == null) return '—';
  final t = v.toStringAsFixed(1);
  // Un -0.04 se pintaba "-0.0%": lo que redondea a cero no lleva signo.
  return '${t == '-0.0' ? '0.0' : t}%';
}

/// Lo que se comparte entre las secciones: la moneda y el formato.
class _Ctx {
  final String signo;
  final bool telefono;
  const _Ctx(this.signo, this.telefono);

  /// "Q1,234.50"
  String m(double v) => formatoMonto(signo, v);

  /// "Q1,235": sin centavos (los montos grandes del diseño).
  String m0(double v) {
    final r = v.isFinite ? v.round() : 0;
    final d = _entero.format(r.abs());
    return r < 0 ? '−$signo$d' : '$signo$d';
  }
}

class RentabilidadBody extends StatefulWidget {
  final ProfitabilityData datos;
  final DateRange rango;

  /// Para decir "te faltan" o "te faltaron"; en las pruebas, un día fijo.
  final DateTime? ahora;
  final String signo;

  /// Las sucursales a la vista que no tienen ningún gasto fijo anotado.
  final List<String> sinGastosFijos;

  /// Hay más de una sucursal a la vista (para nombrar de cuál faltan gastos).
  final bool variasSucursales;

  /// "¿Qué sucursal gana más?"; solo se dibuja con dos o más para comparar.
  final ComparacionSucursales comparacion;

  /// El menú cruzado con lo vendido; null mientras no llega.
  final AnalisisMenu? menu;
  final bool menuCargando;
  final String? menuError;

  /// La vista de año no trae los pedidos: no se puede decir qué se vendió.
  final bool menuSinPedidos;

  /// El período tiene más pedidos de los que se leen de una vez: las unidades
  /// salen cortas.
  final bool ventasIncompletas;

  /// "Acá entran solo las sucursales en Q…": cuando "Todas" mezcla monedas.
  final String? notaMoneda;

  /// "En Todas se usa el precio base…" o "Precios y costos de X".
  final String notaPrecios;

  final AvisoPreproduccion? avisoPreproduccion;
  final VoidCallback? onReintentarMenu;
  final VoidCallback onIrAGastos;
  final VoidCallback? onVerUtilidadPlatillos;

  const RentabilidadBody({
    super.key,
    required this.datos,
    required this.rango,
    required this.signo,
    this.ahora,
    this.sinGastosFijos = const [],
    this.variasSucursales = false,
    this.comparacion = ComparacionSucursales.vacia,
    this.menu,
    this.menuCargando = false,
    this.menuError,
    this.menuSinPedidos = false,
    this.ventasIncompletas = false,
    this.notaMoneda,
    this.notaPrecios = '',
    this.avisoPreproduccion,
    this.onReintentarMenu,
    required this.onIrAGastos,
    this.onVerUtilidadPlatillos,
  });

  @override
  State<RentabilidadBody> createState() => _RentabilidadBodyState();
}

class _RentabilidadBodyState extends State<RentabilidadBody> {
  bool _porVenta = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final telefono = ancho <= kInicioQuiebreTelefono;
      final pad = ancho < 640 ? 16.0 : 20.0;
      final ctx = _Ctx(widget.signo, telefono);
      final d = widget.datos;
      final ahora = widget.ahora ?? DateTime.now();
      const gap = SizedBox(height: 14);

      final hayFijos = !d.sinCostosFijos;
      final faltan = widget.sinGastosFijos;

      final hijos = <Widget>[
        _Heroe(ctx: ctx, d: d, rango: widget.rango, ahora: ahora, faltan: faltan, nombrar: widget.variasSucursales),
        gap,
        _Indicadores(ctx: ctx, d: d, hayFijos: hayFijos, faltan: faltan),
        if (!d.costoConfiable && d.itemsTotales > 0) ...[gap, _AvisoCobertura(d: d)],
        gap,
        _Cascada(
          ctx: ctx,
          d: d,
          faltan: faltan,
          hayFijos: hayFijos,
          nombrar: widget.variasSucursales,
          onIrAGastos: widget.onIrAGastos,
        ),
        if (widget.comparacion.hayQueComparar) ...[
          gap,
          _Sucursales(ctx: ctx, comparacion: widget.comparacion, ancho: ancho - 2 * pad),
        ],
        gap,
        ..._seccionesDeMenu(ctx, ancho - 2 * pad),
        if (widget.avisoPreproduccion != null) ...[gap, _AvisoAmbar(titulo: widget.avisoPreproduccion!.titulo, parrafos: widget.avisoPreproduccion!.parrafos)],
        gap,
        _FueraDeLaCuenta(ctx: ctx, d: d),
        if (widget.onVerUtilidadPlatillos != null) ...[gap, _VerUtilidad(onTap: widget.onVerUtilidadPlatillos!)],
      ];

      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
        ),
      );
    });
  }

  /// Todo lo que depende de cruzar el menú con lo vendido.
  List<Widget> _seccionesDeMenu(_Ctx ctx, double anchoUtil) {
    const gap = SizedBox(height: 14);
    final m = widget.menu;

    Widget aviso(String texto, {Widget? accion}) => _Tarjeta(
          ctx: ctx,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(texto, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45)),
              if (accion != null) ...[const SizedBox(height: 10), accion],
            ],
          ),
        );

    if (widget.menuSinPedidos) {
      return [
        aviso('La vista de año no detalla qué platillos se vendieron. Elige un mes para ver el mapa de tu menú y cuánto deja cada platillo.'),
        gap,
      ];
    }
    if (widget.menuError != null && m == null) {
      return [
        aviso(
          widget.menuError!,
          accion: widget.onReintentarMenu == null ? null : _Boton(texto: 'Reintentar', icono: Icons.refresh_rounded, onTap: widget.onReintentarMenu!),
        ),
        gap,
      ];
    }
    if (m == null) {
      return [
        _Tarjeta(
          ctx: ctx,
          child: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: _C.accent)),
              const SizedBox(width: 14),
              Expanded(child: Text('Cargando tu menú…', style: _t(13.5, FontWeight.w400, _C.muted))),
            ],
          ),
        ),
        gap,
      ];
    }
    if (!m.hayAlgo) {
      return [
        aviso('No hay platillos vendidos con receta en este período, así que no hay mapa del menú que dibujar.'),
        gap,
      ];
    }

    return [
      if (m.sinReceta.isNotEmpty || m.incompletos > 0) ...[
        _SinReceta(ctx: ctx, menu: m),
        gap,
      ],
      if (m.analizados.isNotEmpty) ...[
        _Mapa(ctx: ctx, menu: m, ancho: anchoUtil),
        gap,
        _Ganancia(
          ctx: ctx,
          menu: m,
          rango: widget.rango,
          porVenta: _porVenta,
          onCambiar: (v) => setState(() => _porVenta = v),
        ),
        gap,
        _Metas(),
        if (widget.notaMoneda != null) ...[const SizedBox(height: 10), _Nota(widget.notaMoneda!)],
        const SizedBox(height: 10),
        _Nota([
          if (widget.notaPrecios.isNotEmpty) widget.notaPrecios,
          if (m.sinCostoConfiable > 0)
            '${m.sinCostoConfiable} ${m.sinCostoConfiable == 1 ? 'platillo vendido no entra' : 'platillos vendidos no entran'}: '
                'sin receta, con algún ingrediente sin precio o con la receta por revisar.',
          if (m.sinIdentificar > 0)
            m.sinIdentificar == 1
                ? '1 unidad vendida no se pudo ligar a un platillo del menú.'
                : '${m.sinIdentificar} unidades vendidas no se pudieron ligar a un platillo del menú.',
          if (widget.ventasIncompletas) 'Este período tiene más pedidos de los que se leen de una vez: las unidades salen cortas.',
        ].join(' ')),
        gap,
      ] else if (m.sinReceta.isNotEmpty || m.incompletos > 0) ...[
        aviso('Ningún platillo vendido tiene el costo completo todavía: sin eso no se puede dibujar el mapa del menú ni decir cuánto deja cada uno.'),
        gap,
      ],
    ];
  }
}

// ── Piezas sueltas ──────────────────────────────────────────────────────────

class _Tarjeta extends StatelessWidget {
  final _Ctx ctx;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borde;

  const _Tarjeta({required this.ctx, required this.child, this.padding, this.borde});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 20, vertical: ctx.telefono ? 14 : 16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
        border: borde == null ? null : Border.all(color: borde!, width: 2),
      ),
      child: child,
    );
  }
}

/// El chip de estado del diseño (`.st`): "Bien", "Alto", "Incompleto".
class _Chip extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final Color color;
  final Color fondo;

  const _Chip(this.texto, {required this.color, required this.fondo, this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 4)],
          Flexible(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w700, color))),
        ],
      ),
    );
  }
}

_Chip _chipDeSalud(Salud s, {required String bien, required String atencion, required String mal}) => switch (s) {
      Salud.bien => _Chip(bien, color: _C.gift, fondo: _C.giftTint, icono: Icons.check_rounded),
      Salud.atencion => _Chip(atencion, color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded),
      Salud.mal => _Chip(mal, color: _C.bad, fondo: _C.badTint, icono: Icons.warning_amber_rounded),
      Salud.desconocido => _Chip('Sin datos', color: _C.soft, fondo: _C.subtle),
    };

Color _colorDeSalud(Salud s) => switch (s) {
      Salud.bien => _C.gift,
      Salud.atencion => _C.warn,
      Salud.mal => _C.bad,
      Salud.desconocido => _C.soft,
    };

class _Boton extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final bool derecha;
  final VoidCallback onTap;

  const _Boton({required this.texto, required this.onTap, this.icono, this.derecha = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _C.tint,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icono != null && !derecha) ...[Icon(icono, size: 16, color: _C.accent), const SizedBox(width: 6)],
              Flexible(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13.5, FontWeight.w700, _C.accent))),
              if (icono != null && derecha) ...[const SizedBox(width: 4), Icon(icono, size: 16, color: _C.accent)],
            ],
          ),
        ),
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  final String texto;
  const _Nota(this.texto);

  @override
  Widget build(BuildContext context) {
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 15, color: _C.soft)),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: _t(12.5, FontWeight.w400, _C.soft, height: 1.4))),
        ],
      ),
    );
  }
}

/// El título de una sección (`.sec`): ícono morado, título y una nota chica.
class _Seccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? sub;
  final Widget? derecha;

  const _Seccion({required this.icono, required this.titulo, this.sub, this.derecha});

  @override
  Widget build(BuildContext context) {
    final t = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 2,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 20, color: _C.accent),
          const SizedBox(width: 10),
          Flexible(child: Text(titulo, style: _t(16, FontWeight.w700, _C.ink, height: 1.25))),
        ]),
        if (sub != null) Text(sub!, style: _t(13, FontWeight.w500, _C.muted)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: derecha == null ? t : Row(children: [Expanded(child: t), const SizedBox(width: 10), derecha!]),
    );
  }
}

/// Una barra con una marca (la meta o el punto de equilibrio) y, si se quiere, su
/// rótulo arriba. La marca va en su lugar sin medir nada: se puede usar dentro de
/// un `IntrinsicHeight`.
class _Medidor extends StatelessWidget {
  /// Cuánto se llenó (0 a 1); null deja la barra vacía.
  final double? valor;
  final Color color;
  final double? marca;
  final String? etiqueta;
  final double alto;
  final double sobresale;
  final double anchoMarca;
  final double letra;

  const _Medidor({
    required this.valor,
    required this.color,
    this.marca,
    this.etiqueta,
    this.alto = 10,
    this.sobresale = 4,
    this.anchoMarca = 2,
    this.letra = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    final arriba = etiqueta != null ? 19.0 : 0.0;
    final tope = arriba + sobresale;
    final total = tope + alto + sobresale;
    final v = (valor ?? 0).clamp(0.0, 1.0);
    final m = marca?.clamp(0.0, 1.0);

    return SizedBox(
      height: total,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: tope,
            height: alto,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: _C.subtle)),
                  if (v > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: v,
                        heightFactor: 1,
                        child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999))),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (m != null)
            Positioned(
              left: 0,
              right: 0,
              top: arriba,
              height: alto + 2 * sobresale,
              child: CustomSingleChildLayout(
                delegate: _PosX(m, acotar: false),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _C.ink, borderRadius: BorderRadius.circular(2)),
                  child: SizedBox(width: anchoMarca, height: alto + 2 * sobresale),
                ),
              ),
            ),
          if (m != null && etiqueta != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 16,
              child: CustomSingleChildLayout(
                delegate: _PosX(m, acotar: true),
                child: Text(etiqueta!, maxLines: 1, softWrap: false, style: _t(letra, FontWeight.w700, _C.muted, height: 1.3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centra al hijo en una fracción del ancho; con [acotar], sin salirse.
class _PosX extends SingleChildLayoutDelegate {
  final double fraccion;
  final bool acotar;
  const _PosX(this.fraccion, {required this.acotar});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = size.width * fraccion - childSize.width / 2;
    if (acotar) x = x.clamp(0.0, math.max(0.0, size.width - childSize.width));
    return Offset(x, 0);
  }

  @override
  bool shouldRelayout(_PosX old) => old.fraccion != fraccion || old.acotar != acotar;
}

// ── 1. ¿Ganaste? y el punto de equilibrio ───────────────────────────────────

/// "En octubre", "Hoy", "En 2026".
String _enElPeriodo(DateRange r) {
  switch (r.mode) {
    case PeriodMode.month:
      return 'En ${nombreDelMes(r.start)}';
    case PeriodMode.year:
      return 'En ${r.start.year}';
    case PeriodMode.day:
      final l = r.label;
      return l == 'Hoy' || l == 'Ayer' ? l : 'El $l';
    case PeriodMode.week:
    case PeriodMode.custom:
      return 'En este período';
  }
}

String _alPeriodo(DateRange r) => switch (r.mode) {
      PeriodMode.month => 'al mes',
      PeriodMode.year => 'al año',
      PeriodMode.day => 'en el día',
      PeriodMode.week => 'en la semana',
      PeriodMode.custom => 'en este período',
    };

class _Heroe extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final DateRange rango;
  final DateTime ahora;
  final List<String> faltan;
  final bool nombrar;

  const _Heroe({required this.ctx, required this.d, required this.rango, required this.ahora, required this.faltan, required this.nombrar});

  @override
  Widget build(BuildContext context) {
    final hayFijos = !d.sinCostosFijos;
    final u = d.operatingProfit;

    final izquierda = Padding(
      padding: EdgeInsets.all(ctx.telefono ? 18 : 22).copyWith(left: ctx.telefono ? 18 : 24, right: ctx.telefono ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hayFijos ? '${_enElPeriodo(rango)} ${u >= 0 ? 'ganaste' : 'perdiste'}' : '${_enElPeriodo(rango)} ganaste',
            style: _t(14, FontWeight.w600, _C.muted),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hayFijos ? ctx.m(u.abs()) : '¿?',
              maxLines: 1,
              style: _t(ctx.telefono ? 32 : 40, FontWeight.w800, hayFijos ? (u >= 0 ? _C.gift : _C.bad) : _C.soft, height: 1.15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hayFijos ? 'después de pagar comida y gastos' : 'Sin tus gastos fijos no sabemos si ganaste o perdiste',
            style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4),
          ),
          if (hayFijos && faltan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.warning_amber_rounded, size: 14, color: _C.warn)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    nombrar ? 'Sin contar gastos de ${faltan.join(', ')}' : 'Sin contar gastos fijos',
                    style: _t(12.5, FontWeight.w600, _C.warn, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final derecha = Padding(
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 18 : 24, vertical: ctx.telefono ? 18 : 22),
      child: hayFijos ? _Equilibrio(ctx: ctx, d: d, rango: rango, ahora: ahora) : _FaltanFijos(rango: rango),
    );

    final divisor = ctx.telefono
        ? Divider(height: 1, thickness: 1, color: _C.line)
        : VerticalDivider(width: 1, thickness: 1, color: _C.line);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)),
      child: ctx.telefono
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [izquierda, divisor, derecha])
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(flex: 10, child: izquierda), divisor, Expanded(flex: 15, child: derecha)],
              ),
            ),
    );
  }
}

/// No hay gastos fijos anotados: sin ellos no se puede decir si se ganó.
class _FaltanFijos extends StatelessWidget {
  final DateRange rango;
  const _FaltanFijos({required this.rango});

  @override
  Widget build(BuildContext context) {
    final corto = rango.mode != PeriodMode.month && rango.mode != PeriodMode.year;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.warning_amber_rounded, size: 22, color: _C.warn),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registra tus gastos fijos', style: _t(15, FontWeight.w700, _C.ink, height: 1.3)),
              const SizedBox(height: 2),
              Text(
                'Renta, sueldos, luz. Con eso te decimos cuánto necesitas vender para no perder. Anótalos desde el POS, en Gastos.',
                style: _t(14, FontWeight.w400, _C.muted, height: 1.4),
              ),
              if (corto) ...[
                const SizedBox(height: 6),
                Text(
                  'Si estás viendo un día o una semana, es normal: esos gastos se anotan una vez al mes. Prueba con el mes.',
                  style: _t(12.5, FontWeight.w400, _C.soft, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Equilibrio extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final DateRange rango;
  final DateTime ahora;

  const _Equilibrio({required this.ctx, required this.d, required this.rango, required this.ahora});

  Widget _mensaje({required bool bien, required List<InlineSpan> partes}) {
    final color = bien ? _C.gift : _C.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bien ? _C.giftTint : _C.badTint, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(bien ? Icons.check_rounded : Icons.warning_amber_rounded, size: 18, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(style: _t(14, FontWeight.w400, _C.ink, height: 1.4), children: partes))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final negrita = _t(14, FontWeight.w700, _C.ink, height: 1.4);

    // Cada venta cuesta más de lo que deja: no existe volumen que salve esto.
    if (d.pierdeConCadaVenta) {
      return _mensaje(bien: false, partes: [
        TextSpan(text: 'Cada venta te cuesta dinero. ', style: negrita),
        const TextSpan(
          text: 'Lo que gastas en comida y costos variables supera lo que cobras: vender más aumenta la pérdida. '
              'Revisa los precios del menú o el costo de los insumos.',
        ),
      ]);
    }

    final be = d.breakEven;
    if (be == null) {
      return _mensaje(bien: false, partes: [
        TextSpan(text: 'Sin ventas en el período. ', style: negrita),
        const TextSpan(text: 'Con ventas en cero no se puede medir qué parte de cada venta queda libre para pagar los costos fijos.'),
      ]);
    }

    final ok = d.netSales >= be;
    final mx = math.max(be, d.netSales) * 1.08;
    final enCurso = !ahora.isBefore(rango.start) && !ahora.isAfter(rango.end);
    final dia = ok ? diaDeEquilibrio(d, rango, ahora) : null;
    final cm = d.contributionMarginPct ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('¿Cuánto necesitas vender para no perder?', style: _t(15, FontWeight.w700, _C.ink, height: 1.3)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: _t(14.5, FontWeight.w400, _C.muted),
            children: [
              TextSpan(text: ctx.m0(be), style: _t(18, FontWeight.w800, _C.ink)),
              TextSpan(text: ' ${_alPeriodo(rango)}'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _Medidor(
          valor: mx > 0 ? d.netSales / mx : 0,
          color: ok ? _C.gift : _C.bad,
          marca: mx > 0 ? be / mx : 0,
          etiqueta: 'Para no perder',
          alto: 14,
          sobresale: 6,
          anchoMarca: 3,
          letra: 11.5,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(ctx.m0(0), style: _t(12.5, FontWeight.w400, _C.muted)),
            const SizedBox(width: 12),
            // Con montos grandes o letra grande, "Vendiste …" se achica en vez de
            // salirse de la tarjeta.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text.rich(
                  TextSpan(
                    style: _t(12.5, FontWeight.w400, _C.muted),
                    children: [const TextSpan(text: 'Vendiste '), TextSpan(text: ctx.m0(d.netSales), style: _t(12.5, FontWeight.w700, _C.ink))],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (ok)
          _mensaje(bien: true, partes: dia != null
              ? [
                  const TextSpan(text: 'Cubriste tus gastos alrededor del '),
                  TextSpan(text: 'día $dia de ${nombreDelMes(rango.start)}', style: negrita),
                  const TextSpan(text: '. Lo que vendiste después fue ganancia.'),
                ]
              : [
                  const TextSpan(text: 'Ya cubriste tus gastos. Desde aquí, de cada '),
                  TextSpan(text: '${ctx.signo}100', style: negrita),
                  const TextSpan(text: ' que vendas te quedan '),
                  TextSpan(text: '${ctx.signo}${cm.toStringAsFixed(0)}', style: negrita),
                  const TextSpan(text: ' de ganancia.'),
                ])
        else
          _mensaje(bien: false, partes: [
            TextSpan(text: enCurso ? 'Te faltan ' : 'Te faltaron '),
            TextSpan(text: ctx.m0(be - d.netSales), style: negrita),
            const TextSpan(text: ' para no perder.'),
          ]),
      ],
    );
  }
}

// ── 2. Los tres indicadores ─────────────────────────────────────────────────

class _Indicadores extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final bool hayFijos;
  final List<String> faltan;

  const _Indicadores({required this.ctx, required this.d, required this.hayFijos, required this.faltan});

  @override
  Widget build(BuildContext context) {
    // Costo de comida
    final cp = d.foodCostPct;
    final Widget chipComida;
    final Color colorComida;
    if (d.itemsTotales > 0 && (d.coberturaCosto ?? 0) < 90) {
      chipComida = _Chip('Incompleto', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded);
      colorComida = _C.warn;
    } else if (d.itemsTotales > 0 && d.costoMayormenteEstimado) {
      chipComida = _Chip('Estimado', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded);
      colorComida = _C.warn;
    } else {
      final s = evaluarFoodCost(cp);
      chipComida = _chipDeSalud(s, bien: 'Bien', atencion: 'Atención', mal: 'Alto');
      colorComida = _colorDeSalud(s);
    }

    // Costo primo
    final pp = d.primeCostPct;
    final Widget chipPrimo;
    final Color colorPrimo;
    if (d.payroll <= 0 || faltan.isNotEmpty) {
      chipPrimo = _Chip('Faltan sueldos', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded);
      colorPrimo = _C.warn;
    } else {
      final s = evaluarPrimeCost(pp);
      chipPrimo = _chipDeSalud(s, bien: 'Bien', atencion: 'Atención', mal: 'Alto');
      colorPrimo = _colorDeSalud(s);
    }

    // Margen
    final mg = d.marginPct;
    final Widget chipMargen;
    final Color colorMargen;
    if (!hayFijos) {
      chipMargen = _Chip('No es real aún', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded);
      colorMargen = _C.warn;
    } else if (faltan.isNotEmpty) {
      chipMargen = _Chip('Parcial', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded);
      colorMargen = _C.warn;
    } else {
      final s = evaluarMargen(mg);
      chipMargen = _chipDeSalud(s, bien: 'Sano', atencion: 'Atención', mal: 'Bajo');
      colorMargen = _colorDeSalud(s);
    }

    final comida = _Indicador(
      ctx: ctx,
      titulo: 'Costo de comida',
      chip: chipComida,
      valor: _p(cp),
      lleno: cp == null ? null : cp / 100,
      color: colorComida,
      meta: 0.35,
      etiquetaMeta: '35%',
      sub: 'Meta: menos de 35%',
    );
    final primo = _Indicador(
      ctx: ctx,
      titulo: 'Costo primo',
      chip: chipPrimo,
      valor: _p(pp),
      lleno: pp == null ? null : pp / 100,
      color: colorPrimo,
      meta: 0.65,
      etiquetaMeta: '65%',
      sub: 'Comida + sueldos · Meta: menos de 65%',
    );
    final margen = _Indicador(
      ctx: ctx,
      titulo: 'Margen',
      chip: chipMargen,
      valor: _p(mg),
      lleno: mg == null ? null : math.max(0.0, mg) / 100,
      color: colorMargen,
      meta: 0.10,
      etiquetaMeta: '10%',
      sub: 'Lo que queda de cada venta · sano: más de 10%',
    );

    if (ctx.telefono) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: comida), const SizedBox(width: 12), Expanded(child: primo)],
            ),
          ),
          const SizedBox(height: 12),
          margen,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: comida),
          const SizedBox(width: 12),
          Expanded(child: primo),
          const SizedBox(width: 12),
          Expanded(child: margen),
        ],
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  final _Ctx ctx;
  final String titulo;
  final Widget chip;
  final String valor;
  final double? lleno;
  final Color color;
  final double meta;
  final String etiquetaMeta;
  final String sub;

  const _Indicador({
    required this.ctx,
    required this.titulo,
    required this.chip,
    required this.valor,
    required this.lleno,
    required this.color,
    required this.meta,
    required this.etiquetaMeta,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return _Tarjeta(
      ctx: ctx,
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 20, vertical: ctx.telefono ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(titulo, style: _t(14, FontWeight.w600, _C.muted)),
              chip,
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, maxLines: 1, style: _t(ctx.telefono ? 26 : 32, FontWeight.w800, _C.ink, height: 1.15)),
          ),
          const SizedBox(height: 4),
          _Medidor(valor: lleno, color: color, marca: meta, etiqueta: etiquetaMeta),
          const SizedBox(height: 6),
          Text(sub, style: _t(12.5, FontWeight.w400, _C.muted, height: 1.4)),
        ],
      ),
    );
  }
}

// ── 3. El estado de resultados ──────────────────────────────────────────────

class _Cascada extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final List<String> faltan;
  final bool hayFijos;
  final bool nombrar;
  final VoidCallback onIrAGastos;

  const _Cascada({
    required this.ctx,
    required this.d,
    required this.faltan,
    required this.hayFijos,
    required this.nombrar,
    required this.onIrAGastos,
  });

  @override
  Widget build(BuildContext context) {
    final v = d.netSales;
    double? frac(double x) => v > 0 ? (x / v).clamp(0.0, 1.0) : null;
    final u = d.operatingProfit;
    final faltaAlgo = faltan.isNotEmpty || !hayFijos;

    final filas = <Widget>[
      _FilaResultado(
        ctx: ctx,
        nombre: 'Ventas netas',
        nota: 'Sin propinas ni envíos',
        monto: ctx.m(v),
        pct: v > 0 ? '100%' : '—',
        barra: frac(v),
        colorBarra: _C.accent,
        primera: true,
      ),
      _FilaResultado(
        ctx: ctx,
        nombre: '− Costo de lo vendido',
        monto: ctx.m(-d.cogs),
        pct: _p(d.foodCostPct),
        tipo: _TipoFila.resta,
      ),
      _FilaResultado(
        ctx: ctx,
        nombre: 'Utilidad bruta',
        monto: ctx.m(d.grossProfit),
        pct: _p(d.pct(d.grossProfit)),
        barra: frac(d.grossProfit),
        colorBarra: _C.soft,
      ),
      for (final e in d.expenses)
        _FilaResultado(
          ctx: ctx,
          nombre: '− ${e.label}',
          monto: ctx.m(e.amount == 0 ? 0.0 : -e.amount),
          pct: _p(d.pct(e.amount)),
          tipo: _TipoFila.resta,
        ),
      if (d.expenses.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 0, 8),
          child: Text('Sin gastos registrados en el período', style: _t(13, FontWeight.w400, _C.soft)),
        ),
      if (faltaAlgo)
        _FaltanGastos(
          texto: nombrar && faltan.isNotEmpty ? 'Faltan gastos fijos de ${faltan.join(', ')}' : 'Faltan gastos fijos',
          ctx: ctx,
          onIrAGastos: onIrAGastos,
        ),
      _FilaResultado(
        ctx: ctx,
        nombre: 'Utilidad operativa',
        monto: ctx.m(u),
        pct: _p(d.marginPct),
        barra: frac(u > 0 ? u : 0),
        colorBarra: _C.gift,
        tipo: _TipoFila.total,
        negativa: u < 0,
      ),
    ];

    return _Tarjeta(
      ctx: ctx,
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 22, vertical: ctx.telefono ? 4 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filas),
    );
  }
}

enum _TipoFila { normal, resta, total }

class _FilaResultado extends StatelessWidget {
  final _Ctx ctx;
  final String nombre;
  final String? nota;
  final String monto;
  final String pct;
  final double? barra;
  final Color? _colorBarra;
  Color get colorBarra => _colorBarra ?? _C.accent;
  final _TipoFila tipo;
  final bool primera;
  final bool negativa;

  const _FilaResultado({
    required this.ctx,
    required this.nombre,
    required this.monto,
    required this.pct,
    this.nota,
    this.barra,
    Color? colorBarra,
    this.tipo = _TipoFila.normal,
    this.primera = false,
    this.negativa = false,
  }) : _colorBarra = colorBarra;

  @override
  Widget build(BuildContext context) {
    final resta = tipo == _TipoFila.resta;
    final total = tipo == _TipoFila.total;
    final colorMonto = resta ? _exp : (total ? (negativa ? _C.bad : _C.gift) : _C.ink);

    final fila = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: resta ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: resta
                      ? _t(14, FontWeight.w500, _C.muted, height: 1.3)
                      : _t(total ? 16 : 15, total ? FontWeight.w700 : FontWeight.w600, _C.ink, height: 1.3),
                ),
                if (nota != null) Text(nota!, style: _t(12.5, FontWeight.w500, _C.muted, height: 1.3)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ctx.telefono ? 150 : 220),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              monto,
              maxLines: 1,
              style: resta
                  ? _t(14.5, FontWeight.w600, colorMonto)
                  : _t(total ? 20 : 16, total ? FontWeight.w800 : FontWeight.w700, colorMonto),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: ctx.telefono ? 44 : 56, child: Text(pct, textAlign: TextAlign.right, style: _t(13, FontWeight.w600, _C.muted))),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(vertical: resta ? 7 : 12),
      decoration: BoxDecoration(border: primera || resta ? null : Border(top: BorderSide(color: _C.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fila,
          if (barra != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: _C.subtle)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: barra!,
                        heightFactor: 1,
                        child: DecoratedBox(decoration: BoxDecoration(color: colorBarra, borderRadius: BorderRadius.circular(999))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FaltanGastos extends StatelessWidget {
  final String texto;
  final _Ctx ctx;
  final VoidCallback onIrAGastos;

  const _FaltanGastos({required this.texto, required this.ctx, required this.onIrAGastos});

  @override
  Widget build(BuildContext context) {
    final aviso = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.warning_amber_rounded, size: 18, color: _C.warn),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(texto, style: _t(14, FontWeight.w700, _C.warn, height: 1.3)),
              Text(
                'Renta, sueldos, luz, seguros. Sin ellos la utilidad sale más alta de lo real.',
                style: _t(13, FontWeight.w400, _C.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
    final boton = _Boton(texto: 'Ir a Gastos', icono: Icons.chevron_right_rounded, derecha: true, onTap: onIrAGastos);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
      child: ctx.telefono
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [aviso, const SizedBox(height: 10), boton])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: aviso), const SizedBox(width: 12), boton]),
    );
  }
}

// ── 4. ¿Qué sucursal gana más? ──────────────────────────────────────────────

class _Sucursales extends StatelessWidget {
  final _Ctx ctx;
  final ComparacionSucursales comparacion;
  final double ancho;

  const _Sucursales({required this.ctx, required this.comparacion, required this.ancho});

  @override
  Widget build(BuildContext context) {
    final filas = comparacion.filas;
    final tarjetas = [for (final f in filas) _TarjetaSucursal(ctx: ctx, s: f, mejor: identical(f, comparacion.mejor))];

    final Widget grilla;
    if (ancho <= 900) {
      grilla = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tarjetas.length; i++) ...[if (i > 0) const SizedBox(height: 12), tarjetas[i]],
      ]);
    } else {
      final porFila = math.min(3, tarjetas.length);
      final hileras = <Widget>[];
      for (var i = 0; i < tarjetas.length; i += porFila) {
        final tramo = tarjetas.sublist(i, math.min(i + porFila, tarjetas.length));
        hileras.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < porFila; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(child: j < tramo.length ? tramo[j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ));
      }
      grilla = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < hileras.length; i++) ...[if (i > 0) const SizedBox(height: 12), hileras[i]],
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Seccion(icono: Icons.storefront_outlined, titulo: '¿Qué sucursal gana más?'),
        const SizedBox(height: 10),
        grilla,
        // "Todas" también suma lo de sucursales ocultas o sin sucursal: sin esta
        // nota, las tarjetas no cuadran con el total y no se sabe por qué.
        if (comparacion.ventasFuera.abs() >= 1) ...[
          const SizedBox(height: 10),
          _Nota('En "Todas" también entran ${ctx.m0(comparacion.ventasFuera)} vendidos en sucursales ocultas o sin sucursal: no aparecen en estas tarjetas.'),
        ],
      ],
    );
  }
}

class _TarjetaSucursal extends StatelessWidget {
  final _Ctx ctx;
  final SucursalRentabilidad s;
  final bool mejor;

  const _TarjetaSucursal({required this.ctx, required this.s, required this.mejor});

  Widget _fila(String etiqueta, String valor, {Color? color}) => Container(
        padding: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: _t(13.5, FontWeight.w400, _C.muted))),
            const SizedBox(width: 8),
            Text(valor, style: _t(13.5, FontWeight.w700, color ?? _C.ink)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = s.utilidad;
    final Widget grande;
    if (s.sinMovimiento) {
      grande = Text('Sin movimiento en el período', style: _t(16, FontWeight.w600, _C.soft, height: 1.3));
    } else if (!s.conGastosFijos) {
      grande = Text('Sin gastos fijos · no se sabe', style: _t(16, FontWeight.w600, _C.soft, height: 1.3));
    } else {
      grande = Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 6,
        children: [
          Text(ctx.m0(u), style: _t(24, FontWeight.w800, u >= 0 ? _C.gift : _C.bad, height: 1.2)),
          Text('${_p(s.margen)} margen', style: _t(13, FontWeight.w600, _C.muted)),
        ],
      );
    }

    final costo = s.costoPct;
    return _Tarjeta(
      ctx: ctx,
      borde: mejor ? _C.gift : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15.5, FontWeight.w700, _C.ink))),
              if (mejor) ...[
                const SizedBox(width: 8),
                _Chip('Más margen', color: _C.gift, fondo: _C.giftTint, icono: Icons.star_rounded),
              ] else if (!s.costoConfiable && !s.sinMovimiento) ...[
                // Sin el costo de comida cargado el margen se ve mejor de lo que es.
                const SizedBox(width: 8),
                _Chip('Costo incompleto', color: _C.warn, fondo: _C.warnTint, icono: Icons.warning_amber_rounded),
              ],
            ],
          ),
          const SizedBox(height: 8),
          grande,
          const SizedBox(height: 8),
          _fila('Vendió', ctx.m0(s.ventas)),
          const SizedBox(height: 8),
          _fila('Costo de comida', _p(costo), color: !s.costoConfiable && !s.sinMovimiento ? _C.warn : (costo != null && costo >= 35 ? _C.bad : null)),
          const SizedBox(height: 8),
          _fila('Gastos', s.gastos > 0 ? ctx.m0(s.gastos) : '—'),
        ],
      ),
    );
  }
}

// ── 5. Completa estas recetas primero ───────────────────────────────────────

class _SinReceta extends StatelessWidget {
  final _Ctx ctx;
  final AnalisisMenu menu;

  const _SinReceta({required this.ctx, required this.menu});

  @override
  Widget build(BuildContext context) {
    final lista = menu.sinReceta.take(5).toList();
    final n = menu.sinReceta.length;
    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Completa estas recetas primero', style: _t(15, FontWeight.w700, _C.ink, height: 1.3)),
              if (n > 0) _Chip('$n sin receta', color: _C.warn, fondo: _C.warnTint),
            ],
          ),
          const SizedBox(height: 6),
          if (n > 0)
            Text.rich(
              TextSpan(
                style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4),
                children: [
                  const TextSpan(text: 'Son los productos '),
                  TextSpan(text: 'sin receta que más vendes', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.4)),
                  TextSpan(text: '. Mientras no tengan, su costo cuenta como ${ctx.signo}0. Arma la receta desde el POS, en Recetas.'),
                ],
              ),
            ),
          if (menu.incompletos > 0) ...[
            const SizedBox(height: 6),
            Text(
              menu.incompletos == 1
                  ? 'Otro platillo vendido tiene receta, pero a algún ingrediente le falta el precio de compra.'
                  : 'Otros ${menu.incompletos} platillos vendidos tienen receta, pero a algún ingrediente le falta el precio de compra.',
              style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4),
            ),
          ],
          const SizedBox(height: 6),
          for (var i = 0; i < lista.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: _C.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lista[i].nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w600, _C.ink, height: 1.3)),
                        Text(
                          '${lista[i].presentacion != null ? '${lista[i].presentacion} · ' : ''}${_entero.format(lista[i].cantidad)} vendidos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(12.5, FontWeight.w500, _C.muted, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(ctx.m0(lista[i].ventas), style: _t(14, FontWeight.w700, _C.ink, height: 1.3)),
                      Text('en ventas', style: _t(12, FontWeight.w500, _C.muted, height: 1.3)),
                    ],
                  ),
                ],
              ),
            ),
          if (n > lista.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('y ${n - lista.length} más', style: _t(12.5, FontWeight.w500, _C.muted)),
            ),
        ],
      ),
    );
  }
}

// ── 6. Mapa de tu menú ──────────────────────────────────────────────────────

class _Mapa extends StatelessWidget {
  final _Ctx ctx;
  final AnalisisMenu menu;
  final double ancho;

  const _Mapa({required this.ctx, required this.menu, required this.ancho});

  @override
  Widget build(BuildContext context) {
    final mapa = menu.mapa;
    // El orden del diseño: arriba lo que gana mucho; abajo, lo que gana poco.
    const orden = [Cuadrante.rompecabezas, Cuadrante.estrella, Cuadrante.perro, Cuadrante.caballo];
    final tarjetas = [for (final c in orden) _Cuadro(ctx: ctx, c: c, platillos: mapa[c]!)];

    final Widget grilla;
    if (ancho <= kInicioQuiebreTelefono) {
      grilla = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tarjetas.length; i++) ...[if (i > 0) const SizedBox(height: 12), tarjetas[i]],
      ]);
    } else {
      Widget par(Widget a, Widget b) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
            ),
          );
      grilla = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        par(tarjetas[0], tarjetas[1]),
        const SizedBox(height: 12),
        par(tarjetas[2], tarjetas[3]),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Seccion(icono: Icons.grid_view_rounded, titulo: 'Mapa de tu menú', sub: '¿qué hacer con cada platillo?'),
        if (ancho > kInicioQuiebreTelefono)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              // Íconos y no "↑" ni "→": Poppins no trae esas flechas.
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_upward_rounded, size: 14, color: _C.muted),
                  const SizedBox(width: 4),
                  Text('Gana más por venta', style: _t(12, FontWeight.w400, _C.muted)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Se vende más', style: _t(12, FontWeight.w400, _C.muted)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: _C.muted),
                ]),
              ],
            ),
          ),
        const SizedBox(height: 10),
        grilla,
      ],
    );
  }
}

class _Cuadro extends StatelessWidget {
  final _Ctx ctx;
  final Cuadrante c;
  final List<PlatilloVendido> platillos;

  const _Cuadro({required this.ctx, required this.c, required this.platillos});

  static const _maxChips = 15;

  @override
  Widget build(BuildContext context) {
    final (icono, titulo, accion, color, fondo) = switch (c) {
      Cuadrante.estrella => (Icons.star_rounded, 'Gana mucho, se vende mucho', 'Cuídalo: no le cambies nada', _C.gift, _C.giftTint),
      Cuadrante.caballo => (Icons.price_change_rounded, 'Gana poco, se vende mucho', 'Súbele el precio o baja su costo', _C.warn, _C.warnTint),
      Cuadrante.rompecabezas => (Icons.extension_rounded, 'Gana mucho, se vende poco', 'Promociónalo o ponlo más visible', _C.don, _C.donTint),
      Cuadrante.perro => (Icons.pets_rounded, 'Gana poco, se vende poco', 'Considera quitarlo del menú', _C.bad, _C.badTint),
    };
    final n = platillos.length;
    final visibles = platillos.take(_maxChips).toList();

    Widget chip(Widget hijo) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(999)),
          child: hijo,
        );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 18, vertical: ctx.telefono ? 14 : 16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
        border: Border(top: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(11)),
                child: Icon(icono, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: _t(15.5, FontWeight.w700, _C.ink, height: 1.25)),
                    Text('$n ${n == 1 ? 'producto' : 'productos'}', style: _t(12.5, FontWeight.w400, _C.muted, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
              child: Text(accion, style: _t(13.5, FontWeight.w700, color, height: 1.3)),
            ),
          ),
          const SizedBox(height: 8),
          if (n == 0)
            Text('Ninguno', style: _t(13, FontWeight.w600, _C.muted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in visibles)
                  chip(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w600, _C.ink))),
                      const SizedBox(width: 4),
                      Text(_entero.format(p.cantidad), style: _t(12, FontWeight.w500, _C.muted)),
                    ],
                  )),
                if (n > visibles.length) chip(Text('+${n - visibles.length} más', style: _t(13, FontWeight.w600, _C.muted))),
              ],
            ),
        ],
      ),
    );
  }
}

// ── 7. Ganancia por platillo ────────────────────────────────────────────────

class _Ganancia extends StatelessWidget {
  final _Ctx ctx;
  final AnalisisMenu menu;
  final DateRange rango;
  final bool porVenta;
  final ValueChanged<bool> onCambiar;

  const _Ganancia({required this.ctx, required this.menu, required this.rango, required this.porVenta, required this.onCambiar});

  @override
  Widget build(BuildContext context) {
    final total = rango.mode == PeriodMode.month ? 'Total del mes' : 'Total del período';
    final seg = _Segmentos(
      opciones: [(false, total), (true, 'Por venta')],
      elegido: porVenta,
      onElegir: onCambiar,
      completo: ctx.telefono,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ctx.telefono
            ? const _Seccion(icono: Icons.restaurant_rounded, titulo: 'Ganancia por platillo')
            : _Seccion(icono: Icons.restaurant_rounded, titulo: 'Ganancia por platillo', derecha: seg),
        if (ctx.telefono) ...[const SizedBox(height: 10), seg],
        const SizedBox(height: 10),
        if (!porVenta) _GananciaTotal(ctx: ctx, menu: menu) else _GananciaPorVenta(ctx: ctx, menu: menu),
      ],
    );
  }
}

/// El interruptor del diseño (`.seg`): la opción elegida va en tinta sobre la tarjeta.
class _Segmentos extends StatelessWidget {
  final List<(bool, String)> opciones;
  final bool elegido;
  final ValueChanged<bool> onElegir;
  final bool completo;

  const _Segmentos({required this.opciones, required this.elegido, required this.onElegir, required this.completo});

  @override
  Widget build(BuildContext context) {
    Widget boton((bool, String) o) {
      final activa = o.$1 == elegido;
      return GestureDetector(
        onTap: () => onElegir(o.$1),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: activa ? _C.ink : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Text(
            o.$2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _t(13.5, FontWeight.w600, activa ? _C.card : _C.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
      child: completo
          ? Row(children: [for (final o in opciones) Expanded(child: boton(o))])
          : Row(mainAxisSize: MainAxisSize.min, children: [for (final o in opciones) boton(o)]),
    );
  }
}

class _NombrePlatillo extends StatelessWidget {
  final PlatilloVendido p;
  const _NombrePlatillo(this.p);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: _t(14.5, FontWeight.w600, _C.ink, height: 1.3),
        children: [
          TextSpan(text: p.nombre),
          if (p.presentacion != null) TextSpan(text: '  ${p.presentacion}', style: _t(12.5, FontWeight.w500, _C.muted)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _GananciaTotal extends StatelessWidget {
  final _Ctx ctx;
  final AnalisisMenu menu;
  const _GananciaTotal({required this.ctx, required this.menu});

  @override
  Widget build(BuildContext context) {
    final lista = menu.masGanancia(8);
    final mayor = lista.fold<double>(0, (a, p) => math.max(a, p.gananciaTotal));

    return _Tarjeta(
      ctx: ctx,
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 20, vertical: ctx.telefono ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lista.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: _C.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(width: 24, child: Text('${i + 1}', style: _t(13, FontWeight.w800, _C.soft))),
                      const SizedBox(width: 12),
                      Expanded(child: _NombrePlatillo(lista[i])),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: ctx.telefono ? 130 : 200),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            ctx.m0(lista[i].gananciaTotal),
                            maxLines: 1,
                            style: _t(15, FontWeight.w800, lista[i].gananciaTotal >= 0 ? _C.gift : _C.bad),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const SizedBox(width: 36),
                      Expanded(
                        child: _Medidor(
                          valor: mayor > 0 ? math.max(0.0, lista[i].gananciaTotal) / mayor : 0,
                          color: _C.gift,
                          alto: 7,
                          sobresale: 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: ctx.telefono ? 130 : 200),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${_entero.format(lista[i].cantidad)} × ${ctx.m(lista[i].gananciaPorVenta)}',
                            maxLines: 1,
                            style: _t(12, FontWeight.w400, _C.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GananciaPorVenta extends StatelessWidget {
  final _Ctx ctx;
  final AnalisisMenu menu;
  const _GananciaPorVenta({required this.ctx, required this.menu});

  @override
  Widget build(BuildContext context) {
    final r = menu.porVenta();
    final revisa = _Bloque(ctx: ctx, color: _C.bad, titulo: 'Revisa su precio', sub: 'más arriba de su meta', lista: r.revisa, vacio: 'Ninguno pasa su meta');
    final mas = _Bloque(ctx: ctx, color: _C.gift, titulo: 'Más ganancia', sub: 'más abajo de su meta', lista: r.mas, vacio: 'Ninguno queda bajo su meta');

    if (ctx.telefono) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [revisa, const SizedBox(height: 14), mas]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: revisa), const SizedBox(width: 14), Expanded(child: mas)],
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  final _Ctx ctx;
  final Color color;
  final String titulo;
  final String sub;
  final List<PlatilloVendido> lista;
  final String vacio;

  const _Bloque({required this.ctx, required this.color, required this.titulo, required this.sub, required this.lista, required this.vacio});

  @override
  Widget build(BuildContext context) {
    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(child: Text(titulo, style: _t(15, FontWeight.w700, _C.ink, height: 1.3))),
              ]),
              Text(sub, style: _t(12.5, FontWeight.w500, _C.muted)),
            ],
          ),
          const SizedBox(height: 6),
          if (lista.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(vacio, style: _t(13.5, FontWeight.w400, _C.muted)))
          else
            for (var i = 0; i < lista.length; i++) _FilaPorVenta(ctx: ctx, p: lista[i], primera: i == 0),
        ],
      ),
    );
  }
}

class _FilaPorVenta extends StatelessWidget {
  final _Ctx ctx;
  final PlatilloVendido p;
  final bool primera;

  const _FilaPorVenta({required this.ctx, required this.p, required this.primera});

  @override
  Widget build(BuildContext context) {
    final mala = p.sobreLaMeta > 0;
    final color = mala ? _C.bad : _C.gift;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _NombrePlatillo(p)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: ctx.telefono ? 120 : 180),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(ctx.m(p.gananciaPorVenta), maxLines: 1, style: _t(15, FontWeight.w800, color)),
                    ),
                  ),
                  Text('por venta', style: _t(11.5, FontWeight.w500, _C.muted, height: 1.2)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // Con letra grande el rótulo se achica en vez de empujar la barra fuera.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(999)),
                    child: Text(p.meta.etiqueta, maxLines: 1, style: _t(11, FontWeight.w700, _C.muted)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Medidor(
                  valor: p.recetaPct / 100,
                  color: color.withValues(alpha: 0.85),
                  marca: p.meta.pct / 100,
                  alto: 7,
                  sobresale: 3,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text('${p.recetaPct.round()}%', maxLines: 1, textAlign: TextAlign.right, style: _t(12.5, FontWeight.w700, color)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metas extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget meta(String texto, MetaReceta m) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
          child: Text.rich(TextSpan(
            style: _t(12.5, FontWeight.w600, _C.muted),
            children: [TextSpan(text: '$texto '), TextSpan(text: '${m.pct.round()}%', style: _t(12.5, FontWeight.w700, _C.ink))],
          )),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Meta de receta:', style: _t(12.5, FontWeight.w400, _C.muted)),
          meta('Comida', MetaReceta.comida),
          meta('Bebida preparada', MetaReceta.bebida),
          meta('Reventa', MetaReceta.reventa),
        ],
      ),
    );
  }
}

// ── Lo que no estaba en el diseño pero hay que seguir diciendo ──────────────

/// Un aviso en ámbar con un título y párrafos (la preproducción, la cobertura del
/// costo).
class _AvisoAmbar extends StatelessWidget {
  final String titulo;
  final List<String> parrafos;
  const _AvisoAmbar({required this.titulo, required this.parrafos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: _C.warn),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: _t(14, FontWeight.w700, _C.warn, height: 1.3)),
                for (final p in parrafos) ...[
                  const SizedBox(height: 4),
                  Text(p, style: _t(13, FontWeight.w400, _C.ink, height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Parte de lo vendido no tiene costo cargado. Callarlo sería peor que no mostrar
/// el margen: un costo bajo por falta de datos se ve idéntico a un costo bajo por
/// buena gestión.
class _AvisoCobertura extends StatelessWidget {
  final ProfitabilityData d;
  const _AvisoCobertura({required this.d});

  @override
  Widget build(BuildContext context) {
    final estimado = d.costoMayormenteEstimado;
    return _AvisoAmbar(
      titulo: estimado ? 'El costo es una estimación' : 'Tu ganancia real puede ser menor',
      parrafos: [
        estimado
            // Caso típico al mirar meses anteriores: el POS no guardó el costo de
            // esas ventas, así que se valorizan con el precio de compra de hoy.
            ? '${_p(d.porcentajeEstimado)} del costo se calculó con los precios de compra de hoy, porque esas ventas no '
                'guardaron el costo del momento. Sirve para orientarte, pero si los precios cambiaron desde entonces, '
                'el margen real es distinto.'
            : 'Solo ${_p(d.coberturaCosto)} de lo que vendiste tiene costo. Los ingredientes sin precio de compra cuentan '
                'como costo cero, así que el margen sale optimista.',
        if (d.itemsSinCosto > 0 && estimado) 'Otro ${_p(100 - (d.coberturaCosto ?? 0))} no tiene ni precio actual: esos cuentan como cero.',
      ],
    );
  }
}

/// Lo que NO entra en la cascada, y por qué.
class _FueraDeLaCuenta extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  const _FueraDeLaCuenta({required this.ctx, required this.d});

  Widget _dato(String etiqueta, double monto, String nota, {bool destacar = false, bool primero = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: primero ? null : Border(top: BorderSide(color: _C.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: _t(14, FontWeight.w600, _C.ink, height: 1.3)),
                  Text(nota, style: _t(12.5, FontWeight.w400, _C.muted, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: ctx.telefono ? 130 : 200),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(ctx.m(monto), maxLines: 1, style: _t(destacar ? 16 : 14.5, destacar ? FontWeight.w800 : FontWeight.w700, destacar ? _C.accent : _C.ink)),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final datos = <Widget>[];
    void agrega(String e, double m, String n, {bool destacar = false}) =>
        datos.add(_dato(e, m, n, destacar: destacar, primero: datos.isEmpty));

    // Ya está sumado arriba, en los gastos. Se muestra solo para saber cuánto de la
    // operación se está pagando con el efectivo de la caja.
    if (d.paidFromCash > 0) agrega('Pagado en efectivo desde caja', d.paidFromCash, 'Ya contado arriba en los gastos');
    // Entra arriba, en el costo de lo vendido, al venderse el preparado.
    if (d.cargadoPreproduccion > 0) agrega('Cargado a la preproducción', d.cargadoPreproduccion, _notaPreproduccion(ctx, d));
    agrega(
      'Invertido en compras',
      d.purchases,
      d.entradasSinCosto > 0
          ? 'Mercadería que entró a la despensa · ${d.entradasSinCosto} entrada(s) sin costo quedan fuera'
          : 'Mercadería que entró a la despensa; el gasto se cuenta al vender',
    );
    agrega(
      'Valor de tu despensa hoy',
      d.inventoryValue,
      d.rotacion != null ? 'Se renovó ${d.rotacion!.toStringAsFixed(1)} veces en el período' : 'A precio de compra',
      destacar: true,
    );

    Widget aviso(String t) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(t, style: _t(12.5, FontWeight.w500, _C.warn, height: 1.4)));

    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fuera de la cuenta', style: _t(15, FontWeight.w700, _C.ink, height: 1.3)),
          const SizedBox(height: 4),
          ...datos,
          if (d.ingredientesSinPrecio > 0)
            aviso('${d.ingredientesSinPrecio} ingrediente(s) con stock pero sin precio de compra: no suman al valor.'),
          // El valor de arriba puede salir disparado por existencias que nadie pudo
          // haber comprado: se dice de dónde viene y cuáles revisar.
          if (d.existenciasImposibles.isNotEmpty) aviso(_avisoExistencias(d.existenciasImposibles)),
        ],
      ),
    );
  }
}

/// Si no todo lo cargado se pudo restar, lo dice y manda al aviso que explica en qué
/// categoría quedó la diferencia.
String _notaPreproduccion(_Ctx ctx, ProfitabilityData d) {
  if (d.restadoPreproduccion >= d.cargadoPreproduccion) {
    return 'Gas, luz o mano de obra que tus recetas suman al preparado. Entra al costo de lo vendido al venderse, '
        'por eso se restó de esos gastos';
  }
  if (d.restadoPreproduccion > 0) {
    return 'Entra al costo de lo vendido al venderse el preparado. De tus gastos se restaron '
        '${ctx.m(d.restadoPreproduccion)}: ver el aviso de arriba';
  }
  return 'Entra al costo de lo vendido al venderse el preparado, pero en Gastos no había de dónde restarlo: '
      'ver el aviso de arriba';
}

/// Nombra los ingredientes mal digitados en vez de decir solo cuántos son.
String _avisoExistencias(List<String> nombres) {
  final muestra = nombres.take(3).join(', ');
  final resto = nombres.length - 3;
  final lista = resto > 0 ? '$muestra y $resto más' : muestra;
  if (nombres.length == 1) {
    return 'Ojo: $lista tiene una cantidad imposible en Despensa y por eso este valor sale tan alto. '
        'Revisa cuánto tienes de verdad.';
  }
  return 'Ojo: ${nombres.length} ingredientes tienen una cantidad imposible en Despensa y por eso este valor sale '
      'tan alto ($lista). Revisa cuánto tienes de verdad.';
}

/// El acceso a la lista completa de utilidad por platillo (con los gastos repartidos),
/// que sigue viviendo en su propia pantalla.
class _VerUtilidad extends StatelessWidget {
  final VoidCallback onTap;
  const _VerUtilidad({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InicioToque(
      onTap: onTap,
      radio: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 20, color: _C.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Utilidad por platillo', style: _t(14.5, FontWeight.w700, _C.ink, height: 1.3)),
                  Text('Lo que deja cada platillo después de repartirle los gastos', style: _t(12.5, FontWeight.w400, _C.muted, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 22, color: _C.muted),
          ],
        ),
      ),
    );
  }
}
