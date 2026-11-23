/// Compras vs Ventas. Rediseño 2026-11-22 (`compras-ventas.html` de saborpro_app, en
/// su modo oscuro): cuánto se ganó con la mercadería, qué pasó con la bodega, cómo
/// le fue a cada sucursal, en qué se compró y cuánto se ganó con cada cosa, y la
/// semana por semana.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa los
/// números ya armados. Se prueba a 360dp en
/// test/presentation/widgets/compras_ventas_view_test.dart.
///
/// OJO: los pares de tarjetas van en un `IntrinsicHeight` (misma altura): nada de lo
/// que llevan dentro puede usar `LayoutBuilder`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/date_range.dart';
import '../../data/models/compras_ventas.dart';
import '../../data/models/profitability_data.dart';
import '../../data/models/rentabilidad_data.dart' show nombreDelMes;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El color de "compra" del diseño (`--exp`) y su fondo suave.
Color get _exp => _C.exp;

final _entero = NumberFormat('#,##0', 'en_US');

/// Lo que se sabe de la bodega del período, y por qué a veces no se sabe.
enum DatoBodega {
  /// Hay con qué decir cuánto había, cuánto se compró, cuánto se usó y cuánto queda.
  completo,

  /// Solo se sabe cuánto queda (de hoy o de la foto del cierre).
  soloFin,

  /// Es un mes, pero el servidor todavía no guardó la foto de ese mes.
  sinFotos,

  /// No se pudo leer la foto (sin red, sin permiso): no es lo mismo que "todavía no
  /// hay".
  noSePudo,

  /// No es un mes: las fotos son del día 1 de cada mes.
  noAplica,

  /// Todavía se está leyendo.
  cargando,
}

class BodegaVista {
  final DatoBodega estado;
  final EcuacionBodega? ecuacion;

  /// Lo que queda (o quedó) en bodega; null si no se sabe.
  final double? fin;

  /// "Te queda" es el valor de HOY (el mes todavía no termina).
  final bool finEsHoy;

  /// Existencias que no se pudieron valorar.
  final int sinPrecio;
  final List<String> imposibles;

  /// No se pudo leer la foto del inicio (y por eso no hay "Tenías").
  final bool fallo;

  /// Alguna foto se tomó mucho después del día que dice: no es exacta.
  final bool aproximada;

  /// Lo comprado que NO está en esta cuenta (bodega central, sucursales que no se
  /// ven): el héroe lo suma, la bodega no.
  final double comprasFuera;

  const BodegaVista({
    required this.estado,
    this.ecuacion,
    this.fin,
    this.finEsHoy = false,
    this.sinPrecio = 0,
    this.imposibles = const [],
    this.fallo = false,
    this.aproximada = false,
    this.comprasFuera = 0,
  });

  /// Decide qué se puede decir de la bodega.
  ///
  /// [compraste] y [usaste] son los de las MISMAS sucursales de la bodega (si no, la
  /// cuenta mezclaría conjuntos distintos); [comprasFuera] es lo que quedó fuera;
  /// [leyendo]: todavía no llega nada; [fotosFallaron]: se intentó y falló.
  factory BodegaVista.armar({
    required DateRange rango,
    required BodegaPeriodo bodega,
    required bool leyendo,
    required double compraste,
    required double usaste,
    bool fotosFallaron = false,
    double comprasFuera = 0,
  }) {
    if (rango.mode != PeriodMode.month) return const BodegaVista(estado: DatoBodega.noAplica);
    if (leyendo) return const BodegaVista(estado: DatoBodega.cargando);
    final ini = bodega.inicio;
    final fin = bodega.fin;
    if (fin == null) {
      return BodegaVista(estado: fotosFallaron ? DatoBodega.noSePudo : DatoBodega.sinFotos, fallo: fotosFallaron);
    }
    if (ini == null) {
      return BodegaVista(
        estado: DatoBodega.soloFin,
        fin: fin,
        finEsHoy: bodega.finEsHoy,
        sinPrecio: bodega.sinPrecio,
        imposibles: bodega.imposibles,
        fallo: fotosFallaron,
        aproximada: bodega.aproximada,
        comprasFuera: comprasFuera,
      );
    }
    return BodegaVista(
      estado: DatoBodega.completo,
      ecuacion: EcuacionBodega(tenias: ini, compraste: compraste, usaste: usaste, teQueda: fin),
      fin: fin,
      finEsHoy: bodega.finEsHoy,
      sinPrecio: bodega.sinPrecio,
      imposibles: bodega.imposibles,
      aproximada: bodega.aproximada,
      comprasFuera: comprasFuera,
    );
  }
}

class _Ctx {
  final String signo;
  final bool telefono;
  const _Ctx(this.signo, this.telefono);

  /// "Q1,235", con "−" si es negativo.
  String m0(double v) {
    final r = v.isFinite ? v.round() : 0;
    final d = _entero.format(r.abs());
    return r < 0 ? '−$signo$d' : '$signo$d';
  }
}

