import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final String id;
  final String name;

  LocationModel({required this.id, required this.name});

  factory LocationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LocationModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Sucursal',
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
