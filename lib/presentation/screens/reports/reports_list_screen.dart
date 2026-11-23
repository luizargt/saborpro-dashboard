import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/atencion_inicio.dart' show ResumenPedidosInicio;
import '../../../data/models/datos_reportes.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/reports_list_view.dart';
import '../dashboard/cortesias_screen.dart';
import '../dashboard/propinas_screen.dart';
import 'cancelled_orders_report_screen.dart';
import 'compras_ventas_screen.dart';
import 'cash_closures_report_screen.dart';
import 'expenses_report_screen.dart';
import 'profitability_report_screen.dart';

/// La pestaña "Reportes".
///
/// Rediseño 2026-11-20 (reportes.html, en su modo oscuro). Esta pantalla solo
/// arma la lista —qué reportes hay, a dónde lleva cada uno y el dato de "ahora"
/// que sale del Inicio— y se la pasa a [ReportsListView], que es la parte que se
/// ve y se prueba a 360dp sin Firebase.
///
/// Solo reportes que ya funcionan. Al construir uno nuevo basta agregarlo aquí
/// con su grupo: la pantalla se arma sola.
class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  static const _dinero = 'Dinero';
  static const _control = 'Control y pérdidas';

  void _abrir(BuildContext context, WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute(builder: builder));

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();

    // Mientras carga (o si falló) no hay dato que mostrar: lo de antes podría
    // ser de otro período.
    final cargado = !dash.loading && dash.error == null;
    final metrics = cargado ? dash.metrics : null;
    final datos = DatosReportes.armar(
      periodo: dash.range.label,
      metrics: metrics,
      cajasOk: cargado && dash.cajasLeidas && dash.resumenCajasOk,
      abiertas: dash.openRegisters,
      cerradas: dash.closedRegisters,
      // Cada caja con el signo de su sucursal (no se convierten nunca).
      signoDeCaja: (loc) => dash.locationSymbols[loc] ?? moneda,
      signoVista: moneda,
      pedidos: metrics?.detailAvailable == true ? dash.resumenPedidos : ResumenPedidosInicio.vacio,
    );

    final reportes = [
      // Primero de Dinero a propósito: responde la pregunta que todos los demás
      // rodean — cuánto se está ganando de verdad.
      ReporteItem(
        grupo: _dinero,
        titulo: 'Rentabilidad',
        descripcion: 'Cuánto ganas después de costos y gastos',
        icono: Icons.trending_up_rounded,
        tono: TonoReporte.verde,
        palabras: 'ganancia utilidad margen',
        onTap: () => _abrir(context, (_) => const ProfitabilityReportScreen()),
      ),
      ReporteItem(
        grupo: _dinero,
        titulo: 'Compras vs Ventas',
        descripcion: 'Cuánto ganas con la mercadería que compras',
        icono: Icons.compare_arrows_rounded,
        tono: TonoReporte.azul,
        palabras: 'compras ventas mercaderia bodega inventario despensa roi',
        onTap: () => _abrir(context, (_) => const ComprasVentasScreen()),
      ),
      ReporteItem(
        grupo: _dinero,
        titulo: 'Cierres de caja',
        descripcion: 'Lo que cuadró, faltó o sobró en cada caja',
        icono: Icons.point_of_sale_rounded,
        tono: TonoReporte.verde,
        palabras: 'caja corte arqueo',
        onTap: () => _abrir(context, (_) => const CashClosuresReportScreen()),
        dato: datos[IdReporte.cierres],
      ),
      ReporteItem(
        grupo: _dinero,
        titulo: 'Gastos',
        descripcion: 'En qué se fue el dinero del negocio',
        icono: Icons.receipt_long_rounded,
        tono: TonoReporte.verde,
        palabras: 'compras egresos',
        onTap: () => _abrir(context, (_) => const ExpensesReportScreen()),
        dato: datos[IdReporte.gastos],
      ),
      ReporteItem(
        grupo: _dinero,
        titulo: 'Propinas',
        descripcion: 'Quién recibe más y a qué hora se deja más',
        icono: Icons.paid_outlined,
        tono: TonoReporte.ambar,
        palabras: 'mesero propina',
        onTap: () => abrirPropinas(context),
        dato: datos[IdReporte.propinas],
      ),
      ReporteItem(
        grupo: _control,
        titulo: 'Cortesías y donaciones',
        descripcion: 'Lo que se regaló, quién y por qué',
        icono: Icons.card_giftcard_rounded,
        tono: TonoReporte.morado,
        palabras: 'regalo cortesia donacion',
        onTap: () => abrirCortesias(context),
        dato: datos[IdReporte.cortesias],
      ),
      // Lo que se revisa aquí es producto perdido, no dinero no vendido.
      ReporteItem(
        grupo: _control,
        titulo: 'Pedidos cancelados',
        descripcion: 'Lo anulado y el producto que se perdió',
        icono: Icons.cancel_outlined,
        tono: TonoReporte.rojo,
        palabras: 'cancelacion anulado merma bodega',
        onTap: () => _abrir(context, (_) => const CancelledOrdersReportScreen()),
      ),
    ];

    // Material y no un ColoredBox: así las ondas de los toques se pintan sobre
    // el fondo en vez de quedar tapadas por él.
    return Material(color: kInicioBg, child: ReportsListView(reportes: reportes));
  }
}
