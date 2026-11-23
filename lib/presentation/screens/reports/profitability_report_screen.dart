import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/profitability_data.dart';
import '../../../data/models/rentabilidad_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/menu_margin_provider.dart';
import '../../providers/profitability_provider.dart';
import '../../widgets/dish_profit_card.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import '../../widgets/rentabilidad_view.dart';
import 'expenses_report_screen.dart';
import '../../navigation/contexto_shell.dart';

/// Rentabilidad: si el negocio ganó o perdió, cuánto hay que vender para no perder y
/// qué platillos dejan más.
///
/// Rediseño 2026-11-22 (rentabilidad.html, en su modo oscuro). Los números de
/// siempre salen de [ProfitabilityProvider] (la misma cuenta, ahora también por
/// sucursal) y el menú de [MenuMarginProvider]; lo vendido por platillo sale de los
/// pedidos que el dashboard ya trajo. Solo arma el andamio; lo que se ve lo dibuja
/// [RentabilidadBody].
class ProfitabilityReportScreen extends StatefulWidget {
  const ProfitabilityReportScreen({super.key});

  @override
  State<ProfitabilityReportScreen> createState() => _ProfitabilityReportScreenState();
}

class _ProfitabilityReportScreenState extends State<ProfitabilityReportScreen> {
  final _provider = ProfitabilityProvider();

  /// El costo de receta de cada platillo. Vive aquí y no en cada sección para que
  /// "Utilidad por platillo" use el mismo sin volver a descargar el menú.
  final _menu = MenuMarginProvider();

