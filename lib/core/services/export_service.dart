import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';
import 'package:intl/intl.dart';
import '../../data/models/cortesias_data.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/inventory_data.dart';
import '../../core/services/location_service.dart';
import '../../core/utils/formato_dinero.dart';
import 'fiscal_reports_service.dart';

class ExportService {
  static final _fmt = NumberFormat('#,##0.00', 'en_US');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');

  // ── PLATILLOS VENDIDOS ────────────────────────────────────────────────────
  static void exportProducts(List<ProductSummary> products, String periodLabel) {
    final excel = Excel.createExcel();
    final sheet = excel['Platillos vendidos'];
    excel.setDefaultSheet('Platillos vendidos');

    // Header
    _header(sheet, ['Nombre', 'Cantidad', 'Total (${moneda.trim()})', 'Var. %']);

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
  /// [signo] nulo: el reporte junta monedas distintas, así que los
  /// encabezados no llevan signo y cada fila dice el suyo en "Moneda".
  static List<String> _cajaHeaders(String? signo) {
    final s = signo == null ? '' : ' ($signo)';
    return [
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
    'Subtotal$s',
    'Propinas$s',
    'Descuentos$s',
    'Cortesía / Donación$s',
    'Total$s',
    if (signo == null) 'Moneda',
  ];
  }

  static void exportCajaReport(
    List<Map<String, dynamic>> orders,
    Set<String> certifiedInvoiceOrderIds,
    Map<String, String> userNamesById,
    String periodLabel, {
    List<Map<String, dynamic>> cancelledOrders = const [],
    Map<String, String> simbolos = const {},
    Map<String, String> nombresSucursal = const {},
  }) {
    _download(
      armarCajaReport(
        orders,
        certifiedInvoiceOrderIds,
        userNamesById,
        cancelledOrders: cancelledOrders,
        simbolos: simbolos,
        nombresSucursal: nombresSucursal,
      ),
      'reporte_caja_${_slug(periodLabel)}.xlsx',
    );
  }

  /// El libro del reporte de caja, sin descargarlo: es lo que se prueba.
  static Excel armarCajaReport(
    List<Map<String, dynamic>> orders,
    Set<String> certifiedInvoiceOrderIds,
    Map<String, String> userNamesById, {
    List<Map<String, dynamic>> cancelledOrders = const [],
    Map<String, String> simbolos = const {},
    Map<String, String> nombresSucursal = const {},
  }) {
    final excel = Excel.createExcel();
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');

    // Cada pedido va en la moneda en que se cobró: este reporte se cuadra
    // contra la caja, que nunca se convierte. Si junta sucursales de monedas
    // distintas, cada fila dice la suya.
    String signoDe(Map<String, dynamic> o) =>
        (simbolos[o['location_id']] ?? moneda).trim();
    final usados = {for (final o in [...orders, ...cancelledOrders]) signoDe(o)};
    final String? signo = usados.length > 1 ? null : (usados.isEmpty ? moneda.trim() : usados.single);
    List<CellValue> conMoneda(List<CellValue> fila, Map<String, dynamic> o) =>
        signo == null ? [...fila, TextCellValue(signoDe(o))] : fila;

    // Hoja 1: órdenes completadas
    final sheet = excel['Reporte de Caja'];
    excel.setDefaultSheet('Reporte de Caja');
    _header(sheet, _cajaHeaders(signo));
    for (final o in orders) {
      sheet.appendRow(conMoneda(_buildCajaRow(o, certifiedInvoiceOrderIds, userNamesById, dateFmt), o));
    }

    // Hoja 2: órdenes canceladas — mismas columnas + Razón de cancelación + Monto cancelado
    final cancelSheet = excel['Órdenes Canceladas'];
    _header(cancelSheet, [
      ..._cajaHeaders(signo),
      'Razón de cancelación',
      signo == null ? 'Monto cancelado' : 'Monto cancelado ($signo)',
    ]);
    for (final o in cancelledOrders) {
      final rawFecha = o['cancelled_at'] ?? o['updated_at'] ?? o['created_at'];
      final baseRow = _buildCajaRow(
        o,
        certifiedInvoiceOrderIds,
        userNamesById,
        dateFmt,
        dateOverride: rawFecha,
      );
      final razon = o['cancellation_reason'] as String? ?? '';
      final monto = (o['total_amount'] as num? ?? 0).toDouble();
      cancelSheet.appendRow([...conMoneda(baseRow, o), TextCellValue(razon), DoubleCellValue(monto)]);
    }

    // Hoja 3: solo lo regalado, de las órdenes completadas.
    _hojaCortesias(
      excel,
      orders,
      signo: signo,
      signoDe: signoDe,
      userNamesById: userNamesById,
      nombresSucursal: nombresSucursal,
      dateFmt: dateFmt,
    );

    return excel;
  }

  /// Hoja "Cortesías": un renglón por cada platillo regalado y, debajo, el
  /// resumen por platillo.
  ///
  /// Sale de [CortesiasReport], el mismo armado que la pantalla de cortesías,
  /// y con la misma cuenta que la tarjeta del Inicio (con extras): la suma de
  /// su columna Monto es la suma de la columna "Cortesía / Donación" de la
  /// hoja de caja. En la moneda en que se cobró, como el resto del reporte.
  static void _hojaCortesias(
    Excel excel,
    List<Map<String, dynamic>> orders, {
    required String? signo,
    required String Function(Map<String, dynamic> o) signoDe,
    required Map<String, String> userNamesById,
    required Map<String, String> nombresSucursal,
    required DateFormat dateFmt,
  }) {
    final sheet = excel['Cortesías'];
    final reporte = CortesiasReport.desde(orders);
    String signoDePedido(CortesiaPedido p) =>
        signoDe({'location_id': p.locationId});
    // El nombre de la sucursal solo ayuda si hay cortesías de más de una.
    final variasSucursales = nombresSucursal.isNotEmpty &&
        {for (final p in reporte.pedidos) p.locationId}.length > 1;

    _header(sheet, [
      'Fecha y hora',
      'Nº Ticket',
      'Mesa / Lugar',
      'Cliente',
      if (variasSucursales) 'Sucursal',
      'Platillo',
      'Extras',
      'Cantidad',
      signo == null ? 'Monto' : 'Monto ($signo)',
      'Tipo',
      'Motivo',
      'Registró',
      if (signo == null) 'Moneda',
    ]);

    if (reporte.vacio) {
      sheet.appendRow(
          [TextCellValue('No hubo cortesías ni donaciones en este período.')]);
      return;
    }

    // De la más vieja a la más nueva, como se lee una hoja de cálculo (la
    // pantalla va al revés porque ahí importa lo último).
    for (final p in reporte.pedidos.reversed) {
      for (final r in p.renglones) {
        final usuario = r.usuarioId == null ? null : userNamesById[r.usuarioId];
        sheet.appendRow([
          TextCellValue(p.fecha == null ? '' : dateFmt.format(p.fecha!)),
          TextCellValue(p.numero.replaceFirst('#', '')),
          TextCellValue(p.lugar),
          TextCellValue(p.cliente ?? ''),
          if (variasSucursales) TextCellValue(nombresSucursal[p.locationId] ?? ''),
          TextCellValue(r.nombre),
          TextCellValue(r.extras.join(' · ')),
          _cantidad(r.cantidad),
          DoubleCellValue(r.monto),
          TextCellValue(r.tipo.etiqueta),
          TextCellValue(r.motivo ?? ''),
          TextCellValue(usuario ?? ''),
          if (signo == null) TextCellValue(signoDePedido(p)),
        ]);
      }
    }

    // El resumen va por moneda si el reporte junta varias: sumar quetzales
    // con pesos no da un total de nada.
    final grupos = signo == null
        ? {for (final p in reporte.pedidos) signoDePedido(p)}.toList()
        : <String>[signo];
    grupos.sort();
    for (final m in grupos) {
      final rep = signo != null
          ? reporte
          : CortesiasReport.desde(
              orders.where((o) => signoDe(o) == m).toList());
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue(signo == null ? 'Resumen por platillo ($m)' : 'Resumen por platillo'),
      ]);
      _header(sheet, ['Platillo', 'Cantidad', 'Monto ($m)', 'Pedidos']);
      for (final pl in rep.platillos) {
        sheet.appendRow([
          TextCellValue(pl.nombre),
          _cantidad(pl.cantidad),
          DoubleCellValue(pl.monto),
          IntCellValue(pl.pedidos),
        ]);
      }
      sheet.appendRow([
        TextCellValue('Total'),
        _cantidad(rep.cantidad),
        DoubleCellValue(rep.total),
      ]);
      // Los pedidos van en su propia fila y no bajo la columna "Pedidos":
      // son pedidos distintos (uno con dos platillos regalados es uno), así
      // que no son la suma de esa columna y ahí se leían como un error.
      sheet.appendRow([
        TextCellValue('Pedidos con cortesía'),
        IntCellValue(rep.pedidos.length),
      ]);
    }
  }

  static CellValue _cantidad(double v) =>
      v == v.roundToDouble() ? IntCellValue(v.toInt()) : DoubleCellValue(v);

  static List<CellValue> _buildCajaRow(
    Map<String, dynamic> o,
    Set<String> certifiedInvoiceOrderIds,
    Map<String, String> userNamesById,
    DateFormat dateFmt, {
    dynamic dateOverride,
  }) {
    final docId   = o['_docId'] as String? ?? '';
    final tipo    = _tipoOrden(o['type'] as String? ?? '');
    final ticket  = '${o['order_prefix'] ?? ''}${o['order_no'] ?? ''}';
    final mesa    = (o['type'] == 'dine_in') ? (o['table_name'] as String? ?? '') : '';
    final fecha   = _parsePaidAt(dateOverride ?? o['paid_at']);
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
    final cortesia = _valorCortesia(o);

    return [
      TextCellValue(cajero),
      TextCellValue(o['created_by_user_name'] as String? ?? ''),
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
      DoubleCellValue(cortesia),
      DoubleCellValue(total),
    ];
  }

  static String _tipoOrden(String type) {
    switch (type) {
      case 'dine_in':    return 'Mesa';
      case 'takeout':    return 'Para llevar';
      case 'pickup':     return 'Pasa a Recoger';
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

  /// Lo regalado en el pedido, con la misma cuenta que la tarjeta del Inicio
  /// y que el ticket: el platillo con sus extras (ver valorCortesia). Antes
  /// eran solo unit_price × qty y no cuadraba con la tarjeta.
  static double _valorCortesia(Map<String, dynamic> o) {
    final items = o['items'];
    if (items is! List) return 0;
    var total = 0.0;
    for (final i in items) {
      if (cuentaComoCortesia(i)) total += valorCortesia(i as Map);
    }
    return total;
  }

  static int _contarItems(Map<String, dynamic> o) {
    final items = o['items'];
    if (items is! List) return 0;
    return items.fold<int>(0, (acc, i) {
      if (i is! Map || i['is_void'] == true) return acc;
      return acc + ((i['qty'] as num? ?? 1).toInt());
    });
  }

  // ── VENTAS POR MÉTODO DE PAGO ────────────────────────────────────────────
  static const _metodoPrioridad = [
    'Efectivo', 'Tarjeta', 'Transferencia', 'PedidosYa', 'UberEats', 'Personalizado',
  ];

  static void exportPaymentMethodReport(
    List<Map<String, dynamic>> orders,
    String periodLabel,
  ) {
    final dayFmt = DateFormat('dd/MM/yyyy');
    final dayKeyFmt = DateFormat('yyyy-MM-dd');

    // dayKey -> método -> total
    final byDay = <String, Map<String, double>>{};
    final methodsPresent = <String>{};

    for (final o in orders) {
      final fecha = _parsePaidAt(o['paid_at']);
      if (fecha == null) continue;
      final dayKey = dayKeyFmt.format(fecha.toLocal());
      final dayMap = byDay.putIfAbsent(dayKey, () => {});
      final t = (o['payment_amount'] as num?)?.toDouble() ??
          (o['total_amount'] as num? ?? 0).toDouble();

      var method = o['payment_method'] as String? ?? 'cash';
      if (method == 'mixed') method = 'split';
      if (method == 'split') {
        final rawSplits = o['split_payments'] ?? o['mixed_payments'];
        final splits = (rawSplits is List ? rawSplits : const [])
            .whereType<Map>()
            .map((s) => {
                  'payment_method': s['payment_method'] ?? s['method'] ?? 'cash',
                  'amount': s['amount'] ?? 0,
                })
            .toList();
        final splitsSum = splits.fold<double>(
            0, (s, sp) => s + ((sp['amount'] as num? ?? 0).toDouble()));
        for (final sp in splits) {
          final m = _traducirMetodo(sp['payment_method'] as String? ?? 'cash');
          final amt = (sp['amount'] as num? ?? 0).toDouble();
          final ratio = splitsSum > 0 ? amt / splitsSum : 0.0;
          final allocated = amt + (t - splitsSum) * ratio;
          methodsPresent.add(m);
          dayMap[m] = (dayMap[m] ?? 0) + allocated;
        }
      } else {
        final m = _traducirMetodo(method);
        methodsPresent.add(m);
        dayMap[m] = (dayMap[m] ?? 0) + t;
      }
    }

    final ordered = [
      ..._metodoPrioridad.where(methodsPresent.contains),
      ...(methodsPresent.difference(_metodoPrioridad.toSet()).toList()..sort()),
    ];

    final excel = Excel.createExcel();
    final sheet = excel['Ventas por Metodo de Pago'];
    excel.setDefaultSheet('Ventas por Metodo de Pago');
    _header(sheet, ['Fecha', ...ordered, 'Total (${moneda.trim()})']);

    final sortedDays = byDay.keys.toList()..sort();
    final grandTotals = <String, double>{for (final m in ordered) m: 0};
    double grandTotal = 0;

    for (final dayKey in sortedDays) {
      final dayMap = byDay[dayKey]!;
      double dayTotal = 0;
      final row = <CellValue>[TextCellValue(dayFmt.format(dayKeyFmt.parse(dayKey)))];
      for (final m in ordered) {
        final v = dayMap[m] ?? 0;
        dayTotal += v;
        grandTotals[m] = (grandTotals[m] ?? 0) + v;
        row.add(DoubleCellValue(v));
      }
      grandTotal += dayTotal;
      row.add(DoubleCellValue(dayTotal));
      sheet.appendRow(row);
    }

    final totalRow = <CellValue>[TextCellValue('TOTAL')];
    for (final m in ordered) {
      totalRow.add(DoubleCellValue(grandTotals[m] ?? 0));
    }
    totalRow.add(DoubleCellValue(grandTotal));
    sheet.appendRow(totalRow);

    _download(excel, 'ventas_metodo_pago_${_slug(periodLabel)}.xlsx');
  }

  static DateTime? _parsePaidAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      try { return DateTime.parse(raw); } catch (_) { return null; }
    }
    return null;
  }

  // ── HONDURAS: DOCUMENTOS NO UTILIZADOS (Art. 42) ──────────────────────────
  /// El listado que el obligado tributario debe comunicar al SAR "dentro de los
  /// primeros diez (10) días hábiles del mes siguiente" de que un rango
  /// venciera, se agotara o se diera de baja.
  ///
  /// Sale en Excel y no en pantalla porque su destino no es leerlo: es
  /// entregarlo. Quien lo presenta es el contador, desde una computadora, una
  /// vez al mes.
  static void exportUnusedNumbers(
    List<UnusedNumber> numbers,
    String periodLabel,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['No utilizados'];
    excel.setDefaultSheet('No utilizados');

    _header(sheet, ['No. de documento', 'CAI', 'Motivo']);

    for (final n in numbers) {
      sheet.appendRow([
        TextCellValue(n.number),
        TextCellValue(n.cai),
        TextCellValue(n.cause),
      ]);
    }

    if (numbers.isEmpty) {
      sheet.appendRow([
        TextCellValue('Sin documentos no utilizados en el período'),
      ]);
    }

    _download(excel, 'no_utilizados_${_slug(periodLabel)}.xlsx');
  }

  // ── HONDURAS: RESUMEN DE VENTAS POR ISV (Art. 38) ─────────────────────────
  /// El resumen que debe presentar quien emite en papel térmico.
  ///
  /// Va separado por tarifa porque así se declara el ISV: las ventas al 15% y
  /// las del 18% se informan por aparte, igual que en la declaración mensual.
  static void exportIsvSummary(
    List<IsvSummaryLine> lines,
    String periodLabel,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Resumen ISV'];
    excel.setDefaultSheet('Resumen ISV');

    _header(sheet, [
      'Tarifa',
      'Importe gravado (L)',
      'ISV (L)',
      'Facturas',
    ]);

    var totalBase = 0.0;
    var totalIsv = 0.0;
    for (final line in lines) {
      sheet.appendRow([
        TextCellValue(line.rateLabel),
        DoubleCellValue(line.taxable),
        DoubleCellValue(line.tax),
        IntCellValue(line.invoices),
      ]);
      totalBase += line.taxable;
      totalIsv += line.tax;
    }

    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL'),
      DoubleCellValue(double.parse(totalBase.toStringAsFixed(2))),
      DoubleCellValue(double.parse(totalIsv.toStringAsFixed(2))),
      TextCellValue(''),
    ]);

    _download(excel, 'resumen_isv_${_slug(periodLabel)}.xlsx');
  }

}