class ComprasVentasBody extends StatefulWidget {
  final ProfitabilityData datos;
  final DateRange rango;
  final String signo;
  final BodegaVista bodega;

  /// Una fila por sucursal; solo en "Todas" con varias.
  final List<FilaSucursalCV> sucursales;
  final CategoriasCV categorias;
  final List<SemanaCV> semanas;

  /// Las unidades de la tabla de categorías son de lo que se leyó: si el período es
  /// muy grande salen cortas.
  final bool lecturaIncompleta;

  final ValueChanged<String>? onElegirSucursal;
  final VoidCallback? onVerRentabilidad;

  const ComprasVentasBody({
    super.key,
    required this.datos,
    required this.rango,
    required this.signo,
    required this.bodega,
    this.sucursales = const [],
    this.categorias = CategoriasCV.vacia,
    this.semanas = const [],
    this.lecturaIncompleta = false,
    this.onElegirSucursal,
    this.onVerRentabilidad,
  });

  @override
  State<ComprasVentasBody> createState() => _ComprasVentasBodyState();
}

class _ComprasVentasBodyState extends State<ComprasVentasBody> {
  bool _platillosAbiertos = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final telefono = ancho <= kInicioQuiebreTelefono;
      final pad = ancho < 640 ? 16.0 : 20.0;
      final ctx = _Ctx(widget.signo, telefono);
      final d = widget.datos;
      const gap = SizedBox(height: 14);

      final ganancia = _Ganaste(ctx: ctx, d: d, onVerRentabilidad: widget.onVerRentabilidad);
      final bodega = _TeQueda(ctx: ctx, vista: widget.bodega, rango: widget.rango);

      final hijos = <Widget>[
        telefono
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ganancia, gap, bodega])
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: ganancia), const SizedBox(width: 14), Expanded(child: bodega)],
                ),
              ),
        if (widget.lecturaIncompleta) ...[gap, const _AvisoLectura()],
        if (!d.costoConfiable && d.itemsTotales > 0) ...[gap, _AvisoCosto(d: d)],
        if (widget.sucursales.length >= 2) ...[
          gap,
          _PorSucursal(ctx: ctx, d: d, filas: widget.sucursales, onElegir: widget.onElegirSucursal),
        ],
        if (widget.categorias.hayAlgo) ...[
          gap,
          _PorCategoria(
            ctx: ctx,
            d: d,
            cats: widget.categorias,
            fin: widget.bodega.fin,
            abierto: _platillosAbiertos,
            onAbrir: () => setState(() => _platillosAbiertos = !_platillosAbiertos),
          ),
        ],
        if (widget.semanas.isNotEmpty) ...[
          gap,
          _Semanas(ctx: ctx, semanas: widget.semanas),
          gap,
          _DetalleSemanas(ctx: ctx, d: d, semanas: widget.semanas, rango: widget.rango),
        ],
        gap,
        const _PieDePagina(),
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
}

// ── Piezas sueltas ──────────────────────────────────────────────────────────

class _Tarjeta extends StatelessWidget {
  final _Ctx ctx;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _Tarjeta({required this.ctx, required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? EdgeInsets.symmetric(horizontal: ctx.telefono ? 16 : 22, vertical: ctx.telefono ? 16 : 18),
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)),
        child: child,
      );
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;
  const _Chip(this.texto, {required this.color, required this.fondo, this.icono});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 5)],
            Flexible(child: Text(texto, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w700, color, height: 1.25))),
          ],
        ),
      );
}

class _Enlace extends StatelessWidget {
  final String texto;
  final Color? _color;
  Color get color => _color ?? _C.accent;
  final VoidCallback onTap;
  const _Enlace(this.texto, {required this.onTap, Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(texto, style: _t(14, FontWeight.w700, color, height: 1.3))),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      );
}

/// El encabezado de una tarjeta del héroe: ícono en cuadro, rótulo y número grande.
class _Cabeza extends StatelessWidget {
  final _Ctx ctx;
  final IconData icono;
  final Color color;
  final Color fondo;
  final String rotulo;
  final String numero;
  const _Cabeza({required this.ctx, required this.icono, required this.color, required this.fondo, required this.rotulo, required this.numero});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(13)),
            child: Icon(icono, size: 21, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: _t(14, FontWeight.w600, _C.muted, height: 1.3)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(numero, maxLines: 1, style: _t(ctx.telefono ? 28 : 34, FontWeight.w800, color, height: 1.15)),
                ),
              ],
            ),
          ),
        ],
      );
}

