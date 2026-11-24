/// Hospedaje en el Inicio: cómo está el hotel AHORA (habitaciones ocupadas,
/// reservadas para hoy, en limpieza, en mantenimiento y libres, y lo que sale
/// hoy).
///
/// Lógica pura: [ResumenHospedaje.armar] recibe lo que se leyó de `rooms` y
/// `reservations` del POS y no toca Firestore. Es el estado de AHORA, no un
/// período, igual que "Cuentas abiertas" y "Cajas abiertas".
///
/// Las reglas siguen a la cuadrícula "Hospedar" del POS (room_selection_screen):
/// mantenimiento, luego la ocupación por RESERVACIONES, luego limpieza, y el resto
/// libre. Lo que se queda guardado en la habitación se queda viejo, así que la
/// ocupación se saca de las reservaciones:
///  - Una habitación está ocupada si tiene una estancia ACTIVA (check-in hecho y
///    sin check-out). Está reservada si no la tiene pero una reservación aún no
///    activa la ocupa HOY (la cuadrícula del POS las junta bajo "Ocupada"; aquí se
///    dicen aparte para que "libres" sea lo que de verdad se puede vender hoy).
///  - El estado "ocupada" o "reservada" guardado en la habitación no cuenta: el POS
///    pone "reservada" al crear cualquier reservación, aunque sea de la semana que
///    viene.
///  - Un dormitorio (hostal) se cuenta por CAMAS. El POS nunca libera el estado de
///    una cama ("occupied" se queda pegado después del check-out y se pone también
///    al reservar a futuro), así que una cama solo está ocupada si la reservación
///    que dice tener (`current_reservation_id`) está ACTIVA.
///  - Una estancia de una habitación que ya no existe (el POS borra la habitación y
///    deja las reservaciones) no se cuenta en nada: sería una alerta que el dueño no
///    puede resolver.
library;

/// El `product_id` con que el POS guarda en un pedido el cargo del hospedaje
/// ("Noche de Hospedaje", "Hora de Hospedaje"). No es un producto del menú: no
/// tiene clasificación, y sin esto caería en "Otros".
const kProductoHospedaje = 'hospedaje';

/// La clasificación con que el Inicio agrupa esos cargos.
const kClasificacionHospedaje = 'Hospedaje';

/// Una cama de un dormitorio, tal como la guarda el POS dentro de `rooms.slots`.
class CamaHosp {
  /// `available`, `occupied`, `cleaning` o `maintenance` (el POS solo escribe los
  /// dos primeros, y `occupied` no se libera).
  final String estado;

  /// La reservación a la que dice pertenecer (`current_reservation_id`).
  final String? reservaId;

  const CamaHosp({this.estado = 'available', this.reservaId});
}

/// Una habitación tal como la guarda el POS en `rooms`.
class HabitacionHosp {
  final String id;
  final String locationId;

  /// Dormitorio compartido: se cuenta por camas.
  final bool dormitorio;

  /// `available`, `occupied`, `cleaning`, `maintenance` o `reserved`.
  final String estado;

  /// Las camas (solo dormitorio).
  final List<CamaHosp> camas;

  const HabitacionHosp({
    required this.id,
    required this.locationId,
    this.dormitorio = false,
    this.estado = 'available',
    this.camas = const [],
  });

  /// Nulo si el documento no sirve: sin sucursal, o la habitación está dada de
  /// baja (`active: false`).
  static HabitacionHosp? deDoc(String id, Map<String, dynamic> d) {
    if (d['active'] == false) return null;
    final sucursal = d['location_id'];
    if (sucursal is! String || sucursal.isEmpty) return null;
    final camas = <CamaHosp>[];
    final slots = d['slots'];
    if (slots is List) {
      for (final s in slots) {
        if (s is! Map) continue;
        final reserva = s['current_reservation_id'];
        camas.add(CamaHosp(
          estado: s['status'] is String ? s['status'] as String : 'available',
          reservaId: reserva is String && reserva.isNotEmpty ? reserva : null,
        ));
      }
    }
    return HabitacionHosp(
      id: id,
      locationId: sucursal,
      dormitorio: d['type'] == 'dorm',
      estado: d['status'] is String ? d['status'] as String : 'available',
      camas: camas,
    );
  }
}

