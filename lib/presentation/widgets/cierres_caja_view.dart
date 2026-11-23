/// El historial de cierres de caja. Rediseño 2026-11-21 (`cierres-caja.html` de
/// saborpro_app, en su modo oscuro): el resumen del período, el aviso de la caja
/// que nadie cerró, "En caja ahora" y el cuadre de cada corte.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa los
/// cortes ya contados ([CierreCaja], que es la misma cuenta de siempre). Se
/// prueba a 360dp en test/presentation/widgets/cierres_caja_view_test.dart.
///
/// OJO: el resumen y las filas de "En caja ahora" van en un `IntrinsicHeight`
/// (misma altura en la fila), así que dentro no puede haber `LayoutBuilder`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show MonedaLocal;
import '../../data/models/atencion_inicio.dart' show ParteTexto;
import '../../data/models/cash_register_summary.dart';
import '../../data/models/cierres_caja.dart';
import 'cierres_no_aplicados_block.dart';
import 'inicio_ui.dart';
import 'resumen_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

final _hora = DateFormat('hh:mm a');

String _q(String signo, double v) => formatoMonto(signo, v);

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "las 08:02 AM" si es de hoy; si no, "el 12 nov, 09:03 PM".
String _desde(DateTime d, DateTime ahora) =>
    _mismoDia(d, ahora) ? 'las ${_hora.format(d)}' : 'el ${fechaCorta(d)}, ${_hora.format(d)}';

class CierresCajaBody extends StatelessWidget {
  final List<CierreCaja> cierres;
  final List<CashRegisterSummary> abiertas;

  /// El signo de la moneda de la sucursal de cada caja (las cajas no se convierten).
  final String Function(String? locationId) signoDeCaja;

  /// La moneda (su código) de cada caja: con ella se agrupa el resumen. Sin ella
  /// se agrupa por signo (y dos monedas con el mismo signo se sumarían).
  final String Function(String? locationId)? monedaDeCaja;

  /// Contra qué se mide cuánto lleva abierta una caja.
  final DateTime ahora;

  final ValueChanged<CierreCaja> onVerDetalle;

  /// Lo que se agrega al final de la tarjeta de una caja abierta (el cierre
  /// forzado, que solo existe al depurar).
  final Widget? Function(CashRegisterSummary caja)? accionAbierta;

  const CierresCajaBody({
    super.key,
    required this.cierres,
    required this.abiertas,
    required this.signoDeCaja,
    this.monedaDeCaja,
    required this.ahora,
    required this.onVerDetalle,
    this.accionAbierta,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final pad = ancho < 640 ? 16.0 : 20.0;
      const gap = SizedBox(height: 16);

      final Widget contenido;
      if (cierres.isEmpty && abiertas.isEmpty) {
        contenido = Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: Text(
              'Sin cierres de caja en este período',
              textAlign: TextAlign.center,
              style: _t(14, FontWeight.w400, _C.muted),
            ),
          ),
        );
      } else {
        final resumen = ResumenCierres.desde(
          cierres: cierres,
          abiertas: abiertas,
          signoDeCaja: signoDeCaja,
          monedaDeCaja: monedaDeCaja,
          ahora: ahora,
        );
        final varias = resumen.porMoneda.length > 1;
        final vieja = resumen.olvidadas.isEmpty ? null : resumen.olvidadas.first;
        contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in resumen.porMoneda) ...[
              // Con cajas en más de una moneda, cada resumen dice la suya: no se
              // suman quetzales con dólares.
              if (varias)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    // "GTQ (Q)" cuando se sabe el código: dos monedas pueden compartir signo.
                    g.moneda.isEmpty || g.moneda == g.signo.trim()
                        ? 'Cajas en ${g.signo.trim()}'
                        : 'Cajas en ${g.moneda} (${g.signo.trim()})',
                    style: _t(13, FontWeight.w700, _C.muted),
                  ),
                ),
              _Resumen(g: g, ancho: ancho, ahora: ahora),
              gap,
            ],
            if (vieja != null) ...[_AlertaCajaVieja(vieja: vieja, mas: resumen.olvidadas.length - 1, ahora: ahora), gap],
            if (abiertas.isNotEmpty) ...[
              const _Seccion('En caja ahora'),
              const SizedBox(height: 12),
              _CajasAbiertas(
                abiertas: abiertas,
                ahora: ahora,
                ancho: ancho - 2 * pad,
                accion: accionAbierta,
              ),
              gap,
            ],
            if (cierres.isNotEmpty) ...[
              const _Seccion('Cierres del período'),
              const SizedBox(height: 12),
              for (var i = 0; i < cierres.length; i++) ...[
                if (i > 0) gap,
                _CierreCard(cierre: cierres[i], ancho: ancho, ahora: ahora, onVer: () => onVerDetalle(cierres[i])),
              ],
            ],
          ],
        );
      }

      final lista = SingleChildScrollView(
        // Siempre desplazable: el RefreshIndicator lo necesita aunque haya poco que mostrar.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
        child: contenido,
      );

      // Con poco que mostrar el contenido es más bajo que la pantalla. El cambio
      // de sucursal (un AnimatedSwitcher) entrega restricciones sueltas y un
      // SingleChildScrollView mide lo que mide su contenido: sin esto quedaba
      // CENTRADO en vertical, con un hueco enorme bajo las pestañas.
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
        child: lista,
      );
    });
  }
}