/// La cuenta del diseño (`.eq`): filas con su operador y un total.
class _Cuenta extends StatelessWidget {
  final List<_LineaCuenta> lineas;
  const _Cuenta(this.lineas);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < lineas.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: lineas[i].total ? _C.soft : _C.line, width: lineas[i].total ? 2 : 1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _C.card, shape: BoxShape.circle),
                    child: Text(lineas[i].operador, style: _t(14, FontWeight.w800, _C.muted, height: 1.1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lineas[i].nombre,
                          style: _t(14.5, lineas[i].total ? FontWeight.w700 : FontWeight.w400, lineas[i].total ? _C.ink : _C.muted, height: 1.3),
                        ),
                        if (lineas[i].nota != null) Text(lineas[i].nota!, style: _t(12, FontWeight.w400, _C.soft, height: 1.3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(lineas[i].valor, maxLines: 1, style: _t(lineas[i].total ? 17 : 14.5, lineas[i].total ? FontWeight.w800 : FontWeight.w700, lineas[i].color)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LineaCuenta {
  final String operador;
  final String nombre;
  final String? nota;
  final String valor;
  final Color color;
  final bool total;
  const _LineaCuenta(this.operador, this.nombre, this.valor, this.color, {this.nota, this.total = false});
}

// ── 1. ¿Cuánto ganaste? ─────────────────────────────────────────────────────

class _Ganaste extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final VoidCallback? onVerRentabilidad;
  const _Ganaste({required this.ctx, required this.d, this.onVerRentabilidad});

  @override
  Widget build(BuildContext context) {
    final g = d.netSales - d.cogs;
    final x = d.cogs > 0 ? d.netSales / d.cogs : null;
    final color = g >= 0 ? _C.gift : _C.bad;

    return _Tarjeta(
      ctx: ctx,
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 18 : 22, vertical: ctx.telefono ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabeza(
            ctx: ctx,
            icono: Icons.trending_up_rounded,
            color: color,
            fondo: g >= 0 ? _C.giftTint : _C.badTint,
            rotulo: g >= 0 ? 'Ganaste con tu mercadería' : 'Perdiste con tu mercadería',
            numero: ctx.m0(g.abs()),
          ),
          const SizedBox(height: 12),
          _Cuenta([
            _LineaCuenta('', 'Vendiste', ctx.m0(d.netSales), _C.accent),
            _LineaCuenta('−', 'Lo que usaste para venderlo', ctx.m0(d.cogs), _C.don, nota: 'el costo de la mercadería que vendiste'),
            _LineaCuenta('=', g >= 0 ? 'Ganaste' : 'Perdiste', ctx.m0(g.abs()), color, total: true),
          ]),
          const SizedBox(height: 12),
          if (x != null)
            Text.rich(
              TextSpan(
                style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4),
                children: [
                  const TextSpan(text: 'Por cada '),
                  TextSpan(text: '${ctx.signo}1', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.4)),
                  const TextSpan(text: ' de mercadería, vendiste '),
                  TextSpan(text: '${ctx.signo}${x.toStringAsFixed(2)}', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.4)),
                ],
              ),
            ),
          if (ctx.telefono) const SizedBox(height: 12) else const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, size: 19, color: _C.warn)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(
                        style: _t(13.5, FontWeight.w400, _C.ink, height: 1.4),
                        children: [
                          TextSpan(text: 'Esto no es tu ganancia final. ', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.4)),
                          const TextSpan(text: 'Todavía falta restar tus gastos fijos: renta, sueldos, luz, agua, internet.'),
                        ],
                      )),
                      if (onVerRentabilidad != null) _Enlace('Ver ganancia real en Rentabilidad', color: _C.warn, onTap: onVerRentabilidad!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2. ¿Cuánto te queda? ────────────────────────────────────────────────────

class _TeQueda extends StatelessWidget {
  final _Ctx ctx;
  final BodegaVista vista;
  final DateRange rango;
  const _TeQueda({required this.ctx, required this.vista, required this.rango});

  @override
  Widget build(BuildContext context) {
    final inicio = rango.mode == PeriodMode.month ? '1 de ${nombreDelMes(rango.start)}' : '';
    final fin = vista.fin;
    final e = vista.ecuacion;

    final Widget cuerpo;
    switch (vista.estado) {
      case DatoBodega.completo:
        final eq = e!;
        cuerpo = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cuenta([
              _LineaCuenta('', 'Tenías el $inicio', ctx.m0(eq.tenias), _C.muted),
              _LineaCuenta('+', 'Compraste', ctx.m0(eq.compraste), _exp),
              _LineaCuenta('−', 'Usaste', ctx.m0(eq.usaste), _C.don),
              if (eq.hayOtros)
                _LineaCuenta(
                  eq.otros > 0 ? '−' : '+',
                  eq.otros > 0 ? 'Merma, ajustes y precios' : 'Ajustes y precios',
                  ctx.m0(eq.otros.abs()),
                  _C.warn,
                  nota: eq.otros > 0 ? 'salió más de lo que vendiste' : 'entró más de lo que compraste',
                ),
              _LineaCuenta('=', vista.finEsHoy ? 'Te queda hoy' : 'Te queda', ctx.m0(eq.teQueda), _C.don, total: true),
            ]),
            const SizedBox(height: 12),
            _EstadoBodega(estado: eq.estado, cambio: eq.teQueda - eq.tenias, ctx: ctx),
          ],
        );
      case DatoBodega.soloFin:
        cuerpo = _MensajeBodega(
          icono: Icons.info_outline_rounded,
          texto: vista.fallo
              ? 'No se pudo leer la foto del $inicio (sin conexión o sin permiso), así que no se puede decir cuánto tenías ni si creció o bajó. '
                  'Desliza hacia abajo para reintentar.'
              : vista.finEsHoy
              ? 'Este es el valor de tu bodega de hoy. Todavía no hay foto del $inicio, así que no se puede decir cuánto tenías ni si creció o bajó. '
                  'La foto se toma sola el día 1 de cada mes.'
              : 'Solo hay la foto del cierre. Sin la del $inicio no se puede decir cuánto tenías ni si creció o bajó.',
        );
      case DatoBodega.noSePudo:
        cuerpo = const _MensajeBodega(
          icono: Icons.cloud_off_rounded,
          texto: 'No se pudo leer la foto de tu bodega de ese mes (sin conexión o sin permiso). Desliza hacia abajo para reintentar.',
        );
      case DatoBodega.sinFotos:
        cuerpo = const _MensajeBodega(
          icono: Icons.info_outline_rounded,
          texto: 'Todavía no hay foto de tu bodega de ese mes. El servidor la toma sola el día 1 de cada mes: '
              'desde la primera que guarde, aquí verás cuánto tenías y cuánto te queda.',
        );
      case DatoBodega.noAplica:
        cuerpo = const _MensajeBodega(
          icono: Icons.calendar_month_rounded,
          texto: 'Elige un mes para ver cuánto tenías en bodega, cuánto compraste y cuánto te queda.',
        );
      case DatoBodega.cargando:
        cuerpo = Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: _C.accent)),
            const SizedBox(width: 14),
            Expanded(child: Text('Leyendo tu bodega…', style: _t(13.5, FontWeight.w400, _C.muted))),
          ],
        );
    }

    return _Tarjeta(
      ctx: ctx,
      padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 18 : 22, vertical: ctx.telefono ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabeza(
            ctx: ctx,
            icono: Icons.warehouse_outlined,
            color: _C.don,
            fondo: _C.donTint,
            rotulo: vista.finEsHoy ? 'Te queda en bodega hoy' : 'Te queda en bodega',
            numero: fin == null ? '—' : ctx.m0(fin),
          ),
          const SizedBox(height: 12),
          cuerpo,
          if (vista.aproximada) ...[
            const SizedBox(height: 10),
            Text(
              'Una de las fotos se tomó bastante después del día 1: valora lo que había ese día, no el del día 1. Sirve para orientarte, no es exacta.',
              style: _t(12.5, FontWeight.w500, _C.warn, height: 1.4),
            ),
          ],
          if (vista.comprasFuera.abs() >= 1) ...[
            const SizedBox(height: 10),
            Text(
              'Arriba, "Compraste" suma ${ctx.m0(vista.comprasFuera)} más que esta cuenta: son compras de la bodega central o de sucursales que no se ven. No entran aquí porque su bodega tampoco.',
              style: _t(12.5, FontWeight.w500, _C.warn, height: 1.4),
            ),
          ],
          if (vista.sinPrecio > 0 || vista.imposibles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              [
                if (vista.sinPrecio > 0) '${vista.sinPrecio} ingrediente(s) con existencia pero sin precio de compra no suman.',
                if (vista.imposibles.isNotEmpty)
                  'Con una existencia imposible y fuera de la cuenta: ${vista.imposibles.take(3).join(', ')}${vista.imposibles.length > 3 ? ' y ${vista.imposibles.length - 3} más' : ''}.',
              ].join(' '),
              style: _t(12.5, FontWeight.w500, _C.warn, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _MensajeBodega extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _MensajeBodega({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 19, color: _C.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45))),
          ],
        ),
      );
}

