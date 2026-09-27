import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/core/services/push_token_deletion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Candado de las dos reglas de PushTokenDeletion. Romper cualquiera deja un
/// teléfono sin avisos (o recibiendo los de una cuenta de la que ya salió) sin
/// que nada falle a la vista.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marca el borrado ANTES de borrar y la quita solo al confirmarse', () async {
    bool? marcadoDuranteElBorrado;
    late PushTokenDeletion borrado;
    borrado = PushTokenDeletion(() async {
      marcadoDuranteElBorrado = await borrado.hasPending();
    });

    await borrado.run();

    expect(marcadoDuranteElBorrado, isTrue);
    expect(await borrado.hasPending(), isFalse);
  });

  test('si FCM falla, la marca queda y el siguiente pedido lo reintenta', () async {
    var intentos = 0;
    final borrado = PushTokenDeletion(() async {
      intentos++;
      if (intentos == 1) throw Exception('SERVICE_NOT_AVAILABLE');
    });

    await borrado.run(); // no lanza
    expect(await borrado.hasPending(), isTrue);

    await borrado.runIfPending();
    expect(intentos, 2);
    expect(await borrado.hasPending(), isFalse);
  });

  test('si la app muere a la mitad, el siguiente arranque repite el borrado', () async {
    // Primer proceso: el borrado nunca contesta (la app se cerró antes).
    final colgado = Completer<void>();
    final antes = PushTokenDeletion(() => colgado.future);
    unawaited(antes.run());
    await Future<void>.delayed(Duration.zero);

    // Proceso nuevo: misma marca en disco, instancia nueva.
    var borradoDeNuevo = false;
    final despues = PushTokenDeletion(() async => borradoDeNuevo = true);
    expect(despues.inFlight, isFalse);
    await despues.runIfPending();

    expect(borradoDeNuevo, isTrue);
    expect(await despues.hasPending(), isFalse);
  });

  test('nunca corren dos borrados a la vez: el segundo se suma al primero', () async {
    var llamadas = 0;
    final enVuelo = Completer<void>();
    final borrado = PushTokenDeletion(() {
      llamadas++;
      return enVuelo.future;
    });

    final primero = borrado.run();
    await Future<void>.delayed(Duration.zero);
    final segundo = borrado.run();
    final pedidoDeToken = borrado.runIfPending();

    var terminoAntes = false;
    unawaited(pedidoDeToken.then((_) => terminoAntes = true));
    await Future<void>.delayed(Duration.zero);
    // El pedido de token espera al borrado en curso en vez de adelantarse.
    expect(terminoAntes, isFalse);

    enVuelo.complete();
    await Future.wait([primero, segundo, pedidoDeToken]);

    expect(llamadas, 1);
    expect(borrado.inFlight, isFalse);
    expect(await borrado.hasPending(), isFalse);
  });

  test('sin nada pendiente, pedir token no borra nada', () async {
    var llamadas = 0;
    final borrado = PushTokenDeletion(() async => llamadas++);

    await borrado.runIfPending();

    expect(llamadas, 0);
  });
}
