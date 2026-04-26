import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/models/dashboard_data.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/period_selector.dart';
import '../../../presentation/widgets/location_selector.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return RefreshIndicator(
      color: const Color(0xFF7444fd),
      backgroundColor: const Color(0xFF1E293B),
      onRefresh: provider.load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(builder: (ctx) {
                    final wide = MediaQuery.of(ctx).size.width >= 600;
                    if (wide) {
                      return const Row(
                        children: [
                          Expanded(child: DateNavigator()),
                          SizedBox(width: 8),
                          LocationSelector(),
                        ],
                      );
                    }
                    return const DateNavigator();
                  }),
                  const SizedBox(height: 16),
                  if (provider.loading)
                    const SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF7444fd)),
                      ),
                    )
                  else if (provider.error != null)
                    SizedBox(
                      height: 300,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
                            const SizedBox(height: 12),
                            Text(provider.error!,
                                style: const TextStyle(color: Colors.white54),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: provider.load,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7444fd)),
                              child: const Text('Reintentar',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (provider.metrics == null)
                    const SizedBox(
                      height: 300,
                      child: Center(
                        child: Text('Sin datos', style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  else
                    _ExpensesContent(metrics: provider.metrics!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensesContent extends StatelessWidget {
  final PeriodMetrics metrics;
  const _ExpensesContent({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    String q(double v) => 'Q${fmt.format(v)}';

    final hasExpenses = metrics.operationalExpenses > 0;
    final hasCosts = metrics.purchaseCosts > 0;
    final totalCosts = metrics.operationalExpenses + metrics.purchaseCosts;
    final profit = metrics.totalSales - totalCosts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Resumen rápido
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Ingresos',
                value: q(metrics.totalSales),
                color: const Color(0xFF22C55E),
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'Total gastos',
                value: q(totalCosts),
                color: const Color(0xFFEF4444),
                icon: Icons.trending_down,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          label: 'Utilidad estimada',
          value: q(profit),
          color: profit >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          icon: profit >= 0 ? Icons.savings_outlined : Icons.money_off_outlined,
          large: true,
        ),
        const SizedBox(height: 20),
        // Detalle de gastos
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Detalle de gastos',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (!hasExpenses && !hasCosts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Sin gastos registrados en este período',
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                )
              else ...[
                if (hasCosts)
                  _ExpenseRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Compras / insumos',
                    value: q(metrics.purchaseCosts),
                    color: const Color(0xFFF97316),
                  ),
                if (hasExpenses)
                  _ExpenseRow(
                    icon: Icons.payments_outlined,
                    label: 'Gastos operacionales',
                    value: q(metrics.operationalExpenses),
                    color: const Color(0xFFEF4444),
                  ),
                const Divider(color: Color(0x33FFFFFF), height: 24, thickness: 1),
                _ExpenseRow(
                  icon: Icons.summarize_outlined,
                  label: 'Total gastos',
                  value: q(totalCosts),
                  color: Colors.white,
                  bold: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool large;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(large ? 20 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: large ? 40 : 36,
            height: large ? 40 : 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: large ? 20 : 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: large ? 12 : 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: large ? 20 : 16,
                    fontWeight: FontWeight.w700,
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

class _ExpenseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _ExpenseRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withOpacity(0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: bold ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
