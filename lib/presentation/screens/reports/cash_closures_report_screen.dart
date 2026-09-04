import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/location_selector.dart';
import '../../../presentation/widgets/max_content_width.dart';
import '../dashboard/cajas_screen.dart';

class CashClosuresReportScreen extends StatelessWidget {
  const CashClosuresReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        title: const Text('Cierres de Caja'),
      ),
      // top: false — el AppBar ya reservó arriba. Abajo hace falta: la
      // pantalla se abre con push, sin la barra de navegación de la app
      // debajo, y los 16px de colchón no alcanzan contra los 48dp de la barra
      // de tres botones.
      body: SafeArea(
        top: false,
        child: LocationSwipeArea(
        child: MaxContentWidth(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de sucursales fija, fuera del scroll.
            const LocationHeaderBar(),
            Expanded(
              child: RefreshIndicator(
          color: const Color(0xFF7444fd),
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: provider.load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (provider.loading)
                        const SizedBox(
                          height: 300,
                          child: Center(child: CircularProgressIndicator(color: Color(0xFF7444fd))),
                        )
                      else if (provider.error != null)
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Text(provider.error!, style: const TextStyle(color: Colors.white54)),
                          ),
                        )
                      else
                        CajasScreen(
                          open: provider.openRegisters,
                          closed: provider.closedRegisters,
                          orders: provider.currentOrders,
                          expenseItems: provider.expenseItems,
                          locationNames: {
                            for (final l in provider.locations) l.id: l.name,
                          },
                          tenantId: provider.tenantId,
                          onRegisterClosed: provider.load,
                        ),
                    ],
                  ),
                ),
              ),
            ],
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
