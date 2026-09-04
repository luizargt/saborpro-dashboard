import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/store_update_service.dart';

/// El comparador que decide si se bloquea la app.
///
/// Un falso positivo acá deja a un gerente sin sus reportes hasta que alguien
/// publique una versión nueva, así que cada caso raro tiene su test.
void main() {
  group('VersionComparator — cuándo la instalada está atrasada', () {
    test('una versión anterior está atrasada', () {
      expect(VersionComparator.isOlder('1.1.0', '1.2.0'), isTrue);
      expect(VersionComparator.isOlder('1.1.0', '2.0.0'), isTrue);
      expect(VersionComparator.isOlder('1.1.0', '1.1.1'), isTrue);
    });

    test('la misma versión no está atrasada', () {
      expect(VersionComparator.isOlder('1.1.0', '1.1.0'), isFalse);
      expect(VersionComparator.isOlder('3.102.16', '3.102.16'), isFalse);
    });

    test('una build interna más nueva NO se marca como atrasada', () {
      // Es el caso que encierra a un tester: su versión es distinta a la de la
      // tienda, pero actualizar lo llevaría hacia atrás, así que el aviso no
      // se iría nunca.
      expect(VersionComparator.isOlder('1.3.0', '1.2.0'), isFalse);
      expect(VersionComparator.isOlder('2.0.0', '1.9.9'), isFalse);
    });

    test('compara por número, no alfabéticamente', () {
      // Como texto "1.10.0" < "1.9.0", que es exactamente al revés.
      expect(VersionComparator.isOlder('1.9.0', '1.10.0'), isTrue);
      expect(VersionComparator.isOlder('1.10.0', '1.9.0'), isFalse);
      expect(VersionComparator.isOlder('3.99.0', '3.102.16'), isTrue);
    });

    test('los ceros que faltan se leen como cero', () {
      expect(VersionComparator.isOlder('1.2', '1.2.0'), isFalse);
      expect(VersionComparator.isOlder('1.2.0', '1.2'), isFalse);
      expect(VersionComparator.isOlder('1.2', '1.2.1'), isTrue);
      expect(VersionComparator.isOlder('1', '1.0.0'), isFalse);
    });

    test('sufijos como -beta no rompen la comparación', () {
      expect(VersionComparator.isOlder('1.2.0-beta.3', '1.3.0'), isTrue);
      expect(VersionComparator.isOlder('1.2.0-beta.3', '1.2.0'), isFalse);
      expect(VersionComparator.isOlder('1.2.0 (build 4)', '1.3.0'), isTrue);
    });

    test('lo ilegible no bloquea a nadie', () {
      // Ante la duda no se molesta: es preferible no avisar que encerrar.
      expect(VersionComparator.isOlder('', '1.2.0'), isFalse);
      expect(VersionComparator.isOlder('1.2.0', ''), isFalse);
      expect(VersionComparator.isOlder('vieja', '1.2.0'), isFalse);
      expect(VersionComparator.isOlder('1.2.0', 'nueva'), isFalse);
      expect(VersionComparator.isOlder('   ', '1.2.0'), isFalse);
    });

    test('el caso real de hoy: instalada y tienda coinciden', () {
      // Sabor Manager 1.1.0 en App Store, 1.1.0 instalada. No debe avisar.
      expect(VersionComparator.isOlder('1.1.0', '1.1.0'), isFalse);
    });
  });

  group('StoreUpdateStatus', () {
    test('upToDate no manda a ninguna tienda', () {
      final s = StoreUpdateStatus.upToDate('1.1.0');
      expect(s.updateAvailable, isFalse);
      expect(s.storeUrl, isNull);
      expect(s.currentVersion, '1.1.0');
    });
  });
}
