import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cash_register_summary.dart';
import 'register_detail_screen.dart';

class CajasScreen extends StatelessWidget {
  final List<CashRegisterSummary> open;
  final List<CashRegisterSummary> closed;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> expenseItems;
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
    this.tenantId,
    this.onRegisterClosed,
  });

  @override
  Widget build(BuildContext context) {
    if (open.isEmpty && closed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Text(
            'Sin cierres de caja en este período',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open.isNotEmpty) ...[
          _sectionLabel('En caja ahora'),
          const SizedBox(height: 8),
          ...open.map((r) => _OpenRegisterCard(register: r, onClosed: onRegisterClosed)),
          const SizedBox(height: 20),
        ],
        if (closed.isNotEmpty) ...[
          _sectionLabel('Cierres del período'),
          const SizedBox(height: 8),
          ...closed.map((r) => _ClosedRegisterCard(
                register: r,
                orders: orders,
                expenseItems: expenseItems,
                locationNames: locationNames,
                tenantId: tenantId,
              )),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── CAJA ABIERTA ─────────────────────────────────────────────────────────────
class _OpenRegisterCard extends StatefulWidget {
  final CashRegisterSummary register;
  final VoidCallback? onClosed;
  const _OpenRegisterCard({required this.register, this.onClosed});

  @override
  State<_OpenRegisterCard> createState() => _OpenRegisterCardState();
}

class _OpenRegisterCardState extends State<_OpenRegisterCard> {
  bool _closing = false;

  Future<void> _confirmAndClose() async {
    final register = widget.register;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cerrar caja (debug)', style: GoogleFonts.inter(color: Colors.white)),
        content: Text(
          'Se forzará el cierre de la caja de ${register.userName}, igualando los montos '
          'contados a los esperados (sin diferencia). Solo disponible en modo debug.\n\n'
          'Esta acción no se puede deshacer.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
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
    final register = widget.register;
    final timeFmt = DateFormat('hh:mm a');
    final durStr = _formatDuration(register.duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  register.userName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Abierta desde las ${timeFmt.format(register.openedAt)}  •  $durStr',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
                if (register.locationName != null)
                  Text(
                    register.locationName!,
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (kDebugMode) ...[
            if (_closing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                ),
              )
            else
              IconButton(
                onPressed: _confirmAndClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFFEF4444),
                tooltip: 'Cerrar caja (debug)',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444).withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ACTIVA',
              style: GoogleFonts.inter(
                color: const Color(0xFF22C55E),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── CIERRE DE CAJA ───────────────────────────────────────────────────────────
class _ClosedRegisterCard extends StatelessWidget {
  final CashRegisterSummary register;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> expenseItems;
  final Map<String, String> locationNames;
  final String? tenantId;

  const _ClosedRegisterCard({
    required this.register,
    required this.orders,
    required this.expenseItems,
    required this.locationNames,
    this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('hh:mm a');
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final dur = _formatDuration(register.duration);

    // Cuando el cierre tiene diferencias almacenadas (differenceCash != null), usarlas
    // directamente porque son las calculadas desde órdenes reales al momento del cierre.
    // Si no hay diferencias almacenadas (registros antiguos), recalcular desde órdenes.
    final hasDiffs = register.differenceCash != null;
    final calc = hasDiffs ? const _SalesCalc() : _calcSalesFromOrders(register, orders);
    final salesCash = calc.hasOrders ? calc.cash : register.salesCash;
    final salesCard = calc.hasOrders ? calc.card : register.salesCard;
    final salesTransfer = calc.hasOrders ? calc.transfer : register.salesTransfer;
    final salesPedidosya = calc.hasOrders ? calc.pedidosya : register.salesPedidosya;
    final salesUbereats = calc.hasOrders ? calc.ubereats : register.salesUbereats;
    final totalSales = calc.hasOrders ? calc.total : register.totalSales;
    // Las ventas de métodos propios: de las órdenes si se recalculó, si no las
    // del corte (ver CashRegisterSummary.ventasPropias). Las mismas para las
    // filas, el Total y la tabla: el Total no las sumaba en un corte sellado.
    final ventasPropias = calc.hasOrders ? calc.custom : register.ventasPropias;

    // Diferencia total: usar la almacenada cuando hay diffs, recalcular si no
    double? totalDifference = register.totalDifference;
    if (!hasDiffs && calc.hasOrders) {
      final hasActual = register.actualCash != null || register.actualCard != null ||
          register.actualTransfer != null || register.actualPedidosya != null ||
          register.actualUbereats != null || register.actualCustomMethods.isNotEmpty;
      if (hasActual) {
        final counted = (register.actualCash ?? 0) - register.initialCash +
            (register.actualCard ?? 0) - register.initialCard +
            (register.actualTransfer ?? 0) - register.initialTransfer +
            (register.actualPedidosya ?? 0) - register.initialPedidosya +
            (register.actualUbereats ?? 0) - register.initialUbereats +
            register.actualCustomMethods.values.fold(0.0, (a, b) => a + b);
        totalDifference = counted - totalSales + register.totalWithdrawals - register.totalDeposits;
      }
    }

    final methods = _buildMethodsCalc(register, salesCash, salesCard, salesTransfer, salesPedidosya, salesUbereats, ventasPropias);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: cajero + total ventas
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        register.userName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${timeFmt.format(register.openedAt)} → ${timeFmt.format(register.closedAt!)}  •  $dur',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                      ),
                      if (register.locationName != null)
                        Text(
                          register.locationName!,
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Q${fmt.format(totalSales)}',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF7444fd),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'en ventas',
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                    ),
                    if (totalDifference != null) ...[
                      const SizedBox(height: 5),
                      _StatusBadge(totalDifference),
                    ],
                    if (register.closingNotes != null &&
                        register.closingNotes!.trim().isNotEmpty &&
                        totalDifference != null &&
                        totalDifference.abs() >= 0.01) ...[
                      const SizedBox(height: 5),
                      _JustificationBadge(register.closingNotes!.trim()),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Se cerró más de una vez (otro aparato no se enteró del cierre): el
          // dueño tiene que ver el otro conteo en el corte mismo.
          if (register.cierresNoAplicados.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: CierresNoAplicadosBlock(register),
            ),

          // Desglose resumen de la caja
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── EFECTIVO ─────────────────────────────
                Text(
                  'Efectivo',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                _SummaryRow(label: 'Apertura', value: register.initialCash, fmt: fmt, indent: true),
                const SizedBox(height: 5),
                _SummaryRow(label: 'Venta Efectivo', value: salesCash, fmt: fmt, indent: true, sales: true),
                const SizedBox(height: 5),
                _SummaryRow(label: 'Depósitos', value: register.totalDeposits, fmt: fmt, indent: true),
                const SizedBox(height: 5),
                _SummaryRow(label: 'Retiros', value: register.totalWithdrawals, fmt: fmt, indent: true, negative: true),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Total Efectivo',
                  value: register.initialCash + salesCash + register.totalDeposits - register.totalWithdrawals,
                  fmt: fmt,
                  highlight: true,
                ),

                // ── OTROS MÉTODOS ─────────────────────────
                if (salesCard > 0) ...[
                  const SizedBox(height: 10),
                  _SummaryRow(label: 'Venta Tarjeta', value: salesCard, fmt: fmt, sales: true),
                ],
                if (salesTransfer > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'Venta Transferencia', value: salesTransfer, fmt: fmt, sales: true),
                ],
                if (salesPedidosya > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'PedidosYa', value: salesPedidosya, fmt: fmt, sales: true),
                ],
                if (salesUbereats > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'Uber Eats', value: salesUbereats, fmt: fmt, sales: true),
                ],
                ...ventasPropias.entries
                    .where((e) => e.value > 0)
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _SummaryRow(
                            label: _nombreDelMetodo(register, e.key),
                            value: e.value,
                            fmt: fmt,
                            sales: true,
                          ),
                        )),

                // ── TOTAL ─────────────────────────────────
                const SizedBox(height: 10),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Total',
                  value: register.initialCash + salesCash + register.totalDeposits - register.totalWithdrawals +
                      salesCard + salesTransfer + salesPedidosya + salesUbereats +
                      ventasPropias.values.fold(0.0, (a, b) => a + b),
                  fmt: fmt,
                  total: true,
                ),
              ],
            ),
          ),

          // Tabla de métodos de pago
          if (methods.isNotEmpty) ...[
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  _colHeader('Método', flex: 3),
                  _colHeader('Esperado', flex: 2, right: true),
                  _colHeader('Contado', flex: 2, right: true),
                  _colHeader('Dif.', flex: 2, right: true),
                ],
              ),
            ),
            ...methods.map((m) => _MethodRow(method: m, fmt: fmt)),
            const SizedBox(height: 6),
          ],

          // Enlace ver detalle
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RegisterDetailScreen(
                  register: register,
                  expenseItems: expenseItems,
                  locationNames: locationNames,
                  tenantId: tenantId,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'ver detalle',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF7444fd),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios,
                      size: 11, color: Color(0xFF7444fd)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String text, {int flex = 1, bool right = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: GoogleFonts.inter(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  List<_MethodData> _buildMethodsCalc(
    CashRegisterSummary r,
    double salesCash, double salesCard, double salesTransfer,
    double salesPedidosya, double salesUbereats,
    Map<String, double> salesCustom,
  ) {
    final list = <_MethodData>[];

    void add(String label, double salesExpected, double? actual, double initial,
        {double withdrawals = 0, double deposits = 0}) {
      final adjustedExpected = salesExpected - withdrawals + deposits;
      final salesActual = actual != null ? actual - initial : null;
      if (adjustedExpected == 0 && (salesActual == null || salesActual == 0)) return;
      list.add(_MethodData(label: label, expected: adjustedExpected, actual: salesActual));
    }

    add('Efectivo', salesCash, r.actualCash, r.initialCash,
        withdrawals: r.totalWithdrawals, deposits: r.totalDeposits);
    add('Tarjeta', salesCard, r.actualCard, r.initialCard);
    add('Transferencia', salesTransfer, r.actualTransfer, r.initialTransfer);
    add('PedidosYa', salesPedidosya, r.actualPedidosya, r.initialPedidosya);
    add('Uber Eats', salesUbereats, r.actualUbereats, r.initialUbereats);

    // En un corte sellado, lo contado de un método propio es esperado + su
    // diferencia sellada, como en el ticket del POS: uno que no se declaró sale
    // con su faltante, uno declarado sin ventas con su sobrante, y el de un
    // cierre forzado sin diferencia. Así la tabla suma lo mismo que la insignia.
    final sellado = r.differenceCash != null;
    salesCustom.forEach((id, expected) {
      final actual = sellado
          ? expected + (r.differenceCustomMethods[id] ?? 0)
          : r.actualCustomMethods[id];
      if (expected.abs() < 0.005 && (actual ?? 0).abs() < 0.005) return;
      list.add(_MethodData(label: _nombreDelMetodo(r, id), expected: expected, actual: actual));
    });

    return list;
  }
}

/// Los otros cierres de un corte, hechos cuando la caja ya estaba cerrada (en
/// otro aparato que no se enteró): no cambian su cuadre, pero el dueño los ve
/// con su hora, su aparato y lo que se contó.
///
/// Dice cuál vale por su hora y no "el primero": un aparato sin internet pudo
/// cerrar antes y mandarlo después. Mismas palabras que el historial del POS.
class CierresNoAplicadosBlock extends StatelessWidget {
  final CashRegisterSummary register;
  const CierresNoAplicadosBlock(this.register, {super.key});

  static final _fmt = NumberFormat('#,##0.00', 'en_US');

  /// El mismo formato de hora que la tarjeta del corte: el dueño compara las dos.
  static final _hora = DateFormat('hh:mm a');

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static DateTime? _fecha(dynamic v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  static String _cuando(DateTime f) => '${_dos(f.day)}/${_dos(f.month)} a las ${_hora.format(f)}';

  static String _monto(dynamic v) => 'Q${_fmt.format(v is num ? v.toDouble() : 0.0)}';

  static bool _usado(dynamic v) => v is num && v.abs() > 0.004;

  String _cierre(Map<String, dynamic> c) {
    final modelo = c['device_model'];
    final en = modelo is String &&
            modelo.trim().isNotEmpty &&
            modelo.trim().toLowerCase() != 'desconocido'
        ? ' en ${modelo.trim()}'
        : '';

    // Los métodos propios por su nombre; los que no tienen nombre, en un solo
    // "otros".
    final propios = <String, double>{};
    var sinNombre = 0.0;
    final otros = c['actualCustomMethods'];
    if (otros is Map) {
      for (final e in otros.entries) {
        if (!_usado(e.value)) continue;
        final valor = (e.value as num).toDouble();
        final nombre = register.customMethodNames[e.key.toString()]?.trim();
        if (nombre == null || nombre.isEmpty) {
          sinNombre += valor;
        } else {
          propios[nombre] = (propios[nombre] ?? 0) + valor;
        }
      }
    }

    final contado = [
      'efectivo ${_monto(c['actualCash'])}',
      if (_usado(c['actualCard'])) 'tarjeta ${_monto(c['actualCard'])}',
      if (_usado(c['actualTransfer'])) 'transferencia ${_monto(c['actualTransfer'])}',
      if (_usado(c['actualPedidosya'])) 'PedidosYa ${_monto(c['actualPedidosya'])}',
      if (_usado(c['actualUbereats'])) 'Uber Eats ${_monto(c['actualUbereats'])}',
      for (final e in propios.entries) '${e.key} ${_monto(e.value)}',
      if (_usado(sinNombre)) 'otros ${_monto(sinNombre)}',
    ].join(', ');
    final fecha = _fecha(c['closed_at']);
    if (fecha == null) return 'Contó $contado.';
    // Uno hecho ANTES que el que vale: si no se dice que llegó después, parece
    // que el sistema se quedó con el equivocado.
    final vigente = register.closedAt?.toLocal();
    final tarde = vigente != null && fecha.isBefore(vigente) ? ', pero llegó después' : '';
    return 'Se hizo el ${_cuando(fecha)}$en$tarde. Contó $contado.';
  }

  @override
  Widget build(BuildContext context) {
    const ambar = Color(0xFFF59E0B);
    final cierres = register.cierresNoAplicados;
    final uno = cierres.length == 1;
    final vigente = register.closedAt?.toLocal();
    // El cierre forzado no contó nada: da por contado lo esperado. El conteo
    // real es el de abajo.
    final forzado = register.closingNotes?.contains('Cierre forzado') ?? false;
    final titulo =
        uno ? 'Esta caja se cerró dos veces' : 'Esta caja se cerró ${cierres.length + 1} veces';
    final explicacion = forzado
        ? 'Se cerró sin contar el dinero (cierre forzado), así que el cuadre de '
            'este corte no es real. ${uno ? 'Este es el conteo que se hizo' : 'Estos '
                'son los conteos que se hicieron'}: compáralo con lo esperado.'
        : 'Vale el cierre ${vigente == null ? 'de este corte' : 'del ${_cuando(vigente)}'}. '
            '${uno ? 'Este otro llegó' : 'Estos otros llegaron'} cuando la caja ya '
            'estaba cerrada y no ${uno ? 'cambia' : 'cambian'} el cuadre:';
    final texto = GoogleFonts.inter(color: ambar, fontSize: 11, height: 1.4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ambar.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ambar.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: texto.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(explicacion, style: texto),
          const SizedBox(height: 4),
          for (final c in cierres)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(_cierre(c), style: texto),
            ),
        ],
      ),
    );
  }
}

