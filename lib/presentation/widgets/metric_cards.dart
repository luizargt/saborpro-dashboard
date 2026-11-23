import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import 'inicio_ui.dart';

// Rediseño 2026-11-20 (inicio-manager.html, modo oscuro). Qué se muestra no
// cambia, salvo lo que se dice en cada pieza: las cifras salen de las mismas
// métricas de siempre.

typedef _C = InicioColores;
const _t = inicioTexto;

final _fmt = NumberFormat('#,##0.00', 'en_US');
final _fmtInt = NumberFormat('#,##0', 'en_US');
String _q(double v) => '$moneda${_fmt.format(v)}';

String _cobros(int n) => '$n cobro${n == 1 ? '' : 's'}';

/// Los tres números de arriba (venta bruta, tickets y promedio) y las tarjetas
/// rápidas debajo, juntos. La pantalla los usa por separado para poner en medio
/// lo que requiere atención; esto queda para quien los quiera de una pieza.
class MetricCards extends StatelessWidget {
  final PeriodMetrics metrics;

  /// Abre el detalle de cortesías. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onCourtesyTap;

  /// Abre el detalle de propinas. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onTipsTap;

  /// Abre el detalle de descuentos. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onDiscountTap;

  /// Cobros que llevaron descuento (sale de los pedidos del período).
  final int descuentosCount;

  const MetricCards({
    super.key,
    required this.metrics,
    this.onCourtesyTap,
    this.onTipsTap,
    this.onDiscountTap,
    this.descuentosCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        KpiCards(metrics: metrics),
        const SizedBox(height: 12),
        TarjetasRapidas(
          metrics: metrics,
          onCourtesyTap: onCourtesyTap,
          onTipsTap: onTipsTap,
          onDiscountTap: onDiscountTap,
          descuentosCount: descuentosCount,
        ),
      ],
    );
  }
}

// ── LOS TRES NÚMEROS ─────────────────────────────────────────────────────────

/// Venta bruta, tickets y promedio, cada uno contra el período anterior. En
/// teléfono van uno debajo del otro (el diseño los apila); en pantalla ancha,
/// los tres en fila.
class KpiCards extends StatelessWidget {
  final PeriodMetrics metrics;

  const KpiCards({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return LayoutBuilder(builder: (context, c) {
      final telefono = c.maxWidth <= kInicioQuiebreTelefono;
      final tarjetas = [
        _Kpi(
          etiqueta: 'Venta bruta',
          valor: _q(m.ventaBruta),
          cambio: m.salesChangePercent,
          anterior: 'vs anterior: ${_q(m.prevTotalSales)}',
          telefono: telefono,
          principal: true,
        ),
        _Kpi(
          etiqueta: 'Tickets',
          valor: _fmtInt.format(m.totalOrders),
          cambio: m.ordersChangePercent,
          anterior: 'vs anterior: ${_fmtInt.format(m.prevTotalOrders)}',
          telefono: telefono,
        ),
        _Kpi(
          etiqueta: 'Promedio',
          valor: _q(m.avgTicket),
          cambio: m.avgTicketChangePercent,
          anterior: 'vs anterior: ${_q(m.prevAvgTicket)}',
          telefono: telefono,
        ),
      ];

      if (telefono) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tarjetas.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              tarjetas[i],
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tarjetas.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: tarjetas[i]),
            ],
          ],
        ),
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double cambio;
  final String anterior;
  final bool telefono;

  /// La primera tarjeta: en teléfono su cifra es más grande que las otras.
  final bool principal;

  const _Kpi({
    required this.etiqueta,
    required this.valor,
    required this.cambio,
    required this.anterior,
    required this.telefono,
    this.principal = false,
  });