/// "Tu bodega creció Q…": en ámbar si creció (plata parada), en rojo si bajó.
class _EstadoBodega extends StatelessWidget {
  final EstadoBodega estado;
  final double cambio;
  final _Ctx ctx;
  const _EstadoBodega({required this.estado, required this.cambio, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final (texto, color, fondo, explica) = switch (estado) {
      EstadoBodega.igual => ('Tu bodega quedó igual', _C.gift, _C.giftTint, ''),
      EstadoBodega.crecio => (
          'Tu bodega creció ${ctx.m0(cambio)}',
          _C.warn,
          _C.warnTint,
          'Compraste más de lo que usaste: ese dinero está parado en bodega.'
        ),
      EstadoBodega.bajo => (
          'Tu bodega bajó ${ctx.m0(-cambio)}',
          _C.bad,
          _C.badTint,
          'Usaste más de lo que compraste: pronto tendrás que comprar.'
        ),
    };
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        _Chip(texto, color: color, fondo: fondo),
        if (explica.isNotEmpty) Text(explica, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4)),
      ],
    );
  }
}

/// Se llegó al tope de movimientos que se leen de una vez. Se pierden los más
/// recientes, así que lo comprado y lo usado salen cortos justo en las últimas
/// semanas: la ganancia se ve mayor de lo real.
class _AvisoLectura extends StatelessWidget {
  const _AvisoLectura();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: _C.warn),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Este período tiene más movimientos de inventario de los que se leen de una vez. Lo que compraste y lo que usaste salen cortos, '
              'sobre todo en las últimas semanas, y por eso lo que ganaste se ve mayor de lo real. Prueba con un período más corto.',
              style: _t(13, FontWeight.w400, _C.ink, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parte de lo vendido no tiene costo cargado: callarlo sería dejar que "Ganaste"
/// se vea mejor de lo que es.
class _AvisoCosto extends StatelessWidget {
  final ProfitabilityData d;
  const _AvisoCosto({required this.d});

  @override
  Widget build(BuildContext context) {
    final estimado = d.costoMayormenteEstimado;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: _C.warn),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              estimado
                  ? 'Parte de lo que usaste se calculó con los precios de compra de hoy, porque esas ventas no guardaron su costo. Sirve para orientarte.'
                  : 'Solo ${(d.coberturaCosto ?? 0).toStringAsFixed(1)}% de lo que vendiste tiene costo. Lo que no lo tiene cuenta como costo cero: lo que ganaste sale mayor de lo real.',
              style: _t(13, FontWeight.w400, _C.ink, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ── La tabla (ancha) que en el teléfono se vuelve tarjetas ──────────────────

class _Celda {
  final String? texto;
  final Color? _color;
  Color get color => _color ?? _C.ink;
  final bool negrita;
  final Widget? hijo;
  const _Celda(this.texto, {Color? color, this.negrita = false, this.hijo}) : _color = color;
  static const vacia = _Celda(null);
}

enum _TipoFila { normal, grupo, subfila, total }

class _FilaTabla {
  final Widget primera;
  final List<_Celda> celdas;
  final _TipoFila tipo;
  final VoidCallback? onTap;
  const _FilaTabla({required this.primera, required this.celdas, this.tipo = _TipoFila.normal, this.onTap});
}

class _Tabla extends StatelessWidget {
  final _Ctx ctx;

  /// El rótulo de la primera columna y de las demás.
  final String primera;
  final List<String> columnas;
  final List<_FilaTabla> filas;
  const _Tabla({required this.ctx, required this.primera, required this.columnas, required this.filas});

  Widget _texto(_Celda c) => c.hijo ?? Text(c.texto ?? '', maxLines: 1, style: _t(14, c.negrita ? FontWeight.w700 : FontWeight.w600, c.color));

  @override
  Widget build(BuildContext context) {
    if (ctx.telefono) return _tarjetas();

    Widget fila(_FilaTabla f, {bool cabecera = false}) {
      final total = f.tipo == _TipoFila.total;
      final grupo = f.tipo == _TipoFila.grupo;
      final sub = f.tipo == _TipoFila.subfila;
      final contenido = Container(
        padding: EdgeInsets.fromLTRB(sub ? 16 : 0, 12, 0, 12),
        decoration: BoxDecoration(
          color: total || grupo ? _C.subtle : null,
          border: Border(top: BorderSide(color: total ? _C.line : _C.line, width: total ? 2 : 1)),
        ),
        child: Row(
          children: [
            SizedBox(width: total || grupo ? 12 : 0),
            Expanded(flex: 5, child: f.primera),
            for (final c in f.celdas)
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 12),
                      child: _texto(total ? _Celda(c.texto, color: c.color, negrita: true, hijo: c.hijo) : c),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return f.onTap == null
          ? contenido
          : InkWell(onTap: f.onTap, borderRadius: BorderRadius.circular(8), child: contenido);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text(primera.toUpperCase(), style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6))),
              for (final c in columnas)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 12),
                    child: Text(c.toUpperCase(), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6)),
                  ),
                ),
            ],
          ),
        ),
        for (final f in filas) fila(f),
      ],
    );
  }

  /// En el teléfono cada fila es una tarjeta: el nombre arriba y los datos de dos
  /// en dos, cada uno con su rótulo.
  Widget _tarjetas() {
    Widget dato(String rotulo, _Celda c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo.toUpperCase(), style: _t(11, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.5)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _texto(c)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in filas)
          () {
            final total = f.tipo == _TipoFila.total;
            final grupo = f.tipo == _TipoFila.grupo;
            final presentes = [
              for (var i = 0; i < f.celdas.length; i++)
                if (f.celdas[i].texto != null || f.celdas[i].hijo != null) (columnas[i], f.celdas[i]),
            ];
            final grilla = <Widget>[];
            for (var i = 0; i < presentes.length; i += 2) {
              grilla.add(Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    dato(presentes[i].$1, presentes[i].$2),
                    const SizedBox(width: 12),
                    i + 1 < presentes.length ? dato(presentes[i + 1].$1, presentes[i + 1].$2) : const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ));
            }
            final contenido = Container(
              margin: EdgeInsets.only(top: total || grupo ? 6 : 0),
              padding: EdgeInsets.symmetric(horizontal: total || grupo ? 14 : 0, vertical: 12),
              decoration: BoxDecoration(
                color: total || grupo ? _C.subtle : null,
                borderRadius: total || grupo ? BorderRadius.circular(14) : null,
                border: total || grupo ? null : Border(bottom: BorderSide(color: _C.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Padding(padding: EdgeInsets.only(left: f.tipo == _TipoFila.subfila ? 14 : 0), child: f.primera), ...grilla],
              ),
            );
            return f.onTap == null ? contenido : InkWell(onTap: f.onTap, borderRadius: BorderRadius.circular(14), child: contenido);
          }(),
      ],
    );
  }
}

