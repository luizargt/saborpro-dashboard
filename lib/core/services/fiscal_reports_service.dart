import 'package:cloud_firestore/cloud_firestore.dart';

/// Un correlativo autorizado que nunca llegó a usarse.
class UnusedNumber {
  final String number;
  final String cai;

  /// Por qué quedó sin usar, en los términos del Art. 42.
  final String cause;

  const UnusedNumber({
    required this.number,
    required this.cai,
    required this.cause,
  });
}

/// Un renglón del resumen de ventas: lo vendido a una tarifa en un mes.
class IsvSummaryLine {
  final String rateLabel;
  final double taxable;
  final double tax;
  final int invoices;

  const IsvSummaryLine({
    required this.rateLabel,
    required this.taxable,
    required this.tax,
    required this.invoices,
  });
}

/// Los datos de los dos reportes que el SAR de Honduras obliga a presentar.
///
/// - **Documentos no utilizados (Art. 42):** hay que comunicarlos "dentro de
///   los primeros diez (10) días hábiles del mes siguiente" de que un rango
///   venciera, se agotara o se diera de baja. Un correlativo que se quemó por
///   una falla técnica entra por la causal 10 y también hay que reportarlo.
/// - **Resumen de ventas (Art. 38):** quien factura en papel térmico "debe
///   presentar a la Administración Tributaria los resúmenes de ventas en los
///   plazos, medios y formas que ésta determine".
class FiscalReportsService {
  final FirebaseFirestore _db;

  FiscalReportsService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Si este tenant factura bajo el régimen de Honduras. Solo entonces tienen
  /// sentido estos reportes.
  Future<bool> isHonduras(String tenantId) async {
    try {
      final snap = await _db
          .collection('billingConfigs')
          .where('tenant_id', isEqualTo: tenantId)
          .limit(5)
          .get();
      return snap.docs.any((d) => d.data()['country'] == 'HN');
    } catch (_) {
      return false;
    }
  }

  /// Los números autorizados que no se usaron, rango por rango.
  ///
  /// Son de dos clases y las dos hay que reportarlas:
  ///
  /// - **La cola**: desde el siguiente correlativo sin asignar hasta el final
  ///   del rango. Aparece cuando una autorización vence o se da de baja con
  ///   números todavía disponibles.
  /// - **Los huecos**: correlativos que el sistema entregó pero que no
  ///   terminaron en una factura emitida. Se detectan comparando el libro de
  ///   asignaciones contra las facturas, y son la causal 10 del Art. 42.
  Future<List<UnusedNumber>> unusedNumbers({
    required String tenantId,
    bool onlyClosedRanges = true,
  }) async {
    final result = <UnusedNumber>[];

    final ranges = await _db
        .collection('fiscal_ranges')
        .where('tenant_id', isEqualTo: tenantId)
        .get();

    for (final doc in ranges.docs) {
      final data = doc.data();
      final status = data['status']?.toString() ?? '';
      final cerrado = status == 'expired' ||
          status == 'exhausted' ||
          status == 'cancelled';
      if (onlyClosedRanges && !cerrado) continue;

      final cai = data['cai']?.toString() ?? '';
      final prefix = '${data['establishment_code']}-'
          '${data['emission_point']}-${data['document_type']}';
      final from = (data['range_from'] as num?)?.toInt() ?? 0;
      final to = (data['range_to'] as num?)?.toInt() ?? 0;
      final next = (data['next_number'] as num?)?.toInt() ?? from;

      String format(int n) => '$prefix-${n.toString().padLeft(8, '0')}';

      // La cola sin asignar.
      final causaCola = switch (status) {
        'expired' => 'Vencimiento del plazo de la autorización (Art. 42, 1)',
        'cancelled' => 'Baja del punto de emisión (Art. 42, 5)',
        _ => 'No utilizado',
      };
      if (status != 'exhausted') {
        for (var n = next; n <= to; n++) {
          result.add(UnusedNumber(
            number: format(n),
            cai: cai,
            cause: causaCola,
          ));
        }
      }

      // Los huecos: asignados pero sin factura emitida detrás.
      final assignments = await _db
          .collection('fiscal_assignments')
          .where('tenant_id', isEqualTo: tenantId)
          .where('range_id', isEqualTo: doc.id)
          .get();

      for (final a in assignments.docs) {
        final invoiceId = a.data()['invoice_id']?.toString();
        if (invoiceId == null) continue;

        final invoice = await _db.collection('invoices').doc(invoiceId).get();
        final emitida = invoice.exists &&
            (invoice.data()?['status'] == 'certified' ||
                invoice.data()?['status'] == 'cancelled');
        if (emitida) continue;

        result.add(UnusedNumber(
          number: a.data()['formatted_number']?.toString() ?? '',
          cai: cai,
          cause: 'Problemas o fallas técnicas en el sistema (Art. 42, 10)',
        ));
      }
    }

    result.sort((a, b) => a.number.compareTo(b.number));
    return result;
  }

  /// Ventas del período agrupadas por tarifa de ISV.
  ///
  /// Se arma desde las facturas emitidas, no desde las órdenes: lo que el SAR
  /// controla es lo que se documentó, y una venta sin factura no entra en este
  /// resumen.
  Future<List<IsvSummaryLine>> isvSummary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final snap = await _db
        .collection('invoices')
        .where('tenant_id', isEqualTo: tenantId)
        .where('status', isEqualTo: 'certified')
        .get();

    final taxableByRate = <double, double>{};
    final taxByRate = <double, double>{};
    final invoicesByRate = <double, Set<String>>{};

    for (final doc in snap.docs) {
      final data = doc.data();

      final createdRaw = data['created_at'];
      final created = createdRaw is Timestamp
          ? createdRaw.toDate()
          : DateTime.tryParse(createdRaw?.toString() ?? '');
      if (created == null) continue;
      if (created.isBefore(from) || created.isAfter(to)) continue;

      final items = (data['items'] as List?) ?? const [];
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        final rate = (item['tax_rate'] as num?)?.toDouble() ?? 0.0;
        final total = (item['total'] as num?)?.toDouble() ?? 0.0;
        final tax = (item['tax_amount'] as num?)?.toDouble() ?? 0.0;

        taxableByRate[rate] = (taxableByRate[rate] ?? 0) + (total - tax);
        taxByRate[rate] = (taxByRate[rate] ?? 0) + tax;
        (invoicesByRate[rate] ??= <String>{}).add(doc.id);
      }
    }

    final rates = taxableByRate.keys.toList()..sort();
    return [
      for (final rate in rates)
        IsvSummaryLine(
          rateLabel: rate == 0
              ? 'Exento'
              : '${(rate * 100).toStringAsFixed(0)}%',
          taxable: _round(taxableByRate[rate]!),
          tax: _round(taxByRate[rate]!),
          invoices: invoicesByRate[rate]?.length ?? 0,
        ),
    ];
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}
