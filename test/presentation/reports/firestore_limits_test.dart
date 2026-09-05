import 'package:flutter_test/flutter_test.dart';

/// Firestore rechaza cualquier consulta cuyo `limit` pase de 10000, con
/// `invalid-argument`, sin importar cuántos documentos existan de verdad. Un
/// tope mal puesto no falla "cuando hay muchos datos": falla SIEMPRE, para
/// todos los clientes, desde el primer día.
///
/// Le pasó al reporte de Pedidos Cancelados, que nació con 20000 y por eso no
/// abría nunca. Este test lee los límites del código fuente para que no vuelva
/// a pasar en ningún provider.
import 'dart:io';

const _maximoDeFirestore = 10000;

void main() {
  test('ningún .limit() del proyecto pasa el máximo de Firestore', () {
    final dir = Directory('lib');
    final infractores = <String>[];
    final regex = RegExp(r'\.limit\(\s*(\d+)\s*\)');

    for (final f in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final texto = f.readAsStringSync();
      for (final m in regex.allMatches(texto)) {
        final valor = int.parse(m.group(1)!);
        if (valor > _maximoDeFirestore) {
          infractores.add('${f.path}: limit($valor)');
        }
      }
    }

    expect(infractores, isEmpty,
        reason: 'Firestore rechaza la consulta entera con estos límites:\n'
            '${infractores.join('\n')}');
  });

  test('las constantes de límite tampoco lo pasan', () {
    // Los límites suelen vivir en una constante y usarse como .limit(_kAlgo),
    // que el patrón de arriba no ve.
    final regex = RegExp(r'static const int _k\w*Limit\s*=\s*(\d+)');
    final infractores = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in regex.allMatches(f.readAsStringSync())) {
        final valor = int.parse(m.group(1)!);
        if (valor > _maximoDeFirestore) {
          infractores.add('${f.path}: ${m.group(0)}');
        }
      }
    }

    expect(infractores, isEmpty,
        reason: 'Constantes de límite por encima del máximo:\n'
            '${infractores.join('\n')}');
  });
}