class _JustificationBadge extends StatelessWidget {
  final String notes;
  const _JustificationBadge(this.notes);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 11, color: Color(0xFFF59E0B)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              notes,
              style: GoogleFonts.inter(
                color: const Color(0xFFF59E0B),
                fontSize: 10,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat fmt;
  final bool highlight;
  final bool negative;
  final bool total;
  final bool indent;
  final bool sales;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.fmt,
    this.highlight = false,
    this.negative = false,
    this.total = false,
    this.indent = false,
    this.sales = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (total) {
      color = Colors.white;
    } else if (negative && value > 0) {
      color = const Color(0xFFEF4444);
    } else if (highlight) {
      color = const Color(0xFF22C55E);
    } else if (sales) {
      color = const Color(0xFF7444fd);
    } else {
      color = Colors.white38;
    }

    final String valueText;
    if (value == 0 && !total) {
      valueText = '-';
    } else if (negative && value > 0) {
      valueText = '-Q${fmt.format(value)}';
    } else {
      valueText = 'Q${fmt.format(value)}';
    }

    return Row(
      children: [
        if (indent) const SizedBox(width: 12),
        // Expanded y no Spacer: el nombre de un método propio puede ser largo
        // y a 360 dp desbordaba la fila; así pasa a otra línea.
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: (highlight || total) ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          valueText,
          style: GoogleFonts.inter(
            color: color,
            fontSize: total ? 13 : 12,
            fontWeight: (highlight || total) ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final double difference;
  const _StatusBadge(this.difference);

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    if (difference.abs() < 0.01) {
      label = 'Exacto';
      color = const Color(0xFF22C55E);
    } else if (difference > 0) {
      label = 'Sobrante';
      color = const Color(0xFFF59E0B);
    } else {
      label = 'Faltante';
      color = const Color(0xFFEF4444);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// El nombre de un método propio. 'otros' es donde el POS junta los pagos con
/// un método que no reconoce, y 'custom' la clave de ventas viejas sin el id
/// del método: los dos salían con el id crudo.
String _nombreDelMetodo(CashRegisterSummary r, String id) =>
    r.customMethodNames[id] ??
    switch (id) {
      'otros' => 'Otros (revisar)',
      'custom' => 'Personalizado',
      _ => id,
    };

class _MethodData {
  final String label;
  final double expected;
  final double? actual;
  double? get difference => actual != null ? actual! - expected : null;
  _MethodData({required this.label, required this.expected, this.actual});
}

class _MethodRow extends StatelessWidget {
  final _MethodData method;
  final NumberFormat fmt;
  const _MethodRow({required this.method, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final diff = method.difference;
    final diffColor = diff == null
        ? Colors.white38
        : diff < -0.01
            ? const Color(0xFFEF4444)
            : diff > 0.01
                ? const Color(0xFF22C55E)
                : Colors.white38;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              method.label,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Q${fmt.format(method.expected)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              method.actual != null ? 'Q${fmt.format(method.actual!)}' : '—',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              diff != null
                  ? '${diff >= 0 ? '+' : ''}Q${fmt.format(diff)}'
                  : '—',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: diffColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

// ── CÁLCULO DE VENTAS DESDE ÓRDENES ──────────────────────────────────────────
// Recalcula las ventas por método desde las órdenes reales en lugar de usar
// los valores acumulados del registro (que pueden tener inconsistencias de sync).

class _SalesCalc {
  final double cash, card, transfer, pedidosya, ubereats;
  final Map<String, double> custom;
  final bool hasOrders;

  const _SalesCalc({
    this.cash = 0, this.card = 0, this.transfer = 0,
    this.pedidosya = 0, this.ubereats = 0,
    this.custom = const {}, this.hasOrders = false,
  });

  double get total => cash + card + transfer + pedidosya + ubereats +
      custom.values.fold(0.0, (a, b) => a + b);
}

_SalesCalc _calcSalesFromOrders(
    CashRegisterSummary reg, List<Map<String, dynamic>> orders) {
  if (orders.isEmpty) return const _SalesCalc();

  final rangeEnd = reg.closedAt ?? DateTime.now();
  final openBuf = reg.openedAt.subtract(const Duration(seconds: 1));
  final closeBuf = rangeEnd.add(const Duration(seconds: 1));
  final locId = reg.locationId ?? '';

  double cash = 0, card = 0, transfer = 0, py = 0, ue = 0;
  final customMap = <String, double>{};
  bool found = false;

  for (final o in orders) {
    if ((o['status'] as String? ?? '') == 'CANCELLED') continue;
    if (locId.isNotEmpty && o['location_id'] != locId) continue;

    final paidAt = _tsToDate(o['paid_at']);
    if (paidAt == null) continue;
    if (!paidAt.isAfter(openBuf) || !paidAt.isBefore(closeBuf)) continue;

    found = true;
    final amount = _orderAmount(o);
    final method = o['payment_method'] as String? ?? 'cash';

    if (method == 'split') {
      final splits = (o['split_payments'] as List<dynamic>?)
              ?.whereType<Map>()
              .toList() ??
          [];
      if (splits.isEmpty) {
        cash += amount;
      } else {
        for (final sp in splits) {
          final sm = sp['payment_method'] as String? ?? 'cash';
          final sa = (sp['amount'] as num? ?? 0).toDouble();
          _addToMethod(sm, sa, (v) => cash += v, (v) => card += v,
              (v) => transfer += v, (v) => py += v, (v) => ue += v, customMap);
        }
      }
    } else if (method == 'mixed') {
      final mps = (o['mixed_payments'] as List<dynamic>?)?.whereType<Map>().toList() ?? [];
      if (mps.isEmpty) {
        cash += amount;
      } else {
        for (final mp in mps) {
          final mm = mp['method'] as String? ?? 'cash';
          final ma = (mp['amount'] as num? ?? 0).toDouble();
          _addToMethod(mm, ma, (v) => cash += v, (v) => card += v,
              (v) => transfer += v, (v) => py += v, (v) => ue += v, customMap);
        }
      }
    } else {
      _addToMethod(method, amount, (v) => cash += v, (v) => card += v,
          (v) => transfer += v, (v) => py += v, (v) => ue += v, customMap);
    }
  }

  if (!found) return const _SalesCalc();
  return _SalesCalc(
    cash: cash, card: card, transfer: transfer,
    pedidosya: py, ubereats: ue, custom: customMap, hasOrders: true,
  );
}

void _addToMethod(
  String method, double amount,
  void Function(double) cash, void Function(double) card,
  void Function(double) transfer, void Function(double) pedidosya,
  void Function(double) ubereats, Map<String, double> custom,
) {
  switch (method) {
    case 'cash': cash(amount); break;
    case 'card': card(amount); break;
    case 'transfer': transfer(amount); break;
    case 'pedidosya': pedidosya(amount); break;
    case 'ubereats': ubereats(amount); break;
    default:
      if (method.startsWith('custom_') || method == 'custom') {
        custom[method] = (custom[method] ?? 0) + amount;
      } else {
        cash(amount);
      }
  }
}

double _orderAmount(Map<String, dynamic> o) {
  final pm = o['payment_amount'];
  if (pm is num && pm > 0) return pm.toDouble();
  if (pm is String) {
    final v = double.tryParse(pm);
    if (v != null && v > 0) return v;
  }
  final ta = o['total_amount'];
  if (ta is num) return ta.toDouble();
  if (ta is String) return double.tryParse(ta) ?? 0.0;
  return 0.0;
}

DateTime? _tsToDate(dynamic ts) {
  if (ts is DateTime) return ts.toLocal();
  if (ts is String) return DateTime.tryParse(ts)?.toLocal();
  if (ts is Timestamp) return ts.toDate().toLocal();
  try { return (ts as dynamic).toDate().toLocal() as DateTime; } catch (_) {}
  return null;
}
