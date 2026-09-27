import 'package:shared_preferences/shared_preferences.dart';

/// Borrado en FCM del token de push de ESTE aparato, al cerrar sesión.
///
/// Vive aparte de NotificationService, con el borrado inyectable, para poder
/// probarlo sin Firebase: las dos reglas de abajo son fáciles de romper sin
/// darse cuenta, y romperlas deja un teléfono mudo sin que nadie lo note.
///
/// 1. NUNCA DOS A LA VEZ. En Android el borrado es por aparato, no por token:
///    uno que termina después de que otro ya dejó pedir un token nuevo se
///    lleva también ese token nuevo. Una llamada mientras hay uno corriendo se
///    suma al que corre.
///
/// 2. MARCA EN DISCO HASTA QUE FCM CONFIRME. Si la app muere a la mitad o FCM
///    no contesta, no hay forma de saber si el servidor alcanzó a borrarlo. En
///    Android el teléfono sigue entregando ese token —quizá ya muerto— hasta 7
///    días, así que quien entrara en él guardaría un token muerto. La marca
///    sobrevive al cierre de la app y hace que el siguiente pedido de token (o
///    el siguiente arranque sin sesión) repita el borrado antes.
class PushTokenDeletion {
  PushTokenDeletion(this._borrarEnFcm);

  final Future<void> Function() _borrarEnFcm;
  Future<void>? _enCurso;

  static const _kPendiente = 'push_token_borrado_pendiente';

  /// Si hay un borrado corriendo ahora mismo en este proceso.
  bool get inFlight => _enCurso != null;

  /// Si quedó un borrado sin confirmar, de este arranque o de uno anterior.
  Future<bool> hasPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kPendiente) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Borra el token. Nunca lanza: si falla, la marca queda puesta y el
  /// siguiente [runIfPending] lo vuelve a intentar.
  Future<void> run() {
    final enCurso = _enCurso;
    if (enCurso != null) return enCurso;
    final nuevo = _ejecutar();
    _enCurso = nuevo;
    return nuevo;
  }

  /// Termina el borrado que haya quedado sin confirmar, o espera el que está
  /// corriendo. Si no hay ninguno, no hace nada.
  Future<void> runIfPending() async {
    if (inFlight || await hasPending()) await run();
  }

  Future<void> _ejecutar() async {
    try {
      await _marcar(true);
      try {
        await _borrarEnFcm();
      } catch (e) {
        // ignore: avoid_print
        print('[PUSH] No se pudo borrar el token en FCM; se reintenta en el próximo pedido de token: $e');
        return;
      }
      await _marcar(false);
      // ignore: avoid_print
      print('[PUSH] Token de este aparato borrado en FCM');
    } finally {
      _enCurso = null;
    }
  }

  Future<void> _marcar(bool pendiente) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pendiente) {
        await prefs.setBool(_kPendiente, true);
      } else {
        await prefs.remove(_kPendiente);
      }
    } catch (e) {
      // Sin la marca se pierde solo el reintento; el borrado sigue.
      // ignore: avoid_print
      print('[PUSH] No se pudo guardar la marca de borrado pendiente: $e');
    }
  }
}
