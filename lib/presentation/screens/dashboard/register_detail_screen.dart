import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/services/firestore_service.dart';
import '../../../data/models/cash_register_summary.dart';

class RegisterDetailScreen extends StatefulWidget {
  final CashRegisterSummary register;
  final List<Map<String, dynamic>> expenseItems;
  final Map<String, String> locationNames;
  final String? tenantId;

  const RegisterDetailScreen({
    super.key,
    required this.register,
    required this.expenseItems,
    required this.locationNames,
    this.tenantId,
  });

  @override
  State<RegisterDetailScreen> createState() => _RegisterDetailScreenState();
}

class _RegisterDetailScreenState extends State<RegisterDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  late final List<Map<String, dynamic>> _expenses;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _filterExpenses();
    _loadOrders();
  }

  void _filterExpenses() {
    _expenses = widget.expenseItems
        .where((e) =>
            e['source'] == 'cashRegister' &&
            e['register_id'] == widget.register.id)
        .toList()
      ..sort((a, b) =>
          (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
  }

  Future<void> _loadOrders() async {
    final reg = widget.register;
    final tenantId = widget.tenantId;
    if (tenantId == null || tenantId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

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

      final results = [snapTs, snapIso];

      final seen = <String>{};
      final all = <Map<String, dynamic>>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          if (seen.add(doc.id)) all.add(doc.data());
        }
      }

      // Filtrar en memoria: excluir canceladas, filtrar por sucursal y por cajero.
      // Filtramos por paid_by_user_id cuando está disponible para mostrar solo las
      // órdenes cobradas por este cajero. Si el campo está vacío (órdenes muy antiguas),
      // se incluye la orden para mantener compatibilidad con registros históricos.
      final locationId = reg.locationId ?? '';
      final registerId = reg.userId;
      final filtered = all.where((o) {
        final status = o['status'] as String? ?? '';
        if (status == 'CANCELLED') return false;

        if (locationId.isNotEmpty) {
          if (o['location_id'] != locationId) return false;
        }

        final paidByUserId = o['paid_by_user_id'] as String? ?? '';
        if (paidByUserId.isNotEmpty && paidByUserId != registerId) return false;

        return true;
      }).toList()
        ..sort((a, b) {
          final da = _toDateTime(a['paid_at']);
          final db = _toDateTime(b['paid_at']);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });

      setState(() {
        _orders = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
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
            Tab(text: _loading ? 'Pedidos' : 'Pedidos (${_orders.length})'),
            Tab(text: 'Gastos (${_expenses.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7444fd)))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.construction_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Text(
                        'Esta sección está en desarrollo',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFF59E0B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OrdersTab(
                        orders: _orders,
                        locationNames: widget.locationNames,
                      ),
                      _ExpensesTab(expenses: _expenses),
                    ],
                  ),
                ),
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

    final rawMethod = order['payment_method'] as String? ?? 'cash';
    final method = _methodLabel(rawMethod);

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
            _methodBadge(method, rawMethod, 100),
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

  Widget _methodBadge(String label, String rawMethod, double width) {
    final color = _methodColor(rawMethod);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: color,
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
    case 'cash':        return 'Efectivo';
    case 'card':        return 'Tarjeta';
    case 'transfer':    return 'Transferencia';
    case 'pedidosya':   return 'PedidosYa';
    case 'ubereats':    return 'Uber Eats';
    case 'split':
    case 'mixed':       return 'Mixto';
    default:            return method;
  }
}

Color _methodColor(String method) {
  switch (method) {
    case 'cash':        return const Color(0xFF22C55E); // verde
    case 'card':        return const Color(0xFF3B82F6); // azul
    case 'transfer':    return const Color(0xFF06B6D4); // cyan
    case 'pedidosya':   return const Color(0xFFF59E0B); // amarillo
    case 'ubereats':    return const Color(0xFFF97316); // naranja
    case 'split':
    case 'mixed':       return const Color(0xFFA855F7); // violeta
    default:            return const Color(0xFF94A3B8); // gris
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
  try {
    return (ts as dynamic).toDate().toLocal() as DateTime;
  } catch (_) {}
  return null;
}
