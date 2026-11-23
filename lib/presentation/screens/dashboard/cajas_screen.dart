import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formato_dinero.dart';
import '../../../data/models/cash_register_summary.dart';
import '../../../data/models/cierres_caja.dart';
import '../../widgets/cierres_caja_view.dart';
import '../../widgets/inicio_ui.dart';
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
      // El cierre forzado solo existe al depurar.
      accionAbierta: kDebugMode ? (r) => _CierreForzado(register: r, onClosed: onRegisterClosed) : null,
    );
  }
}

/// Cierra a la fuerza una caja abierta, igualando lo contado a lo esperado (sin
/// diferencia). SOLO existe en modo debug: está para probar, no para el dueño.
class _CierreForzado extends StatefulWidget {
  final CashRegisterSummary register;
  final VoidCallback? onClosed;
  const _CierreForzado({required this.register, this.onClosed});

  @override
  State<_CierreForzado> createState() => _CierreForzadoState();
}

class _CierreForzadoState extends State<_CierreForzado> {
  bool _closing = false;

  Future<void> _confirmAndClose() async {
    final register = widget.register;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: InicioColores.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cerrar caja (debug)', style: inicioTexto(17, FontWeight.w700, InicioColores.ink)),
        content: Text(
          'Se forzará el cierre de la caja de ${register.userName}, igualando los montos '
          'contados a los esperados (sin diferencia). Solo disponible en modo debug.\n\n'
          'Esta acción no se puede deshacer.',
          style: inicioTexto(14, FontWeight.w400, InicioColores.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: inicioTexto(14, FontWeight.w600, InicioColores.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: InicioColores.bad),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _closing = true);
    try {
      final now = Timestamp.now();
      await FirebaseFirestore.instance.collection('cashRegisters').doc(register.id).set({
        'status': 'closed',
        'closedAt': now,
        'updatedAt': now,
        'syncedAt': now,
        'sync_status': 'synced',
        'actualCash': register.expectedCash,
        'actualCard': register.expectedCard,
        'actualTransfer': register.expectedTransfer,
        'actualPedidosya': register.expectedPedidosya,
        'actualUbereats': register.expectedUbereats,
        'differenceCash': 0.0,
        'differenceCard': 0.0,
        'differenceTransfer': 0.0,
        'differencePedidosya': 0.0,
        'differenceUbereats': 0.0,
        'closingNotes': 'Cierre forzado (debug) desde Sabor Reports',
      }, SetOptions(merge: true));

      widget.onClosed?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cerrar caja: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_closing) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: InicioColores.bad),
        ),
      );
    }
    return IconButton(
      onPressed: _confirmAndClose,
      icon: const Icon(Icons.close_rounded, size: 18),
      color: InicioColores.bad,
      tooltip: 'Cerrar caja (debug)',
      style: IconButton.styleFrom(
        backgroundColor: InicioColores.badTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
