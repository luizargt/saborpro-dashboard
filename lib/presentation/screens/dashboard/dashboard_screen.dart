import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/date_range.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/location_selector.dart';
import '../../../presentation/widgets/metric_cards.dart';
import '../../../presentation/widgets/location_sales_breakdown.dart';
import '../../../presentation/widgets/top_categories_carousel.dart';
import '../../../presentation/widgets/max_content_width.dart';
import '../../../presentation/widgets/sales_chart.dart';
import '../../../presentation/widgets/products_list.dart';
import '../../../presentation/widgets/summary_table.dart';
import '../../../presentation/widgets/payment_method_breakdown.dart';
import '../../../presentation/widgets/year_detail_notice.dart';

enum DashboardView { chart, table }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardView _view = DashboardView.chart;

  @override
  Widget build(BuildContext context) {
    return _DashboardBody(
      view: _view,
      onViewChanged: (v) => setState(() => _view = v),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final DashboardView view;
  final ValueChanged<DashboardView> onViewChanged;

  const _DashboardBody({
    required this.view,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return LocationSwipeArea(
      child: MaxContentWidth(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de sucursales fija: queda fuera del scroll para seguir
          // visible mientras se recorre el contenido.
          const LocationHeaderBar(),
          Expanded(
            child: LocationContentSwitcher(
              child: RefreshIndicator(
              color: const Color(0xFF7444fd),
              backgroundColor: const Color(0xFF1E293B),
              onRefresh: provider.refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (provider.loading)
                            const _LoadingState()
                          else if (provider.error != null)
                            _ErrorState(error: provider.error!, onRetry: provider.load)
                          else if (provider.metrics != null)
                            _DataContent(
                              provider: provider,
                              view: view,
                              onViewChanged: onViewChanged,
                            )
                          else
                            const _EmptyState(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
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
    final wide = MediaQuery.of(context).size.width >= 900;
    // Solo existe en la vista de año, y solo si el dueño lo mandó calcular.
    final detalle = provider.yearDetail;
    final categorias = detalle?.categoriesByClassification.isNotEmpty == true
        ? detalle!.categoriesByClassification
        : metrics.categoriesByClassification;

    final metodos = detalle != null && detalle.salesByMethod.isNotEmpty
        ? detalle.salesByMethod
        : metrics.salesByMethod;
    final paymentCard = metodos.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: PaymentMethodBreakdown(
              salesByMethod: metodos,
              customMethodNames: {
                for (final r in provider.openRegisters) ...r.customMethodNames,
                for (final r in provider.closedRegisters) ...r.customMethodNames,
              },
            ),
          );

    // En la vista de año no hay órdenes en memoria, así que la venta por
    // sucursal viene ya sumada por Firestore. Sin eso este bloque saldría con
    // todas las sucursales en cero.
    final locationsCard = provider.selectedLocationId != null
        ? null
        : LocationSalesBreakdown(
            locations: provider.locations,
            orders: provider.currentOrders,
            expenseItems: provider.expenseItems,
            purchaseItems: provider.purchaseItems,
            precomputedSales: provider.yearSalesByLocation,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricCards(metrics: metrics),
        // Método de pago y sucursales: apilados en móvil, lado a lado en
        // pantalla ancha para no dejar barras de un extremo al otro.
        if (paymentCard != null || locationsCard != null) ...[
          const SizedBox(height: 20),
          if (wide && paymentCard != null && locationsCard != null)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: paymentCard),
                  const SizedBox(width: 20),
                  Expanded(child: locationsCard),
                ],
              ),
            )
          else ...[
            if (paymentCard != null) paymentCard,
            if (paymentCard != null && locationsCard != null)
              const SizedBox(height: 20),
            if (locationsCard != null) locationsCard,
          ],
        ],
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
                  Expanded(
                    child: Text(
                      view == DashboardView.chart || !metrics.detailAvailable
                          ? _chartTitle(provider.range.mode)
                          : 'Resumen financiero',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // El resumen financiero desglosa descuentos, impuestos y
                  // cortesías, y eso vive dentro de cada ticket. En la vista de
                  // año no hay tickets en memoria, así que el botón se esconde
                  // en vez de abrir una tabla llena de ceros.
                  if (metrics.detailAvailable)
                    _ViewToggle(view: view, onChanged: onViewChanged),
                ],
              ),
              const SizedBox(height: 16),
              if (view == DashboardView.chart || !metrics.detailAvailable)
                SalesChart(
                  points: metrics.chartPoints,
                  prevPoints: metrics.prevChartPoints,
                  mode: provider.range.mode,
                  weeklyHourly: provider.weeklyHourly,
                  monthlyDailyPoints: provider.monthlyDailyPoints,
                )
              else
                SummaryTable(metrics: metrics),
            ],
          ),
        ),
        // En la vista de año estas salen del detalle que el dueño mandó
        // calcular; en los demás períodos ya vienen en las métricas.
        if (categorias.isNotEmpty) ...[
          const SizedBox(height: 20),
          TopCategoriesCarousel(categoriesByClassification: categorias),
        ],
        const SizedBox(height: 20),
        if (metrics.detailAvailable || detalle != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ProductsList(
              products: detalle?.topProducts ?? metrics.topProducts,
              productsByMethod: metrics.productsByMethod,
              prevLabel: provider.range.prevLabel,
              tips: metrics.tips,
              discounts: metrics.discounts,
              totalSales: metrics.totalSales,
            ),
          )
        else
          YearDetailNotice(mes: provider.mesDetalle),
        const SizedBox(height: 32),
      ],
    );
  }

  String _chartTitle(PeriodMode mode) {
    switch (mode) {
      case PeriodMode.day: return 'Ventas por hora';
      case PeriodMode.week: return 'Ventas de cada semana del mes';
      case PeriodMode.month: return 'Ventas de cada semana · vs mes pasado';
      case PeriodMode.year: return 'Ventas por mes · vs año pasado';
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
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
