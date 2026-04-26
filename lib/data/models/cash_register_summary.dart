import 'package:cloud_firestore/cloud_firestore.dart';

class CashRegisterSummary {
  final String id;
  final String userName;
  final String status; // 'open' | 'closed'
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? locationId;

  // Montos iniciales (fondo de apertura)
  final double initialCash;
  final double initialCard;
  final double initialTransfer;
  final double initialPedidosya;
  final double initialUbereats;

  // Montos esperados (initial + ventas acumuladas)
  final double expectedCash;
  final double expectedCard;
  final double expectedTransfer;
  final double expectedPedidosya;
  final double expectedUbereats;
  final Map<String, double> expectedCustomMethods;

  // Montos contados al cierre (incluyen initial en efectivo)
  final double? actualCash;
  final double? actualCard;
  final double? actualTransfer;
  final double? actualPedidosya;
  final double? actualUbereats;
  final Map<String, double> actualCustomMethods;

  // Nombres de métodos personalizados: id → nombre
  final Map<String, String> customMethodNames;
  final String? locationName;

  CashRegisterSummary({
    required this.id,
    required this.userName,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.locationId,
    this.initialCash = 0,
    this.initialCard = 0,
    this.initialTransfer = 0,
    this.initialPedidosya = 0,
    this.initialUbereats = 0,
    this.expectedCash = 0,
    this.expectedCard = 0,
    this.expectedTransfer = 0,
    this.expectedPedidosya = 0,
    this.expectedUbereats = 0,
    this.expectedCustomMethods = const {},
    this.actualCash,
    this.actualCard,
    this.actualTransfer,
    this.actualPedidosya,
    this.actualUbereats,
    this.actualCustomMethods = const {},
    this.customMethodNames = const {},
    this.locationName,
  });

  bool get isOpen => status == 'open';

  // Fondo inicial total (abre la caja con esto)
  double get totalInitial =>
      initialCash + initialCard + initialTransfer + initialPedidosya + initialUbereats;

  // Ventas en efectivo = expected - initial (lo que se vendió, sin el fondo)
  double get salesCash => expectedCash - initialCash;
  double get salesCard => expectedCard - initialCard;
  double get salesTransfer => expectedTransfer - initialTransfer;
  double get salesPedidosya => expectedPedidosya - initialPedidosya;
  double get salesUbereats => expectedUbereats - initialUbereats;

  // Total de ventas (sin fondo inicial)
  double get totalSales =>
      salesCash +
      salesCard +
      salesTransfer +
      salesPedidosya +
      salesUbereats +
      expectedCustomMethods.values.fold(0, (a, b) => a + b);

  // Diferencia total (contado - esperado). null si no se contó nada.
  double? get totalDifference {
    final hasActual = actualCash != null || actualCard != null ||
        actualTransfer != null || actualPedidosya != null || actualUbereats != null ||
        actualCustomMethods.isNotEmpty;
    if (!hasActual) return null;
    final counted = (actualCash ?? 0) - initialCash +
        (actualCard ?? 0) - initialCard +
        (actualTransfer ?? 0) - initialTransfer +
        (actualPedidosya ?? 0) - initialPedidosya +
        (actualUbereats ?? 0) - initialUbereats +
        actualCustomMethods.values.fold(0.0, (a, b) => a + b);
    return counted - totalSales;
  }

  Duration get duration {
    final end = closedAt ?? DateTime.now();
    return end.difference(openedAt);
  }

  CashRegisterSummary copyWith({
    Map<String, String>? customMethodNames,
    String? locationName,
  }) {
    return CashRegisterSummary(
      id: id,
      userName: userName,
      status: status,
      openedAt: openedAt,
      closedAt: closedAt,
      locationId: locationId,
      initialCash: initialCash,
      initialCard: initialCard,
      initialTransfer: initialTransfer,
      initialPedidosya: initialPedidosya,
      initialUbereats: initialUbereats,
      expectedCash: expectedCash,
      expectedCard: expectedCard,
      expectedTransfer: expectedTransfer,
      expectedPedidosya: expectedPedidosya,
      expectedUbereats: expectedUbereats,
      expectedCustomMethods: expectedCustomMethods,
      actualCash: actualCash,
      actualCard: actualCard,
      actualTransfer: actualTransfer,
      actualPedidosya: actualPedidosya,
      actualUbereats: actualUbereats,
      actualCustomMethods: actualCustomMethods,
      customMethodNames: customMethodNames ?? this.customMethodNames,
      locationName: locationName ?? this.locationName,
    );
  }

  factory CashRegisterSummary.fromMap(Map<String, dynamic> map) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate().toLocal();
      return DateTime.now();
    }

    double dbl(dynamic v) => (v as num? ?? 0).toDouble();
    double? dblN(dynamic v) => v == null ? null : (v as num).toDouble();

    Map<String, double> customMap(dynamic v) {
      if (v == null) return {};
      return (v as Map<String, dynamic>)
          .map((k, val) => MapEntry(k, (val as num? ?? 0).toDouble()));
    }

    return CashRegisterSummary(
      id: map['id'] as String? ?? '',
      userName: map['userName'] as String? ?? 'Sin nombre',
      status: map['status'] as String? ?? 'unknown',
      openedAt: parseTs(map['openedAt']),
      closedAt: map['closedAt'] != null ? parseTs(map['closedAt']) : null,
      locationId: map['locationId'] as String?,
      initialCash: dbl(map['initialCash']),
      initialCard: dbl(map['initialCard']),
      initialTransfer: dbl(map['initialTransfer']),
      initialPedidosya: dbl(map['initialPedidosya']),
      initialUbereats: dbl(map['initialUbereats']),
      expectedCash: dbl(map['expectedCash']),
      expectedCard: dbl(map['expectedCard']),
      expectedTransfer: dbl(map['expectedTransfer']),
      expectedPedidosya: dbl(map['expectedPedidosya']),
      expectedUbereats: dbl(map['expectedUbereats']),
      expectedCustomMethods: customMap(map['expectedCustomMethods']),
      actualCash: dblN(map['actualCash']),
      actualCard: dblN(map['actualCard']),
      actualTransfer: dblN(map['actualTransfer']),
      actualPedidosya: dblN(map['actualPedidosya']),
      actualUbereats: dblN(map['actualUbereats']),
      actualCustomMethods: customMap(map['actualCustomMethods']),
    );
  }
}