  @override
  Widget build(BuildContext context) {
    final tamano = telefono && !principal ? 24.0 : 32.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: telefono ? 16 : 22, vertical: telefono ? 16 : 20),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: _t(13.5, FontWeight.w600, _C.muted)),
          const SizedBox(height: 4),
          // Con una cifra enorme la letra se achica en vez de salirse de la
          // tarjeta.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: _t(tamano, FontWeight.w800, _C.ink, height: 1.2).copyWith(letterSpacing: -0.01 * tamano),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _Cambio(cambio),
              Text(anterior, style: _t(13, FontWeight.w400, _C.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// La pastilla del cambio contra el período anterior: verde si subió, roja si
/// bajó y apagada si quedó igual.
class _Cambio extends StatelessWidget {
  final double cambio;
  const _Cambio(this.cambio);

  @override
  Widget build(BuildContext context) {
    final igual = cambio == 0;
    final sube = cambio > 0;
    final color = igual ? _C.soft : (sube ? _C.gift : _C.bad);
    final fondo = igual ? _C.subtle : (sube ? _C.giftTint : _C.badTint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            igual ? Icons.remove_rounded : (sube ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Text('${cambio.abs().toStringAsFixed(1)}%', style: _t(13, FontWeight.w700, color)),
        ],
      ),
    );
  }
}

// ── LAS TARJETAS RÁPIDAS ─────────────────────────────────────────────────────

class _Datos {
  final String etiqueta;
  final String valor;
  final String detalle;
  final Color color;
  final VoidCallback? onTap;

  const _Datos({
    required this.etiqueta,
    required this.valor,
    required this.detalle,
    required this.color,
    this.onTap,
  });
}

/// Propinas, cortesías, descuentos y cobro de envío. En el teléfono cada una es
/// una fila (la etiqueta a la izquierda y la cifra a la derecha); en pantalla
/// ancha, una tarjeta por columna.
///
/// Solo llevan flecha las que se pueden abrir (hoy, propinas, cortesías y
/// descuentos): una flecha que no lleva a ningún lado engaña.
class TarjetasRapidas extends StatelessWidget {
  final PeriodMetrics metrics;
  final VoidCallback? onCourtesyTap;
  final VoidCallback? onTipsTap;
  final VoidCallback? onDiscountTap;
  final int descuentosCount;

  const TarjetasRapidas({
    super.key,
    required this.metrics,
    this.onCourtesyTap,
    this.onTipsTap,
    this.onDiscountTap,
    this.descuentosCount = 0,
  });

  List<_Datos> _tarjetas() {
    final m = metrics;
    // Cortesías y descuentos viven dentro de los renglones del ticket: en la
    // vista de año no se pueden calcular y mostrarlos en cero sería mentir.
    final conDetalle = m.detailAvailable;

    String propinas() {
      if (m.tipsCount > 0) return _cobros(m.tipsCount);
      // Solo cuando TODAS son de las metidas a la caja como ingreso (no son
      // cobros). Con propinas de tickets y sin saber en cuántos cobros (la vista
      // de año las suma en el servidor), decirlo sería falso.
      if (m.tips <= 0 && m.tipsOutsideSales > 0) return 'Metidas a la caja';
      if (m.allTips > 0) return '';
      return 'Sin propinas';
    }

    return [
      if (conDetalle || m.allTips > 0)
        _Datos(
          etiqueta: 'Propinas',
          valor: _q(m.allTips),
          detalle: propinas(),
          color: _C.warn,
          onTap: onTipsTap,
        ),
      if (conDetalle)
        _Datos(
          etiqueta: 'Cortesías / Donaciones',
          valor: _q(m.courtesyTotal),
          detalle: m.courtesyCount > 0 ? _cobros(m.courtesyCount) : 'Ninguna',
          color: _C.gift,
          onTap: onCourtesyTap,
        ),
      if (conDetalle)
        _Datos(
          etiqueta: 'Descuentos',
          valor: _q(m.discounts),
          // Con descuento y sin saber en cuántos cobros (quien arma esto no
          // contó los pedidos), no se dice nada: "Ningún descuento" junto a un
          // monto sería una contradicción.
          detalle: m.discounts <= 0
              ? 'Ningún descuento'
              : (descuentosCount > 0 ? _cobros(descuentosCount) : ''),
          color: _C.don,
          onTap: onDiscountTap,
        ),
      if (m.deliveryFees > 0)
        _Datos(
          etiqueta: 'Cobro Envío Domicilio',
          valor: _q(m.deliveryFees),
          detalle: m.deliveryCount > 0 ? _cobros(m.deliveryCount) : '',
          color: _C.accent,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = _tarjetas();
    if (tarjetas.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      if (ancho <= kInicioQuiebreTelefono) {
        final reservar = tarjetas.any((t) => t.onTap != null);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tarjetas.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _TarjetaFila(tarjetas[i], reservarFlecha: reservar),
            ],
          ],
        );
      }

      // 2 columnas hasta 1100 de ancho; después, una por tarjeta (hasta 4).
      final columnas = ancho >= 1100 ? tarjetas.length.clamp(1, 4) : 2;
      final filas = <List<_Datos>>[];
      for (var i = 0; i < tarjetas.length; i += columnas) {
        filas.add(tarjetas.sublist(i, (i + columnas).clamp(0, tarjetas.length)));
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
                      child: i < filas[f].length ? _TarjetaColumna(filas[f][i]) : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Punto extends StatelessWidget {
  final Color color;
  const _Punto(this.color);

  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

Widget get _flecha => Icon(Icons.chevron_right_rounded, color: _C.soft, size: 20);

/// Pantalla ancha: la etiqueta arriba, la cifra grande y el detalle debajo.
class _TarjetaColumna extends StatelessWidget {
  final _Datos d;
  const _TarjetaColumna(this.d);

  @override
  Widget build(BuildContext context) {
    return InicioToque(
      onTap: d.onTap,
      radio: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Punto(d.color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    d.etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(14.5, FontWeight.w400, _C.muted),
                  ),
                ),
                if (d.onTap != null) _flecha,
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(d.valor, maxLines: 1, style: _t(24, FontWeight.w800, d.color, height: 1.25)),
            ),
            if (d.detalle.isNotEmpty)
              Text(d.detalle, style: _t(12.5, FontWeight.w500, _C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Teléfono: una fila baja, con la etiqueta a la izquierda y la cifra y su
/// detalle a la derecha.
class _TarjetaFila extends StatelessWidget {
  final _Datos d;

  /// Deja el lugar de la flecha en todas las filas, para que las cifras queden
  /// alineadas aunque no todas se puedan abrir.
  final bool reservarFlecha;

  const _TarjetaFila(this.d, {required this.reservarFlecha});

  @override
  Widget build(BuildContext context) {
    return InicioToque(
      onTap: d.onTap,
      radio: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        // La cifra tiene prioridad sobre la etiqueta, pero nunca pasa del 60%
        // de la fila: con una cantidad enorme se achica en vez de salirse.
        child: LayoutBuilder(builder: (context, c) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Punto(d.color),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        d.etiqueta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(14.5, FontWeight.w400, _C.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(d.valor, maxLines: 1, style: _t(19, FontWeight.w800, d.color, height: 1.25)),
                    ),
                    if (d.detalle.isNotEmpty)
                      Text(
                        d.detalle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: _t(12.5, FontWeight.w500, _C.muted),
                      ),
                  ],
                ),
              ),
              if (reservarFlecha) SizedBox(width: 28, child: d.onTap != null ? _flecha : null),
            ],
          );
        }),
      ),
    );
  }
}