/// Una estancia o reservación tal como la guarda el POS en `reservations`.
class EstanciaHosp {
  /// El id de la reservación (el de su documento).
  final String id;
  final String roomId;
  final String locationId;

  /// `true` = estancia activa (ya entró); `false` = reservada (todavía no).
  final bool activa;

  /// Se renta por noches (la salida es a la hora de entrada, pero el día de salida
  /// ya queda libre); lo demás (por horas, planes propios) ocupa hasta el día de
  /// la salida.
  final bool porNoches;
  final DateTime? entrada;
  final DateTime? salidaEstimada;

  const EstanciaHosp({
    this.id = '',
    required this.roomId,
    required this.locationId,
    required this.activa,
    this.porNoches = true,
    this.entrada,
    this.salidaEstimada,
  });

  /// Nulo si el documento no sirve (sin habitación o sin sucursal). [id] es el del
  /// documento; sin él se usa el campo `id` que el POS también guarda.
  static EstanciaHosp? deDoc(Map<String, dynamic> d, {String? id, required bool activa}) {
    final sucursal = d['location_id'];
    final habitacion = d['room_id'];
    if (sucursal is! String || sucursal.isEmpty) return null;
    if (habitacion is! String || habitacion.isEmpty) return null;
    final propio = d['id'];
    return EstanciaHosp(
      id: id ?? (propio is String ? propio : ''),
      roomId: habitacion,
      locationId: sucursal,
      activa: activa,
      // El POS guarda 'night' por omisión cuando falta.
      porNoches: (d['rental_type'] ?? 'night') == 'night',
      entrada: fechaDe(d['check_in']),
      salidaEstimada: fechaDe(d['estimated_check_out']),
    );
  }

  /// ¿Esta reservación ocupa la habitación el día de [ahora]? La misma regla que
  /// `Reservation.diasOcupados` del POS:
  ///  - por noches, de la entrada al día ANTES de la salida (el día de salida queda
  ///    libre: el siguiente huésped entra después de la hora de salida);
  ///  - por horas (o plan propio), todos los días que toca, de la entrada al de la
  ///    salida; si sale justo a las 00:00, ese día ya no cuenta;
  ///  - una estancia ACTIVA ocupa hasta el check-out aunque ya pasó la salida
  ///    estimada.
  /// Sin fecha de entrada no se sabe: no ocupa.
  bool ocupaHoy(DateTime ahora) {
    final llegada = entrada;
    if (llegada == null) return false;
    DateTime dia(DateTime t) => DateTime(t.year, t.month, t.day);
    DateTime siguiente(DateTime d) => DateTime(d.year, d.month, d.day + 1);
    DateTime anterior(DateTime d) => DateTime(d.year, d.month, d.day - 1);

    final hoy = dia(ahora);
    final primero = dia(llegada);
    final fin = salidaEstimada;
    DateTime ultimo;
    if (fin == null) {
      ultimo = primero;
    } else if (porNoches) {
      var salida = dia(fin);
      if (!salida.isAfter(primero)) salida = siguiente(primero);
      ultimo = anterior(salida);
    } else {
      ultimo = dia(fin);
      if (ultimo.isAfter(primero) && fin.isAtSameMomentAs(ultimo)) ultimo = anterior(ultimo);
      if (ultimo.isBefore(primero)) ultimo = primero;
    }
    if (activa && hoy.isAfter(ultimo)) ultimo = hoy;
    return !hoy.isBefore(primero) && !hoy.isAfter(ultimo);
  }

  /// El POS guarda las fechas de las reservaciones como texto ISO sin zona (hora
  /// local del aparato); por si algún día llegan como `Timestamp`, también se
  /// leen. Lo que no se entiende queda nulo, nunca una fecha inventada.
  static DateTime? fechaDe(Object? v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    if (v != null) {
      try {
        final f = (v as dynamic).toDate();
        if (f is DateTime) return f.toLocal();
      } catch (_) {}
    }
    return null;
  }
}

/// Lo que el Inicio dice del hospedaje.
class ResumenHospedaje {
  /// Habitaciones (o camas, en dormitorios) contadas.
  final int total;
  final int ocupadas;

  /// Reservadas para hoy: todavía no entran, pero la reservación las ocupa hoy.
  final int reservadas;
  final int enLimpieza;
  final int enMantenimiento;

