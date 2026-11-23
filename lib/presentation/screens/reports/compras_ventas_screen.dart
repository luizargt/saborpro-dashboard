import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_range.dart';
import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/compras_ventas.dart';
import '../../../data/models/rentabilidad_data.dart';
import '../../providers/compras_ventas_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/menu_margin_provider.dart';
import '../../providers/profitability_provider.dart';
import '../../widgets/compras_ventas_view.dart';
import '../../widgets/dish_profit_card.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import 'profitability_report_screen.dart';
import '../../navigation/contexto_shell.dart';

/// Compras vs Ventas: cuánto se ganó con la mercadería y qué pasó con la bodega.
///
/// Rediseño 2026-11-22 (compras-ventas.html, en su modo oscuro). Los números salen
/// de los de Rentabilidad (la misma venta, el mismo costo y las mismas compras:
/// "Ganaste" es su utilidad bruta); lo único que se lee aparte son las fotos
/// mensuales de la bodega, la despensa de hoy y las categorías. Solo arma el
/// andamio; lo que se ve lo dibuja [ComprasVentasBody].
class ComprasVentasScreen extends StatefulWidget {
  const ComprasVentasScreen({super.key});

  @override
  State<ComprasVentasScreen> createState() => _ComprasVentasScreenState();
}

class _ComprasVentasScreenState extends State<ComprasVentasScreen> {
  final _rent = ProfitabilityProvider();
  final _menu = MenuMarginProvider();
  final _cv = ComprasVentasProvider();

