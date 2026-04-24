import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/date_range.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/period_selector.dart';
import '../../../presentation/widgets/location_selector.dart';
import '../../../presentation/widgets/metric_cards.dart';
import '../../../presentation/widgets/sales_chart.dart';
import '../../../presentation/widgets/products_list.dart';
import '../../../presentation/widgets/summary_table.dart';
import '../../../presentation/widgets/payment_method_breakdown.dart';
import 'cajas_screen.dart';

enum DashboardView { chart, table }
enum DashboardTab { resumen, cajas }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardView _view = DashboardView.chart;
  DashboardTab _tab = DashboardTab.resumen;

  @override
  Widget build(BuildContext context) {
    return _DashboardBody(
      view: _view,
      onViewChanged: (v) => setState(() => _view = v),
      tab: _tab,
      onTabChanged: (t) => setState(() => _tab = t),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final DashboardView view;
  final ValueChanged<DashboardView> onViewChanged;
  final DashboardTab tab;
  final ValueChanged<DashboardTab> onTabChanged;

  const _DashboardBody({
    required this.view,
    required this.onViewChanged,
    required this.tab,
    required this.onTabChanged,
  });

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
                  // Fecha: ancho completo en móvil, comparte con sucursal en desktop
                  Builder(builder: (ctx) {
                    final wide = MediaQuery.of(ctx).size.width >= 600;
                    if (wide) {
                      return Row(
                        children: [
                          const Expanded(child: DateNavigator()),
                          const SizedBox(width: 8),
                          const LocationSelector(),
                        ],
                      );
                    }
                    return const DateNavigator();
                  }),
                  const SizedBox(height: 12),
                  // Tab selector
                  _TabSelector(tab: tab, onChanged: onTabChanged),
                  const SizedBox(height: 16),
                  // Contenido
                  if (provider.loading)
                    const _LoadingState()
                  else if (provider.error != null)
                    _ErrorState(error: provider.error!, onRetry: provider.load)
                  else if (tab == DashboardTab.resumen)
                    provider.metrics != null
                        ? _DataContent(
                            provider: provider,
                            view: view,
                            onViewChanged: onViewChanged,
                          )
                        : const _EmptyState()
                  else
                    CajasScreen(
                      open: provider.openRegisters,
                      closed: provider.closedRegisters,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabSelector extends StatelessWidget {
  final DashboardTab tab;
  final ValueChanged<DashboardTab> onChanged;

  const _TabSelector({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tab(DashboardTab.resumen, 'Resumen'),
          _tab(DashboardTab.cajas, 'Cajas'),
        ],
      ),
    );
  }

  Widget _tab(DashboardTab t, String label) {
    final active = tab == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7444fd) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: active ? Colors.white : Colors.white54,
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _DataContent extends StatelessWidget {
  final DashboardProvider provider;
  final DashboardView view;
  final ValueChanged<DashboardView> onViewChanged;

  const _DataContent({
    required this.provider,
    required this.view,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = provider.metrics!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricCards(metrics: metrics),
        const SizedBox(height: 20),
        // Toggle pegado al contenido de visualización
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header con título + toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    view == DashboardView.chart ? _chartTitle(provider.range.mode) : 'Resumen financiero',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _ViewToggle(view: view, onChanged: onViewChanged),
                ],
              ),
              const SizedBox(height: 16),
              if (view == DashboardView.chart)
                SalesChart(
                  points: metrics.chartPoints,
                  mode: provider.range.mode,
                  weeklyHourly: provider.weeklyHourly,
                  monthlyDailyPoints: provider.monthlyDailyPoints,
                )
              else
                SummaryTable(metrics: metrics),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Desglose por método de pago
        if (metrics.salesByMethod.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: PaymentMethodBreakdown(
              salesByMethod: metrics.salesByMethod,
              customMethodNames: {
                for (final r in provider.openRegisters) ...r.customMethodNames,
                for (final r in provider.closedRegisters) ...r.customMethodNames,
              },
            ),
          ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ProductsList(
            products: metrics.topProducts,
            prevLabel: provider.range.prevLabel,
            tips: metrics.tips,
            discounts: metrics.discounts,
            totalSales: metrics.totalSales,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  String _chartTitle(PeriodMode mode) {
    switch (mode) {
      case PeriodMode.day: return 'Ventas por hora — semana actual';
      case PeriodMode.week: return 'Ventas por semana';
      case PeriodMode.month: return 'Ventas por semana';
      case PeriodMode.year: return 'Ventas por mes';
      case PeriodMode.custom: return 'Ventas del período';
    }
  }
}

class _ViewToggle extends StatelessWidget {
  final DashboardView view;
  final ValueChanged<DashboardView> onChanged;

  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.bar_chart, DashboardView.chart),
          _btn(Icons.table_rows_outlined, DashboardView.table),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, DashboardView v) {
    final active = view == v;
    return GestureDetector(
      onTap: () => onChanged(v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7444fd) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: active ? Colors.white : Colors.white38),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(color: Color(0xFF7444fd))),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              Text(error,
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7444fd)),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 300,
        child: Center(
            child: Text('Sin datos',
                style: TextStyle(color: Colors.white38))),
      );
}
