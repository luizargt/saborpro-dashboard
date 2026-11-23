import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/gastos_data.dart';
import '../../../data/models/propinas_data.dart' show PropinasReporte;
import '../../providers/dashboard_provider.dart';
import '../../widgets/gastos_view.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import '../../navigation/contexto_shell.dart';

/// Gastos: lo que se compró y se gastó en el período, y qué dice de los precios.
///
/// Rediseño 2026-11-22 (gastos.html, en su modo oscuro). Usa los MISMOS gastos,
/// retiros y compras con que el Inicio sumó el total, así que cuadra con él y
/// obedece a la misma barra de sucursal y fecha. Lo único que lee aparte es el
/// período anterior (para decir si se gastó más o menos y qué subió de precio), una
/// vez al abrir. Solo arma el andamio; lo que se ve lo dibuja [GastosBody].
class ExpensesReportScreen extends StatefulWidget {
  const ExpensesReportScreen({super.key});

  @override
  State<ExpensesReportScreen> createState() => _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends State<ExpensesReportScreen> {
  // El período anterior que se leyó, y para qué período, sucursal y moneda.
  GastosPeriodo? _anterior;
  String? _clave;

  // El período actual, armado una vez por cada juego de datos.
  List<Map<String, dynamic>>? _compras;
  List<Map<String, dynamic>>? _gastos;
  GastosPeriodo _periodo = GastosPeriodo.vacio;

  Future<void> _cargarAnterior(DashboardProvider dash, String clave) async {
    final r = await dash.cargarGastosAnteriores();
    if (!mounted || _clave != clave) return;
    setState(() => _anterior = r == null ? null : GastosPeriodo.desde(r.compras, r.gastos));
  }

  Future<void> _refrescar(DashboardProvider dash) async {
    // Al volver a cargar se vuelve a leer también el período anterior.
    _clave = null;
    await dash.load();
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final metricas = dash.metrics;

    final Widget contenido;
    if (dash.error != null) {
      contenido = _Relleno(child: _TextoAviso(dash.error!));
    } else if (dash.loading || metricas == null) {
      contenido = _Relleno(child: CircularProgressIndicator(color: InicioColores.accent));
    } else {
      if (!identical(_compras, dash.purchaseItems) || !identical(_gastos, dash.expenseItems)) {
        _compras = dash.purchaseItems;
        _gastos = dash.expenseItems;
        _periodo = GastosPeriodo.desde(dash.purchaseItems, dash.expenseItems);
      }

      // Se vuelve a leer el período anterior cuando cambia el período, la sucursal o
      // la moneda de la vista; mientras tanto no se muestra una comparación vieja.
      final clave = '${dash.range.start.toIso8601String()}|${dash.range.end.toIso8601String()}|${dash.selectedLocationId}|$moneda|${dash.convierte}';
      if (_clave != clave) {
        _clave = clave;
        _anterior = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _cargarAnterior(dash, clave);
        });
      }

      // Las sucursales que se ven: la elegida arriba o, sin elegir, todas.
      final todas = [...dash.locations, ...dash.sucursalesOcultas];
      final elegida = dash.selectedLocationId;
      final visibles = elegida != null && elegida.isNotEmpty ? todas.where((l) => l.id == elegida).toList() : todas;

      // Lo vendido (la "Venta bruta" del Inicio) y por sucursal, de los mismos
      // pedidos. La vista de año no los trae en memoria: solo el total.
      Map<String, double>? ventasPorSucursal;
      if (!dash.sinOrdenesEnMemoria) {
        ventasPorSucursal = {};
        for (final o in dash.currentOrders) {
          final loc = o['location_id'];
          if (loc is! String) continue;
          ventasPorSucursal.update(loc, (v) => v + PropinasReporte.ventaDe(o), ifAbsent: () => PropinasReporte.ventaDe(o));
        }
      }

      contenido = GastosBody(
        periodo: _periodo,
        anterior: _anterior,
        vsEtiqueta: dash.range.prevLabel,
        ventas: metricas.ventaBruta,
        ventasPorSucursal: ventasPorSucursal,
        sucursales: GastoSucursal.de([for (final l in visibles) (l.id, l.name)]),
        signo: moneda,
      );
    }

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
                // Las pestañas de sucursal (si hay varias) y la moneda de la vista; la
                // fecha ya va en el encabezado.
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
                    child: RefreshIndicator(
                      color: InicioColores.accent,
                      backgroundColor: InicioColores.card,
                      onRefresh: () => _refrescar(dash),
                      child: contenido,
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
      'Gastos',
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
  Widget build(BuildContext context) => Text(texto, textAlign: TextAlign.center, style: inicioTexto(13.5, FontWeight.w400, InicioColores.muted));
}

class _Relleno extends StatelessWidget {
  final Widget child;
  const _Relleno({required this.child});

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el RefreshIndicator necesita algo desplazable para que
    // se pueda reintentar jalando hacia abajo.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [const SizedBox(height: 140), Center(child: child)],
    );
  }
}
