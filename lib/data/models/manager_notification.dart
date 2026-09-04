import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Los avisos que Sabor Manager acumula en su bandeja.
///
/// El `type` es el mismo string que mandan las Cloud Functions en el payload
/// del push, así que agregar un aviso nuevo allá y olvidarse de acá no rompe
/// nada: cae en [otro] y se muestra con el aspecto neutro.
enum ManagerNotificationType {
  cajaAbierta('cash_register_opened'),
  cajaCerrada('cash_register_closed'),
  retiro('cash_withdrawal'),
  retirosEnLote('cash_withdrawals_batch'),
  gasto('expense_created'),
  inventario('inventory_movement_created'),
  stockBajo('low_stock_summary'),
  otro('');

  final String clave;
  const ManagerNotificationType(this.clave);

  static ManagerNotificationType desde(String? valor) {
    if (valor == null || valor.isEmpty) return otro;
    for (final t in values) {
      if (t.clave == valor) return t;
    }
    return otro;
  }
}

/// Cómo se ve cada tipo en la lista. Vive junto al enum para que agregar un
/// aviso nuevo sea una sola línea y no una cacería por tres archivos.
extension ManagerNotificationLook on ManagerNotificationType {
  IconData get icono => switch (this) {
        ManagerNotificationType.cajaAbierta => Icons.lock_open_rounded,
        ManagerNotificationType.cajaCerrada => Icons.lock_rounded,
        ManagerNotificationType.retiro ||
        ManagerNotificationType.retirosEnLote =>
          Icons.call_made_rounded,
        ManagerNotificationType.gasto => Icons.receipt_long_rounded,
        ManagerNotificationType.inventario => Icons.inventory_2_rounded,
        ManagerNotificationType.stockBajo => Icons.trending_down_rounded,
        ManagerNotificationType.otro => Icons.notifications_rounded,
      };

  /// Un color por familia de aviso, no uno por aviso: caja en verde, dinero
  /// que sale en ámbar, despensa en azul, y rojo reservado para lo que exige
  /// hacer algo. Con siete colores distintos la lista se vuelve un arcoíris y
  /// deja de comunicar.
  Color get color => switch (this) {
        ManagerNotificationType.cajaAbierta ||
        ManagerNotificationType.cajaCerrada =>
          const Color(0xFF34D399),
        ManagerNotificationType.retiro ||
        ManagerNotificationType.retirosEnLote ||
        ManagerNotificationType.gasto =>
          const Color(0xFFFBBF24),
        ManagerNotificationType.inventario => const Color(0xFF60A5FA),
        ManagerNotificationType.stockBajo => const Color(0xFFF87171),
        ManagerNotificationType.otro => const Color(0xFF7444fd),
      };

  /// Etiqueta corta para agrupar y para el filtro.
  String get etiqueta => switch (this) {
        ManagerNotificationType.cajaAbierta ||
        ManagerNotificationType.cajaCerrada =>
          'Caja',
        ManagerNotificationType.retiro ||
        ManagerNotificationType.retirosEnLote =>
          'Retiros',
        ManagerNotificationType.gasto => 'Gastos',
        ManagerNotificationType.inventario => 'Inventario',
        ManagerNotificationType.stockBajo => 'Stock bajo',
        ManagerNotificationType.otro => 'Avisos',
      };
}

class ManagerNotification {
  final String id;
  final ManagerNotificationType tipo;
  final String title;
  final String body;
  final Map<String, String> data;
  final String locationId;
  final bool read;
  final DateTime createdAt;

  const ManagerNotification({
    required this.id,
    required this.tipo,
    required this.title,
    required this.body,
    required this.data,
    required this.locationId,
    required this.read,
    required this.createdAt,
  });

  /// Un cierre de caja que no cuadró se marca distinto del que cuadró: es el
  /// único aviso de la lista que puede exigir una acción esa misma noche.
  bool get esAlerta =>
      tipo == ManagerNotificationType.stockBajo ||
      (tipo == ManagerNotificationType.cajaCerrada &&
          data['cuadro'] == 'false');

  Color get color =>
      esAlerta ? const Color(0xFFF87171) : tipo.color;

  factory ManagerNotification.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final crudo = d['data'];
    return ManagerNotification(
      id: doc.id,
      tipo: ManagerNotificationType.desde(d['type'] as String?),
      title: (d['title'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      data: crudo is Map
          ? crudo.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : const {},
      locationId: (d['location_id'] as String?) ?? '',
      read: d['read'] == true,
      // Un documento recién escrito puede llegar con created_at en null: el
      // serverTimestamp todavía no resolvió y la caché local lo entrega vacío.
      // Tratarlo como "ahora" lo deja arriba de la lista, que es donde va.
      createdAt: (d['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
