import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/monedas.dart';

class LocationModel {
  final String id;
  final String name;

  /// El signo de moneda con que vende la sucursal. Se configura en Sabor Suite
  /// (settings.currency_symbol) y es texto libre: "Q", "\$", "L", "USD"...
  /// Sin configurar vale "Q", igual que en el POS.
  final String currencySymbol;

  /// País de la sucursal, tal como lo guarda el POS ("Guatemala", "Argentina").
  final String country;

  final bool active;

  /// Bodega central (`is_central_warehouse`). No vende.
  final bool centralWarehouse;

  /// Canales de venta (`settings.sales_channels`): `dine_in`, `takeout`,
  /// `delivery`, `quick_sale` y `room_service`. Nulo = la sucursal no los guardó
  /// (el POS entonces toma mesa, llevar, domicilio y mostrador, sin habitaciones).
  final List<String>? salesChannels;

  LocationModel({
    required this.id,
    required this.name,
    this.currencySymbol = 'Q',
    this.country = 'Guatemala',
    this.active = true,
    this.centralWarehouse = false,
    this.salesChannels,
  });

  /// ¿Vende habitaciones? Lo dice el canal `room_service`, que el POS enciende
  /// en los hoteles y en los negocios que activan Hospedaje.
  bool get vendeHabitaciones => salesChannels?.contains('room_service') ?? false;

  /// Los canales guardados en `settings.sales_channels`; nulo si no hay una lista.
  static List<String>? canalesDe(Object? settings) {
    final lista = settings is Map ? settings['sales_channels'] : null;
    if (lista is! List) return null;
    return [for (final c in lista) if (c is String) c];
  }

  /// Bodega: no vende, solo guarda inventario. Por bandera o por nombre, que
  /// es como la reconocen las pestañas desde siempre.
  bool get esBodega =>
      centralWarehouse ||
      name.toLowerCase().contains('bodega') ||
      name.toLowerCase().contains('warehouse');

  /// Las que salen en las pestañas: activas y que no son bodega.
  bool get visible =>
      active &&
      !name.toLowerCase().contains('bodega') &&
      !name.toLowerCase().contains('warehouse');

  /// Qué moneda es de verdad (GTQ, ARS, USD…). "\$" solo no lo dice: lo
  /// decide el país. Ver core/utils/monedas.dart.
  String get currencyCode => codigoDeMoneda(currencySymbol, country);

  factory LocationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final settings = data['settings'];
    final simbolo = settings is Map ? settings['currency_symbol'] : null;
    final pais = data['country'];
    return LocationModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Sucursal',
      currencySymbol: simbolo is String && simbolo.trim().isNotEmpty
          ? simbolo.trim()
          : 'Q',
      country: pais is String && pais.trim().isNotEmpty ? pais.trim() : 'Guatemala',
      active: data['active'] == true,
      centralWarehouse: data['is_central_warehouse'] == true,
      salesChannels: canalesDe(settings),
    );
  }
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// TODAS las sucursales del negocio, también las inactivas y las bodegas.
  /// Las pestañas no las muestran, pero sus ventas viejas siguen entrando en
  /// "Todas" y hay que saber en qué moneda están.
  Future<List<LocationModel>> getTodas(String tenantId) async {
    final snap = await _db.collection('locations').where('tenant_id', isEqualTo: tenantId).get();
    return snap.docs.map((d) => LocationModel.fromDoc(d)).toList();
  }

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
