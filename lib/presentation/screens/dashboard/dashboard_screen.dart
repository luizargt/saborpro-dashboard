import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/date_range.dart';
import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/atencion_inicio.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/inicio_atencion.dart';
import '../../../presentation/widgets/inicio_hospedaje.dart';
import '../../../presentation/widgets/inicio_ui.dart';
import '../../../presentation/widgets/location_selector.dart';
import '../../../presentation/widgets/metric_cards.dart';
import '../../../presentation/widgets/location_sales_breakdown.dart';
import '../../../presentation/widgets/moneda_vista_aviso.dart';
import '../../../presentation/widgets/period_selector.dart';
import '../../../presentation/widgets/top_categories_carousel.dart';
import '../../../presentation/widgets/max_content_width.dart';
import '../../../presentation/widgets/sales_chart.dart';
import '../../../presentation/widgets/products_list.dart';
import '../../../presentation/widgets/summary_table.dart';
import '../../../presentation/widgets/payment_method_breakdown.dart';
import '../../../presentation/widgets/year_detail_notice.dart';
import '../reports/cash_closures_report_screen.dart';
import 'cortesias_screen.dart';
import 'descuentos_screen.dart';
import 'propinas_screen.dart';
import '../../navigation/contexto_shell.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

enum DashboardView { chart, table }

/// El Inicio de Sabor Manager.
///
/// Rediseño 2026-11-20 (assets/Desing/Sabor Manager/inicio-manager.html de
/// saborpro_app, en su modo oscuro). Las cifras, los períodos, las sucursales y
/// la conversión de moneda son los de siempre: solo cambió cómo se ve, y se
/// sumaron dos bloques que salen de datos que ya estaban en memoria ("Requiere
/// tu atención" y "Cajas abiertas").
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardView _view = DashboardView.chart;

  @override
  void initState() {
    super.initState();
    // Las cuentas por cobrar son lo de AHORA: al volver al Inicio se vuelven a
    // mirar (sin repetir si se leyeron hace menos de un minuto).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<DashboardProvider>();
      provider.cargarCuentasAbiertas();
      provider.cargarHospedaje();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    // En la vista de año los pedidos no están en memoria: no hay nada que contar.
    final resumen = provider.metrics?.detailAvailable == true
        ? provider.resumenPedidos
        : ResumenPedidosInicio.vacio;

    return _DashboardBody(
      view: _view,
      resumenPedidos: resumen,
      onViewChanged: (v) => setState(() => _view = v),
    );
  }
}

void _abrirCierres(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CashClosuresReportScreen()));
}

class _DashboardBody extends StatelessWidget {
  final DashboardView view;
  final ResumenPedidosInicio resumenPedidos;
  final ValueChanged<DashboardView> onViewChanged;

  const _DashboardBody({
    required this.view,
    required this.resumenPedidos,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final pad = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono ? 16.0 : 20.0;

    // Material y no un ColoredBox: así las ondas de los toques se pintan sobre
    // el fondo en vez de quedar tapadas por él.
    return Material(
      color: kInicioBg,
      child: LocationSwipeArea(
        child: MaxContentWidth(
          maxWidth: 1240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Encabezado(),
              // Barra de sucursales fija: queda fuera del scroll para seguir
              // visible mientras se recorre el contenido.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [LocationTabsBar(), MonedaVistaAviso()],
                ),
              ),
              Expanded(
                child: LocationContentSwitcher(
                  child: RefreshIndicator(
                    color: _C.accent,
                    backgroundColor: _C.card,
                    onRefresh: provider.refresh,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
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
                                    resumenPedidos: resumenPedidos,
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
      ),
    );
  }
}

/// "Inicio" y, en pantalla ancha, el selector de fecha. En teléfono el selector
/// ya vive en la barra de arriba del shell: ponerlo aquí también lo duplicaría.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    // Dentro del shell el encabezado (migas, título y fecha) lo pone el shell.
    if (ContextoShell.enShell(context)) return const SizedBox.shrink();

    final ancho = MediaQuery.sizeOf(context).width;
    final telefono = ancho <= kInicioQuiebreTelefono;
    final conFecha = ancho >= 600;
    final pad = telefono ? 16.0 : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, telefono ? 12 : 16, pad, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Inicio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(telefono ? 22 : 24, FontWeight.w700, _C.ink, height: 1.2),
            ),
          ),
          if (conFecha) ...[
            const SizedBox(width: 14),
            const DateSelectorChip(),
          ],
        ],
      ),
    );
  }
}

