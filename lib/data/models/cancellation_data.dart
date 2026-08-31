/// Modelos del reporte "Pedidos Cancelados".
///
/// Fase 4 del inventario. Cancelar un pedido ya no descuenta en silencio: al
/// anular, el usuario declara si el producto REGRESA a despensa o se pierde.
/// Cada declaración deja movimientos en `inventoryMovements`:
///
///   - `devolucionCancelacion` (+q): revierte la salida original.
///   - `mermaCancelacion`      (-q): solo cuando el producto NO regresa.
///
/// Cuando el producto no regresa se escribe el PAR (devolución + merma): el
/// neto sobre el stock es cero, pero el costo queda RECLASIFICADO de costo de
/// ventas a merma. Sin ese par el inventario cuadraría y nadie sabría a dónde
/// se fue el producto, que es justo lo que vuelve invisible a un robo. Este
/// reporte existe para leer esa reclasificación.
library;

/// Los dos tipos de movimiento que produce una cancelación.
enum CancellationKind {
  /// `devolucionCancelacion`: el producto volvió a la despensa.
  devolucion,

  /// `mermaCancelacion`: alguien declaró que el producto se perdió.
  merma,
}

/// Qué tanto tocó el inventario una cancelación.
///
/// Las tres son cancelaciones reales, pero solo la primera mueve producto. Las
/// otras dos NO son un error del reporte y por eso se marcan distinto en vez de
/// esconderse: un pedido que se toma y se deshace antes de cocina es otro
/// síntoma que al dueño le sirve, y un pedido sin receta no tenía nada que
/// devolver aunque haya llegado a la plancha.
enum InventoryImpact {
  /// Hubo devolución y/o merma declarada.
  conMovimiento,

  /// Se canceló antes de mandar a cocina: nunca se descontó nada.
  sinCocina,

  /// Llegó a cocina pero ningún producto tenía receta: no había qué devolver.
  sinReceta,
}

extension InventoryImpactLabel on InventoryImpact {
  String get label {
    switch (this) {
      case InventoryImpact.conMovimiento:
        return 'Movió inventario';
      case InventoryImpact.sinCocina:
        return 'No llegó a cocina';
      case InventoryImpact.sinReceta:
        return 'Sin receta';
    }
  }
}

/// Costo y unidad de un ingrediente, tal como está hoy en `ingredients`.
///
/// `price` es nullable A PROPÓSITO y no se rellena con cero: en producción más
/// de la mitad de los ingredientes de una sucursal no tienen precio de compra
/// —y son justo las bebidas, las que más se devuelven—. Un cero convertiría
/// "no sé cuánto vale" en "no valía nada", que es una mentira con forma de
/// número.
class IngredientCost {
  final String name;
  final String unit;
  final double? price;

  const IngredientCost({
    required this.name,
    required this.unit,
    this.price,
  });

  bool get hasPrice => price != null && price! > 0;
}

/// Un valor que puede ser solo PARCIALMENTE conocido en quetzales.
///
/// Lo que tiene precio de compra se suma en `amount`; lo que no, se acumula en
/// `unpricedByUnit` como cantidad física por unidad de medida. Así el reporte
/// nunca muestra "Q0.00" para algo que sí se perdió: muestra el dinero que
/// puede probar y, al lado, el producto que no puede valorar.
class PartialValue {
  final double amount;

  /// Cantidad sin costo, agrupada por unidad de medida ('u', 'lb', 'ml'...).
  /// Agrupar por unidad es lo único que se puede sumar sin mentir: 3 botellas
  /// y 200 gramos no son "203 de algo".
  final Map<String, double> unpricedByUnit;

  /// Ingredientes distintos que quedaron sin valorar (para poder decir cuántos
  /// son, no solo cuánto suman).
  final Set<String> unpricedIngredientIds;

  const PartialValue({
    this.amount = 0,
    this.unpricedByUnit = const {},
    this.unpricedIngredientIds = const {},
  });

  static const empty = PartialValue();

  bool get hasMoney => amount > 0.0001;
  bool get hasUnpriced => unpricedByUnit.isNotEmpty;
  bool get isEmpty => !hasMoney && !hasUnpriced;

  PartialValue operator +(PartialValue other) {
    final units = Map<String, double>.from(unpricedByUnit);
    for (final e in other.unpricedByUnit.entries) {
      units[e.key] = (units[e.key] ?? 0) + e.value;
    }
    return PartialValue(
      amount: amount + other.amount,
      unpricedByUnit: units,
      unpricedIngredientIds: {
        ...unpricedIngredientIds,
        ...other.unpricedIngredientIds,
      },
    );
  }

  /// Texto corto de la parte que NO se puede valorar: "14 u · 2.5 lb".
  String get unpricedLabel {
    final parts = unpricedByUnit.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return parts.map((e) => '${_qty(e.value)} ${e.key}').join(' · ');
  }

  static String _qty(double v) {
    if ((v - v.roundToDouble()).abs() < 0.005) return v.round().toString();
    return v.toStringAsFixed(2);
  }
}

/// Un movimiento de cancelación ya leído de Firestore.
class CancellationMovement {
  final String id;
  final CancellationKind kind;
  final String ingredientId;
  final String locationId;
  final String orderId;