  @override
  void dispose() {
    _provider.dispose();
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider.loadIfNeeded(dash);
      final tenant = dash.tenantId;
      if (tenant != null) _menu.cargarSiHaceFalta(tenant);
    });

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _provider),
        ChangeNotifierProvider.value(value: _menu),
      ],
      child: Scaffold(
        backgroundColor: kInicioBg,
        body: SafeArea(
          child: LocationSwipeArea(
            child: MaxContentWidth(
              maxWidth: 1280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Encabezado(),
                  // Las pestañas de sucursal (si hay varias) y la moneda de la vista;
                  // la fecha ya va en el encabezado.
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [LocationTabsBar(), MonedaVistaAviso()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LocationContentSwitcher(
                      child: Consumer2<ProfitabilityProvider, MenuMarginProvider>(
                        builder: (context, p, menu, _) => RefreshIndicator(
                          color: InicioColores.accent,
                          backgroundColor: InicioColores.card,
                          // El menú se recarga en paralelo: esperarlo en fila alargaba
                          // el giro del indicador sin necesidad.
                          onRefresh: () => Future.wait([
                            dash.load().then((_) => p.load(dash)),
                            menu.recargar(),
                          ]),
                          child: _Cuerpo(dash: dash, provider: p, menu: menu),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  final DashboardProvider dash;
  final ProfitabilityProvider provider;
  final MenuMarginProvider menu;

  const _Cuerpo({required this.dash, required this.provider, required this.menu});

  @override
  Widget build(BuildContext context) {
    // dash.loading cuenta como cargando: las ventas salen de ahí, y mientras no
    // lleguen no hay reporte que mostrar. Sin esto quedaban en pantalla los números
    // del mes anterior, sin ninguna señal de que ya no correspondían.
    if (provider.loading || dash.loading) {
      return _Relleno(child: CircularProgressIndicator(color: InicioColores.accent));
    }
    if (provider.error != null) {
      return _Relleno(child: _TextoAviso('${provider.error!}\n\nDesliza hacia abajo para reintentar.'));
    }
    final d = provider.data;
    if (d.sinDatos) {
      return const _Relleno(
        child: _TextoAviso('Sin movimientos en este período.\nElige otro rango de fechas para ver tu rentabilidad.'),
      );
    }

    // Las sucursales que se ven: la elegida o, sin elegir, las de la barra.
    final elegida = dash.selectedLocationId;
    final todas = [for (final l in dash.locations) (l.id, l.name)];
    final visibles = elegida != null && elegida.isNotEmpty ? [for (final s in todas) if (s.$1 == elegida) s] : todas;
    final enTodas = elegida == null || elegida.isEmpty;

    final sinFijos = sucursalesSinGastosFijos(gastos: dash.expenseItems, sucursales: visibles);
    final comparacion = enTodas
        ? ComparacionSucursales.armar(porSucursal: provider.porSucursal, sucursales: todas, ventasTotales: d.netSales)
        : ComparacionSucursales.vacia;

    // El menú cruzado con lo vendido. En la vista de año no hay pedidos en memoria.
    AnalisisMenu? analisis;
    final vista = platillosDeLaVista(dash, menu);
    if (vista != null && !dash.sinOrdenesEnMemoria) {
      final sucursal = sucursalEfectiva(elegida, [for (final s in todas) s.$1]);
      final vendidas = UnidadesVendidas.desde(
        dash.currentOrders,
        vista.platillos,
        sucursal: sucursal,
        soloSucursales: vista.soloSucursales,
      );
      analisis = AnalisisMenu.armar(
        platillos: vista.platillos,
        vendidas: vendidas,
        clasificacion: dash.clasificacionDeProductos,
      );
    }

    final nombreSucursal = [for (final s in visibles) s.$2];
    final notaPrecios = enTodas && todas.length > 1
        ? 'En "Todas" se usa el precio base y el costo de la sucursal donde se armó cada receta. '
            'Elige una sucursal para verlo con sus precios.'
        : (nombreSucursal.length == 1 ? 'Precios y costos de ${nombreSucursal.first}.' : '');

    return RentabilidadBody(
      datos: d,
      rango: dash.range,
      signo: moneda,
      sinGastosFijos: sinFijos,
      variasSucursales: visibles.length > 1,
      comparacion: comparacion,
      menu: analisis,
      menuCargando: menu.cargando && !menu.listo,
      menuError: menu.error,
      menuSinPedidos: dash.sinOrdenesEnMemoria,
      ventasIncompletas: !dash.sinOrdenesEnMemoria && dash.ordenesCortadas,
      notaMoneda: notaMonedaPlatillos(dash),
      notaPrecios: notaPrecios,
      avisoPreproduccion: avisoPreproduccion(
        d,
        rango: dash.range,
        // El dashboard se traga los fallos de gastos y de cajas; estas dos señales
        // son la única huella.
        gastosLeidos: dash.expenseRawCount >= 0 && dash.cajasLeidas,
      ),
      onReintentarMenu: menu.recargar,
      onIrAGastos: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpensesReportScreen())),
      onVerUtilidadPlatillos: () => abrirUtilidadPlatillos(context),
    );
  }
}

/// Regresar, el título y la fecha del período (como el diseño). En el teléfono la
/// fecha baja a su propia línea: al lado se comía el título.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    // Dentro del shell el encabezado (migas, título y fecha) lo pone el shell.
    if (ContextoShell.enShell(context)) return const SizedBox.shrink();

    final telefono = MediaQuery.sizeOf(context).width < 640;
    final regresar = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: InicioColores.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => Navigator.of(context).maybePop(),
          child: Tooltip(message: 'Regresar', child: Icon(Icons.arrow_back_rounded, color: InicioColores.ink, size: 22)),
        ),
      ),
    );
    final titulo = Text(
      'Rentabilidad',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: inicioTexto(telefono ? 20 : 24, FontWeight.w700, InicioColores.ink),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: telefono
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [regresar, const SizedBox(width: 14), Expanded(child: titulo)]),
                const SizedBox(height: 10),
                const DateSelectorChip(),
              ],
            )
          : Row(children: [regresar, const SizedBox(width: 14), Expanded(child: titulo), const SizedBox(width: 14), const DateSelectorChip()]),
    );
  }
}

class _TextoAviso extends StatelessWidget {
  final String texto;
  const _TextoAviso(this.texto);

  @override
  Widget build(BuildContext context) =>
      Text(texto, textAlign: TextAlign.center, style: inicioTexto(13.5, FontWeight.w400, InicioColores.muted, height: 1.5));
}

class _Relleno extends StatelessWidget {
  final Widget child;
  const _Relleno({required this.child});

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el RefreshIndicator necesita algo desplazable para que se
    // pueda reintentar jalando hacia abajo.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [const SizedBox(height: 140), Center(child: child)],
    );
  }
}