/// El nombre de una fila con una línea chica debajo.
class _Nombre extends StatelessWidget {
  final String nombre;
  final String? nota;
  const _Nombre(this.nombre, {this.nota});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: _t(14, FontWeight.w600, _C.ink, height: 1.3)),
          if (nota != null) Text(nota!, style: _t(12, FontWeight.w400, _C.muted, height: 1.3)),
        ],
      );
}

Widget _tituloBloque(String titulo, {String? sub, Widget? derecha}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          derecha == null
              ? Text(titulo, style: _t(15.5, FontWeight.w700, _C.ink, height: 1.3))
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 6,
                  children: [Text(titulo, style: _t(15.5, FontWeight.w700, _C.ink, height: 1.3)), derecha],
                ),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: _t(13, FontWeight.w400, _C.muted, height: 1.35))),
        ],
      ),
    );

// ── 3. Por sucursal ─────────────────────────────────────────────────────────

class _PorSucursal extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final List<FilaSucursalCV> filas;
  final ValueChanged<String>? onElegir;
  const _PorSucursal({required this.ctx, required this.d, required this.filas, this.onElegir});

  Widget _estado(FilaSucursalCV f) {
    final e = f.estado;
    if (e == null || f.cambio == null) return Text('—', style: TextStyle(color: _C.soft));
    return switch (e) {
      EstadoBodega.igual => _Chip('= igual', color: _C.gift, fondo: _C.giftTint),
      // Íconos y no "↑" ni "↓": Poppins no trae esas flechas.
      EstadoBodega.crecio => _Chip(ctx.m0(f.cambio!), color: _C.warn, fondo: _C.warnTint, icono: Icons.arrow_upward_rounded),
      EstadoBodega.bajo => _Chip(ctx.m0(-f.cambio!), color: _C.bad, fondo: _C.badTint, icono: Icons.arrow_downward_rounded),
    };
  }

  @override
  Widget build(BuildContext context) {
    final total = filas.fold<List<double>>([0, 0, 0], (a, f) => [a[0] + f.compro, a[1] + f.vendio, a[2] + f.usaste]);
    final hayQueda = filas.any((f) => f.leQueda != null);
    final queda = filas.fold<double>(0, (a, f) => a + (f.leQueda ?? 0));
    // Lo de arriba (el héroe) suma TODO lo que se movió; la tabla, solo las
    // sucursales que se ven. Si no coinciden, se dice por qué.
    final ventasFuera = d.netSales - total[1];
    final comprasFuera = d.purchases - total[0];
    final hayFuera = ventasFuera.abs() >= 1 || comprasFuera.abs() >= 1;

    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloBloque('Por sucursal', sub: onElegir == null ? null : 'Toca una sucursal para ver su detalle'),
          _Tabla(
            ctx: ctx,
            primera: 'Sucursal',
            columnas: const ['Compró', 'Vendió', 'Ganó*', 'Le queda', 'Bodega'],
            filas: [
              for (final f in filas)
                _FilaTabla(
                  primera: Text(f.nombre, style: _t(15, FontWeight.w600, _C.ink, height: 1.3)),
                  onTap: onElegir == null ? null : () => onElegir!(f.id),
                  celdas: [
                    _Celda(ctx.m0(f.compro), color: _exp),
                    _Celda(ctx.m0(f.vendio), color: _C.accent),
                    _Celda(ctx.m0(f.gano), color: f.gano >= 0 ? _C.gift : _C.bad, negrita: true),
                    f.leQueda == null ? _Celda('—', color: _C.soft) : _Celda(ctx.m0(f.leQueda!), color: _C.don),
                    _Celda(null, hijo: _estado(f)),
                  ],
                ),
              _FilaTabla(
                primera: Text('Total', style: _t(14, FontWeight.w800, _C.ink)),
                tipo: _TipoFila.total,
                celdas: [
                  _Celda(ctx.m0(total[0]), color: _exp),
                  _Celda(ctx.m0(total[1]), color: _C.accent),
                  _Celda(ctx.m0(total[1] - total[2]), color: total[1] - total[2] >= 0 ? _C.gift : _C.bad),
                  hayQueda ? _Celda(ctx.m0(queda), color: _C.don) : _Celda('—', color: _C.soft),
                  _Celda.vacia,
                ],
              ),
            ],
          ),
          if (hayFuera) ...[
            const SizedBox(height: 10),
            Text(
              'Los totales de arriba también suman ${[
                if (ventasFuera.abs() >= 1) '${ctx.m0(ventasFuera)} vendidos',
                if (comprasFuera.abs() >= 1) '${ctx.m0(comprasFuera)} comprados',
              ].join(' y ')} en la bodega central, en sucursales que no se ven o sin sucursal: no están en estas filas.',
              style: _t(12.5, FontWeight.w500, _C.warn, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 4. ¿En qué compraste y cuánto ganaste? ──────────────────────────────────

class _PorCategoria extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final CategoriasCV cats;
  final double? fin;
  final bool abierto;
  final VoidCallback onAbrir;
  const _PorCategoria({required this.ctx, required this.d, required this.cats, required this.fin, required this.abierto, required this.onAbrir});

  _Celda _queda(double? v) => v == null ? _Celda('—', color: _C.soft) : _Celda(ctx.m0(v), color: _C.don);

  @override
  Widget build(BuildContext context) {
    final p = cats.platillos;
    final compras = cats.reventa.fold<double>(0, (a, f) => a + f.compraste) + (p?.compraste ?? 0);
    final g = d.netSales - d.cogs;

    final filas = <_FilaTabla>[
      for (final f in cats.reventa)
        _FilaTabla(
          primera: _Nombre(f.nombre, nota: f.porCadaQ == null ? null : 'por cada ${ctx.signo}1 vendiste ${ctx.signo}${f.porCadaQ!.toStringAsFixed(2)}'),
          celdas: [
            _Celda(ctx.m0(f.compraste), color: _exp),
            _queda(f.teQueda),
            _Celda(ctx.m0(f.vendiste!), color: _C.accent),
            _Celda(ctx.m0(f.ganaste!), color: f.ganaste! >= 0 ? _C.gift : _C.bad, negrita: true),
          ],
        ),
      if (p != null)
        _FilaTabla(
          tipo: _TipoFila.grupo,
          onTap: onAbrir,
          primera: Row(
            children: [
              Flexible(child: _Nombre('Platillos', nota: 'carnes, abarrotes, verduras')),
              const SizedBox(width: 6),
              AnimatedRotation(turns: abierto ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: _C.muted)),
            ],
          ),
          celdas: [
            _Celda(ctx.m0(p.compraste), color: _exp),
            _queda(p.teQueda),
            _Celda(ctx.m0(p.vendiste!), color: _C.accent),
            _Celda(ctx.m0(p.ganaste!), color: p.ganaste! >= 0 ? _C.gift : _C.bad, negrita: true),
          ],
        ),
      if (p != null && abierto)
        for (final f in cats.insumos)
          _FilaTabla(
            tipo: _TipoFila.subfila,
            primera: Text(f.nombre, style: _t(13, FontWeight.w400, _C.muted, height: 1.3)),
            celdas: [
              _Celda(ctx.m0(f.compraste), color: _exp),
              _queda(f.teQueda),
              _Celda(null, hijo: Text('en platillos', maxLines: 1, style: _t(12.5, FontWeight.w400, _C.muted))),
              _Celda('—', color: _C.soft),
            ],
          ),
      _FilaTabla(
        tipo: _TipoFila.total,
        primera: Text('Total', style: _t(14, FontWeight.w800, _C.ink)),
        celdas: [
          _Celda(ctx.m0(compras), color: _exp),
          fin == null ? _Celda('—', color: _C.soft) : _Celda(ctx.m0(fin!), color: _C.don),
          _Celda(ctx.m0(d.netSales), color: _C.accent),
          _Celda(ctx.m0(g), color: g >= 0 ? _C.gift : _C.bad),
        ],
      ),
    ];

    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloBloque('¿En qué compraste y cuánto ganaste?', sub: 'Lo que revendes se ve directo. Los insumos de cocina se ven juntos en "Platillos".'),
          _Tabla(ctx: ctx, primera: 'Producto', columnas: const ['Compraste', 'Te queda', 'Vendiste', 'Ganaste'], filas: filas),
        ],
      ),
    );
  }
}

