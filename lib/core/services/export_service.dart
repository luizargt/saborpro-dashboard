import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/inventory_data.dart';
import '../../core/services/location_service.dart';

class ExportService {
  static final _fmt = NumberFormat('#,##0.00', 'en_US');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');

  // ── PLATILLOS VENDIDOS ────────────────────────────────────────────────────
  static void exportProducts(List<ProductSummary> products, String periodLabel) {
    final excel = Excel.createExcel();
    final sheet = excel['Platillos vendidos'];
    excel.setDefaultSheet('Platillos vendidos');

    // Header
    _header(sheet, ['Nombre', 'Cantidad', 'Total (Q)', 'Var. %']);

    // Filas
    for (final p in products) {
      final change = p.changePercent;
      sheet.appendRow([
        TextCellValue(p.name),
        IntCellValue(p.quantity),
        DoubleCellValue(p.total),
        TextCellValue(change == 0 ? '—' : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%'),
      ]);
    }

    // Total
    final totalQty = products.fold<int>(0, (s, p) => s + p.quantity);
    final totalAmt = products.fold<double>(0, (s, p) => s + p.total);
    sheet.appendRow([
      TextCellValue('TOTAL'),
      IntCellValue(totalQty),
      DoubleCellValue(totalAmt),
      TextCellValue(''),
    ]);

    _download(excel, 'platillos_${_slug(periodLabel)}.xlsx');
  }

  // ── INVENTARIO ────────────────────────────────────────────────────────────
  static void exportInventory(
    List<IngredientStock> items,
    List<LocationModel> locations,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Inventario'];
    excel.setDefaultSheet('Inventario');

    // Header
    final headers = [
      'Ingrediente',
      'Unidad',
      'Estado',
      ...locations.map((l) => l.name),
      ...locations.map((l) => '${l.name} (días)'),
      'Total stock',
    ];
    _header(sheet, headers);

    // Filas
    for (final item in items) {
      final status = _statusLabel(item.worstStatus);
      final row = <CellValue>[
        TextCellValue(item.name),
        TextCellValue(item.unit),
        TextCellValue(status),
        ...locations.map((l) {
          final v = item.stockByLocation[l.id];
          return v != null ? DoubleCellValue(v) : TextCellValue('—');
        }),
        ...locations.map((l) {
          final d = item.daysRemainingByLocation[l.id];
          return d != null ? IntCellValue(d.round()) : TextCellValue('—');
        }),
        DoubleCellValue(item.totalStock),
      ];
      sheet.appendRow(row);
    }

    _download(excel, 'inventario_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  static void _header(Sheet sheet, List<String> cols) {
    sheet.appendRow(cols.map((c) => TextCellValue(c)).toList());
  }

  static String _statusLabel(StockStatus s) {
    switch (s) {
      case StockStatus.critical: return 'Crítico';
      case StockStatus.low:      return 'Bajo stock';
      case StockStatus.ok:       return 'OK';
      case StockStatus.noData:   return 'Sin datos';
    }
  }

  static String _slug(String label) =>
      label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

  static void _download(Excel excel, String filename) {
    final bytes = excel.encode();
    if (bytes == null) return;
    downloadExcel(bytes, filename);
  }

  // ── REPORTE DE CAJA ───────────────────────────────────────────────────────
  static void exportCajaReport(
    List<Map<String, dynamic>> orders,
    Set<String> certifiedInvoiceOrderIds,
    Map<String, String> userNamesById,
    String periodLabel,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Reporte de Caja'];
    excel.setDefaultSheet('Reporte de Caja');

    _header(sheet, [
      'Cajero',
      'Mesero',
      'Tipo de pedido',
      'Nº Ticket',
      'Mesa / Zona',
      'Fecha y hora',
      'Método de pago',
      'Tipo de venta',
      'Comprobante',
      'Cant. items',
      'Subtotal (Q)',
      'Propinas (Q)',
      'Descuentos (Q)',
      'Total (Q)',
    ]);

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');

    for (final o in orders) {
      final docId   = o['_docId'] as String? ?? '';
      final tipo    = _tipoOrden(o['type'] as String? ?? '');
      final ticket  = '${o['order_prefix'] ?? ''}${o['order_no'] ?? ''}';
      final mesa    = (o['type'] == 'dine_in') ? (o['table_name'] as String? ?? '') : '';
      final fecha   = _parsePaidAt(o['paid_at']);
      final metodo  = _metodoPago(o);
      final venta   = _tipoVenta(o);
      final comprobante = certifiedInvoiceOrderIds.contains(docId) ? 'Factura' : '—';
      final cantItems = _contarItems(o);
      final propina   = (o['tip_amount']      as num? ?? 0).toDouble();
      final descuento = (o['discount_amount'] as num? ?? 0).toDouble();
      final total     = (o['payment_amount']  as num? ?? o['total_amount'] as num? ?? 0).toDouble();
      final stored    = (o['subtotal']        as num? ?? 0).toDouble();
      final subtotal  = stored > 0 ? stored : total - propina + descuento;

      final paidByUserId = o['paid_by_user_id'] as String? ?? '';
      final cajero = (o['paid_by_user_name'] as String? ?? '').isNotEmpty
          ? o['paid_by_user_name'] as String
          : userNamesById[paidByUserId] ?? '';

      sheet.appendRow([
        TextCellValue(cajero),
        TextCellValue(o['created_by_user_name']  as String? ?? ''),
        TextCellValue(tipo),
        TextCellValue(ticket),
        TextCellValue(mesa),
        TextCellValue(fecha != null ? dateFmt.format(fecha.toLocal()) : ''),
        TextCellValue(metodo),
        TextCellValue(venta),
        TextCellValue(comprobante),
        IntCellValue(cantItems),
        DoubleCellValue(subtotal),
        DoubleCellValue(propina),
        DoubleCellValue(descuento),
        DoubleCellValue(total),
      ]);
    }

    _download(excel, 'reporte_caja_${_slug(periodLabel)}.xlsx');
  }

  static String _tipoOrden(String type) {
    switch (type) {
      case 'dine_in':    return 'Mesa';
      case 'takeout':    return 'Para llevar';
      case 'delivery':   return 'Delivery';
      case 'quick_sale': return 'Venta rápida';
      default:           return type;
    }
  }

  static String _metodoPago(Map<String, dynamic> o) {
    final method = o['payment_method'] as String? ?? '';
    if (method == 'split' || method == 'mixed') {
      final splits = o['split_payments'] ?? o['mixed_payments'];
      if (splits is List && splits.isNotEmpty) {
        final parts = splits
            .map((s) {
              if (s is! Map) return '';
              return _traducirMetodo(s['payment_method'] as String? ?? s['method'] as String? ?? '');
            })
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (parts.isNotEmpty) return parts.join(' + ');
      }
    }
    return _traducirMetodo(method);
  }

  static String _traducirMetodo(String method) {
    switch (method) {
      case 'cash':       return 'Efectivo';
      case 'card':       return 'Tarjeta';
      case 'transfer':   return 'Transferencia';
      case 'pedidosya':  return 'PedidosYa';
      case 'ubereats':   return 'UberEats';
      default:
        if (method.startsWith('custom_')) return 'Personalizado';
        return method;
    }
  }

  static String _tipoVenta(Map<String, dynamic> o) {
    final items = o['items'];
    if (items is List && items.isNotEmpty) {
      final active = items.where((i) => i is Map && i['is_void'] != true);
      if (active.isNotEmpty && active.every((i) => i is Map && i['is_courtesy'] == true)) {
        final courtesyType = active.first['courtesy_type'] as String?;
        if (courtesyType == 'DONACION') return 'Donación';
        return 'Cortesía';
      }
    }
    final total = (o['payment_amount'] as num? ?? o['total_amount'] as num? ?? 0).toDouble();
    if (total == 0) return 'Cortesía';
    return 'Venta';
  }

  static int _contarItems(Map<String, dynamic> o) {
    final items = o['items'];
    if (items is! List) return 0;
    return items.fold<int>(0, (acc, i) {
      if (i is! Map || i['is_void'] == true) return acc;
      return acc + ((i['qty'] as num? ?? 1).toInt());
    });
  }

  static DateTime? _parsePaidAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      try { return DateTime.parse(raw); } catch (_) { return null; }
    }
    return null;
  }
}
