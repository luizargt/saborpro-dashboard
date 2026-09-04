import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/cancellations_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/cancellations_view.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';

const _kAppBar = Color(0xFF0A1020);
const _kCard = Color(0xFF1E293B);
const _kAccent = Color(0xFF7444fd);

/// Reporte "Pedidos Cancelados" (fase 4 del inventario).
///
/// Cancelar ya no descuenta en silencio: quien anula declara si el producto
/// regresa a despensa o se pierde, y esa declaración no pide PIN ni permiso.
/// El control, por decisión del dueño, es a posteriori — y es esta pantalla.
///
/// Solo arma el andamio (barra de filtros, carga, error) y le entrega el
/// reporte ya calculado a [CancellationsReportBody], que es la parte que se
/// puede probar a 360dp sin Firebase.
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
        appBar: AppBar(
          backgroundColor: _kAppBar,
          elevation: 0,
          title: const Text('Pedidos Cancelados'),
        ),
        // top: false — el AppBar ya reservó arriba. Los 32px de colchón del
        // listado aguantan la barra de gestos, pero no los 48dp de la de tres
        // botones, y esta pantalla se abre con push (sin bottom nav debajo).
        body: SafeArea(
          top: false,
          child: LocationSwipeArea(
          child: MaxContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra de sucursales + fecha fija, fuera del scroll.
                const LocationHeaderBar(),
                Expanded(
                  child: Consumer<CancellationsProvider>(
                    builder: (context, provider, _) => RefreshIndicator(
                      color: _kAccent,
                      backgroundColor: _kCard,
                      onRefresh: () => provider.load(dashboard),
                      child: provider.loading
                          ? const _Filler(
                              child: CircularProgressIndicator(color: _kAccent))
                          : provider.error != null
                              ? _Filler(
                                  child: Text(
                                    provider.error!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                        color: Colors.white54, fontSize: 13),
                                  ),
                                )
                              : CancellationsReportBody(
                                  report: provider.report),
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

class _Filler extends StatelessWidget {
  final Widget child;
  const _Filler({required this.child});

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el RefreshIndicator necesita algo desplazable para
    // que se pueda reintentar jalando hacia abajo.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 140),
        Center(child: child),
      ],
    );
  }
}
