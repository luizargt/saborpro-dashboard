import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/cortesias_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/cortesias_view.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';

const _kCard = CortesiasColores.card;
const _kAccent = CortesiasColores.accent;

/// Abre el detalle desde la tarjeta "Cortesías / Donaciones" del Inicio.
void abrirCortesias(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const CortesiasScreen()),
  );
}

/// Qué pedidos y qué platillos se regalaron en el período, y el resumen por
/// platillo.
///
/// No consulta nada propio: arma el detalle con los MISMOS pedidos con que el
/// Inicio sumó la tarjeta, así que el total cuadra con ella al centavo y
/// obedece a la misma barra de sucursal y fecha. La excepción es la vista de
/// año, donde el Inicio no tiene los pedidos en memoria (los totales los suma
/// Firestore): ahí se bajan solo si alguien lo pide (ver [PanelDetalleAnio] y
/// `DashboardProvider.bajarCortesiasDelAnio`), y si el total no coincide con
/// el de la tarjeta, la pantalla lo dice.
///
/// Solo arma el andamio (barras, carga, error); lo que se ve lo dibuja
/// [CortesiasReportBody], que es la parte que se prueba a 360dp.
class CortesiasScreen extends StatefulWidget {
  const CortesiasScreen({super.key});

  @override
  State<CortesiasScreen> createState() => _CortesiasScreenState();
}

class _CortesiasScreenState extends State<CortesiasScreen> {
  // Fuera del año, el reporte se rehace solo cuando cambian los pedidos, no
  // en cada redibujo.
  List<Map<String, dynamic>>? _ordenesDelReporte;
  CortesiasReport _reporte = CortesiasReport.empty;

  // Nombre de quien marcó cada cortesía (users/{id}.name).
  final Map<String, String> _nombres = {};
  final Set<String> _nombresPedidos = {};

  Future<void> _refrescar(DashboardProvider dash) async {
    // En la vista de año, refrescar tira el detalle bajado (y el que se
    // estaba bajando): se vuelve a bajar solo si alguien ya lo había pedido y
    // si al terminar se sigue mirando lo mismo (bajar el año es caro y se hace
    // cuando alguien lo pide).
    final clave = dash.claveCortesiasAnio;
    final loHabiaPedido =
        dash.cortesiasDelAnio != null || dash.bajandoCortesiasDelAnio;
    await dash.refresh();
    if (!mounted) return;
    if (loHabiaPedido &&
        dash.sinOrdenesEnMemoria &&
        dash.claveCortesiasAnio == clave) {
      await dash.bajarCortesiasDelAnio();
    }
  }

  void _pedirNombres(DashboardProvider dash, CortesiasReport reporte) {
    final faltan =
        reporte.usuarios.where((id) => !_nombresPedidos.contains(id)).toList();
    if (faltan.isEmpty) return;
    _nombresPedidos.addAll(faltan);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final nombres = await dash.fetchUserNamesById(faltan);
      if (mounted && nombres.isNotEmpty) setState(() => _nombres.addAll(nombres));
    });
  }

  /// Nombre de cada sucursal, solo cuando se miran todas juntas.
  Map<String, String> _nombresSucursal(DashboardProvider d) {
    if (d.selectedLocationId != null && d.selectedLocationId!.isNotEmpty) {
      return const {};
    }
    return {
      for (final l in [...d.locations, ...d.sucursalesOcultas]) l.id: l.name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final enAnio = dash.sinOrdenesEnMemoria;

    CortesiasReport? reporte;
    if (!dash.loading) {
      if (enAnio) {
        reporte = dash.cortesiasDelAnio;
      } else {
        final ordenes = dash.currentOrders;
        if (!identical(ordenes, _ordenesDelReporte)) {
          _ordenesDelReporte = ordenes;
          _reporte = CortesiasReport.desde(ordenes);
        }
        reporte = _reporte;
      }
    }
    if (reporte != null) _pedirNombres(dash, reporte);

    // La tarjeta del año solo sabe de cortesías cuando ya llegaron los
    // resúmenes de cada mes; antes vale cero y compararla diría una mentira.
    final metricas = dash.metrics;
    final totalTarjeta = enAnio && metricas != null && metricas.detailAvailable
        ? metricas.courtesyTotal
        : null;

    final Widget contenido;
    if (dash.error != null) {
      contenido = _Relleno(child: _TextoAviso(dash.error!));
    } else if (dash.loading) {
      contenido = const _Relleno(
          child: CircularProgressIndicator(color: _kAccent));
    } else if (reporte == null) {
      // Solo pasa en la vista de año, antes de bajar los pedidos.
      contenido = PanelDetalleAnio(
        onCargar: () => dash.bajarCortesiasDelAnio(),
        cargando: dash.bajandoCortesiasDelAnio,
        error: dash.errorCortesiasDelAnio,
      );
    } else {
      contenido = CortesiasReportBody(
        report: reporte,
        nombresUsuario: _nombres,
        nombresSucursal: _nombresSucursal(dash),
        incompleto: !enAnio && dash.ordenesCortadas,
        convertido: dash.convierte,
        totalTarjeta: totalTarjeta,
        bajadoA: enAnio ? dash.cortesiasDelAnioBajadoA : null,
        // La "Venta Bruta" del Inicio, para decir qué parte se regaló.
        ventas: metricas?.ventaBruta,
      );
    }

    return Scaffold(
      backgroundColor: kCortesiasBg,
      body: SafeArea(
        child: LocationSwipeArea(
          child: MaxContentWidth(
            maxWidth: 1280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Encabezado(),
                // Las pestañas de sucursal (si hay varias) y la moneda de la
                // vista; la fecha ya va en el encabezado.
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
                      color: _kAccent,
                      backgroundColor: _kCard,
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

/// Regresar, el título y la fecha del período (como el diseño). En el
/// teléfono la fecha baja a su propia línea: al lado se comía el título.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width < 640;
    final regresar = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: CortesiasColores.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => Navigator.of(context).maybePop(),
          child: const Tooltip(
            message: 'Regresar',
            child: Icon(Icons.arrow_back_rounded, color: CortesiasColores.ink, size: 22),
          ),
        ),
      ),
    );
    final titulo = Text(
      'Cortesías y donaciones',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: cortesiasTexto(telefono ? 20 : 24, FontWeight.w700, CortesiasColores.ink),
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
          : Row(
              children: [
                regresar,
                const SizedBox(width: 14),
                Expanded(child: titulo),
                const SizedBox(width: 14),
                const DateSelectorChip(),
              ],
            ),
    );
  }
}

class _TextoAviso extends StatelessWidget {
  final String texto;
  const _TextoAviso(this.texto);

  @override
  Widget build(BuildContext context) => Text(
        texto,
        textAlign: TextAlign.center,
        style: cortesiasTexto(13.5, FontWeight.w400, CortesiasColores.muted),
      );
}

class _Relleno extends StatelessWidget {
  final Widget child;
  const _Relleno({required this.child});

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el RefreshIndicator necesita algo desplazable para
    // que se pueda reintentar jalando hacia abajo.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 140),
        Center(child: child),
      ],
    );
  }
}
