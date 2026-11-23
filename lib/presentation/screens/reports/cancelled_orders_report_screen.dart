import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/cancellations_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/cancellations_view.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import '../../navigation/contexto_shell.dart';

Color get _kCard => CancelColores.card;
Color get _kAccent => CancelColores.accent;

/// Reporte "Pedidos Cancelados" (fase 4 del inventario).
///
/// Cancelar ya no descuenta en silencio: quien anula declara si el producto
/// regresa a despensa o se pierde, y esa declaración no pide PIN ni permiso.
/// El control, por decisión del dueño, es a posteriori — y es esta pantalla.
///
/// Solo arma el andamio (barras, carga, error) y le entrega el reporte ya
/// calculado a [CancellationsReportBody], que es la parte que se puede probar a
/// 360dp sin Firebase. Diseño: `cancelados.html` (ver el cuerpo).
class CancelledOrdersReportScreen extends StatefulWidget {
  const CancelledOrdersReportScreen({super.key});

  @override
  State<CancelledOrdersReportScreen> createState() =>
      _CancelledOrdersReportScreenState();
}

class _CancelledOrdersReportScreenState
    extends State<CancelledOrdersReportScreen> {
  // Provider local: los datos solo los mira esta pantalla, no vale la pena
  // pagar la consulta en el arranque de la app.
  final _provider = CancellationsProvider();

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();

    // El rango y la sucursal los manda la barra de filtros compartida; el
    // provider decide solo si eso cambió lo suficiente para reconsultar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.loadIfNeeded(dashboard);
    });

    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: kCancelBg,
        // Sin AppBar: el encabezado (Regresar, título y fecha) es parte del
        // diseño. Esta pantalla se abre con push, sin bottom nav debajo, así que
        // el SafeArea cuida también la barra de gestos.
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
                      child: Consumer<CancellationsProvider>(
                        builder: (context, provider, _) => RefreshIndicator(
                          color: _kAccent,
                          backgroundColor: _kCard,
                          onRefresh: () => provider.load(dashboard),
                          // También mientras el dashboard carga: el reporte
                          // espera a que termine (ver loadIfNeeded) y, sin esto,
                          // se vería el período anterior.
                          child: provider.loading || dashboard.loading
                              ? _Relleno(
                                  child: CircularProgressIndicator(
                                      color: _kAccent))
                              : provider.error != null
                                  ? _Relleno(child: _TextoAviso(provider.error!))
                                  : CancellationsReportBody(
                                      report: provider.report),
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

/// Regresar, el título y la fecha del período (como el diseño). En el teléfono
/// la fecha baja a su propia línea: al lado se comía el título.
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
        color: CancelColores.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => Navigator.of(context).maybePop(),
          child: Tooltip(
            message: 'Regresar',
            child: Icon(Icons.arrow_back_rounded,
                color: CancelColores.ink, size: 22),
          ),
        ),
      ),
    );
    final titulo = Text(
      'Pedidos cancelados',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: cancelTexto(
          telefono ? 20 : 24, FontWeight.w700, CancelColores.ink),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: telefono
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  regresar,
                  const SizedBox(width: 14),
                  Expanded(child: titulo),
                ]),
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
        style: cancelTexto(13.5, FontWeight.w400, CancelColores.muted),
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
