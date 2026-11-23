import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/firestore_service.dart';
import '../../../core/utils/formato_dinero.dart';
import '../../../data/models/cash_register_summary.dart';
import '../../../data/models/detalle_caja.dart';
import '../../widgets/detalle_caja_view.dart';
import '../../widgets/inicio_ui.dart';
import '../../widgets/max_content_width.dart';

/// El detalle de un corte: los pedidos que se cobraron en esa caja y sus gastos.
///
/// Rediseño 2026-11-21 (cierres-caja.html, en su modo oscuro). Esta pantalla solo
/// lee los pedidos de la caja y arma el andamio; qué pedidos son de la caja lo
/// decide `DetalleCaja.ordenesDeLaCaja` y lo que se ve lo dibuja
/// [DetalleCajaBody] (se prueba a 360dp sin Firebase).
class RegisterDetailScreen extends StatefulWidget {
  final CashRegisterSummary register;
  final List<Map<String, dynamic>> expenseItems;
  final Map<String, String> locationNames;
  final String? tenantId;

  /// Signo de la moneda de la sucursal de esta caja. La caja nunca se
  /// convierte: se ve en lo que de verdad entró.
  final String? simbolo;

  const RegisterDetailScreen({
    super.key,
    required this.register,
    required this.expenseItems,
    required this.locationNames,
    this.tenantId,
    this.simbolo,
  });

  @override
  State<RegisterDetailScreen> createState() => _RegisterDetailScreenState();
}

class _RegisterDetailScreenState extends State<RegisterDetailScreen> {
  PestanaCaja _pestana = PestanaCaja.pedidos;
  bool _cargando = true;
  bool _error = false;
  DetalleCaja _detalle = DetalleCaja.vacio;
  late final List<GastoCaja> _gastos;

  @override
  void initState() {
    super.initState();
    _gastos = GastoCaja.deLaCaja(widget.expenseItems, widget.register.id);
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    final reg = widget.register;
    final tenantId = widget.tenantId;
    if (tenantId == null || tenantId.isEmpty) {
      setState(() => _cargando = false);
      return;
    }

    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final rangeEnd = reg.closedAt ?? DateTime.now();
      final openBuffer = reg.openedAt.subtract(const Duration(seconds: 1));
      final closeBuffer = rangeEnd.add(const Duration(seconds: 1));

      final fs = FirestoreService().instance;

      // Query por Timestamp (formato principal de paid_at)
      final snapTs = await fs
          .collection('orders')
          .where('tenant_id', isEqualTo: tenantId)
          .where('paid_at', isGreaterThanOrEqualTo: Timestamp.fromDate(openBuffer))
          .where('paid_at', isLessThanOrEqualTo: Timestamp.fromDate(closeBuffer))
          .get();

      // Query por ISO string (formato offline: paid_at se guarda como hora local sin timezone)
      final openIso = openBuffer.toIso8601String().substring(0, 23);
      final closeIso = closeBuffer.toIso8601String().substring(0, 23);

      final snapIso = await fs
          .collection('orders')
          .where('tenant_id', isEqualTo: tenantId)
          .where('paid_at', isGreaterThanOrEqualTo: openIso)
          .where('paid_at', isLessThanOrEqualTo: closeIso)
          .get();

      final seen = <String>{};
      final todas = <Map<String, dynamic>>[];
      for (final snap in [snapTs, snapIso]) {
        for (final doc in snap.docs) {
          if (seen.add(doc.id)) todas.add(doc.data());
        }
      }

      if (!mounted) return;
      setState(() {
        _detalle = DetalleCaja.desde(
          DetalleCaja.ordenesDeLaCaja(todas, reg),
          nombresMetodos: reg.customMethodNames,
        );
        _cargando = false;
      });
    } catch (e) {
      // Un error no se muestra como "sin pedidos": la caja pudo tener cientos.
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signo = signoParaMostrar(widget.simbolo ?? moneda);
    return MonedaLocal(
      simbolo: signo,
      child: Scaffold(
        backgroundColor: kInicioBg,
        body: SafeArea(
          child: MaxContentWidth(
            maxWidth: 1280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetalleCajaEncabezado(
                  caja: widget.register,
                  pestana: _pestana,
                  onPestana: (p) => setState(() => _pestana = p),
                  onRegresar: () => Navigator.of(context).maybePop(),
                  pedidos: _cargando || _error ? null : _detalle.pedidos.length,
                  gastos: _gastos.length,
                ),
                Expanded(
                  child: DetalleCajaBody(
                    caja: widget.register,
                    detalle: _detalle,
                    gastos: _gastos,
                    pestana: _pestana,
                    signo: signo,
                    cargando: _cargando,
                    error: _error,
                    onReintentar: _cargarPedidos,
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
