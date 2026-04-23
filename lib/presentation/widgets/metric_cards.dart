import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';

class MetricCards extends StatelessWidget {
  final PeriodMetrics metrics;
  const MetricCards({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final fmtInt = NumberFormat('#,##0', 'en_US');

    final showTips = metrics.tips > 0;
    final showDelivery = metrics.deliveryFees > 0;

    return Column(
      children: [
        // Fila principal
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Venta Bruta',
                value: 'Q${fmt.format(metrics.ventaBruta)}',
                change: metrics.salesChangePercent,
                prevLabel: 'vs anterior: Q${fmt.format(metrics.prevTotalSales)}',
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
                value: 'Q${fmt.format(metrics.avgTicket)}',
                change: metrics.avgTicketChangePercent,
                prevLabel: 'vs anterior: Q${fmt.format(metrics.prevAvgTicket)}',
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
                    value: 'Q${fmt.format(metrics.tips)}',
                    accent: const Color(0xFFF59E0B),
                  ),
                ),
              ],
              if (showTips && showDelivery) const SizedBox(width: 10),
              if (showDelivery) ...[
                Expanded(
                  child: _CompactMetricCard(
                    label: 'Cobros delivery',
                    value: 'Q${fmt.format(metrics.deliveryFees)}',
                    accent: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _CompactMetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
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
        ],
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
                color: Colors.white24,
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
