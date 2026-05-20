import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cash_register_summary.dart';

class RegisterDetailScreen extends StatefulWidget {
  final CashRegisterSummary register;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> expenseItems;
  final Map<String, String> locationNames;

  const RegisterDetailScreen({
    super.key,
    required this.register,
    required this.orders,
    required this.expenseItems,
    required this.locationNames,
  });

  @override
  State<RegisterDetailScreen> createState() => _RegisterDetailScreenState();
}

class _RegisterDetailScreenState extends State<RegisterDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  late final List<Map<String, dynamic>> _orders;
  late final List<Map<String, dynamic>> _expenses;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    final reg = widget.register;
    final rangeEnd = reg.closedAt ?? DateTime.now();
    final openBuffer = reg.openedAt.subtract(const Duration(seconds: 1));
    final closeBuffer = rangeEnd.add(const Duration(seconds: 1));

    _orders = widget.orders.where((o) {
      // Misma sucursal
      if (reg.locationId != null && reg.locationId!.isNotEmpty) {
        if (o['location_id'] != reg.locationId) return false;
      }
      // Mismo cajero (igual que CashRegisterCalculator)
      if (reg.userId.isNotEmpty) {
        if (o['paid_by_user_id'] != reg.userId) return false;
      }
      // Rango de tiempo con buffer de 1 segundo
      final paidAt = _toDateTime(o['paid_at']);
      if (paidAt == null) return false;
      return paidAt.isAfter(openBuffer) && paidAt.isBefore(closeBuffer);
    }).toList()
      ..sort((a, b) {
        final da = _toDateTime(a['paid_at']);
        final db = _toDateTime(b['paid_at']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    _expenses = widget.expenseItems
        .where((e) =>
            e['source'] == 'cashRegister' &&
            e['register_id'] == widget.register.id)
        .toList()
      ..sort((a, b) =>
          (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('hh:mm a');
    final reg = widget.register;
    final subtitle = reg.closedAt != null
        ? '${timeFmt.format(reg.openedAt)} → ${timeFmt.format(reg.closedAt!)}  ·  ${reg.locationName ?? ''}'
        : 'Abierta desde ${timeFmt.format(reg.openedAt)}  ·  ${reg.locationName ?? ''}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reg.userName,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF7444fd),
          indicatorWeight: 2,
          labelColor: const Color(0xFF7444fd),
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
          tabs: [
            Tab(text: 'Pedidos (${_orders.length})'),
            Tab(text: 'Gastos (${_expenses.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrdersTab(
            orders: _orders,
            locationNames: widget.locationNames,
          ),
          _ExpensesTab(expenses: _expenses),
        ],
      ),
    );
  }
}

// ── PESTAÑA PEDIDOS ───────────────────────────────────────────────────────────

class _OrdersTab extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final Map<String, String> locationNames;

  const _OrdersTab({required this.orders, required this.locationNames});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          'Sin pedidos en esta caja',
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    final fmt = NumberFormat('#,##0.00', 'en_US');

    return Column(
      children: [
        // Encabezado de columnas (sticky)
        _TableHeader(),
        const Divider(color: Color(0x1AFFFFFF), height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (int i = 0; i < orders.length; i++) ...[
                  _OrderRow(
                    order: orders[i],
                    fmt: fmt,
                    locationNames: locationNames,
                    even: i.isEven,
                  ),
                  if (i < orders.length - 1)
                    const Divider(
                        color: Color(0x0DFFFFFF), height: 1, indent: 14, endIndent: 14),
                ],
              ],
            ),
          ),
        ),
        // Fila de totales
        const Divider(color: Color(0x2AFFFFFF), height: 1),
        _TotalsRow(orders: orders, fmt: fmt),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _hdr('Fecha / Hora', 120),
            _hdr('Usuario', 110),
            _hdr('Sucursal', 100),
            _hdr('#Pedido', 70, right: true),
            _hdr('SubTotal', 90, right: true),
            _hdr('Descuentos', 90, right: true),
            _hdr('Propinas', 80, right: true),
            _hdr('Cortesía', 80, right: true),
            _hdr('Total Pagado', 100, right: true),
            _hdr('Método', 100),
          ],
        ),
      ),
    );
  }

  Widget _hdr(String text, double width, {bool right = false}) {
    return SizedBox(
      width: width,
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
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final NumberFormat fmt;
  final Map<String, String> locationNames;
  final bool even;

  const _OrderRow({
    required this.order,
    required this.fmt,
    required this.locationNames,
    required this.even,
  });

  @override
  Widget build(BuildContext context) {
    final paidAt = _toDateTime(order['paid_at']);
    final dateStr = paidAt != null
        ? DateFormat('dd/MM/yy hh:mm a').format(paidAt)
        : '—';

    final userName = order['paid_by_user_name'] as String? ??
        order['waiter_name'] as String? ??
        order['created_by_user_name'] as String? ??
        '—';

    final locationId = order['location_id'] as String? ?? '';
    final locationName = locationId.isNotEmpty
        ? (locationNames[locationId] ?? locationId)
        : '—';

    final orderNo = order['order_no'];
    final orderPrefix = order['order_prefix'] as String? ?? '';
    final orderNumStr = orderNo != null ? '$orderPrefix$orderNo' : '—';

    final total = _parseAmount(order['payment_amount']) ??
        _parseAmount(order['total_amount']) ??
        0.0;
    final subtotal = (order['subtotal'] as num?)?.toDouble() ?? total;
    final discounts = (order['discount_amount'] as num? ?? 0).toDouble();
    final tips = (order['tip_amount'] as num? ?? 0).toDouble();
    final courtesy = _courtesyTotal(order);

    final method = _methodLabel(
        order['payment_method'] as String? ?? 'cash');

    return Container(
      color: even ? Colors.transparent : const Color(0x06FFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _cell(dateStr, 120,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            _cell(userName, 110,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
            _cell(locationName, 100,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            _cell(orderNumStr, 70,
                right: true,
                style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            _amtCell(subtotal, 90, fmt),
            _amtCell(discounts, 90, fmt, negative: true),
            _amtCell(tips, 80, fmt, accent: const Color(0xFF22C55E)),
            _amtCell(courtesy, 80, fmt, accent: const Color(0xFFF59E0B)),
            _cell('Q${fmt.format(total)}', 100,
                right: true,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            _methodBadge(method, 100),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, double width,
      {bool right = false, TextStyle? style}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: style ??
            GoogleFonts.inter(color: Colors.white70, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _amtCell(double value, double width, NumberFormat fmt,
      {bool negative = false, Color? accent}) {
    if (value == 0) {
      return SizedBox(
        width: width,
        child: Text('—',
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(color: Colors.white24, fontSize: 12)),
      );
    }
    final Color color;
    if (negative) {
      color = const Color(0xFFEF4444);
    } else if (accent != null) {
      color = accent;
    } else {
      color = Colors.white54;
    }
    final prefix = negative ? '-Q' : 'Q';
    return SizedBox(
      width: width,
      child: Text(
        '$prefix${fmt.format(value)}',
        textAlign: TextAlign.right,
        style: GoogleFonts.inter(color: color, fontSize: 12),
      ),
    );
  }

  Widget _methodBadge(String label, double width) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF7444fd).withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF7444fd),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final NumberFormat fmt;

  const _TotalsRow({required this.orders, required this.fmt});

  @override
  Widget build(BuildContext context) {
    double subtotal = 0, discounts = 0, tips = 0, courtesy = 0, total = 0;
    for (final o in orders) {
      final t = _parseAmount(o['payment_amount']) ??
          _parseAmount(o['total_amount']) ??
          0.0;
      subtotal += (o['subtotal'] as num?)?.toDouble() ?? t;
      discounts += (o['discount_amount'] as num? ?? 0).toDouble();
      tips += (o['tip_amount'] as num? ?? 0).toDouble();
      courtesy += _courtesyTotal(o);
      total += t;
    }

    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 120 + 110 + 100 + 70,
              child: Text(
                '${orders.length} pedidos',
                style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
            _tot('Q${fmt.format(subtotal)}', 90),
            _tot(discounts > 0 ? '-Q${fmt.format(discounts)}' : '—', 90,
                color: discounts > 0 ? const Color(0xFFEF4444) : Colors.white24),
            _tot(tips > 0 ? 'Q${fmt.format(tips)}' : '—', 80,
                color: tips > 0 ? const Color(0xFF22C55E) : Colors.white24),
            _tot(courtesy > 0 ? 'Q${fmt.format(courtesy)}' : '—', 80,
                color: courtesy > 0 ? const Color(0xFFF59E0B) : Colors.white24),
            _tot('Q${fmt.format(total)}', 100,
                color: Colors.white, bold: true),
            const SizedBox(width: 100),
          ],
        ),
      ),
    );
  }

  Widget _tot(String text, double width,
      {Color color = Colors.white54, bool bold = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

// ── PESTAÑA GASTOS ────────────────────────────────────────────────────────────

class _ExpensesTab extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;

  const _ExpensesTab({required this.expenses});

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Center(
        child: Text(
          'Sin gastos registrados en esta caja',
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    final fmt = NumberFormat('#,##0.00', 'en_US');
    final total = expenses.fold<double>(
        0, (s, e) => s + (e['amount'] as num? ?? 0).toDouble());

    return Column(
      children: [
        // Total banner
        Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text('Total gastos',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
              const Spacer(),
              Text('Q${fmt.format(total)}',
                  style: GoogleFonts.inter(
                      color: const Color(0xFFEF4444),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const Divider(color: Color(0x1AFFFFFF), height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: expenses.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Color(0x1AFFFFFF), height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) => _ExpenseRow(item: expenses[i], fmt: fmt),
          ),
        ),
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
    final registeredBy = item['registered_by'] as String?;

    String dateLabel = '';
    try {
      if (dateStr.isNotEmpty) {
        final dt = DateTime.parse(dateStr);
        dateLabel = DateFormat('d MMM hh:mm a', 'es').format(dt);
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (description != null && description.isNotEmpty)
                      ? description
                      : category,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    category,
                    if (registeredBy != null && registeredBy.isNotEmpty)
                      registeredBy,
                  ].join(' · '),
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
                if (dateLabel.isNotEmpty)
                  Text(dateLabel,
                      style:
                          GoogleFonts.inter(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
          Text(
            'Q${fmt.format(amount)}',
            style: GoogleFonts.inter(
                color: const Color(0xFFEF4444),
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────

double _courtesyTotal(Map<String, dynamic> order) {
  final items = order['items'] as List<dynamic>? ?? [];
  double total = 0;
  for (final item in items) {
    if (item is! Map) continue;
    if (item['is_courtesy'] != true) continue;
    final qty = (item['qty'] as num? ?? item['quantity'] as num? ?? 1).toDouble();
    final price =
        (item['unit_price'] as num? ?? item['price'] as num? ?? 0).toDouble();
    total += qty * price;
  }
  return total;
}

String _methodLabel(String method) {
  switch (method) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'transfer':
      return 'Transferencia';
    case 'pedidosya':
      return 'PedidosYa';
    case 'ubereats':
      return 'Uber Eats';
    case 'split':
    case 'mixed':
      return 'Mixto';
    default:
      return method;
  }
}

double? _parseAmount(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _toDateTime(dynamic ts) {
  if (ts is DateTime) return ts.toLocal();
  if (ts is String) return DateTime.tryParse(ts)?.toLocal();
  // Firestore Timestamp duck-type
  try {
    return (ts as dynamic).toDate().toLocal() as DateTime;
  } catch (_) {}
  return null;
}