class _Seccion extends StatelessWidget {
  final String texto;
  const _Seccion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        texto.toUpperCase(),
        style: _t(13, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.78),
      ),
    );
  }
}

// ── RESUMEN ──────────────────────────────────────────────────────────────────

class _Resumen extends StatelessWidget {
  final ResumenMoneda g;
  final double ancho;
  final DateTime ahora;

  const _Resumen({required this.g, required this.ancho, required this.ahora});

  String _tiempo(CashRegisterSummary r) {
    final dias = ahora.difference(r.openedAt).inDays;
    return dias >= 2 ? '$dias días' : '24 h';
  }

  @override
  Widget build(BuildContext context) {
    final s = g.signo;
    final hay = g.cierres > 0;

    // Diferencia en caja: lo que faltó, sin netearlo contra un sobrante de otro cierre.
    final String difValor;
    final Color difColor;
    final String difSub;
    if (!hay) {
      difValor = '—';
      difColor = _C.muted;
      difSub = 'Sin cierres';
    } else if (g.conFaltante > 0) {
      difValor = _q(s, -g.faltante);
      difColor = _C.bad;
      difSub = '${g.conFaltante} ${g.conFaltante == 1 ? 'cierre con faltante' : 'cierres con faltante'}'
          '${g.conSobrante > 0 ? ' · ${g.conSobrante} con sobrante' : ''}';
    } else if (g.conSobrante > 0) {
      difValor = _q(s, g.sobrante);
      difColor = _C.warn;
      difSub = '${g.conSobrante} ${g.conSobrante == 1 ? 'cierre con sobrante' : 'cierres con sobrante'}';
    } else if (g.sinContar == g.cierres) {
      difValor = '—';
      difColor = _C.muted;
      difSub = 'Sin contar';
    } else {
      difValor = 'Cuadró';
      difColor = _C.gift;
      difSub = g.sinContar > 0 ? 'Los contados cuadraron' : 'Todos los cierres cuadraron';
    }

    final String abiertasSub;
    if (g.abiertas == 0) {
      abiertasSub = 'Ninguna abierta';
    } else if (g.olvidadas.isEmpty) {
      abiertasSub = 'Todo normal';
    } else if (g.olvidadas.length == 1) {
      abiertasSub = '1 lleva más de ${_tiempo(g.olvidadas.first)}';
    } else {
      abiertasSub = '${g.olvidadas.length} llevan más de 24 h';
    }

    return ResumenCard(
      ancho: ancho,
      celdas: [
        ResumenCelda(
          etiqueta: 'Ventas del período',
          valor: hay ? _q(s, g.ventas) : '—',
          colorValor: hay ? _C.ink : _C.muted,
          sub: [
            ResumenCard.linea(hay ? '${g.cierres} ${g.cierres == 1 ? 'cierre' : 'cierres'}' : 'Sin cierres', ancho),
            if (g.sinContar > 0) ResumenCard.linea('${g.sinContar} sin contar', ancho),
            // Un corte antiguo se recalcula de los pedidos sin saber de qué cajero es
            // cada uno: si hubo dos cajas a la vez, esas ventas pueden repetirse.
            if (g.recalculados > 0)
              ResumenCard.linea(
                '${g.recalculados} ${g.recalculados == 1 ? 'recalculado' : 'recalculados'} de los pedidos: pueden repetir ventas',
                ancho,
                color: _C.warn,
              ),
          ],
        ),
        ResumenCelda(
          etiqueta: 'Diferencia en caja',
          valor: difValor,
          colorValor: difColor,
          sub: [ResumenCard.linea(difSub, ancho)],
        ),
        ResumenCelda(etiqueta: 'Efectivo y tarjeta', cuerpo: _Reparto(g: g)),
        ResumenCelda(
          etiqueta: 'Cajas abiertas ahora',
          valor: '${g.abiertas}',
          sub: [ResumenCard.linea(abiertasSub, ancho, color: g.olvidadas.isEmpty ? _C.muted : _C.warn)],
        ),
      ],
    );
  }
}

