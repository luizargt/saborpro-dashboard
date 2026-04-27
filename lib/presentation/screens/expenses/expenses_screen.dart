import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../presentation/providers/dashboard_provider.dart';
import '../../../presentation/widgets/period_selector.dart';
import '../../../presentation/widgets/location_selector.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return RefreshIndicator(
      color: const Color(0xFF7444fd),
      backgroundColor: const Color(0xFF1E293B),
      onRefresh: provider.load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(builder: (ctx) {
                    final wide = MediaQuery.of(ctx).size.width >= 600;
                    if (wide) {
                      return const Row(
                        children: [
                          Expanded(child: DateNavigator()),
                          SizedBox(width: 8),
                          LocationSelector(),
                        ],
                      );
                    }
                    return const DateNavigator();
                  }),
                  const SizedBox(height: 16),
                  if (provider.loading)
                    const SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF7444fd)),
                      ),
                    )
                  else if (provider.error != null)
                    _ErrorView(error: provider.error!, onRetry: provider.load)
                  else
                    _ExpensesBody(
                      expenseItems: provider.expenseItems,
                      purchaseItems: provider.purchaseItems,
                      expenseRawCount: provider.expenseRawCount,
                      expenseSampleDate: provider.expenseSampleDate,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              Text(error,
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7444fd)),
                child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
}

class _ExpensesBody extends StatelessWidget {
  final List<Map<String, dynamic>> expenseItems;
  final List<Map<String, dynamic>> purchaseItems;
  final int expenseRawCount;
  final String expenseSampleDate;

