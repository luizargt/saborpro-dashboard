import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/navigation/destinos.dart';

/// Los nombres y el orden de la navegación (sidebar-manager.html).
void main() {
  group('la barra lateral', () {
    test('las tres secciones, con los lugares y el orden del diseño', () {
      expect(Destinos.deSeccion(SeccionNav.general), [Destino.inicio, Destino.avisos, Destino.despensa]);
      expect(Destinos.deSeccion(SeccionNav.dinero), [Destino.rentabilidad, Destino.comprasVentas, Destino.gastos, Destino.cierres, Destino.propinas]);
      expect(Destinos.deSeccion(SeccionNav.control), [Destino.cortesias, Destino.cancelados]);
    });

    test('los títulos de las secciones', () {
      expect(Destinos.tituloDeSeccion(SeccionNav.general), 'General');
      expect(Destinos.tituloDeSeccion(SeccionNav.dinero), 'Reportes · Dinero');
      expect(Destinos.tituloDeSeccion(SeccionNav.control), 'Control y pérdidas');
    });

    test('los nombres', () {
      expect(Destinos.nombre(Destino.comprasVentas), 'Compras vs Ventas');
      expect(Destinos.nombre(Destino.cierres), 'Cierres de caja');
      expect(Destinos.nombre(Destino.cortesias), 'Cortesías y donaciones');
      expect(Destinos.nombre(Destino.cancelados), 'Pedidos cancelados');
      expect(Destinos.nombre(Destino.descargas), 'Descargar reportes');
    });

    test('todos tienen nombre, ícono y descripción', () {
      for (final d in Destino.values) {
        expect(Destinos.nombre(d), isNotEmpty, reason: '$d');
        expect(Destinos.descripcion(d), isNotEmpty, reason: '$d');
        expect(Destinos.icono(d), isNotNull);
      }
    });
  });

  group('qué es un reporte', () {
    test('lo de Dinero y de Control; no Inicio, Avisos, Despensa ni lo de la cuenta', () {
      final reportes = Destino.values.where(Destinos.esReporte).toList();
      expect(reportes, [Destino.rentabilidad, Destino.comprasVentas, Destino.gastos, Destino.cierres, Destino.propinas, Destino.cortesias, Destino.cancelados]);
    });

    test('las descargas son una acción, no una pantalla', () {
      expect(Destinos.esPantalla(Destino.descargas), isFalse);
      expect(Destino.values.where(Destinos.esPantalla).length, Destino.values.length - 1);
    });
  });

  group('el encabezado', () {
    test('Inicio saluda según la hora, con el nombre de pila', () {
      expect(Destinos.miga(Destino.inicio, hora: 8, nombre: 'Luis Arreago'), 'Buenos días, Luis');
      expect(Destinos.miga(Destino.inicio, hora: 12, nombre: 'Luis'), 'Buenas tardes, Luis');
      expect(Destinos.miga(Destino.inicio, hora: 18, nombre: 'Luis'), 'Buenas tardes, Luis');
      expect(Destinos.miga(Destino.inicio, hora: 19, nombre: 'Luis'), 'Buenas noches, Luis');
      expect(Destinos.miga(Destino.inicio, hora: 3, nombre: 'Luis'), 'Buenos días, Luis');
    });

    test('sin nombre, solo el saludo', () {
      expect(Destinos.miga(Destino.inicio, hora: 9), 'Buenos días');
      expect(Destinos.miga(Destino.inicio, hora: 9, nombre: '   '), 'Buenos días');
    });

    test('el nombre de pila', () {
      expect(Destinos.primerNombre('  Ana  María  López '), 'Ana');
      expect(Destinos.primerNombre(null), isNull);
      expect(Destinos.primerNombre(''), isNull);
    });

    test('la línea de sobre el título en los demás lugares', () {
      expect(Destinos.miga(Destino.rentabilidad, hora: 9), 'Reportes · Dinero');
      expect(Destinos.miga(Destino.cancelados, hora: 9), 'Reportes · Control');
      expect(Destinos.miga(Destino.avisos, hora: 9), 'General');
      expect(Destinos.miga(Destino.despensa, hora: 9), 'General');
      expect(Destinos.miga(Destino.notificaciones, hora: 9), 'Avisos');
    });

    test('el selector de fecha: no en Avisos, sus ajustes ni Despensa (que es de hoy)', () {
      expect(Destinos.muestraFecha(Destino.inicio), isTrue);
      expect(Destinos.muestraFecha(Destino.rentabilidad), isTrue);
      expect(Destinos.muestraFecha(Destino.cancelados), isTrue);
      expect(Destinos.muestraFecha(Destino.avisos), isFalse);
      expect(Destinos.muestraFecha(Destino.notificaciones), isFalse);
      expect(Destinos.muestraFecha(Destino.despensa), isFalse);
    });

    test('"Configurar avisos" solo en Avisos', () {
      expect([for (final d in Destino.values) if (Destinos.muestraConfigurarAvisos(d)) d], [Destino.avisos]);
    });
  });

  group('la paleta de comandos busca', () {
    test('sin escribir nada, todo en el orden de la barra y al final lo de la cuenta', () {
      final t = Destinos.buscar('');
      expect(t.first, Destino.inicio);
      expect(t.sublist(t.length - 2), [Destino.descargas, Destino.notificaciones]);
      expect(t.length, Destino.values.length);
    });

    test('sin importar mayúsculas ni tildes', () {
      expect(Destinos.buscar('cortesias'), [Destino.cortesias]);
      expect(Destinos.buscar('CORTESÍAS'), [Destino.cortesias]);
      expect(Destinos.buscar('  gastos '), [Destino.gastos]);
      expect(Destinos.buscar('notific'), [Destino.notificaciones]);
    });

    test('por cualquier parte del nombre', () {
      expect(Destinos.buscar('caja'), [Destino.cierres]);
      expect(Destinos.buscar('vs'), [Destino.comprasVentas]);
      expect(Destinos.buscar('descargar'), [Destino.descargas]);
      expect(Destinos.buscar('pedidos'), [Destino.cancelados]);
    });

    test('varios a la vez, en el orden de la barra', () {
      final r = Destinos.buscar('ca');
      expect(r, containsAll([Destino.cierres, Destino.cancelados]));
      expect(r.indexOf(Destino.cierres) < r.indexOf(Destino.cancelados), isTrue);
    });

    test('lo que no existe no devuelve nada', () {
      expect(Destinos.buscar('xyz'), isEmpty);
      expect(Destinos.buscar('suscripción'), isEmpty, reason: 'esa pantalla no existe en el Manager');
    });

    test('el grupo con que sale cada uno', () {
      expect(Destinos.grupoDeBusqueda(Destino.inicio), 'Ir a');
      expect(Destinos.grupoDeBusqueda(Destino.gastos), 'Reportes · Dinero');
      expect(Destinos.grupoDeBusqueda(Destino.cortesias), 'Reportes · Control');
      expect(Destinos.grupoDeBusqueda(Destino.descargas), 'Cuenta');
    });
  });

  group('las notificaciones piden pestañas por número', () {
    test('0 Inicio, 1 Reportes (abre el primero), 2 Despensa, 3 Avisos', () {
      expect(Destinos.dePestana(0), Destino.inicio);
      expect(Destinos.dePestana(1), Destino.rentabilidad);
      expect(Destinos.dePestana(2), Destino.despensa);
      expect(Destinos.dePestana(3), Destino.avisos);
      expect(Destinos.dePestana(9), isNull);
      expect(Destinos.dePestana(-1), isNull);
    });
  });

  test('sinTildes', () {
    expect(Destinos.sinTildes('Cortesías Ñandú Çá'), 'cortesias nandu ca');
  });
}