/// La barra de cuánto entró en efectivo y en tarjeta (y en otros métodos, si
/// hubo), con sus montos.
class _Reparto extends StatelessWidget {
  final ResumenMoneda g;
  const _Reparto({required this.g});

  @override
  Widget build(BuildContext context) {
    final ef = math.max(0.0, g.efectivo);
    final tj = math.max(0.0, g.tarjeta);
    final ot = math.max(0.0, g.otros);
    final total = ef + tj + ot;
    if (g.cierres == 0 || total <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('—', style: _t(26, FontWeight.w800, _C.muted, height: 1.2)),
      );
    }

    Widget tramo(double v, Color color) =>
        Expanded(flex: math.max(1, (v / total * 1000).round()), child: ColoredBox(color: color, child: const SizedBox.expand()));

    // En un teléfono con letra grande la celda no da para nombre y monto en la
    // misma línea: el monto baja debajo del nombre.
    final media = MediaQuery.of(context);
    final apilada = media.size.width < 640 && media.textScaler.scale(13) > 13 * 1.1;

    Widget cuadro(Color color) =>
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)));

    Widget monto(double valor, Alignment alinea) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alinea,
          child: Text(_q(g.signo, valor), maxLines: 1, style: _t(13, FontWeight.w600, _C.ink)),
        );

    Widget fila(String nombre, double valor, Color color) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: apilada
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      cuadro(color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w400, _C.muted))),
                    ]),
                    Padding(padding: const EdgeInsets.only(left: 18), child: monto(valor, Alignment.centerLeft)),
                  ],
                )
              : Row(
                  children: [
                    cuadro(color),
                    const SizedBox(width: 8),
                    // El nombre toma lo suyo (no se parte); el monto, lo que quede, y con
                    // cifras enormes la letra se achica en vez de salirse.
                    Text(nombre, maxLines: 1, style: _t(13, FontWeight.w400, _C.muted)),
                    const SizedBox(width: 8),
                    Expanded(child: monto(valor, Alignment.centerRight)),
                  ],
                ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                if (ef > 0) tramo(ef, _C.gift),
                if (tj > 0) tramo(tj, _C.don),
                if (ot > 0) tramo(ot, _C.accent),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          fila('Efectivo', g.efectivo, _C.gift),
          fila('Tarjeta', g.tarjeta, _C.don),
          if (g.otros != 0) fila('Otros', g.otros, _C.accent),
        ],
      ),
    );
  }
}

class _AlertaCajaVieja extends StatelessWidget {
  final CashRegisterSummary vieja;
  final int mas;
  final DateTime ahora;

  const _AlertaCajaVieja({required this.vieja, required this.mas, required this.ahora});

  @override
  Widget build(BuildContext context) {
    return AlertaAmbar(
      partes: [
        ParteTexto(vieja.userName, negrita: true),
        const ParteTexto(' tiene la caja abierta desde hace '),
        ParteTexto(formatoDuracion(ahora.difference(vieja.openedAt)), negrita: true),
        const ParteTexto('. Una caja tan larga mezcla días y no se puede cuadrar bien.'),
        if (mas > 0) ParteTexto(' Hay ${mas == 1 ? 'otra caja' : 'otras $mas cajas'} con más de 24 horas abiertas.'),
      ],
    );
  }
}

