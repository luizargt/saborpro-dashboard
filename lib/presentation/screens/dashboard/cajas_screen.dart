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
                    if (register.closingNotes != null &&
                        register.closingNotes!.trim().isNotEmpty &&
                        register.totalDifference != null &&
                        register.totalDifference!.abs() >= 0.01) ...[
                      const SizedBox(height: 5),
                      _JustificationBadge(register.closingNotes!.trim()),
                    ],
                  ],
                ),
              ],
            ),
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
                _SummaryRow(label: 'Venta Efectivo', value: register.salesCash, fmt: fmt, indent: true, sales: true),
                const SizedBox(height: 5),
                _SummaryRow(label: 'Depósitos', value: register.totalDeposits, fmt: fmt, indent: true),
                const SizedBox(height: 5),
                _SummaryRow(label: 'Retiros', value: register.totalWithdrawals, fmt: fmt, indent: true, negative: true),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Total Efectivo',
                  value: register.initialCash + register.salesCash + register.totalDeposits - register.totalWithdrawals,
                  fmt: fmt,
                  highlight: true,
                ),

                // ── OTROS MÉTODOS ─────────────────────────
                if (register.salesCard > 0) ...[
                  const SizedBox(height: 10),
                  _SummaryRow(label: 'Venta Tarjeta', value: register.salesCard, fmt: fmt, sales: true),
                ],
                if (register.salesTransfer > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'Venta Transferencia', value: register.salesTransfer, fmt: fmt, sales: true),
                ],
                if (register.salesPedidosya > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'PedidosYa', value: register.salesPedidosya, fmt: fmt, sales: true),
                ],
                if (register.salesUbereats > 0) ...[
                  const SizedBox(height: 5),
                  _SummaryRow(label: 'Uber Eats', value: register.salesUbereats, fmt: fmt, sales: true),
                ],
                ...register.expectedCustomMethods.entries
                    .where((e) => e.value > 0)
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: _SummaryRow(
                            label: register.customMethodNames[e.key] ?? e.key,
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
                  value: register.initialCash + register.salesCash + register.totalDeposits - register.totalWithdrawals +
                      register.salesCard + register.salesTransfer + register.salesPedidosya + register.salesUbereats +
                      register.expectedCustomMethods.values.fold(0.0, (a, b) => a + b),
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

    void add(String label, double salesExpected, double? actual, double initial,
        {double withdrawals = 0, double deposits = 0}) {
      // "Esperado neto" = ventas del método - retiros en efectivo + depósitos
      final adjustedExpected = salesExpected - withdrawals + deposits;
      final salesActual = actual != null ? actual - initial : null;
      if (adjustedExpected == 0 && (salesActual == null || salesActual == 0)) return;
      list.add(_MethodData(label: label, expected: adjustedExpected, actual: salesActual));
    }

    add('Efectivo', r.salesCash, r.actualCash, r.initialCash,
        withdrawals: r.totalWithdrawals, deposits: r.totalDeposits);
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
        Text(
          label,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 12,
            fontWeight: (highlight || total) ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const Spacer(),
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
