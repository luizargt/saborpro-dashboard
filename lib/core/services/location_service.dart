import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String name;

  /// El signo de moneda con que vende la sucursal. Se configura en Sabor Suite
  /// (settings.currency_symbol) y es texto libre: "Q", "\$", "L", "USD"...
  /// Sin configurar vale "Q", igual que en el POS.
  final String currencySymbol;

  LocationModel({required this.id, required this.name, this.currencySymbol = 'Q'});

  factory LocationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final settings = data['settings'];
    final simbolo = settings is Map ? settings['currency_symbol'] : null;
    return LocationModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Sucursal',
      currencySymbol: simbolo is String && simbolo.trim().isNotEmpty
          ? simbolo.trim()
          : 'Q',
    );
  }
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<LocationModel>> getLocations(String tenantId) async {
    final snap = await _db
        .collection('locations')
        .where('tenant_id', isEqualTo: tenantId)
        .where('active', isEqualTo: true)
        .get();

    return snap.docs
        .map((d) => LocationModel.fromDoc(d))
        .where((l) => !l.name.toLowerCase().contains('bodega') &&
            !l.name.toLowerCase().contains('warehouse'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