class _DataContent extends StatelessWidget {
  final DashboardProvider provider;
  final DashboardView view;
  final ResumenPedidosInicio resumenPedidos;
  final ValueChanged<DashboardView> onViewChanged;

  const _DataContent({
    required this.provider,
    required this.view,
    required this.resumenPedidos,
    required this.onViewChanged,
  });

  static const _gap = SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    final metrics = provider.metrics!;
    final wide = MediaQuery.of(context).size.width >= 900;
    // Solo existe en la vista de año, y solo si el dueño lo mandó calcular.
    final detalle = provider.yearDetail;
    final categorias = detalle?.categoriesByClassification.isNotEmpty == true
        ? detalle!.categoriesByClassification
        : metrics.categoriesByClassification;

    final metodos = detalle != null && detalle.salesByMethod.isNotEmpty ? detalle.salesByMethod : metrics.salesByMethod;
    final paymentCard = metodos.isEmpty
        ? null
        : InicioCard(
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
    // todas las sucursales en cero. Con una sola sucursal no se dibuja (no hay
    // nada que repartir): se trata como que no está, para no dejarle su lugar
    // vacío al lado de "Ventas por método de pago".
    final locationsCard = provider.selectedLocationId != null || provider.locations.length <= 1
        ? null
        : LocationSalesBreakdown(
            locations: provider.locations,
            otras: provider.sucursalesOcultas,
            orders: provider.currentOrders,
            expenseItems: provider.expenseItems,
            purchaseItems: provider.purchaseItems,
            precomputedSales: provider.yearSalesByLocation,
            simboloConvertido: provider.convierte ? provider.simboloDe(provider.codigoPrincipal) : null,
            excluidas: {for (final l in provider.sucursalesSinTasa) l.id},
          );

    // Las cajas no se leyeron (falló la consulta): ni "0 cajas abiertas" ni
    // faltantes que no se pudieron ver. Callar es mejor que afirmar algo falso.
    final cajas = provider.cajasLeidas && provider.resumenCajasOk;
    final cuentas = provider.cuentasPorCobrar;
    final hospedaje = provider.hospedaje;
    final atencion = AtencionInicio.armar(
      cerradas: cajas ? provider.closedRegisters : const [],
      abiertas: cajas ? provider.openRegisters : const [],
      cortesiasSinMotivo: resumenPedidos.cortesiasSinMotivo,
      montoSinMotivo: resumenPedidos.montoSinMotivo,
      // Cada caja con el signo de su sucursal (no se convierten nunca); las
      // cortesías vienen en la moneda de la vista.
      signoDeCaja: (loc) => provider.locationSymbols[loc] ?? moneda,
      signoVista: moneda,
      ahora: DateTime.now(),
      mostrarSucursal: provider.locations.length > 1,
    );

    Widget tarjetaAtencion({bool llenarAlto = false}) => AtencionCard(
          items: atencion,
          llenarAlto: llenarAlto,
          onTap: (item) {
            switch (item.destino) {
              case DestinoAtencion.cierresDeCaja:
                _abrirCierres(context);
              case DestinoAtencion.cortesias:
                abrirCortesias(context);
            }
          },
        );

    // "Requiere tu atención" va después de las tarjetas rápidas, en el teléfono y en
    // la PC (el mismo orden en los dos). En pantalla ancha, al lado de "Ventas por
    // método de pago" y de su mismo alto: los avisos que no caben se desplazan
    // dentro de la tarjeta. Así no queda medio renglón vacío.
    final atencionAlLado = wide && paymentCard != null && atencion.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiCards(metrics: metrics),
        // Hospedaje: cómo están las habitaciones AHORA. Solo si alguna de las
        // sucursales que se miran vende habitaciones, y se calla si no se pudo leer.
        if (hospedaje != null) ...[
          _gap,
          HospedajeCard(resumen: hospedaje),
        ],
        // Lo que pasa AHORA: las cuentas pendientes de cobro y las cajas
        // abiertas. Cada una se calla sola si no se pudo leer.
        if (cuentas != null || cajas) ...[
          _gap,
          FilaAhora(
            tarjetas: [
              if (cuentas != null) CuentasAbiertasCard(resumen: cuentas),
              if (cajas) CajasAbiertasCard(abiertas: provider.openRegisters, onTap: () => _abrirCierres(context)),
            ],
          ),
        ],
        _gap,
        TarjetasRapidas(
          metrics: metrics,
          onCourtesyTap: () => abrirCortesias(context),
          onTipsTap: () => abrirPropinas(context),
          onDiscountTap: () => abrirDescuentos(context),
          descuentosCount: resumenPedidos.descuentos,
        ),
        if (atencionAlLado) ...[
          _gap,
          InicioLadoALado(izquierda: paymentCard, derecha: tarjetaAtencion(llenarAlto: true), altoMinimo: 200),
          if (locationsCard != null) ...[_gap, locationsCard],
        ] else ...[
          if (atencion.isNotEmpty) ...[_gap, tarjetaAtencion()],
          // Método de pago y sucursales: apilados en móvil, lado a lado en
          // pantalla ancha para no dejar barras de un extremo al otro.
          if (paymentCard != null || locationsCard != null) ...[
            _gap,
            if (wide && paymentCard != null && locationsCard != null)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: paymentCard),
                    const SizedBox(width: 16),
                    Expanded(child: locationsCard),
                  ],
                ),
              )
            else ...[
              if (paymentCard != null) paymentCard,
              if (paymentCard != null && locationsCard != null) _gap,
              if (locationsCard != null) locationsCard,
            ],
          ],
        ],
        _gap,
        // Toggle pegado al contenido de visualización
        InicioCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InicioTituloTarjeta(
                titulo: view == DashboardView.chart || !metrics.detailAvailable
                    ? _chartTitle(provider.range.mode)
                    : 'Resumen financiero',
                // El resumen financiero desglosa descuentos, impuestos y
                // cortesías, y eso vive dentro de cada ticket. En la vista de
                // año no hay tickets en memoria, así que el botón se esconde
                // en vez de abrir una tabla llena de ceros.
                derecha: metrics.detailAvailable ? _ViewToggle(view: view, onChanged: onViewChanged) : null,
              ),
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
          _gap,
          TopCategoriesCarousel(categoriesByClassification: categorias),
        ],
        _gap,
        if (metrics.detailAvailable || detalle != null)
          InicioCard(
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
        const SizedBox(height: 24),
      ],
    );
  }

  String _chartTitle(PeriodMode mode) {
    switch (mode) {
      case PeriodMode.day:
        return 'Ventas por hora';
      case PeriodMode.week:
        return 'Ventas de cada semana del mes';
      case PeriodMode.month:
        return 'Ventas de cada semana · vs mes pasado';
      case PeriodMode.year:
        return 'Ventas por mes · vs año pasado';
      case PeriodMode.custom:
        return 'Ventas del período';
    }
  }
}

/// El interruptor gráfica / tabla del diseño: la opción elegida en el color de
/// acento.
class _ViewToggle extends StatelessWidget {
  final DashboardView view;
  final ValueChanged<DashboardView> onChanged;

  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.bar_chart_rounded, DashboardView.chart, 'Gráfica'),
          _btn(Icons.table_rows_outlined, DashboardView.table, 'Resumen financiero'),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, DashboardView v, String etiqueta) {
    final active = view == v;
    return Tooltip(
      message: etiqueta,
      child: GestureDetector(
        onTap: () => onChanged(v),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 36,
          decoration: BoxDecoration(
            color: active ? _C.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 19, color: active ? kInicioBg : _C.muted),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(color: _C.accent)),
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
              Icon(Icons.error_outline_rounded, color: _C.bad, size: 48),
              const SizedBox(height: 12),
              Text(error, style: _t(14, FontWeight.w400, _C.muted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _C.accent,
                  foregroundColor: kInicioBg,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text('Reintentar', style: _t(14, FontWeight.w700, kInicioBg)),
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: Center(child: Text('Sin datos', style: _t(14, FontWeight.w400, _C.muted))),
      );
}
