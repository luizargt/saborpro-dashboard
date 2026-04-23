import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';

class SummaryTable extends StatelessWidget {
  final PeriodMetrics metrics;
  const SummaryTable({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    String q(double v) => 'Q${fmt.format(v)}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SectionHeader('Ingresos'),
          _Row(label: 'Ventas brutas', value: q(metrics.grossSales), bold: true),
          _Row(label: 'Descuentos', value: q(metrics.discounts), negative: true),
          if (metrics.refunds > 0)
            _Row(label: 'Reembolsos', value: q(metrics.refunds), negative: true),
          const _Divider(),
          _Row(label: 'Ventas netas', value: q(metrics.netSales), bold: true),
          if (metrics.tips > 0)
            _Row(label: 'Propinas', value: q(metrics.tips)),
          const _Divider(),
          _Row(
            label: 'Total cobrado',
            value: q(metrics.totalSales),
            bold: true,
            highlight: true,
          ),
          if (metrics.totalCosts > 0) ...[
            _SectionHeader('Costos y gastos'),
            if (metrics.purchaseCosts > 0)
              _Row(label: 'Compras / insumos', value: q(metrics.purchaseCosts), negative: true),
            if (metrics.operationalExpenses > 0)
              _Row(label: 'Gastos operacionales', value: q(metrics.operationalExpenses), negative: true),
            const _Divider(),
            _Row(
              label: 'Utilidad estimada',
              value: q(metrics.operatingProfit),
              bold: true,
              profit: true,
              negative: metrics.operatingProfit < 0,
            ),
          ],
          _SectionHeader('Resumen'),
          _Row(label: 'Número de tickets', value: '${metrics.totalOrders}'),
          _Row(label: 'Ticket promedio', value: q(metrics.avgTicket)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool negative;
  final bool highlight;
  final bool profit;

  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.negative = false,
    this.highlight = false,
    this.profit = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = highlight
        ? const Color(0xFF7444fd)
        : profit
            ? const Color(0xFF22C55E)
            : negative
                ? const Color(0xFFEF4444)
                : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x0AFFFFFF))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: bold ? Colors.white : Colors.white70,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: Color(0x33FFFFFF), height: 1, thickness: 1);
  }
}