  const _ExpensesBody({
    required this.expenseItems,
    required this.purchaseItems,
    required this.expenseRawCount,
    required this.expenseSampleDate,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    String q(double v) => 'Q${fmt.format(v)}';

    final totalExpenses = expenseItems.fold<double>(
        0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble());
    final totalPurchases = purchaseItems.fold<double>(
        0, (s, e) => s + (e['total'] as num? ?? 0).toDouble());
    final grandTotal = totalExpenses + totalPurchases;

    final hasExpenses = expenseItems.isNotEmpty;
    final hasPurchases = purchaseItems.isNotEmpty;

    if (!hasExpenses && !hasPurchases) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sin gastos registrados en este período',
                  style: TextStyle(color: Colors.white38)),
              const SizedBox(height: 12),
              // Info de diagnóstico
              Text('Docs en Firestore: $expenseRawCount',
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
              if (expenseSampleDate.isNotEmpty)
                Text('Fecha de muestra: $expenseSampleDate',
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                    textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Ordenar gastos por fecha descendente
    final sortedExpenses = [...expenseItems];
    sortedExpenses.sort((a, b) {
      final da = a['date'] as String? ?? '';
      final db = b['date'] as String? ?? '';
      return db.compareTo(da);
    });

    final sortedPurchases = [...purchaseItems];
    sortedPurchases.sort((a, b) {
      final da = a['received_at'] as String? ?? '';
      final db = b['received_at'] as String? ?? '';
      return db.compareTo(da);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card total
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_outlined, color: Color(0xFFEF4444), size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total gastos del período',
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(q(grandTotal),
                      style: GoogleFonts.inter(
                          color: const Color(0xFFEF4444),
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sección gastos operacionales
        if (hasExpenses) ...[
          _SectionHeader(
            icon: Icons.receipt_long_outlined,
            label: 'Gastos operacionales',
            total: q(totalExpenses),
            color: const Color(0xFFEF4444),
            count: sortedExpenses.length,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < sortedExpenses.length; i++) ...[
                  _ExpenseRow(item: sortedExpenses[i], fmt: fmt),
                  if (i < sortedExpenses.length - 1)
                    const Divider(
                        color: Color(0x1AFFFFFF), height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Sección compras / insumos
        if (hasPurchases) ...[
          _SectionHeader(
            icon: Icons.inventory_2_outlined,
            label: 'Compras / insumos',
            total: q(totalPurchases),
            color: const Color(0xFFF97316),
            count: sortedPurchases.length,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < sortedPurchases.length; i++) ...[
                  _PurchaseRow(item: sortedPurchases[i], fmt: fmt),
                  if (i < sortedPurchases.length - 1)
                    const Divider(
                        color: Color(0x1AFFFFFF), height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String total;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.total,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$count',
              style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        Text(total,
            style: GoogleFonts.inter(
                color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final NumberFormat fmt;

  const _ExpenseRow({required this.item, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final category = item['category_name'] as String? ?? 'Sin categoría';
    final description = item['description'] as String?;
    final amount = (item['amount'] as num? ?? 0).toDouble();
    final dateStr = item['date'] as String? ?? '';
    final type = item['type'] as String?;
    final source = item['source'] as String?;
    final assignedTo = item['assigned_to'] as String?;

    String dateLabel = '';
    try {
      if (dateStr.isNotEmpty) {
        final dt = DateTime.parse(dateStr);
        dateLabel = DateFormat('d MMM', 'es').format(dt);
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Indicador de categoría
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_categoryIcon(category),
                size: 16, color: const Color(0xFFEF4444).withOpacity(0.8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Descripción como texto principal
                Text(
                  (description != null && description.isNotEmpty) ? description : category,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Categoría - Tipo - Fuente como subtítulo
                Text(
                  [
                    category,
                    if (type == 'fixed') 'Fijo' else 'Variable',
                    if (source == 'cashRegister') 'Caja',
                  ].join(' · '),
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
                if (assignedTo != null && (assignedTo as String).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(assignedTo as String,
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Q${fmt.format(amount)}',
                  style: GoogleFonts.inter(
                      color: const Color(0xFFEF4444),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(dateLabel,
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('agua') || c.contains('luz') || c.contains('electric') || c.contains('servicio')) {
      return Icons.bolt_outlined;
    }
    if (c.contains('alquil') || c.contains('renta') || c.contains('arrend')) {
      return Icons.home_outlined;
    }
    if (c.contains('sueldo') || c.contains('salario') || c.contains('personal') || c.contains('nomina')) {
      return Icons.people_outlined;
    }
    if (c.contains('publicidad') || c.contains('marketing') || c.contains('promoc')) {
      return Icons.campaign_outlined;
    }
    if (c.contains('manten') || c.contains('reparac')) {
      return Icons.build_outlined;
    }
    if (c.contains('limpieza') || c.contains('higiene')) {
      return Icons.cleaning_services_outlined;
    }
    return Icons.receipt_outlined;
  }
}

class _PurchaseRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final NumberFormat fmt;

  const _PurchaseRow({required this.item, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final supplier = item['supplier_name'] as String?;
    final notes = item['notes'] as String?;
    final total = (item['total'] as num? ?? 0).toDouble();
    final orderNumber = item['order_number'];
    final receivedAt = item['received_at'] as String? ?? '';
    final items = item['items'] as List<dynamic>? ?? [];

    String dateLabel = '';
    try {
      if (receivedAt.isNotEmpty) {
        final dt = DateTime.parse(receivedAt);
        dateLabel = DateFormat('d MMM', 'es').format(dt);
      }
    } catch (_) {}

    final itemCount = items.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                size: 16, color: Color(0xFFF97316)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier ?? 'Sin proveedor',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(notes,
                      style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (orderNumber != null)
                      _Tag(label: '#$orderNumber', color: const Color(0xFFF97316)),
                    if (orderNumber != null && itemCount > 0) const SizedBox(width: 4),
                    if (itemCount > 0)
                      _Tag(
                          label: '$itemCount ${itemCount == 1 ? 'insumo' : 'insumos'}',
                          color: Colors.white38),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Q${fmt.format(total)}',
                  style: GoogleFonts.inter(
                      color: const Color(0xFFF97316),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(dateLabel,
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