// ── EN CAJA AHORA ────────────────────────────────────────────────────────────

class _CajasAbiertas extends StatelessWidget {
  final List<CashRegisterSummary> abiertas;
  final DateTime ahora;

  /// Lo que mide el contenido (sin los márgenes de la pantalla).
  final double ancho;
  final Widget? Function(CashRegisterSummary caja)? accion;

  const _CajasAbiertas({required this.abiertas, required this.ahora, required this.ancho, this.accion});

  @override
  Widget build(BuildContext context) {
    // Como `repeat(auto-fill, minmax(320px, 1fr))` del diseño.
    final columnas = math.max(1, ((ancho + 12) / (320 + 12)).floor());
    final filas = <List<CashRegisterSummary>>[];
    for (var i = 0; i < abiertas.length; i += columnas) {
      filas.add(abiertas.sublist(i, math.min(i + columnas, abiertas.length)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var f = 0; f < filas.length; f++) ...[
          if (f > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columnas; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: i < filas[f].length
                        ? _CajaAbierta(caja: filas[f][i], ahora: ahora, accion: accion?.call(filas[f][i]))
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CajaAbierta extends StatelessWidget {
  final CashRegisterSummary caja;
  final DateTime ahora;
  final Widget? accion;

  const _CajaAbierta({required this.caja, required this.ahora, this.accion});

  @override
  Widget build(BuildContext context) {
    final dur = ahora.difference(caja.openedAt);
    // Más de 24 h abierta: es de un turno que nadie cerró.
    final vieja = dur >= const Duration(hours: 24);
    final color = vieja ? _C.warn : _C.gift;
    final halo = vieja ? _C.warnTint : _C.giftTint;
    final sucursal = caja.locationName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
        border: vieja ? Border.all(color: _C.warn, width: 2) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: halo, spreadRadius: 5)],
            ),
          ),
          const SizedBox(width: 19),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(caja.userName, style: _t(16, FontWeight.w700, _C.ink)),
                Text(
                  'Abierta desde ${_desde(caja.openedAt, ahora)}${sucursal != null && sucursal.isNotEmpty ? ' · $sucursal' : ''}',
                  style: _t(13, FontWeight.w400, _C.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Abierta', style: _t(13, FontWeight.w400, _C.muted)),
              Text(formatoDuracion(dur), style: _t(18, FontWeight.w700, vieja ? _C.warn : _C.ink)),
            ],
          ),
          if (accion != null) ...[const SizedBox(width: 8), accion!],
        ],
      ),
    );
  }
}

// ── UN CIERRE ────────────────────────────────────────────────────────────────

class _CierreCard extends StatelessWidget {
  final CierreCaja cierre;
  final double ancho;
  final DateTime ahora;
  final VoidCallback onVer;

