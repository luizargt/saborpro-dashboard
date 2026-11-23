import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/dashboard_provider.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import '../dashboard/cajas_screen.dart';
import '../../navigation/contexto_shell.dart';

/// Cierres de caja: las cajas abiertas y el cuadre de cada corte del período.
///
/// Rediseño 2026-11-21 (cierres-caja.html, en su modo oscuro). Solo arma el
/// andamio (barras, carga, error); lo que se ve lo dibuja `CierresCajaBody`.
class CashClosuresReportScreen extends StatelessWidget {
  const CashClosuresReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    final Widget contenido;
    if (provider.error != null) {
      contenido = _Relleno(child: _TextoAviso(provider.error!));
    } else if (provider.loading) {
      contenido = _Relleno(child: CircularProgressIndicator(color: InicioColores.accent));
    } else {
      contenido = CajasScreen(
        open: provider.openRegisters,
        closed: provider.closedRegisters,
        // Sin convertir: cada caja se cuadra en su moneda.
        orders: provider.currentOrdersLocal,
        expenseItems: provider.expenseItemsLocal,
        locationNames: {for (final l in provider.locations) l.id: l.name},
        locationSymbols: provider.locationSymbols,
        locationCurrencies: {for (final l in provider.locations) l.id: l.currencyCode},
        tenantId: provider.tenantId,
        onRegisterClosed: provider.load,
      );
    }

    return Scaffold(
      backgroundColor: kInicioBg,
      // La pantalla se abre con push, sin la barra de navegación de la app debajo:
      // SafeArea también por abajo (la barra de tres botones mide 48dp).
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
                    child: RefreshIndicator(
                      color: InicioColores.accent,
                      backgroundColor: InicioColores.card,
                      onRefresh: provider.load,
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
          child: Tooltip(
            message: 'Regresar',
            child: Icon(Icons.arrow_back_rounded, color: InicioColores.ink, size: 22),
          ),
        ),
      ),
    );
    final titulo = Text(
      'Cierres de caja',
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
        style: inicioTexto(13.5, FontWeight.w400, InicioColores.muted),
      );
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
      children: [
        const SizedBox(height: 140),
        Center(child: child),
      ],
    );
  }
}
