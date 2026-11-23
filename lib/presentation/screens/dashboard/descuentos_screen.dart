import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/descuentos_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/cortesias_view.dart' show CortesiasColores, cortesiasTexto, kCortesiasBg;
import '../../widgets/descuentos_view.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';

Color get _kCard => CortesiasColores.card;
Color get _kAccent => CortesiasColores.accent;

/// Abre el detalle desde la tarjeta "Descuentos" del Inicio.
void abrirDescuentos(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const DescuentosScreen()),
  );
}

/// Qué pedidos se cobraron con descuento en el período, quién los cobró, por qué
/// y a qué platillos.
///
/// No consulta nada propio: arma el detalle con los MISMOS pedidos con que el
/// Inicio sumó la tarjeta, así que el total cuadra con ella al centavo y obedece
/// a la misma barra de sucursal y fecha.
///
/// La vista de año no tiene los pedidos en memoria (los totales los suma
/// Firestore) y, por eso, la tarjeta "Descuentos" ni siquiera se muestra ahí. Si
/// alguien cambia a año con esta pantalla abierta, dice que no hay detalle en vez
/// de mostrar una lista vacía que se leería como "no hubo descuentos".
///
/// Solo arma el andamio (barras, carga, error); lo que se ve lo dibuja
/// [DescuentosReportBody], que es la parte que se prueba a 360dp.
class DescuentosScreen extends StatefulWidget {
  const DescuentosScreen({super.key});

  @override
  State<DescuentosScreen> createState() => _DescuentosScreenState();
}

class _DescuentosScreenState extends State<DescuentosScreen> {
  // El reporte se rehace solo cuando cambian los pedidos, no en cada redibujo.
  List<Map<String, dynamic>>? _ordenesDelReporte;
  DescuentosReport _reporte = DescuentosReport.empty;

  // Nombre de quien cobró cada pedido (users/{id}.name), para los pedidos que no
  // lo guardaron.
  final Map<String, String> _nombres = {};
  final Set<String> _nombresPedidos = {};

  void _pedirNombres(DashboardProvider dash, DescuentosReport reporte) {
    final faltan = reporte.usuarios.where((id) => !_nombresPedidos.contains(id)).toList();
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

    DescuentosReport? reporte;
    if (!dash.loading && !enAnio) {
      final ordenes = dash.currentOrders;
      if (!identical(ordenes, _ordenesDelReporte)) {
        _ordenesDelReporte = ordenes;
        _reporte = DescuentosReport.desde(ordenes);
      }
      reporte = _reporte;
      _pedirNombres(dash, reporte);
    }

    final Widget contenido;
    if (dash.error != null) {
      contenido = _Relleno(child: _TextoAviso(dash.error!));
    } else if (dash.loading) {
      contenido = _Relleno(child: CircularProgressIndicator(color: _kAccent));
    } else if (reporte == null) {
      // Solo pasa en la vista de año.
      contenido = const _Relleno(
        child: _TextoAviso(
          'El detalle de los descuentos no está disponible en la vista de año. '
          'Elegí un mes o un día.',
        ),
      );
    } else {
      contenido = DescuentosReportBody(
        report: reporte,
        nombresUsuario: _nombres,
        nombresSucursal: _nombresSucursal(dash),
        incompleto: dash.ordenesCortadas,
        convertido: dash.convierte,
        // La "Venta Bruta" del Inicio, para decir qué parte se descontó.
        ventas: dash.metrics?.ventaBruta,
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
                      onRefresh: () => dash.refresh(),
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
          child: Tooltip(
            message: 'Regresar',
            child: Icon(Icons.arrow_back_rounded, color: CortesiasColores.ink, size: 22),
          ),
        ),
      ),
    );
    final titulo = Text(
      'Descuentos',
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
