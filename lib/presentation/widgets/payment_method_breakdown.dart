import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class PaymentMethodBreakdown extends StatelessWidget {
  final Map<String, double> salesByMethod;
  final Map<String, String> customMethodNames;

  const PaymentMethodBreakdown({
    super.key,
    required this.salesByMethod,
    this.customMethodNames = const {},
  });

  static const _knownNames = {
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'transfer': 'Transferencia',
    'pedidosya': 'PedidosYa',
    'ubereats': 'Uber Eats',
    '_tips': 'Propinas',
  };

  static const _knownColors = {
    'cash': Color(0xFF22C55E),
    'card': Color(0xFF3B82F6),
    'transfer': Color(0xFF06B6D4),
    'pedidosya': Color(0xFFF59E0B),
    'ubereats': Color(0xFFEF4444),
    '_tips': Color(0xFFF59E0B),
  };

  String _name(String key) {
    if (_knownNames.containsKey(key)) return _knownNames[key]!;
    if (customMethodNames.containsKey(key)) return customMethodNames[key]!;
    final cleaned = key.replaceAll('custom_', '');
    return cleaned.length > 12 ? cleaned.substring(0, 12) : cleaned;
  }

  Color _color(String key, int index) {
    if (_knownColors.containsKey(key)) return _knownColors[key]!;
    const fallback = [
      Color(0xFF7444fd), Color(0xFFF97316), Color(0xFFEC4899),
      Color(0xFF8B5CF6), Color(0xFF14B8A6),
    ];
    return fallback[index % fallback.length];
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    // Propinas al final, el resto ordenado por monto
    final entries = salesByMethod.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) {
        if (a.key == '_tips') return 1;
        if (b.key == '_tips') return -1;
        return b.value.compareTo(a.value);
      });

    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold(0.0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VENTAS POR MÉTODO DE PAGO',
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ...entries.asMap().entries.map((entry) {
          final idx = entry.key;
          final e = entry.value;
          final color = _color(e.key, idx);
          final pct = total > 0 ? e.value / total : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _name(e.key),
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      'Q${fmt.format(e.value)}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(color: Color(0x1AFFFFFF)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Q${fmt.format(total)}',
              style: GoogleFonts.inter(
                color: const Color(0xFF7444fd),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