  const _CierreCard({required this.cierre, required this.ancho, required this.ahora, required this.onVer});

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    final r = c.caja;
    final telefono = ancho < 640;
    final dos = ancho > 980;
    // Con letra grande el encabezado en una sola fila no cabe aunque haya ancho.
    final letraGrande = MediaQuery.textScalerOf(context).scale(17) > 17 * 1.15;
    final aclaracion = c.aclaracion;
    final box1 = _Box(
      titulo: '¿Cuadró la caja?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_Cuadre(cierre: c), if (aclaracion != null) _Aclaracion(aclaracion)],
      ),
    );
    final box2 = _Box(titulo: 'Efectivo en caja', child: _EfectivoEnCaja(cierre: c));

    return MonedaLocal(
      simbolo: c.signo,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecera(cierre: c, telefono: telefono || letraGrande, ahora: ahora),
            // Se cerró más de una vez (otro aparato no se enteró del cierre): el
            // dueño tiene que ver el otro conteo en el corte mismo.
            if (r.cierresNoAplicados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: CierresNoAplicadosBlock(r),
              ),
            const _Linea(),
            if (dos)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 12, child: box1),
                    Container(width: 1, color: _C.line),
                    Expanded(flex: 10, child: box2),
                  ],
                ),
              )
            else
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [box1, const _Linea(), box2]),
            const _Linea(),
            InkWell(
              onTap: onVer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Flexible: con letra grande el enlace se acorta en vez de salirse.
                    Flexible(
                      child: Text(
                        'Ver pedidos y gastos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(14.5, FontWeight.w700, _C.accent),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, size: 18, color: _C.accent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea();

  @override
  Widget build(BuildContext context) => Container(height: 1, color: _C.line);
}

class _Cabecera extends StatelessWidget {
  final CierreCaja cierre;
  final bool telefono;
  final DateTime ahora;

  const _Cabecera({required this.cierre, required this.telefono, required this.ahora});

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    final r = c.caja;
    final cerrada = r.closedAt;
    final fecha = _mismoDia(r.openedAt, ahora) ? '' : '${fechaCorta(r.openedAt)} · ';
    final sucursal = r.locationName;
    final rango = '$fecha${_hora.format(r.openedAt)}${cerrada != null ? ' → ${_hora.format(cerrada)}' : ''}'
        ' · ${formatoDuracion(r.duration)}${sucursal != null && sucursal.isNotEmpty ? ' · $sucursal' : ''}';

    final avatar = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _C.tint, shape: BoxShape.circle),
      child: Text(inicialesDe(r.userName), style: _t(14, FontWeight.w700, _C.accent, height: 1.0)),
    );
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(r.userName, style: _t(17, FontWeight.w700, _C.ink)),
        Text(rango, style: _t(13, FontWeight.w400, _C.muted)),
      ],
    );
    final estado = _Estado(cierre: c);
    final total = Column(
      crossAxisAlignment: telefono ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: telefono ? Alignment.centerLeft : Alignment.centerRight,
          child: Text(_q(c.signo, c.ventas), maxLines: 1, style: _t(22, FontWeight.w800, _C.ink)),
        ),
        Text('en ventas', style: _t(12.5, FontWeight.w400, _C.muted)),
      ],
    );

    if (telefono) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [avatar, const SizedBox(width: 12), Expanded(child: texto)]),
            if (c.estado != EstadoCierre.sinContar) ...[const SizedBox(height: 10), estado],
            const SizedBox(height: 10),
            total,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(child: texto),
          if (c.estado != EstadoCierre.sinContar) ...[const SizedBox(width: 14), estado],
          const SizedBox(width: 14),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: total),
        ],
      ),
    );
  }
}