  /// Lo que de verdad se puede vender hoy.
  final int libres;

  /// Estancias activas que hoy llegan a su hora de salida (todavía no pasa).
  final int porSalirHoy;

  /// Estancias activas que ya pasaron su hora de salida estimada y siguen sin
  /// check-out (en un motel, "se pasó de su hora").
  final int pasadasDeHora;

  /// Estancias activas ahora mismo (de las habitaciones contadas).
  final int estanciasActivas;

  const ResumenHospedaje({
    required this.total,
    required this.ocupadas,
    this.reservadas = 0,
    required this.enLimpieza,
    required this.enMantenimiento,
    required this.libres,
    required this.porSalirHoy,
    required this.pasadasDeHora,
    required this.estanciasActivas,
  });

  /// Ocupadas sobre el total contado (mantenimiento incluido), redondeado.
  int get porcentaje => total == 0 ? 0 : (ocupadas * 100 / total).round();

  /// Sin habitaciones que contar no hay nada que decir.
  bool get vacio => total == 0;

  /// Arma el resumen de las sucursales para las que [pasa] diga que sí (todas si
  /// no se da). [ahora] es la hora del aparato: "hoy" es su día local.
  static ResumenHospedaje armar({
    required List<HabitacionHosp> habitaciones,
    required List<EstanciaHosp> estancias,
    required DateTime ahora,
    bool Function(String locationId)? pasa,
  }) {
    final vale = pasa ?? (_) => true;
    bool esHoy(DateTime t) => t.year == ahora.year && t.month == ahora.month && t.day == ahora.day;

    final contadas = [for (final h in habitaciones) if (vale(h.locationId)) h];
    final idsContadas = {for (final h in contadas) h.id};

    // Solo estancias de habitaciones que se cuentan: el POS borra la habitación y
    // deja sus reservaciones.
    bool deContada(EstanciaHosp e) => vale(e.locationId) && idsContadas.contains(e.roomId);
    final activas = [for (final e in estancias) if (e.activa && deContada(e)) e];
    final reservadasHoy = [for (final e in estancias) if (!e.activa && deContada(e) && e.ocupaHoy(ahora)) e];

    final conActiva = {for (final e in activas) e.roomId};
    final conReservaHoy = {for (final e in reservadasHoy) e.roomId};
    final idsActivas = {for (final e in activas) if (e.id.isNotEmpty) e.id};
    final idsReservadasHoy = {for (final e in reservadasHoy) if (e.id.isNotEmpty) e.id};

    var total = 0, ocupadas = 0, reservadas = 0, limpieza = 0, mantenimiento = 0, libres = 0;

    for (final h in contadas) {
      final mantenida = h.estado == 'maintenance';
      if (h.dormitorio && h.camas.isNotEmpty) {
        for (final cama in h.camas) {
          total++;
          final reserva = cama.reservaId;
          if (mantenida || cama.estado == 'maintenance') {
            mantenimiento++;
          } else if (reserva != null ? idsActivas.contains(reserva) : cama.estado == 'occupied') {
            // Con reservación declarada manda ella; sin ella, lo único que hay es
            // el estado de la cama.
            ocupadas++;
          } else if (reserva != null && idsReservadasHoy.contains(reserva)) {
            reservadas++;
          } else if (cama.estado == 'cleaning') {
            limpieza++;
          } else {
            libres++;
          }
        }
      } else {
        total++;
        if (mantenida) {
          mantenimiento++;
        } else if (conActiva.contains(h.id)) {
          ocupadas++;
        } else if (conReservaHoy.contains(h.id)) {
          reservadas++;
        } else if (h.estado == 'cleaning') {
          limpieza++;
        } else {
          libres++;
        }
      }
    }

    return ResumenHospedaje(
      total: total,
      ocupadas: ocupadas,
      reservadas: reservadas,
      enLimpieza: limpieza,
      enMantenimiento: mantenimiento,
      libres: libres,
      porSalirHoy: activas
          .where((e) => e.salidaEstimada != null && esHoy(e.salidaEstimada!) && !e.salidaEstimada!.isBefore(ahora))
          .length,
      pasadasDeHora: activas.where((e) => e.salidaEstimada != null && e.salidaEstimada!.isBefore(ahora)).length,
      estanciasActivas: activas.length,
    );
  }
}
