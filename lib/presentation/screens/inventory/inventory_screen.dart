import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/export_service.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/despensa_view.dart';
import '../../widgets/inicio_ui.dart';

/// La pestaña Despensa: lo que hay de cada ingrediente en cada sucursal.
///
/// Rediseño 2026-11-21 (despensa.html, en su modo oscuro). Esta pantalla solo
/// junta los datos (el inventario y la sucursal que se mira arriba) y se los pasa a
/// [DespensaBody], que es la parte que se ve y se prueba a 360dp sin Firebase. El
/// estado de cada ingrediente, el dinero y el orden son lógica pura en
/// `despensa_data.dart`.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<InventoryProvider>();
    final dash = context.watch<DashboardProvider>();
    final elegida = dash.selectedLocationId;

    // Las sucursales que se ven: la elegida arriba o, sin elegir, todas.
    final visibles = elegida != null ? prov.locations.where((l) => l.id == elegida).toList() : prov.locations;

    // Material y no un ColoredBox: así las ondas de los toques se pintan sobre el
    // fondo en vez de quedar tapadas por él.
    return Material(
      color: kInicioBg,
      child: DespensaBody(
        items: prov.items,
        sucursales: [for (final l in visibles) DespensaSucursal(l.id, l.name, simbolo: l.currencySymbol)],
        dias: prov.last7DayKeys,
        actualizado: prov.lastUpdated,
        ahora: DateTime.now(),
        cargando: prov.loading,
        error: prov.error,
        onReintentar: prov.load,
        onActualizar: prov.load,
        onDescargar: () => ExportService.exportInventory(prov.items, prov.locations),
        sucursalElegida: elegida != null,
        onElegirSucursal: dash.selectLocation,
      ),
    );
  }
}
