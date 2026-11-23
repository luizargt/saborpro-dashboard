import 'package:flutter/foundation.dart';
import '../../core/services/firestore_service.dart';

/// De dónde se leen y dónde se guardan las preferencias. Existe para poder
/// probar el proveedor sin Firebase: en la app es siempre [_AlmacenFirestore].
abstract class AlmacenPreferenciasAvisos {
  /// El map `notification_preferences` del usuario (null si no tiene).
  Future<Map<String, dynamic>?> leer(String uid);

  /// Guarda UNA llave sin pisar las demás ni el resto del documento.
  Future<void> guardar(String uid, String llave, Object valor);
}

class _AlmacenFirestore implements AlmacenPreferenciasAvisos {
  final _firestore = FirestoreService();

  @override
  Future<Map<String, dynamic>?> leer(String uid) async {
    final doc = await _firestore.users.doc(uid).get();
    return doc.data()?['notification_preferences'] as Map<String, dynamic>?;
  }

  @override
  Future<void> guardar(String uid, String llave, Object valor) {
    // Dot-notation: escribe solo esa clave sin pisar el resto del map ni el
    // resto del documento del usuario.
    return _firestore.users.doc(uid).update({'notification_preferences.$llave': valor});
  }
}

/// "7:00 a. m.", "12:00 p. m.", "11:00 p. m.": la hora entera como se lee en la
/// pantalla de avisos.
String etiquetaDeHora(int hora) {
  final h = hora % 24;
  final sufijo = h < 12 ? 'a. m.' : 'p. m.';
  final en12 = h % 12 == 0 ? 12 : h % 12;
  return '$en12:00 $sufijo';
}

/// Preferencias de notificaciones push del usuario, guardadas en el map
/// `notification_preferences` de users/{uid}.
///
/// REGLA CRÍTICA — es opt-out, no opt-in: hoy ningún usuario tiene el campo
/// escrito, así que "ausente" tiene que significar ACTIVADO. Todo se evalúa con
/// `raw[k] != false`; usar `== true` dejaría a la base entera sin avisos.
///
/// Además de los interruptores, dos avisos diarios tienen una HORA elegible
/// (entero 0–23, hora de Guatemala): las ventas de ayer (7 por defecto) y el
/// resumen de stock bajo (8 por defecto). Las Cloud Functions corren cada hora y
/// le avisan a cada quien a la suya; una hora ausente o mal escrita vale la de
/// por defecto (mismas llaves y mismos valores que en
/// `functions/notifications/`).
class NotificationSettingsProvider extends ChangeNotifier {
  NotificationSettingsProvider({AlmacenPreferenciasAvisos? almacen})
      : _almacen = almacen ?? _AlmacenFirestore();

  final AlmacenPreferenciasAvisos _almacen;

  /// Las claves, en el orden en que se muestran en la pantalla de ajustes.
  static const List<String> keys = [
    'cash_open',
    'cash_close',
    'yesterday_sales',
    'courtesy',
    'cancellation',
    'expense',
    'inventory_movement',
    'low_stock_summary',
  ];

  /// La hora de cada aviso diario: llave del interruptor → llave de la hora.
  static const Map<String, String> horaDe = {
    'yesterday_sales': 'yesterday_sales_hour',
    'low_stock_summary': 'low_stock_summary_hour',
  };

  /// Las horas de siempre. Las mismas que usan las funciones del servidor.
  static const Map<String, int> horaPorDefecto = {
    'yesterday_sales_hour': 7,
    'low_stock_summary_hour': 8,
  };

  String? _uid;

  /// Arranca con todo en true, no vacío: mientras no se sepa lo contrario la
  /// regla es opt-out, así que ese es el estado honesto para pintar.
  final Map<String, bool> _values = {for (final k in keys) k: true};

  final Map<String, int> _horas = Map.of(horaPorDefecto);

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

  /// La hora (0–23) de un aviso diario; [llaveHora] es la de [horaDe].
  int hora(String llaveHora) => _horas[llaveHora] ?? horaPorDefecto[llaveHora] ?? 8;

  /// Solo vale un entero de 0 a 23: cualquier otra cosa es "no eligió", igual
  /// que en el servidor (`horaDePreferencia`).
  static int? _horaValida(Object? v) {
    if (v is! num) return null;
    final n = v.toInt();
    if (n != v || n < 0 || n > 23) return null;
    return n;
  }

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
      final raw = await _almacen.leer(uid).timeout(const Duration(seconds: 10));
      for (final k in keys) {
        // Ausente => true. Solo un false explícito apaga la notificación.
        _values[k] = raw?[k] != false;
      }
      for (final e in horaPorDefecto.entries) {
        _horas[e.key] = _horaValida(raw?[e.key]) ?? e.value;
      }
    } catch (e) {
      // Un error de red no puede dejar al usuario incomunicado: se cae del lado
      // seguro dejando todo encendido y las horas de siempre.
      for (final k in keys) {
        _values[k] = true;
      }
      _horas
        ..clear()
        ..addAll(horaPorDefecto);
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
      await _almacen.guardar(uid, key, v);
      return true;
    } catch (e) {
      _values[key] = previous;
      notifyListeners();
      debugPrint('[Notifs] Falló guardar $key=$v para $uid: $e');
      return false;
    }
  }

  /// Cambia la hora de un aviso diario, con las mismas garantías que
  /// [setValue]: optimista, y se revierte si no se pudo guardar. Una hora fuera
  /// de 0–23 no se guarda (devuelve false).
  Future<bool> setHora(String llaveHora, int nueva) async {
    if (!horaPorDefecto.containsKey(llaveHora) || nueva < 0 || nueva > 23) return false;
    final previa = hora(llaveHora);
    if (previa == nueva) return true;

    _horas[llaveHora] = nueva;
    notifyListeners();

    final uid = _uid;
    if (uid == null) {
      _horas[llaveHora] = previa;
      notifyListeners();
      debugPrint('[Notifs] No se pudo guardar $llaveHora=$nueva: el provider no tiene uid');
      return false;
    }

    try {
      await _almacen.guardar(uid, llaveHora, nueva);
      return true;
    } catch (e) {
      _horas[llaveHora] = previa;
      notifyListeners();
      debugPrint('[Notifs] Falló guardar $llaveHora=$nueva para $uid: $e');
      return false;
    }
  }
}