/// "Faltante Q385.00", "Sobrante Q50.00" o "Cuadró".
class _Estado extends StatelessWidget {
  final CierreCaja cierre;
  const _Estado({required this.cierre});

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    final (String texto, Color color, Color fondo, IconData icono) = switch (c.estado) {
      EstadoCierre.faltante => ('Faltante ${_q(c.signo, c.faltante)}', _C.bad, _C.badTint, Icons.warning_amber_rounded),
      EstadoCierre.sobrante => ('Sobrante ${_q(c.signo, c.sobrante)}', _C.warn, _C.warnTint, Icons.info_outline_rounded),
      _ => ('Cuadró', _C.gift, _C.giftTint, Icons.check_rounded),
    };
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w700, color))),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final String titulo;
  final Widget child;
  const _Box({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              titulo.toUpperCase(),
              style: _t(13, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.65),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// "¿Cuadró la caja?": por cada método, lo esperado, lo contado y la diferencia.
/// En un teléfono angosto (o con letra grande) cada método pasa a dos líneas en
/// vez de apretar cuatro columnas.
class _Cuadre extends StatelessWidget {
  final CierreCaja cierre;
  const _Cuadre({required this.cierre});

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    if (c.cuadre.isEmpty) {
      return Text('Sin ventas en este corte', style: _t(14.5, FontWeight.w400, _C.muted));
    }
    final media = MediaQuery.of(context);
    final apretado = media.size.width < 400 || media.textScaler.scale(14.5) > 14.5 * 1.15;

    Text dif(FilaCuadre f) {
      final d = f.diferencia;
      if (d == null) return Text('—', style: _t(14.5, FontWeight.w400, _C.muted), textAlign: TextAlign.right);
      final color = d < -0.01 ? _C.bad : (d > 0.01 ? _C.gift : _C.ink);
      final peso = d.abs() > 0.01 ? FontWeight.w700 : FontWeight.w400;
      return Text(_q(c.signo, d), style: _t(14.5, peso, color), textAlign: TextAlign.right);
    }

    Text monto(double? v) => Text(
          v == null ? '—' : _q(c.signo, v),
          style: _t(14.5, FontWeight.w400, v == null ? _C.muted : _C.ink),
          textAlign: TextAlign.right,
        );

    if (apretado) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < c.cuadre.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(c.cuadre[i].metodo, style: _t(14.5, FontWeight.w600, _C.ink))),
                      const SizedBox(width: 8),
                      // Con una diferencia enorme la letra se achica en vez de salirse.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: dif(c.cuadre[i])),
                      ),
                    ],
                  ),
                  Text(
                    'Esperado ${_q(c.signo, c.cuadre[i].esperado)} · Contado '
                    '${c.cuadre[i].contado == null ? '—' : _q(c.signo, c.cuadre[i].contado!)}',
                    style: _t(12.5, FontWeight.w400, _C.muted),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final encabezado = _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.48);
    Widget celda(Widget w, {bool izq = true}) =>
        Padding(padding: EdgeInsets.only(left: izq ? 0 : 16, bottom: 6), child: w);

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          celda(Text('MÉTODO', style: encabezado)),
          celda(Text('ESPERADO', style: encabezado, textAlign: TextAlign.right), izq: false),
          celda(Text('CONTADO', style: encabezado, textAlign: TextAlign.right), izq: false),
          celda(Text('DIFERENCIA', style: encabezado, textAlign: TextAlign.right), izq: false),
        ]),
        for (final f in c.cuadre)
          TableRow(children: [
            celda(Text(f.metodo, style: _t(14.5, FontWeight.w400, _C.ink))),
            celda(monto(f.esperado), izq: false),
            celda(monto(f.contado), izq: false),
            celda(dif(f), izq: false),
          ]),
      ],
    );
  }
}

class _Aclaracion extends StatelessWidget {
  final String texto;
  const _Aclaracion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: _C.warn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: _t(13.5, FontWeight.w400, _C.ink, height: 1.4),
                children: [
                  TextSpan(text: 'Aclaración: ', style: _t(13.5, FontWeight.w700, _C.ink, height: 1.4)),
                  TextSpan(text: texto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Efectivo en caja": del fondo a lo que debe haber en la gaveta, y el total con
/// los demás métodos.
class _EfectivoEnCaja extends StatelessWidget {
  final CierreCaja cierre;
  const _EfectivoEnCaja({required this.cierre});

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    final s = c.signo;

    Widget linea(String etiqueta, String valor, {bool total = false, double arriba = 0}) {
      final fila = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(etiqueta, style: _t(14.5, total ? FontWeight.w700 : FontWeight.w400, total ? _C.ink : _C.muted)),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(valor, maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)),
            ),
          ),
        ],
      );
      return Container(
        margin: EdgeInsets.only(top: arriba),
        padding: EdgeInsets.only(top: total ? 10 : 6, bottom: 6),
        decoration: total ? BoxDecoration(border: Border(top: BorderSide(color: _C.line))) : null,
        child: fila,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        linea('Apertura', _q(s, c.apertura)),
        linea('Venta en efectivo', _q(s, c.ventasEfectivo)),
        linea('Depósitos', c.depositos != 0 ? _q(s, c.depositos) : '—'),
        linea('Retiros', c.retiros != 0 ? _q(s, -c.retiros) : '—'),
        linea('Total efectivo', _q(s, c.totalEfectivo), total: true, arriba: 4),
        for (var i = 0; i < c.otrosMetodos.length; i++)
          linea(c.otrosMetodos[i].$1, _q(s, c.otrosMetodos[i].$2), arriba: i == 0 ? 6 : 0),
        linea('Total (con apertura)', _q(s, c.totalConApertura), total: true, arriba: 4),
      ],
    );
  }
}
