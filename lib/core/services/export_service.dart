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
}
