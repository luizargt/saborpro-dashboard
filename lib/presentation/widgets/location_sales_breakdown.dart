import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/services/location_service.dart';

// ── LOCATION SALES BREAKDOWN ─────────────────────────────────────────────────
// Tabla que se muestra solo en la vista "Todas las sucursales": monto vendido
// por sucursal y % de participación respecto al total del período.
class LocationSalesBreakdown extends StatelessWidget {
  final List<LocationModel> locations;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> expenseItems;
  final List<Map<String, dynamic>> purchaseItems;

  const LocationSalesBreakdown({
    super.key,
    required this.locations,
    required this.orders,
    required this.expenseItems,
    required this.purchaseItems,
  });

  static const _palette = [
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF7444fd),
    Color(0xFF14B8A6),
  ];

  Map<String, double> _sumByLocation(List<Map<String, dynamic>> items, String amountField) {
    final result = <String, double>{};
    for (final item in items) {
      final locId = item['location_id'] as String?;
      if (locId == null || locId.isEmpty) continue;
      final amount = (item[amountField] as num?)?.toDouble() ?? 0;
      result[locId] = (result[locId] ?? 0) + amount;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (locations.length <= 1) return const SizedBox.shrink();

    // payment_amount no siempre está presente; usamos fallback a total_amount por orden.
    final sales = <String, double>{};
    for (final o in orders) {
      final locId = o['location_id'] as String?;
      if (locId == null || locId.isEmpty) continue;
      final amount = (o['payment_amount'] as num?)?.toDouble() ?? (o['total_amount'] as num?)?.toDouble() ?? 0;
      sales[locId] = (sales[locId] ?? 0) + amount;
    }

    final expensesByLoc = _sumByLocation(expenseItems, 'amount');
    final purchasesByLoc = _sumByLocation(purchaseItems, 'total');

    final rows = locations
        .map((loc) => (
              loc: loc,
              sales: sales[loc.id] ?? 0,
              utilidad: (sales[loc.id] ?? 0) - (expensesByLoc[loc.id] ?? 0) - (purchasesByLoc[loc.id] ?? 0),
            ))
        .where((r) => r.sales != 0)
        .toList()
      ..sort((a, b) => b.sales.compareTo(a.sales));

    if (rows.isEmpty) return const SizedBox.shrink();

    final total = rows.fold<double>(0, (s, r) => s + r.sales);
    final fmt = NumberFormat('#,##0', 'en_US');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ventas por sucursal',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _LocationRow(
              color: _palette[i % _palette.length],
              name: rows[i].loc.name,
              sales: rows[i].sales,
              utilidad: rows[i].utilidad,
              percent: total > 0 ? (rows[i].sales / total) * 100 : 0,
              fmt: fmt,
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final Color color;
  final String name;
  final double sales;
  final double utilidad;
  final double percent;
  final NumberFormat fmt;

  const _LocationRow({
    required this.color,
    required this.name,
    required this.sales,
    required this.utilidad,
    required this.percent,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0, 1),
            minHeight: 4,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Q ${fmt.format(sales)} · utilidad ${utilidad < 0 ? '-' : ''}Q ${fmt.format(utilidad.abs())}',
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
