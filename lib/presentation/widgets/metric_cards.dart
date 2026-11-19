import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';

class MetricCards extends StatelessWidget {
  final PeriodMetrics metrics;

  /// Abre el detalle de cortesías. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onCourtesyTap;

  const MetricCards({super.key, required this.metrics, this.onCourtesyTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final fmtInt = NumberFormat('#,##0', 'en_US');

    // Con las propinas metidas a la caja como ingreso (no son ventas).
    final showTips     = metrics.allTips > 0;
    final showDelivery = metrics.deliveryFees > 0;
    final showCourtesy = metrics.courtesyTotal > 0;

    return Column(
      children: [
        // Fila principal
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Venta Bruta',
                value: '$moneda${fmt.format(metrics.ventaBruta)}',
                change: metrics.salesChangePercent,
                prevLabel: 'vs anterior: $moneda${fmt.format(metrics.prevTotalSales)}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Tickets',
                value: fmtInt.format(metrics.totalOrders),
                change: metrics.ordersChangePercent,
                prevLabel: 'vs anterior: ${fmtInt.format(metrics.prevTotalOrders)}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Promedio',
                value: '$moneda${fmt.format(metrics.avgTicket)}',
                change: metrics.avgTicketChangePercent,
                prevLabel: 'vs anterior: $moneda${fmt.format(metrics.prevAvgTicket)}',
              ),
            ),
          ],
        ),
        // Fila propinas + delivery (solo si hay datos)
        if (showTips || showDelivery) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (showTips) ...[
                Expanded(
                  child: _CompactMetricCard(
                    label: 'Propinas',
                    value: '$moneda${fmt.format(metrics.allTips)}',
                    // "N cobros" son tickets: las de la caja no son cobros.
                    count: metrics.tipsCount,
                    accent: const Color(0xFFF59E0B),
                  ),
                ),
              ],
              if (showTips && showDelivery) const SizedBox(width: 10),
              if (showDelivery) ...[
                Expanded(
                  child: _CompactMetricCard(
                    label: 'Cobro Envío Domicilio',
                    value: '$moneda${fmt.format(metrics.deliveryFees)}',
                    count: metrics.deliveryCount,
                    accent: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ],
          ),
        ],
        // Fila cortesías (solo si hay)
        if (showCourtesy) ...[
          const SizedBox(height: 10),
          _CompactMetricCard(
            label: 'Cortesías / Donaciones',
            value: '$moneda${fmt.format(metrics.courtesyTotal)}',
            count: metrics.courtesyCount,
            accent: const Color(0xFF14B8A6),
            onTap: onCourtesyTap,
          ),
        ],
      ],
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final int count;
  final Color accent;

  /// Con esto la tarjeta se puede tocar y lleva una flecha que lo dice.
  final VoidCallback? onTap;

  const _CompactMetricCard({
    required this.label,
    required this.value,
    this.count = 0,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contenido = Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count > 0)
                Text(
                  '$count cobro${count == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white54, size: 20),
          ],
        ],
    );

    if (onTap == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.3), width: 1),
        ),
        child: contenido,
      );
    }

    // Material + InkWell en vez del Container: con el color en el Container
    // la onda del toque quedaba tapada y no se notaba que se tocó.
    return Material(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.3), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Un punto más que el Container de las otras: ahí el borde de 1 se
          // suma al relleno, aquí no, y la tarjeta salía 2 puntos más baja.
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          child: contenido,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final double change;
  final String prevLabel;
  final Color? accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.change,
    required this.prevLabel,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change >= 0;
    final changeColor = change == 0
        ? Colors.white38
        : isPositive
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);
    final changeIcon = change == 0
        ? Icons.remove
        : isPositive
            ? Icons.arrow_upward
            : Icons.arrow_downward;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: accent != null
            ? Border.all(color: accent!.withOpacity(0.3), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (accent != null)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: accent ?? Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (prevLabel.isEmpty)
            const SizedBox(height: 22)
          else ...[
            Row(
              children: [
                Icon(changeIcon, size: 12, color: changeColor),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    '${change.abs().toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      color: changeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              prevLabel,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