  @override
  void dispose() {
    _rent.dispose();
    _menu.dispose();
    _cv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rent.loadIfNeeded(dash);
      final tenant = dash.tenantId;
      if (tenant != null) {
        _menu.cargarSiHaceFalta(tenant);
        _cv.cargarSiHaceFalta(tenant, dash.range);
      }
    });

    return Scaffold(
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
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_rent, _menu, _cv]),
                      builder: (context, _) => RefreshIndicator(
                        color: InicioColores.accent,
                        backgroundColor: InicioColores.card,
                        onRefresh: () => Future.wait([
                          dash.load().then((_) => _rent.load(dash)),
                          _menu.recargar(),
                          _cv.recargar(),
                        ]),
                        child: _Cuerpo(dash: dash, rent: _rent, menu: _menu, cv: _cv),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  final DashboardProvider dash;
  final ProfitabilityProvider rent;
  final MenuMarginProvider menu;
  final ComprasVentasProvider cv;

  const _Cuerpo({required this.dash, required this.rent, required this.menu, required this.cv});

  @override
  Widget build(BuildContext context) {
    if (rent.loading || dash.loading) {
      return _Relleno(child: CircularProgressIndicator(color: InicioColores.accent));
    }
    if (rent.error != null) {
      return _Relleno(child: _TextoAviso('${rent.error!}\n\nDesliza hacia abajo para reintentar.'));
    }
    final d = rent.data;
    if (d.netSales == 0 && d.cogs == 0 && d.purchases == 0) {
      return const _Relleno(
        child: _TextoAviso('Sin compras ni ventas en este período.\nElige otro rango de fechas para ver tu reporte.'),
      );
    }

    final rango = dash.range;
    final elegida = dash.selectedLocationId;
    final todas = [for (final l in dash.locations) (l.id, l.name)];
    final visibles = elegida != null && elegida.isNotEmpty ? [for (final s in todas) if (s.$1 == elegida) s] : todas;
    final enTodas = elegida == null || elegida.isEmpty;
    final sinPedidos = dash.sinOrdenesEnMemoria;

    // La bodega: las fotos del día 1 y, en un mes que sigue abierto, la de hoy.
    final ahora = DateTime.now();
    final finEsHoy = rango.mode == PeriodMode.month && !ahora.isBefore(rango.start) && !ahora.isAfter(rango.end);
    final bodega = BodegaPeriodo.armar(
      inicio: cv.inicio,
      fin: finEsHoy ? cv.vivo : cv.fin,
      finEsHoy: finEsHoy,
      sucursales: {for (final s in visibles) s.$1},
      factor: (loc, fecha) => dash.factorDe(loc, fecha),
    );

    // La cuenta de la bodega (Tenías + Compraste − Usaste) tiene que ser de las MISMAS
    // sucursales que la bodega: las que aportan a la foto. El héroe suma todo lo que
    // se movió (también la bodega central y las sucursales que no se ven); la
    // diferencia se dice en la tarjeta en vez de mezclar los dos conjuntos.
    var compraste = d.purchases;
    var usaste = d.cogs;
    var comprasFuera = 0.0;
    if (enTodas && rent.porSucursal.isNotEmpty) {
      final ids = bodega.finPorSucursal.isNotEmpty
          ? bodega.finPorSucursal.keys.toSet()
          : (bodega.inicioPorSucursal.isNotEmpty ? bodega.inicioPorSucursal.keys.toSet() : {for (final s in visibles) s.$1});
      compraste = ids.fold<double>(0, (a, id) => a + (rent.porSucursal[id]?.purchases ?? 0));
      usaste = ids.fold<double>(0, (a, id) => a + (rent.porSucursal[id]?.cogs ?? 0));
      comprasFuera = d.purchases - compraste;
    }
    final vista = BodegaVista.armar(
      rango: rango,
      bodega: bodega,
      // `fotosLeidas` ya no entra: si la lectura falla, se dice (noSePudo) en vez de
      // quedarse esperando para siempre.
      leyendo: cv.cargando || !cv.vivoLeido,
      compraste: compraste,
      usaste: usaste,
      fotosFallaron: cv.fotosFallaron,
      comprasFuera: comprasFuera,
    );

    final filasSucursal = enTodas && rent.porSucursal.isNotEmpty
        ? FilaSucursalCV.armar(porSucursal: rent.porSucursal, sucursales: todas, bodega: bodega)
        : const <FilaSucursalCV>[];

    // Las categorías: lo comprado y lo usado de cada una, y lo vendido directo de
    // lo que se revende. Necesitan el menú (qué se revende) y los pedidos.
    var categorias = CategoriasCV.vacia;
    var semanas = const <SemanaCV>[];
    if (!sinPedidos) {
      final vistaMenu = platillosDeLaVista(dash, menu);
      final menuListo = vistaMenu != null || menu.error != null;
      if (menuListo) {
        final reventa = <String, double>{};
        if (vistaMenu != null) {
          final sucursal = sucursalEfectiva(elegida, [for (final s in todas) s.$1]);
          final vendidas = UnidadesVendidas.desde(
            dash.currentOrders,
            vistaMenu.platillos,
            sucursal: sucursal,
            soloSucursales: vistaMenu.soloSucursales,
          );
          final clasificacion = dash.clasificacionDeProductos;
          // `ventas` de cada platillo es precio de lista × cantidad, antes de
          // descuentos; la venta neta de arriba ya los trae descontados. Se escala lo
          // de reventa con la misma proporción para que "Platillos" (lo que sobra de
          // la venta neta) no salga recortado y las filas sumen el total.
          final deLista = vendidas.porClave.values.fold<double>(0, (a, v) => a + v.ventas);
          final k = deLista > 0 && d.netSales.isFinite ? d.netSales / deLista : 1.0;
          for (final p in vistaMenu.platillos) {
            if (metaDe(p, clasificacion[p.productoId]) != MetaReceta.reventa) continue;
            final ing = p.lineas.first.ingredienteId;
            final v = vendidas.porClave[p.clave]?.ventas;
            if (ing == null || v == null || v <= 0) continue;
            reventa.update(ing, (x) => x + v * k, ifAbsent: () => v * k);
          }
        }
        categorias = CategoriasCV.armar(
          porIngrediente: rent.costo.porIngrediente,
          categoriaDe: cv.categoriaDeIngrediente,
          reventaPorIngrediente: reventa,
          // Solo si la tarjeta de la bodega muestra su "Te queda": las dos tienen que decir lo mismo.
          bodegaPorCategoria: vista.fin == null ? null : bodega.finPorCategoria,
          ventasTotales: d.netSales,
        );
      }
      semanas = semanasDelMes(
        rango: rango,
        ventas: ventasPorDia(dash.currentOrders, sucursal: enTodas ? null : elegida),
        porDia: rent.costo.porDia,
      );
    }

    return ComprasVentasBody(
      datos: d,
      rango: rango,
      signo: moneda,
      bodega: vista,
      sucursales: filasSucursal,
      categorias: categorias,
      semanas: semanas,
      lecturaIncompleta: rent.costo.truncado,
      onElegirSucursal: dash.selectLocation,
      onVerRentabilidad: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfitabilityReportScreen())),
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
      'Compras vs Ventas',
      maxLines: 2,
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
