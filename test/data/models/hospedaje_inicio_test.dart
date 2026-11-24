import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/hospedaje_inicio.dart';

// Hospedaje en el Inicio: el estado de AHORA. Las reglas siguen a la cuadrícula
// "Hospedar" del POS (ver hospedaje_inicio.dart); lo que se queda guardado en la
// habitación o en la cama se queda viejo, así que la ocupación sale de las
// reservaciones.

final _ahora = DateTime(2026, 11, 24, 15, 0);

HabitacionHosp _hab(String id,
        {String estado = 'available', String sucursal = 'S1', bool dorm = false, List<CamaHosp> camas = const []}) =>
    HabitacionHosp(id: id, locationId: sucursal, estado: estado, dormitorio: dorm, camas: camas);

EstanciaHosp _est(String room,
        {String id = '',
        bool activa = true,
        String sucursal = 'S1',
        bool porNoches = true,
        DateTime? entrada,
        DateTime? salida}) =>
    EstanciaHosp(
      id: id.isEmpty ? '$room-${activa ? 'a' : 'r'}' : id,
      roomId: room,
      locationId: sucursal,
      activa: activa,
      porNoches: porNoches,
      entrada: entrada,
      salidaEstimada: salida,
    );

ResumenHospedaje _armar(List<HabitacionHosp> h, List<EstanciaHosp> e, {DateTime? ahora, bool Function(String)? pasa}) =>
    ResumenHospedaje.armar(habitaciones: h, estancias: e, ahora: ahora ?? _ahora, pasa: pasa);

/// [ocupadas, reservadas, limpieza, mantenimiento, libres]
List<int> _reparto(ResumenHospedaje r) => [r.ocupadas, r.reservadas, r.enLimpieza, r.enMantenimiento, r.libres];