  /// Item del pedido del que salió. La llave del movimiento lleva el itemId
  /// (`dec.{roundId}.{itemId}.{ingredientId}`) justamente porque dos líneas de
  /// la misma comanda pueden compartir ingrediente; aquí se usa para no fundir
  /// en una sola fila dos anulaciones distintas.
  final String orderItemId;
  final String itemName;
  final int itemQty;

  /// Magnitud SIEMPRE positiva. En Firestore la merma viaja negativa (es una
  /// salida); para sumar es más claro guardar el valor absoluto y que el signo
  /// lo dé `kind`.
  final double quantity;

  final String? reason;
  final String userId;
  final String userName;
  final DateTime createdAt;

  const CancellationMovement({
    required this.id,
    required this.kind,
    required this.ingredientId,
    required this.locationId,
    required this.orderId,
    required this.orderItemId,
    required this.itemName,
    required this.itemQty,
    required this.quantity,
    required this.reason,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });
}

/// Un item anulado dentro de una cancelación.
class CancellationItem {
  final String itemId;
  final String name;
  final int qty;

  /// Lo que efectivamente volvió a la despensa (devolución menos merma).
  final PartialValue returned;

  /// Lo que alguien declaró perdido.
  final PartialValue wasted;

  /// true si de este item se declaró merma (aunque sea parcial). Es la señal
  /// que alimenta el corte por persona.
  final bool declaredLost;

  const CancellationItem({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.returned,
    required this.wasted,
    required this.declaredLost,
  });
}

/// Una cancelación: una fila del reporte.
class CancellationEvent {
  final String orderId;

  /// Número de pedido / mesa, lo que se pueda mostrar.
  final String orderLabel;
  final String tableLabel;
  final DateTime at;
  final String userName;
  final String? reason;
  final InventoryImpact impact;
  final List<CancellationItem> items;
  final PartialValue returned;
  final PartialValue wasted;

  const CancellationEvent({
    required this.orderId,
    required this.orderLabel,
    required this.tableLabel,
    required this.at,
    required this.userName,
    required this.reason,
    required this.impact,
    required this.items,
    required this.returned,
    required this.wasted,
  });

  bool get movedInventory => impact == InventoryImpact.conMovimiento;
}

/// El corte por persona.
///
/// Es la parte más importante del reporte: el dueño decidió que cualquiera
/// pueda declarar merma sin PIN ni permiso, así que el único control que queda
/// es a posteriori. Lo que delata a alguien no es cuánto canceló, sino qué
/// PORCENTAJE de lo que canceló declaró perdido: cancelar mucho puede ser el
/// turno; marcar "no regresa" mucho más que el resto, no.
class PersonCut {
  final String userId;
  final String userName;

  /// Cancelaciones (pedidos) en las que aparece.
  final int events;

  /// Items anulados que sí movieron inventario.
  final int itemsCancelled;

  /// De esos, cuántos declaró perdidos.
  final int itemsLost;

  final PartialValue wasted;
  final PartialValue returned;

  const PersonCut({
    required this.userId,
    required this.userName,
    required this.events,
    required this.itemsCancelled,
    required this.itemsLost,
    required this.wasted,
    required this.returned,
  });

  /// Fracción 0..1 de items anulados que declaró perdidos.
  ///
  /// Se mide por CANTIDAD DE ITEMS y no por quetzales a propósito: con más de
  /// la mitad de los ingredientes sin precio, un ranking por dinero pondría
  /// arriba a quien tocó los pocos productos costeados, no a quien más marca.
  double get lostRate => itemsCancelled == 0 ? 0 : itemsLost / itemsCancelled;
}

/// Todo lo que la vista necesita, ya calculado.
class CancellationsReport {
  final List<CancellationEvent> events;
  final List<PersonCut> people;

  /// Merma total del periodo: el número grande.
  final PartialValue totalWasted;
  final PartialValue totalReturned;

  final int itemsCancelled;
  final int itemsLost;

  /// Cancelaciones que nunca tocaron inventario, por motivo.
  final int cancelledBeforeKitchen;
  final int cancelledWithoutRecipe;

  /// Ingredientes distintos involucrados que no tienen precio de compra.
  final int unpricedIngredients;

  /// La consulta llegó al tope: hay más movimientos de los que se leyeron.
  final bool truncated;

  const CancellationsReport({
    required this.events,
    required this.people,
    required this.totalWasted,
    required this.totalReturned,
    required this.itemsCancelled,
    required this.itemsLost,
    required this.cancelledBeforeKitchen,
    required this.cancelledWithoutRecipe,
    required this.unpricedIngredients,
    required this.truncated,
  });

  static const empty = CancellationsReport(
    events: [],
    people: [],
    totalWasted: PartialValue.empty,
    totalReturned: PartialValue.empty,
    itemsCancelled: 0,
    itemsLost: 0,
    cancelledBeforeKitchen: 0,
    cancelledWithoutRecipe: 0,
    unpricedIngredients: 0,
    truncated: false,
  );

  bool get isEmpty => events.isEmpty;

  /// Porcentaje de la casa: la vara contra la que se compara a cada persona.
  double get houseLostRate => itemsCancelled == 0 ? 0 : itemsLost / itemsCancelled;
}
