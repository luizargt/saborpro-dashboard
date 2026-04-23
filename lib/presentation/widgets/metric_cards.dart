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

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Ventas',
                value: 'Q${fmt.format(metrics.totalSales)}',
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
        if (metrics.tips > 0) ...[
          const SizedBox(height: 10),
          _MetricCard(
            label: 'Propinas',
            value: 'Q${fmt.format(metrics.tips)}',
            change: 0,
            prevLabel: '',
            fullWidth: true,
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final double change;
  final String prevLabel;
  final bool fullWidth;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.change,
    required this.prevLabel,
    this.fullWidth = false,
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
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
      ),
    );
  }
}
