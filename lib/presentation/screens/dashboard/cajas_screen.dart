import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/cierre_admin_service.dart';
import '../../../core/utils/formato_dinero.dart';
import '../../../data/models/cash_register_summary.dart';
import '../../../data/models/cierres_caja.dart';
import '../../widgets/cierres_caja_view.dart';
import '../../widgets/menu_caja_abierta.dart';
import 'register_detail_screen.dart';

// La tarjeta "este corte se cerró dos veces" vive en su propio archivo; se
// reexporta aquí porque desde siempre se importó de este.
export '../../widgets/cierres_no_aplicados_block.dart' show CierresNoAplicadosBlock;

/// Las cajas del período: las que siguen abiertas y el cuadre de cada corte.
///
/// Rediseño 2026-11-21 (cierres-caja.html, en su modo oscuro). Esta pantalla solo
/// arma lo que se ve: cuenta cada corte (`CierreCaja`: la misma cuenta de
/// siempre) y se lo pasa a [CierresCajaBody], que es la parte que se prueba a
/// 360dp sin Firebase.
class CajasScreen extends StatelessWidget {
  final List<CashRegisterSummary> open;
  final List<CashRegisterSummary> closed;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> expenseItems;

  /// Signo de moneda de cada sucursal: cada caja se pinta con el suyo, aunque
  /// el resto del reporte esté convertido a la moneda principal.
  final Map<String, String> locationSymbols;

  /// El código de moneda de cada sucursal ("GTQ"): con él se agrupa el resumen
  /// (el signo puede repetirse entre monedas distintas). Sin él, se agrupa por signo.
  final Map<String, String> locationCurrencies;
  final Map<String, String> locationNames;
  final String? tenantId;
  final VoidCallback? onRegisterClosed;

  const CajasScreen({
    super.key,
    required this.open,
    required this.closed,
    required this.orders,
    required this.expenseItems,
    required this.locationNames,
    this.locationSymbols = const {},
    this.locationCurrencies = const {},
    this.tenantId,
    this.onRegisterClosed,
  });

  @override
  Widget build(BuildContext context) {
    // El signo de cada sucursal, normalizado ("USD" → "USD ").
    String signoDe(String? loc) => signoParaMostrar(locationSymbols[loc] ?? moneda);

    // La moneda (código) de la sucursal; si no se conoce, el signo.
    String monedaDe(String? loc) => locationCurrencies[loc] ?? signoDe(loc);

    final cierres = <CierreCaja>[];
    for (final r in closed) {
      final signo = signoDe(r.locationId);
      final moneda = monedaDe(r.locationId);
      try {
        cierres.add(CierreCaja.desde(r, orders, signo: signo, moneda: moneda));
      } catch (e) {
        // Un pedido con un dato raro no tira abajo toda la pantalla: ese corte se
        // muestra con los acumulados del corte, sin recalcular desde los pedidos.
        debugPrint('[Cajas] no se pudo recalcular el corte ${r.id} desde los pedidos: $e');
        cierres.add(CierreCaja.desde(r, const [], signo: signo, moneda: moneda));
      }
    }

    return CierresCajaBody(
      cierres: cierres,
      abiertas: open,
      signoDeCaja: signoDe,
      monedaDeCaja: monedaDe,
      ahora: DateTime.now(),
      onVerDetalle: (c) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RegisterDetailScreen(
            register: c.caja,
            expenseItems: expenseItems,
            locationNames: locationNames,
            tenantId: tenantId,
            simbolo: c.signo,
          ),
        ),
      ),
      // Los tres puntos de cada caja abierta: el dueño la puede cerrar.
      accionAbierta: tenantId == null
          ? null
          : (r) => MenuCajaAbierta(
                caja: r,
                onCerrar: () => _cerrarComoAdmin(r, tenantId!),
                onTerminado: onRegisterClosed,
              ),
    );
  }

  /// Cierra la caja a nombre de quien tiene la sesión.
  static Future<ResultadoCierreAdmin> _cerrarComoAdmin(CashRegisterSummary caja, String tenantId) async {
    final sesion = AuthService();
    final nombre = sesion.displayName?.trim() ?? '';
    return CierreAdminService().cerrar(
      cajaId: caja.id,
      tenantId: tenantId,
      adminId: sesion.firestoreUid ?? await sesion.readPersistedUid() ?? '',
      adminNombre: nombre.isNotEmpty ? nombre : (sesion.sessionEmail ?? 'Administrador'),
    );
  }
}
