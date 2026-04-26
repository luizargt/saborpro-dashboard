import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cash_register_summary.dart';

class CajasScreen extends StatelessWidget {
  final List<CashRegisterSummary> open;
  final List<CashRegisterSummary> closed;

  const CajasScreen({super.key, required this.open, required this.closed});

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
          ...open.map((r) => _OpenRegisterCard(register: r)),
          const SizedBox(height: 20),
        ],
        if (closed.isNotEmpty) ...[
          _sectionLabel('Cierres del período'),
          const SizedBox(height: 8),
          ...closed.map((r) => _ClosedRegisterCard(register: r)),
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
class _OpenRegisterCard extends StatelessWidget {
  final CashRegisterSummary register;
  const _OpenRegisterCard({required this.register});

  @override
  Widget build(BuildContext context) {
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
  const _ClosedRegisterCard({required this.register});

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('hh:mm a');
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final dur = _formatDuration(register.duration);
    final methods = _buildMethods(register);

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
                      'Q${fmt.format(register.totalSales)}',
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
                    if (register.totalDifference != null) ...[
                      const SizedBox(height: 5),
                      _StatusBadge(register.totalDifference!),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Fondo inicial (si hay)
          if (register.totalInitial > 0) ...[
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 13, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    'Fondo inicial',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    'Q${fmt.format(register.totalInitial)}',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

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

  List<_MethodData> _buildMethods(CashRegisterSummary r) {
    final list = <_MethodData>[];

    void add(String label, double salesExpected, double? actual, double initial) {
      // Mostrar si hay ventas o si se contó algo
      final salesActual = actual != null ? actual - initial : null;
      if (salesExpected == 0 && (salesActual == null || salesActual == 0)) return;
      list.add(_MethodData(label: label, expected: salesExpected, actual: salesActual));
    }

    add('Efectivo', r.salesCash, r.actualCash, r.initialCash);
    add('Tarjeta', r.salesCard, r.actualCard, r.initialCard);
    add('Transferencia', r.salesTransfer, r.actualTransfer, r.initialTransfer);
    add('PedidosYa', r.salesPedidosya, r.actualPedidosya, r.initialPedidosya);
    add('Uber Eats', r.salesUbereats, r.actualUbereats, r.initialUbereats);

    r.expectedCustomMethods.forEach((id, expected) {
      if (expected == 0) return;
      final actual = r.actualCustomMethods[id];
      final name = r.customMethodNames[id] ?? id;
      list.add(_MethodData(label: name, expected: expected, actual: actual));
    });

    return list;
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