// ── 5. Semana por semana ────────────────────────────────────────────────────

String _miles(double v) {
  final a = v.abs();
  final s = v < 0 ? '−' : '+';
  return a >= 1000 ? '$s${(a / 1000).toStringAsFixed(1)}k' : '$s${a.round()}';
}

String _corto(double v) => v.abs() >= 1000 ? '${(v / 1000).round()}k' : '${v.round()}';

class _Semanas extends StatelessWidget {
  final _Ctx ctx;
  final List<SemanaCV> semanas;
  const _Semanas({required this.ctx, required this.semanas});

  Widget _leyenda(String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(t, style: _t(13, FontWeight.w400, _C.muted)),
      ]);

  @override
  Widget build(BuildContext context) {
    final mayor = semanas.fold<double>(0, (a, s) => math.max(a, math.max(s.vendiste, s.compraste)));
    final alto = ctx.telefono ? 150.0 : 180.0;

    // Una barra de ancho fijo (como máximo 42) y su número encima.
    Widget barra(double v, Color c, double ancha) {
      final h = mayor > 0 ? math.max(0.0, v) / mayor * alto : 0.0;
      return SizedBox(
        width: ancha,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ctx.telefono)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(_corto(v), maxLines: 1, style: _t(11, FontWeight.w700, _C.muted))),
              ),
            Container(height: h, decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)))),
          ],
        ),
      );
    }

    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloBloque(
            'Semana por semana',
            derecha: Wrap(spacing: 14, runSpacing: 4, children: [_leyenda('Vendiste', _C.accent), _leyenda('Compraste', _exp)]),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final s in semanas)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: ctx.telefono ? 2 : 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: alto + (ctx.telefono ? 0 : 36),
                          child: LayoutBuilder(builder: (context, c) {
                            final ancha = math.min(42.0, c.maxWidth * (ctx.telefono ? 0.42 : 0.38));
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [barra(s.vendiste, _C.accent, ancha), SizedBox(width: ctx.telefono ? 3 : 6), barra(s.compraste, _exp, ancha)],
                            );
                          }),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(s.nombre.replaceFirst('Semana ', 'Sem '), maxLines: 1, style: _t(13, FontWeight.w700, _C.ink))),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(s.rango, maxLines: 1, style: _t(11.5, FontWeight.w400, _C.muted))),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Chip(_miles(s.ganaste), color: s.ganaste >= 0 ? _C.gift : _C.bad, fondo: s.ganaste >= 0 ? _C.giftTint : _C.badTint),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: _C.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(
                    style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45),
                    children: [
                      const TextSpan(text: 'Es normal que las compras suban y bajen de una semana a otra (compras fuerte una semana y luego vendes de la bodega). El número de color es lo que '),
                      TextSpan(text: 'ganaste', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.45)),
                      const TextSpan(text: ' cada semana.'),
                    ],
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetalleSemanas extends StatelessWidget {
  final _Ctx ctx;
  final ProfitabilityData d;
  final List<SemanaCV> semanas;
  final DateRange rango;
  const _DetalleSemanas({required this.ctx, required this.d, required this.semanas, required this.rango});

  @override
  Widget build(BuildContext context) {
    final c = semanas.fold<double>(0, (a, s) => a + s.compraste);
    final v = semanas.fold<double>(0, (a, s) => a + s.vendiste);
    final u = semanas.fold<double>(0, (a, s) => a + s.usaste);
    Color gc(double x) => x >= 0 ? _C.gift : _C.bad;

    return _Tarjeta(
      ctx: ctx,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloBloque('Detalle por semana'),
          _Tabla(
            ctx: ctx,
            primera: 'Semana',
            columnas: const ['Compraste', 'Vendiste', 'Usaste', 'Ganaste'],
            filas: [
              for (final s in semanas)
                _FilaTabla(
                  primera: _Nombre(s.nombre, nota: s.rango),
                  celdas: [
                    _Celda(ctx.m0(s.compraste), color: _exp),
                    _Celda(ctx.m0(s.vendiste), color: _C.accent),
                    _Celda(ctx.m0(s.usaste), color: _C.don),
                    _Celda(ctx.m0(s.ganaste), color: gc(s.ganaste), negrita: true),
                  ],
                ),
              _FilaTabla(
                tipo: _TipoFila.total,
                primera: Text('Total ${nombreDelMes(rango.start)}', style: _t(14, FontWeight.w800, _C.ink)),
                celdas: [
                  _Celda(ctx.m0(c), color: _exp),
                  _Celda(ctx.m0(v), color: _C.accent),
                  _Celda(ctx.m0(u), color: _C.don),
                  _Celda(ctx.m0(v - u), color: gc(v - u)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PieDePagina extends StatelessWidget {
  const _PieDePagina();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 15, color: _C.soft)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(
              style: _t(12.5, FontWeight.w400, _C.soft, height: 1.4),
              children: [
                TextSpan(text: '*Todas las ganancias de este reporte son antes de gastos fijos ', style: _t(12.5, FontWeight.w700, _C.ink, height: 1.4)),
                const TextSpan(
                  text: '(renta, sueldos, luz): esos se restan en Rentabilidad. Compras = mercadería que entró a tu despensa, sin gastos de caja. '
                      '"Usaste" = el costo de lo que vendiste: es el mismo de Rentabilidad. '
                      '"Tenías" y "Te queda" salen de la foto de tu bodega que se toma el día 1 de cada mes.',
                ),
              ],
            )),
          ),
        ],
      ),
    );
  }
}
