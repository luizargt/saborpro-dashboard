import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/date_range.dart';
import '../../data/models/profitability_data.dart';
import 'dashboard_provider.dart';

/// Categorías de gasto que son sueldos. Entran en el costo primo.
const _idsSueldos = {'salarios'};

/// Movimientos de inventario que forman el costo de lo vendido.
const _tipoSalidaVenta = 'salidaVenta';

class ProfitabilityProvider extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  ProfitabilityData _data = ProfitabilityData.vacio;
  bool _loading = false;
  String? _error;
  String? _cacheKey;

  ProfitabilityData get data => _data;
  bool get loading => _loading;
  String? get error => _error;

  static String _keyOf(DateRange r, String? locationId) =>
      '${r.start.toIso8601String()}|${r.end.toIso8601String()}|${locationId ?? "*"}';

  /// Recalcula solo si cambió el período o la sucursal.
  Future<void> loadIfNeeded(DashboardProvider dash) async {
    final key = _keyOf(dash.range, dash.selectedLocationId);
    if (key == _cacheKey && !_loading) return;
    await load(dash);
  }

  Future<void> load(DashboardProvider dash) async {
    final tenantId = dash.tenantId;
    if (tenantId == null) return;

    _cacheKey = _keyOf(dash.range, dash.selectedLocationId);
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Ventas, gastos y compras ya están en memoria para este período y
      // sucursal: el dashboard los trajo. Solo hay que ir a Firestore por el
      // costo de lo vendido y por el valor de la despensa.
      final cogsFuture = _fetchCogs(
        tenantId,
        dash.range,
        dash.selectedLocationId,
      );
      final inventarioFuture = _fetchValorInventario(
        tenantId,
        dash.selectedLocationId,
      );
      final cogs = await cogsFuture;
      final inventario = await inventarioFuture;

      _data = _armar(dash, cogs, inventario);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = 'No se pudo calcular la rentabilidad';
      debugPrint('[RENTABILIDAD] $e');
      notifyListeners();
    }
  }

  // ── Costo de lo vendido ────────────────────────────────────────────────
  //
  // Se lee de los movimientos de inventario, que sellan `totalCost` con el
  // precio del ingrediente al momento de descontarlo. Es el dato histórico
  // correcto: valorizar hoy con el precio de hoy reescribiría el pasado cada
  // vez que sube un proveedor.
  Future<_Cogs> _fetchCogs(
    String tenantId,
    DateRange range,
    String? locationId,
  ) async {
    final desde = DateTime(range.start.year, range.start.month, range.start.day);
    final hasta = DateTime(
        range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);

    // `createdAt` se guarda como String ISO local (lo escribe el POS), así que
    // el rango también va como String. Índice (tenantId, type, createdAt): ya
    // existe en producción.
    final snap = await _db
        .collection('inventoryMovements')
        .where('tenantId', isEqualTo: tenantId)
        .where('type', isEqualTo: _tipoSalidaVenta)
        .where('createdAt', isGreaterThanOrEqualTo: desde.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: hasta.toIso8601String())
        .limit(20000)
        .get();

    var total = 0.0;
    var conCosto = 0;
    var sinCosto = 0;

    for (final doc in snap.docs) {
      final d = doc.data();
      if (locationId != null && d['locationId'] != locationId) continue;

      final costo = (d['totalCost'] as num?)?.toDouble();
      if (costo == null) {
        // Ingrediente sin precio de compra cargado. NO se cuenta como cero:
        // se cuenta aparte para poder avisar que el margen está incompleto.
        sinCosto++;
        continue;
      }
      // Las salidas guardan cantidad negativa; el costo puede venir con
      // cualquier signo según cómo se calculó. Lo que suma al costo es su
      // magnitud.
      total += costo.abs();
      conCosto++;
    }

    return _Cogs(total: total, conCosto: conCosto, sinCosto: sinCosto);
  }

  // ── Valor de la despensa ───────────────────────────────────────────────
  //
  // Foto de HOY, no del período: no hay histórico de cuánto valía la despensa
  // en una fecha pasada. Se valoriza a precio de compra, que es lo que costó,
  // y no a precio de venta, que mezclaría ganancia futura con capital.
  Future<_Inventario> _fetchValorInventario(
    String tenantId,
    String? locationId,
  ) async {
    final snap = await _db
        .collection('ingredients')
        .where('tenant_id', isEqualTo: tenantId)
        .get();

    var total = 0.0;
    var sinPrecio = 0;

    for (final doc in snap.docs) {
      final d = doc.data();
      if ((d['active'] as bool? ?? true) == false) continue;
      if (locationId != null && d['location_id'] != locationId) continue;

      final stock = (d['currentStock'] as num?)?.toDouble() ?? 0;
      if (stock <= 0) continue;

      final precio = (d['lastPurchasePrice'] as num?)?.toDouble();
      if (precio == null || precio <= 0) {
        sinPrecio++;
        continue;
      }
      total += stock * precio;
    }

    return _Inventario(valor: total, sinPrecio: sinPrecio);
  }

  // ── Armado ─────────────────────────────────────────────────────────────
  ProfitabilityData _armar(
    DashboardProvider dash,
    _Cogs cogs,
    _Inventario inv,
  ) {
    final locId = dash.selectedLocationId;

    // Venta neta: lo cobrado menos propina y envío. La propina es del personal
    // y el envío se cobra para pagarlo; ninguno es ingreso del negocio.
    var netSales = 0.0;
    for (final o in dash.currentOrders) {
      if (locId != null && o['location_id'] != locId) continue;
      final cobrado = (o['payment_amount'] as num?)?.toDouble() ??
          (o['total_amount'] as num? ?? 0).toDouble();
      final propina = (o['tip_amount'] as num? ?? 0).toDouble();
      final envio = (o['delivery_fee'] as num? ?? 0).toDouble();
      netSales += cobrado - propina - envio;
    }

    // Gastos por categoría. Los retiros de caja vienen mezclados en la misma
    // lista (el dashboard los inyecta) y se separan por su marca de origen:
    // sacar plata de la caja no es un gasto de operación, es reparto de
    // utilidad, y contarlo como gasto hace parecer al negocio menos rentable
    // de lo que es.
    final porCategoria = <String, ExpenseLine>{};
    var sueldos = 0.0;
    var retiros = 0.0;

    for (final e in dash.expenseItems) {
      if (locId != null && e['location_id'] != locId) continue;
      final monto = (e['amount'] as num? ?? 0).toDouble();
      if (monto == 0) continue;

      if (e['source'] == 'cashRegister') {
        retiros += monto;
        continue;
      }

      final id = (e['category_id'] as String?) ?? 'otros';
      final nombre = (e['category_name'] as String?) ?? 'Otros gastos';
      if (_idsSueldos.contains(id)) sueldos += monto;

      // El POS marca cada gasto como 'fixed' o 'variable' al crearlo. Ante la
      // duda se toma como variable: contar de más en los fijos infla el punto
      // de equilibrio y le diría al usuario que necesita vender más de lo que
      // realmente necesita.
      final esFijo = e['type'] == 'fixed';

      final previa = porCategoria[id];
      porCategoria[id] = ExpenseLine(
        categoryId: id,
        label: nombre,
        amount: (previa?.amount ?? 0) + monto,
        esFijo: previa?.esFijo ?? esFijo,
      );
    }

    final lineas = porCategoria.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    // Compras: informativas. No se restan — el gasto de esa mercadería ya lo
    // cuenta el costo de lo vendido cuando se vende. Restar ambas sería
    // contar dos veces lo mismo.
    var compras = 0.0;
    for (final p in dash.purchaseItems) {
      if (locId != null && p['location_id'] != locId) continue;
      compras += (p['total'] as num? ?? 0).toDouble();
    }

    return ProfitabilityData(
      netSales: netSales,
      cogs: cogs.total,
      itemsConCosto: cogs.conCosto,
      itemsSinCosto: cogs.sinCosto,
      expenses: lineas,
      payroll: sueldos,
      ownerWithdrawals: retiros,
      purchases: compras,
      inventoryValue: inv.valor,
      ingredientesSinPrecio: inv.sinPrecio,
    );
  }
}

class _Cogs {
  final double total;
  final int conCosto;
  final int sinCosto;
  const _Cogs({
    required this.total,
    required this.conCosto,
    required this.sinCosto,
  });
}

class _Inventario {
  final double valor;
  final int sinPrecio;
  const _Inventario({required this.valor, required this.sinPrecio});
}
