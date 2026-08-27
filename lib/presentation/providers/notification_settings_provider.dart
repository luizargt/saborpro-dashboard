import 'package:flutter/foundation.dart';
import '../../core/services/firestore_service.dart';

/// Preferencias de notificaciones push del usuario, guardadas en el map
/// `notification_preferences` de users/{uid}.
///
/// REGLA CRÍTICA — es opt-out, no opt-in: hoy ningún usuario tiene el campo
/// escrito, así que "ausente" tiene que significar ACTIVADO. Todo se evalúa con
/// `raw[k] != false`; usar `== true` dejaría a la base entera sin avisos.
class NotificationSettingsProvider extends ChangeNotifier {
  final _firestore = FirestoreService();

  /// Las 5 claves, en el orden en que se muestran en la pantalla de ajustes.
  static const List<String> keys = [
    'cash_open',
    'cash_close',
    'expense',
    'inventory_movement',
    'low_stock_summary',
  ];

  String? _uid;

  /// Arranca con las 5 en true, no vacío: mientras no se sepa lo contrario la
  /// regla es opt-out, así que ese es el estado honesto para pintar.
  final Map<String, bool> _values = {for (final k in keys) k: true};

  /// NO arranca en true. Antes sí, y solo `init()` lo apagaba: si nadie llamaba
  /// a init() —lo que pasa cuando AppShell sale temprano porque `firestoreUid`
  /// es null— la pantalla de ajustes se quedaba girando para siempre. Ahora
  /// `loading` significa literalmente "hay una lectura en curso", que es lo
  /// único que justifica tapar la UI con un spinner.
  bool _loading = false;

  /// Si ya se leyó (o se intentó leer) Firestore para algún uid. La pantalla lo
  /// usa para inicializarse sola cuando el shell no pudo hacerlo.
  bool _initialized = false;

  bool get loading => _loading;
  bool get initialized => _initialized;

  /// Valor actual de una preferencia. Si no está cargada todavía o la clave no
  /// existe, se asume activada (misma regla opt-out que en el backend).
  bool value(String key) => _values[key] ?? true;

  Future<void> init(String uid) async {
    // AppShell y la pantalla de ajustes pueden pedir la carga casi a la vez
    // (entrar a Notificaciones justo después de iniciar sesión). Sin este
    // guardia se dispararían dos lecturas del mismo documento.
    if (_loading && _uid == uid) return;

    _uid = uid;
    _loading = true;
    notifyListeners();

    try {
      // Timeout obligatorio: sin servidor y sin caché, el get() de Firestore
      // puede no resolver nunca, y eso volvería a dejar el spinner eterno por
      // otro camino. Vencido el plazo se cae al lado seguro (todo encendido).
      final doc = await _firestore.users
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final raw = doc.data()?['notification_preferences'] as Map<String, dynamic>?;
      for (final k in keys) {
        // Ausente => true. Solo un false explícito apaga la notificación.
        _values[k] = raw?[k] != false;
      }
    } catch (e) {
      // Un error de red no puede dejar al usuario incomunicado: se cae del lado
      // seguro dejando todo encendido.
      for (final k in keys) {
        _values[k] = true;
      }
      debugPrint('[Notifs] No se pudieron leer las preferencias de $uid: $e');
    } finally {
      // En finally y no al final del try: pase lo que pase el spinner se apaga.
      _loading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  /// Cambia una preferencia de forma optimista (el Switch responde al instante)
  /// y luego la persiste. Si no se pudo guardar, revierte el valor.
  ///
  /// Devuelve true solo si la escritura quedó encargada a Firestore. La pantalla
  /// usa el false para avisar: revertir el switch sin decir nada deja al usuario
  /// pensando que el toque no le registró.
  ///
  /// Ojo con el "encargada": sin conexión el future del update no resuelve
  /// (Firestore lo encola en local y lo manda al reconectar), así que esta
  /// llamada se queda esperando. Es correcto y NO lleva timeout a propósito:
  /// vencerlo revertiría un cambio que sí va a aplicarse, y ahí sí mentiríamos.
  Future<bool> setValue(String key, bool v) async {
    final previous = value(key);
    if (previous == v) return true;

    _values[key] = v;
    notifyListeners();

    final uid = _uid;
    if (uid == null) {
      // Sin uid no hay documento que actualizar. Antes se salía aquí dejando el
      // valor optimista puesto: el usuario apagaba un aviso, lo veía apagado y
      // no se guardaba nada ni se le decía. Pasa de verdad cuando esta pantalla
      // se abre antes de que el shell llame a init() y `firestoreUid` es null.
      _values[key] = previous;
      notifyListeners();
      debugPrint('[Notifs] No se pudo guardar $key=$v: el provider no tiene uid');
      return false;
    }

    try {
      // Dot-notation: escribe solo esa clave sin pisar el resto del map ni el
      // resto del documento del usuario.
      await _firestore.users.doc(uid).update({'notification_preferences.$key': v});
      return true;
    } catch (e) {
      _values[key] = previous;
      notifyListeners();
      debugPrint('[Notifs] Falló guardar $key=$v para $uid: $e');
      return false;
    }
  }
}
