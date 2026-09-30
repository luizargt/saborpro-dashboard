import 'package:cloud_firestore/cloud_firestore.dart';

class CashRegisterSummary {
  final String id;
  final String userId;
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

  // Movimientos de caja (retiros y depósitos en efectivo)
  final double totalWithdrawals;
  final double totalDeposits;

  // Diferencias almacenadas al cierre (calculadas desde órdenes reales en saborpro_app).
  // Cuando están presentes, son más confiables que expectedCash/expectedCard que pueden
  // ser sobreescritos por sincronización posterior de otro dispositivo.
  final double? differenceCash;
  final double? differenceCard;
  final double? differenceTransfer;
  final double? differencePedidosya;
  final double? differenceUbereats;

  /// Las diferencias selladas de los métodos propios, por id.
  final Map<String, double> differenceCustomMethods;

  // Notas de cierre (incluye aclaraciones de cuadre si hubo diferencia)
  final String? closingNotes;

  /// Otros cierres de esta misma caja que llegaron cuando ya estaba cerrada
  /// (otro aparato que no se enteró del cierre). No cuentan: vale el que se
  /// guardó primero. Los escribe el POS en `cierres_no_aplicados`, con el
  /// aparato, la hora y lo que contó. Solo se leen: esta app nunca los escribe.
  final List<Map<String, dynamic>> cierresNoAplicados;

  // Nombres de métodos personalizados: id → nombre
  final Map<String, String> customMethodNames;
  final String? locationName;

  CashRegisterSummary({
    required this.id,
    required this.userId,
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
    this.totalWithdrawals = 0,
    this.totalDeposits = 0,
    this.differenceCash,
    this.differenceCard,
    this.differenceTransfer,
    this.differencePedidosya,
    this.differenceUbereats,
    this.differenceCustomMethods = const {},
    this.closingNotes,
    this.cierresNoAplicados = const [],
    this.customMethodNames = const {},
    this.locationName,
  });

  bool get isOpen => status == 'open';

  // Fondo inicial total (abre la caja con esto)
  double get totalInitial =>
      initialCash + initialCard + initialTransfer + initialPedidosya + initialUbereats;

  // Ventas por método de pago.
  // Cuando están disponibles las diferencias del cierre, se derivan desde actual-diferencia
  // (más confiable que expected, que puede ser sobreescrito por sync posterior).
  // Fórmula: actual - difference - initial + withdrawals - deposits (solo efectivo lleva ajuste)
  double get salesCash {
    if (differenceCash != null) {
      return (actualCash ?? 0) - differenceCash! - initialCash + totalWithdrawals - totalDeposits;
    }
    return expectedCash - initialCash;
  }

  double get salesCard {
    if (differenceCard != null) {
      return (actualCard ?? 0) - differenceCard! - initialCard;
    }
    return expectedCard - initialCard;
  }

  double get salesTransfer {
    if (differenceTransfer != null) {
      return (actualTransfer ?? 0) - differenceTransfer! - initialTransfer;
    }
    return expectedTransfer - initialTransfer;
  }

  double get salesPedidosya {
    if (differencePedidosya != null) {
      return (actualPedidosya ?? 0) - differencePedidosya! - initialPedidosya;
    }
    return expectedPedidosya - initialPedidosya;
  }

  double get salesUbereats {
    if (differenceUbereats != null) {
      return (actualUbereats ?? 0) - differenceUbereats! - initialUbereats;
    }
    return expectedUbereats - initialUbereats;
  }

  /// Las ventas de cada método propio según lo que el corte selló: declarado −
  /// diferencia, como el efectivo arriba. `expectedCustomMethods` es el
  /// acumulado del turno y puede traer restos (una venta anulada con un método
  /// propio no se descuenta, y el cierre escribe con merge, que no borra
  /// claves): salían como ventas. Sin diferencias selladas (caja abierta,
  /// cierre forzado, cortes anteriores a marzo 2026), el acumulado. Igual que
  /// `CashRegisterCalculator.ventasPropiasSelladas` en el POS.
  Map<String, double> get ventasPropias => differenceCustomMethods.isEmpty
      ? expectedCustomMethods
      : {
          for (final e in differenceCustomMethods.entries)
            e.key: (actualCustomMethods[e.key] ?? 0) - e.value,
        };

  // Total de ventas (sin fondo inicial)
  double get totalSales =>
      salesCash +
      salesCard +
      salesTransfer +
      salesPedidosya +
      salesUbereats +
      ventasPropias.values.fold(0, (a, b) => a + b);

  // Diferencia total (contado - esperado). null si no se contó nada.
  // Los retiros reducen el efectivo esperado en gaveta; los depósitos lo aumentan.
  double? get totalDifference {
    // Corte con diferencias selladas: la suma de las de cada método, igual que
    // el POS. Recontar con lo declarado daba otra cosa en los cierres forzados,
    // que no tocan los métodos propios (salían con un faltante por esas ventas).
    if (differenceCash != null) {
      return differenceCash! +
          (differenceCard ?? 0) +
          (differenceTransfer ?? 0) +
          (differencePedidosya ?? 0) +
          (differenceUbereats ?? 0) +
          differenceCustomMethods.values.fold(0.0, (a, b) => a + b);
    }
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
    return counted - totalSales + totalWithdrawals - totalDeposits;
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
      userId: userId,
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
      totalWithdrawals: totalWithdrawals,
      totalDeposits: totalDeposits,
      differenceCash: differenceCash,
      differenceCard: differenceCard,
      differenceTransfer: differenceTransfer,
      differencePedidosya: differencePedidosya,
      differenceUbereats: differenceUbereats,
      differenceCustomMethods: differenceCustomMethods,
      closingNotes: closingNotes,
      cierresNoAplicados: cierresNoAplicados,
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

    List<Map<String, dynamic>> lista(dynamic v) => [
          if (v is List)
            for (final e in v)
              if (e is Map) Map<String, dynamic>.from(e),
        ];

    double totalWithdrawals = 0;
    double totalDeposits = 0;
    final movements = (map['movements'] as List<dynamic>?) ?? [];
    for (final m in movements) {
      final type = (m as Map<String, dynamic>?)?['type'] as String? ?? '';
      final amount = (m?['amount'] as num? ?? 0).toDouble();
      if (type == 'withdrawal') { totalWithdrawals += amount; }
      else if (type == 'deposit') { totalDeposits += amount; }
    }

    return CashRegisterSummary(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
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
      totalWithdrawals: totalWithdrawals,
      totalDeposits: totalDeposits,
      differenceCash: dblN(map['differenceCash']),
      differenceCard: dblN(map['differenceCard']),
      differenceTransfer: dblN(map['differenceTransfer']),
      differencePedidosya: dblN(map['differencePedidosya']),
      differenceUbereats: dblN(map['differenceUbereats']),
      differenceCustomMethods: customMap(map['differenceCustomMethods']),
      closingNotes: map['closingNotes'] as String?,
      cierresNoAplicados: lista(map['cierres_no_aplicados']),
    );
  }
}