void main() {
  group('armar: habitaciones', () {
    test('sin habitaciones no hay nada que decir', () {
      final r = _armar(const [], const []);
      expect(r.vacio, isTrue);
      expect(r.total, 0);
      expect(r.porcentaje, 0);
    });

    test('cada habitación cae en UN solo grupo y los grupos suman el total', () {
      final r = _armar(
        [_hab('1'), _hab('2'), _hab('3', estado: 'cleaning'), _hab('4', estado: 'maintenance'), _hab('5')],
        [_est('1'), _est('2')],
      );
      expect(_reparto(r), [2, 0, 1, 1, 1]);
      expect(r.total, 5);
      expect(r.ocupadas + r.reservadas + r.enLimpieza + r.enMantenimiento + r.libres, r.total);
      expect(r.porcentaje, 40);
      expect(r.estanciasActivas, 2);
    });

    test('una estancia activa manda sobre limpieza y sobre "disponible"; mantenimiento manda sobre la estancia (como el POS)', () {
      final r = _armar([_hab('1', estado: 'cleaning'), _hab('2'), _hab('3', estado: 'maintenance')], [_est('1'), _est('2'), _est('3')]);
      expect(_reparto(r), [2, 0, 0, 1, 0]);
    });

    test('"ocupada" o "reservada" guardadas en la habitación, sin estancia ni reservación, no cuentan', () {
      final r = _armar([_hab('1', estado: 'occupied'), _hab('2', estado: 'reserved')], const []);
      expect(_reparto(r), [0, 0, 0, 0, 2]);
    });

    test('el porcentaje se redondea: 7 de 11 es 64%', () {
      final r = _armar([for (var i = 0; i < 11; i++) _hab('$i')], [for (var i = 0; i < 7; i++) _est('$i')]);
      expect([r.ocupadas, r.total, r.porcentaje], [7, 11, 64]);
    });

    test('dos estancias activas en la misma habitación (dato raro) ocupan UNA habitación', () {
      final r = _armar([_hab('1'), _hab('2')], [_est('1', id: 'x'), _est('1', id: 'y')]);
      expect([r.ocupadas, r.libres, r.estanciasActivas], [1, 1, 2]);
    });
  });

  group('armar: reservadas para hoy', () {
    final hoyNoche = DateTime(2026, 11, 24, 20, 0);

    test('una reservación de esta noche deja la habitación "reservada", no "libre"', () {
      final r = _armar([_hab('1')], [_est('1', activa: false, entrada: hoyNoche, salida: DateTime(2026, 11, 25, 12, 0))]);
      expect(_reparto(r), [0, 1, 0, 0, 0]);
    });

    test('reservada manda sobre limpieza (la cuadrícula del POS dice "Ocupada")', () {
      final r = _armar([_hab('1', estado: 'cleaning')], [_est('1', activa: false, entrada: hoyNoche, salida: DateTime(2026, 11, 25, 12, 0))]);
      expect(_reparto(r), [0, 1, 0, 0, 0]);
    });

    test('una de mañana no ocupa hoy: la habitación sigue libre', () {
      final r = _armar([_hab('1', estado: 'reserved')],
          [_est('1', activa: false, entrada: DateTime(2026, 11, 25, 20, 0), salida: DateTime(2026, 11, 26, 12, 0))]);
      expect(_reparto(r), [0, 0, 0, 0, 1]);
    });

    test('una noche que ya terminó (entró ayer, sale hoy) no ocupa hoy', () {
      final r = _armar([_hab('1')],
          [_est('1', activa: false, entrada: DateTime(2026, 11, 23, 20, 0), salida: DateTime(2026, 11, 24, 12, 0))]);
      expect(r.libres, 1);
    });

    test('un no-show de varias noches que todavía cubre hoy sigue bloqueando la habitación', () {
      final r = _armar([_hab('1')],
          [_est('1', activa: false, entrada: DateTime(2026, 11, 23, 20, 0), salida: DateTime(2026, 11, 26, 12, 0))]);
      expect(r.reservadas, 1);
    });

    test('por horas: de hoy cuenta aunque entre y salga el mismo día', () {
      final r = _armar([_hab('1')],
          [_est('1', activa: false, porNoches: false, entrada: hoyNoche, salida: DateTime(2026, 11, 24, 23, 0))]);
      expect(r.reservadas, 1);
    });

    test('una reservación sin fecha de entrada no se sabe: no ocupa', () {
      final r = _armar([_hab('1')], [_est('1', activa: false)]);
      expect([r.reservadas, r.libres], [0, 1]);
    });
  });

  group('armar: dormitorios (hostal)', () {
    test('se cuentan por camas, con el estado de cada cama y sin reservación declarada', () {
      final r = _armar([
        _hab('D', dorm: true, camas: const [
          CamaHosp(estado: 'occupied'), // sin reservación declarada: lo único que hay es el estado
          CamaHosp(),
          CamaHosp(estado: 'cleaning'),
          CamaHosp(estado: 'maintenance'),
        ]),
        _hab('P'),
      ], const []);
      expect([r.total, ..._reparto(r)], [5, 1, 0, 1, 1, 2]);
    });

    test('una cama "occupied" cuya reservación ya NO está activa (el POS no la libera) queda libre', () {
      final r = _armar([
        _hab('D', dorm: true, camas: const [
          CamaHosp(estado: 'occupied', reservaId: 'ya-salio'),
          CamaHosp(estado: 'occupied', reservaId: 'activa-1'),
        ]),
      ], [
        _est('D', id: 'activa-1'),
      ]);
      expect(_reparto(r), [1, 0, 0, 0, 1]);
    });

    test('una cama reservada a futuro (el POS ya la marca "occupied") no es de hoy: libre', () {
      final r = _armar([
        _hab('D', dorm: true, camas: const [CamaHosp(estado: 'occupied', reservaId: 'futura')]),
      ], [
        _est('D', id: 'futura', activa: false, entrada: DateTime(2026, 12, 3, 20), salida: DateTime(2026, 12, 4, 12)),
      ]);
      expect(_reparto(r), [0, 0, 0, 0, 1]);
    });

    test('una cama con reservación de esta noche cuenta como reservada', () {
      final r = _armar([
        _hab('D', dorm: true, camas: const [CamaHosp(estado: 'occupied', reservaId: 'hoy')]),
      ], [
        _est('D', id: 'hoy', activa: false, entrada: DateTime(2026, 11, 24, 20), salida: DateTime(2026, 11, 25, 12)),
      ]);
      expect(_reparto(r), [0, 1, 0, 0, 0]);
    });

    test('la habitación en mantenimiento lleva TODAS sus camas a mantenimiento', () {
      final r = _armar([
        _hab('D', dorm: true, estado: 'maintenance', camas: const [CamaHosp(), CamaHosp(estado: 'occupied')]),
      ], const []);
      expect(_reparto(r), [0, 0, 0, 2, 0]);
    });

    test('un dormitorio sin camas guardadas cuenta como una habitación', () {
      final r = _armar([_hab('D', dorm: true)], [_est('D')]);
      expect([r.total, r.ocupadas], [1, 1]);
    });
  });

  group('armar: sucursales', () {
    test('solo cuentan las sucursales que pasan el filtro', () {
      final h = [_hab('1'), _hab('2', sucursal: 'S2'), _hab('3', sucursal: 'S2')];
      final e = [_est('1'), _est('2', sucursal: 'S2')];
      final solo2 = _armar(h, e, pasa: (s) => s == 'S2');
      expect([solo2.total, solo2.ocupadas, solo2.estanciasActivas], [2, 1, 1]);
      final todas = _armar(h, e);
      expect([todas.total, todas.ocupadas, todas.estanciasActivas], [3, 2, 2]);
    });
  });

  group('armar: estancias de habitaciones que no se cuentan', () {
    test('las de una habitación borrada (el POS deja sus reservaciones) no dan alertas', () {
      final r = _armar([_hab('1')], [
        _est('FANTASMA', salida: DateTime(2026, 11, 23, 12, 0)), // se "pasó de su hora"
        _est('FANTASMA-2', salida: DateTime(2026, 11, 24, 18, 0)), // "sale hoy"
        _est('FANTASMA-3', activa: false, entrada: DateTime(2026, 11, 24, 20), salida: DateTime(2026, 11, 25, 12)),
      ]);
      expect([r.estanciasActivas, r.porSalirHoy, r.pasadasDeHora, r.reservadas], [0, 0, 0, 0]);
      expect(r.libres, 1);
    });

    test('tampoco las de una habitación dada de baja ni las de una sucursal que no se mira', () {
      final h = [
        // `active: false` ya la descarta HabitacionHosp.deDoc: no llega a armar.
        _hab('2', sucursal: 'S2'),
      ];
      final r = _armar(h, [_est('1'), _est('2', sucursal: 'S2')], pasa: (s) => s == 'S1');
      expect([r.total, r.estanciasActivas], [0, 0]);
    });
  });

  group('armar: lo de hoy', () {
    test('por salir hoy y pasadas de hora', () {
      final r = _armar([for (var i = 1; i <= 6; i++) _hab('$i')], [
        _est('1', salida: DateTime(2026, 11, 24, 18, 0)), // hoy, todavía no
        _est('2', salida: DateTime(2026, 11, 24, 12, 0)), // hoy, ya pasó
        _est('3', salida: DateTime(2026, 11, 25, 12, 0)), // mañana
        _est('4'), // sin hora de salida
        _est('5', salida: DateTime(2026, 11, 23, 12, 0)), // ayer: se pasó
        _est('6', salida: DateTime(2026, 11, 24, 15, 0)), // justo ahora: todavía no pasó
      ]);
      expect(r.porSalirHoy, 2); // 1 y 6
      expect(r.pasadasDeHora, 2); // 2 y 5
      expect(r.estanciasActivas, 6);
    });

    test('las reservaciones (no activas) no cuentan como salidas ni como pasadas', () {
      final r = _armar([_hab('1')], [_est('1', activa: false, salida: DateTime(2026, 11, 24, 10, 0))]);
      expect([r.porSalirHoy, r.pasadasDeHora, r.estanciasActivas], [0, 0, 0]);
    });
  });

  group('EstanciaHosp.ocupaHoy (la regla de Reservation.diasOcupados del POS)', () {
    EstanciaHosp e({bool activa = false, bool noches = true, DateTime? entrada, DateTime? salida}) =>
        _est('R', activa: activa, porNoches: noches, entrada: entrada, salida: salida);

    test('por noches: de la entrada al día ANTES de la salida', () {
      final x = e(entrada: DateTime(2026, 11, 23, 20), salida: DateTime(2026, 11, 26, 12));
      expect(x.ocupaHoy(DateTime(2026, 11, 22, 10)), isFalse);
      expect(x.ocupaHoy(DateTime(2026, 11, 23, 10)), isTrue);
      expect(x.ocupaHoy(DateTime(2026, 11, 25, 23)), isTrue);
      expect(x.ocupaHoy(DateTime(2026, 11, 26, 8)), isFalse); // el día de salida ya queda libre
    });

    test('por noches con la salida el mismo día (rango vacío): ocupa solo el día de entrada', () {
      final x = e(entrada: DateTime(2026, 11, 24, 20), salida: DateTime(2026, 11, 24, 23));
      expect(x.ocupaHoy(DateTime(2026, 11, 24, 10)), isTrue);
      expect(x.ocupaHoy(DateTime(2026, 11, 25, 10)), isFalse);
    });

    test('por horas: todos los días que toca; si sale a las 00:00 ese día ya no cuenta', () {
      final cruza = e(noches: false, entrada: DateTime(2026, 11, 24, 22), salida: DateTime(2026, 11, 25, 3));
      expect(cruza.ocupaHoy(DateTime(2026, 11, 24, 23)), isTrue);
      expect(cruza.ocupaHoy(DateTime(2026, 11, 25, 1)), isTrue);
      final medianoche = e(noches: false, entrada: DateTime(2026, 11, 24, 22), salida: DateTime(2026, 11, 25, 0, 0));
      expect(medianoche.ocupaHoy(DateTime(2026, 11, 25, 1)), isFalse);
    });

    test('una estancia ACTIVA ocupa hasta el check-out aunque ya pasó la salida estimada', () {
      final x = e(activa: true, entrada: DateTime(2026, 11, 20, 20), salida: DateTime(2026, 11, 22, 12));
      expect(x.ocupaHoy(DateTime(2026, 11, 24, 10)), isTrue);
      final reservadaVieja = e(entrada: DateTime(2026, 11, 20, 20), salida: DateTime(2026, 11, 22, 12));
      expect(reservadaVieja.ocupaHoy(DateTime(2026, 11, 24, 10)), isFalse);
    });

    test('sin entrada no se sabe: no ocupa; sin salida, solo el día de entrada', () {
      expect(e().ocupaHoy(_ahora), isFalse);
      final x = e(entrada: DateTime(2026, 11, 24, 9));
      expect(x.ocupaHoy(_ahora), isTrue);
      expect(x.ocupaHoy(DateTime(2026, 11, 25, 9)), isFalse);
    });
  });

  group('HabitacionHosp.deDoc', () {
    test('una habitación dada de baja no se cuenta', () {
      expect(HabitacionHosp.deDoc('1', {'location_id': 'S1', 'active': false}), isNull);
    });

    test('sin sucursal no sirve', () {
      expect(HabitacionHosp.deDoc('1', {'status': 'available'}), isNull);
      expect(HabitacionHosp.deDoc('1', {'location_id': ''}), isNull);
    });

    test('lee estado, tipo y camas (con su reservación); el estado que falta es "available"', () {
      final h = HabitacionHosp.deDoc('D', {
        'location_id': 'S1',
        'type': 'dorm',
        'status': 'cleaning',
        'slots': [
          {'name': 'Cama 1', 'status': 'occupied', 'current_reservation_id': 'R1'},
          {'name': 'Cama 2'},
          {'name': 'Cama 3', 'status': 'occupied', 'current_reservation_id': ''},
          'basura',
        ],
      })!;
      expect([h.dormitorio, h.estado], [true, 'cleaning']);
      expect([for (final c in h.camas) c.estado], ['occupied', 'available', 'occupied']);
      expect([for (final c in h.camas) c.reservaId], ['R1', null, null]);
      final sin = HabitacionHosp.deDoc('1', {'location_id': 'S1'})!;
      expect([sin.dormitorio, sin.estado, sin.camas.length], [false, 'available', 0]);
    });
  });

  group('EstanciaHosp.deDoc', () {
    test('lee las fechas en texto ISO sin zona (hora local) y el tipo de renta', () {
      final e = EstanciaHosp.deDoc({
        'location_id': 'S1',
        'room_id': 'R1',
        'rental_type': 'hour',
        'check_in': '2026-11-24T09:30:00.000',
        'estimated_check_out': '2026-11-24T12:00:00.000',
      }, id: 'abc', activa: true)!;
      expect(e.id, 'abc');
      expect(e.entrada, DateTime(2026, 11, 24, 9, 30));
      expect(e.salidaEstimada, DateTime(2026, 11, 24, 12, 0));
      expect([e.activa, e.porNoches], [true, false]);
    });

    test('sin tipo de renta es por noches (como el POS); sin id usa el campo `id`', () {
      final e = EstanciaHosp.deDoc({'location_id': 'S1', 'room_id': 'R1', 'id': 'del-campo'}, activa: false)!;
      expect([e.porNoches, e.id], [true, 'del-campo']);
    });

    test('lo que no se entiende queda nulo, nunca una fecha inventada', () {
      final e = EstanciaHosp.deDoc({'location_id': 'S1', 'room_id': 'R1', 'check_in': 'ayer', 'estimated_check_out': 42}, activa: false)!;
      expect([e.entrada, e.salidaEstimada], [null, null]);
    });

    test('también lee algo que sepa darse como fecha (Timestamp)', () {
      final e = EstanciaHosp.deDoc({'location_id': 'S1', 'room_id': 'R1', 'check_in': _FalsoTimestamp(DateTime(2026, 11, 24, 7))}, activa: false)!;
      expect(e.entrada, DateTime(2026, 11, 24, 7));
    });

    test('sin habitación o sin sucursal no sirve', () {
      expect(EstanciaHosp.deDoc({'location_id': 'S1'}, activa: true), isNull);
      expect(EstanciaHosp.deDoc({'room_id': 'R1'}, activa: true), isNull);
      expect(EstanciaHosp.deDoc({'location_id': '', 'room_id': 'R1'}, activa: true), isNull);
    });
  });
}

class _FalsoTimestamp {
  final DateTime _f;
  _FalsoTimestamp(this._f);
  DateTime toDate() => _f;
}
