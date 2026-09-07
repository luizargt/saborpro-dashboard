import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../navigation/app_navigator.dart';
import 'auth_service.dart';

/// Handler de mensajes cuando la app está en segundo plano o cerrada.
///
/// Corre en un isolate propio, sin nada del árbol de widgets ni de los
/// singletons ya construidos, así que hay que inicializar Firebase de nuevo.
/// No hace falta mostrar nada: los mensajes que manda `processNotificationQueue`
/// traen bloque `notification`, y en background el sistema operativo los pinta
/// solo. Aquí únicamente se deja rastro para depurar.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // ignore: avoid_print
    print('[PUSH] Error inicializando Firebase en background: $e');
  }
  // ignore: avoid_print
  print('[PUSH] Mensaje en background: ${message.messageId} data=${message.data}');
}

/// Plataformas donde tiene sentido pedir un token FCM.
///
/// Windows y Linux no tienen FCM. Web sí lo tendría, pero exige un
/// `web/firebase-messaging-sw.js` y una VAPID key propias que Sabor Manager
/// todavía no tiene; sin eso `getToken()` lanza. Se deja apagado a propósito
/// para no ensuciar la consola del dashboard: cuando exista el service worker,
/// basta con devolver true en `kIsWeb` y pasarle la VAPID key a `getToken`.
///
/// macOS TAMPOCO está: el target de macOS no tiene la capability de push
/// (`macos/Runner/*.entitlements` no declara `aps-environment`), así que APNs
/// nunca entregaría un token, y `permission_handler` ni siquiera está en el
/// `GeneratedPluginRegistrant` de macOS, con lo que el botón "Abrir Ajustes"
/// del diálogo revienta con MissingPluginException. Declararlo soportado solo
/// servía para insistirle al usuario con algo que no puede funcionar. Vuelve a
/// la lista cuando el target macOS tenga la capability de Push Notifications.
bool get _isFCMSupported {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// Por qué terminó `ensurePermissionAndToken`.
///
/// Antes devolvía solo bool y la UI no podía distinguir "falta el permiso" de
/// "el permiso está dado pero `getToken()` falló" (en iOS el caso típico es
/// apns-token-not-set en el primer arranque). Con un bool se mandaba al usuario
/// a Ajustes a activar algo que ya estaba activado.
enum ResultadoPush {
  /// Permiso concedido y token guardado en `users/{uid}.manager_fcm_tokens`.
  ok,

  /// El usuario no dio el permiso. Es el ÚNICO caso en el que tiene sentido
  /// ofrecerle abrir los Ajustes del sistema.
  permisoDenegado,

  /// Hay permiso pero no se pudo obtener/guardar el token. No hay que molestar
  /// al usuario: el listener de `onTokenRefresh` lo guarda solo en cuanto FCM
  /// entregue uno.
  tokenFallido,

  /// Plataforma sin FCM (Windows, Linux, web, macOS).
  noSoportado,
}

/// Recepción de notificaciones push en Sabor Manager.
///
/// Sabor Manager solo RECIBE: quien encola y envía es la app POS junto con la
/// Cloud Function `processNotificationQueue`. Por eso aquí no hay nada de
/// `notification_queue` ni de armar destinatarios.
///
/// OJO — POR QUÉ HAY DOS CAMPOS DE TOKENS EN `users/{uid}` Y NO UNO
///
/// Sabor Manager guarda su token en `manager_fcm_tokens`. `fcm_tokens` es del
/// POS (Sabor Suite) y desde aquí no se escribe nunca, salvo la limpieza que
/// explica `saveFcmToken`. Los dos documentos son el MISMO: las dos apps
/// comparten Firestore y la colección `users`.
///
/// El motivo es la CAJA CIEGA. Los avisos de administración (cierre y apertura
/// de caja, gastos, inventario, stock bajo) llevan el descuadre y la venta
/// total del turno: números que el cajero no puede ver nunca, porque son el
/// control anti-fraude del negocio. Y el POS escribe el token DEL APARATO en
/// `fcm_tokens` en cada login por PIN, incluido el del administrador que entra
/// una sola vez a la tablet del mostrador para configurar algo. Su `logout()`
/// no borra ese token (la función para hacerlo existe, pero nadie la llama) y
/// el token de FCM se emite por INSTALACIÓN de app, no por usuario: no cambia
/// cuando entra otra persona. Resultado: esa tablet, con el cajero enfrente,
/// queda colgada del documento del administrador para siempre y recibiría cada
/// cierre de caja con su descuadre.
///
/// Filtrar por rol NO tapa eso, porque el filtro mira al USUARIO y el envío va
/// al DISPOSITIVO: el usuario sí es administrador, el aparato no es suyo. Lo
/// que lo tapa es que el POS jamás escribe en `manager_fcm_tokens`, así que en
/// ese array solo pueden caer aparatos donde alguien instaló Sabor Manager. No
/// depende de que nadie cierre sesión bien, y no hay que tocar el POS.
///
/// El filtro de administrador de las Cloud Functions sigue ahí, pero como
/// SEGUNDA capa, no como única defensa.
///
/// OJO — UN APARATO, UNA CUENTA (fuga ENTRE TENANTS medida en producción)
///
/// Separar los campos tapa la fuga POS → Sabor Manager, pero NO la fuga entre
/// dos cuentas de Sabor Manager. El token de FCM se emite por INSTALACIÓN de
/// app, no por persona: es el mismo antes y después de cambiar de usuario. Si
/// alguien entra con la cuenta A y luego con la B en el mismo teléfono sin que
/// el borrado al cerrar sesión llegue a ejecutarse, el token queda en las DOS
/// cuentas y ese aparato recibe los avisos de los DOS negocios.
///
/// No es hipotético: en producción se encontró el token que empieza por
/// `eBBQs7JwT7u4Zr` a la vez en "Administrador Demo" (tenant_1766782843192) y
/// en "Soporte SaborPro" (tenant_1773447631977). El dueño de un restaurante
/// estaba viendo los cierres de caja, los descuadres y los gastos del otro.
///
/// Por eso `saveFcmToken` desvincula el token de cualquier OTRA cuenta antes de
/// guardarlo. Ver `_desvincularTokenDeOtrasCuentas`, y sobre todo POR QUÉ el
/// borrado al cerrar sesión no alcanza.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  CollectionReference get _usersCollection => _firestore.collection('users');

  // Mismo id de canal que usa processNotificationQueue en el backend. Si aquí
  // se creara con otro id, las notificaciones que llegan en background caerían
  // en un canal que Android crea solo, con importancia baja y sin banner.
  static const String _avisosChannelId = 'avisos_channel';
  static const String _avisosChannelName = 'Avisos de Sabor Manager';
  static const String _avisosChannelDesc =
      'Aperturas y cierres de caja, gastos, inventario y stock bajo';

  // Guardas de idempotencia: initialize() se llama desde main() y también
  // podría llamarse tras un re-login. Sin esto se duplicarían los listeners y
  // cada push se mostraría dos veces.
  bool _initialized = false;
  bool _initializing = false;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// Par `uid|token` para el que la desvinculación de otras cuentas YA terminó
  /// bien en este proceso de la app. Vive solo en memoria a propósito: al
  /// reiniciar la app se vuelve a intentar, que es justo lo que hace falta si
  /// la última vez falló por falta de red.
  ///
  /// Existe porque `saveFcmToken` se llama varias veces por sesión (al entrar,
  /// en cada regreso a la app desde `_reintentarPush`, y en cada refresco de
  /// token) y no tiene sentido repetir la consulta cuando ya se sabe que ese
  /// token no está en ninguna otra cuenta. Se marca SOLO cuando la limpieza
  /// terminó sin errores: si falló, el siguiente intento la repite.
  String? _desvinculacionHecha;

  /// Si esta plataforma puede recibir push. En Windows, Linux y web no,
  /// así que la UI no debería ni ofrecer activar notificaciones.
  bool get isSupported => _isFCMSupported;

  // ==================== INICIALIZACIÓN ====================

  Future<void> initialize() async {
    if (!_isFCMSupported) {
      // ignore: avoid_print
      print('[PUSH] FCM no soportado en esta plataforma, no se inicializa nada');
      return;
    }
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      await _initializeLocalNotifications();

      // NO se piden permisos aquí: eso se hace en ensurePermissionAndToken,
      // que la app llama después del login (y en iOS/Android 13 el diálogo
      // debe salir con la sesión ya iniciada, no en el arranque en frío).
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      _onOpenedSub?.cancel();
      _onOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Si el token rota (reinstalación, restore de backup, limpieza de datos),
      // el viejo deja de servir y el nuevo hay que guardarlo solo: si no, el
      // usuario deja de recibir avisos hasta el siguiente login.
      _onTokenRefreshSub?.cancel();
      _onTokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
        final uid = AuthService().firestoreUid;
        if (uid == null) {
          // ignore: avoid_print
          print('[PUSH] Token renovado sin sesión activa, se guardará al iniciar sesión');
          return;
        }
        // ignore: avoid_print
        print('[PUSH] Token renovado, re-guardando para $uid');
        await saveFcmToken(uid, token);
      });

      // App abierta desde una notificación estando cerrada del todo.
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      _initialized = true;
      // ignore: avoid_print
      print('[PUSH] Servicio de notificaciones inicializado');
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] Error inicializando notificaciones: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Ícono monocromo dedicado: desde Android 5 la barra de estado pinta el
    // ícono como silueta, así que el launcher a color sale como un cuadrado
    // blanco. `ic_notification` es el drawable de una sola tinta.
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');

    // En iOS los permisos los pide firebase_messaging en
    // ensurePermissionAndToken; si también los pidiera este plugin saldrían
    // dos diálogos (o peor, el primero se comería la respuesta del segundo).
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    try {
      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    } catch (e) {
      // Si el drawable no llegara a estar en el APK, el plugin responde error y
      // esta llamada lanza; como initialize() del servicio registra los
      // listeners DESPUÉS, un ícono ausente dejaría a la app sin ningún aviso.
      // Un ícono feo es mejor que quedarse mudo.
      // ignore: avoid_print
      print('[PUSH] initialize falló con @drawable/ic_notification ($e); se reintenta con el ícono del launcher');
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: iosSettings,
          macOS: iosSettings,
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _createNotificationChannel();
    }
  }

  /// Crea el canal de Android. Crear el mismo canal dos veces es inofensivo
  /// (Android lo ignora), pero la importancia queda congelada al crearlo: si
  /// alguna vez hay que subirla, hay que estrenar id de canal.
  Future<void> _createNotificationChannel() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const canal = AndroidNotificationChannel(
      _avisosChannelId,
      _avisosChannelName,
      description: _avisosChannelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await androidPlugin.createNotificationChannel(canal);
    // ignore: avoid_print
    print('[PUSH] Canal $_avisosChannelId listo');
  }

  // ==================== PERMISOS Y TOKEN ====================

  /// Se llama en CADA inicio de sesión, no solo la primera vez: el usuario
  /// pudo reinstalar, cambiar de teléfono o revocar el permiso a mano, y el
  /// token guardado en Firestore ya no valdría.
  ///
  /// [pedirSiHaceFalta] decide si esta llamada puede sacar el diálogo NATIVO
  /// del sistema. Va en false cuando la llamada NO nace de que el usuario acabe
  /// de entrar (el reintento al volver a la app desde otra): Android muestra ese
  /// diálogo dos veces en toda la vida de la instalación y no más, así que
  /// gastar el segundo cuando el usuario regresa de WhatsApp —sin contexto de
  /// qué se le está pidiendo— deja el permiso denegado PARA SIEMPRE, recuperable
  /// solo desde los Ajustes del sistema. Con false esta función se limita a
  /// releer el estado y, si ya hay permiso, guardar el token.
  ///
  /// Devuelve [ResultadoPush.ok] solo si quedó con permiso Y con token guardado.
  Future<ResultadoPush> ensurePermissionAndToken(
    String uid, {
    bool pedirSiHaceFalta = true,
  }) async {
    if (!_isFCMSupported) return ResultadoPush.noSoportado;

    try {
      final settings = await _messaging.getNotificationSettings();
      var status = settings.authorizationStatus;
      // ignore: avoid_print
      print('[PUSH] Estado de permisos (pedirSiHaceFalta=$pedirSiHaceFalta): $status');

      if (!_concedido(status) && pedirSiHaceFalta) {
        // En Android getNotificationSettings NUNCA devuelve notDetermined: el
        // plugin manda 1 si POST_NOTIFICATIONS está concedido y 0 si no, y el
        // 0 se traduce a `denied`. O sea que en un Android recién instalado el
        // estado inicial ya llega como denied; si solo pidiéramos en
        // notDetermined, el diálogo del sistema no saldría JAMÁS y el usuario
        // vería nuestro diálogo casero de "Abrir Ajustes" sin haber rechazado
        // nada. Por eso en Android se pide siempre (es lo que hace la app POS).
        //
        // En iOS/macOS sí existe notDetermined y ahí la distinción importa:
        // tras un rechazo Apple no vuelve a mostrar el diálogo nativo nunca
        // más, la llamada devuelve denied al instante y el usuario no vería
        // nada — parecería que el botón está roto.
        final esAndroid = !kIsWeb && Platform.isAndroid;
        if (esAndroid || status == AuthorizationStatus.notDetermined) {
          final pedido = await _messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );
          status = pedido.authorizationStatus;
          // ignore: avoid_print
          print('[PUSH] Respuesta al diálogo de permisos: $status');
        }
      }

      if (!_concedido(status)) {
        // Sigue sin permiso. Si se llegó aquí con pedirSiHaceFalta en true, el
        // diálogo del sistema ya salió y se descartó (y en iOS Apple no lo
        // vuelve a mostrar), así que lo único que queda es que la UI insista con
        // un diálogo propio que abra los Ajustes. Con pedirSiHaceFalta en false
        // no se preguntó nada: el llamador (el reintento por ciclo de vida) se
        // limita a anotar que sigue faltando y NO debe mostrar nada.
        // ignore: avoid_print
        print('[PUSH] Sin permiso de notificaciones');
        return ResultadoPush.permisoDenegado;
      }

      final guardado = await _obtenerYGuardarToken(uid);
      return guardado ? ResultadoPush.ok : ResultadoPush.tokenFallido;
    } catch (e) {
      // Si lo que falló fue consultar/pedir el permiso no sabemos si está
      // denegado, así que se reporta como tokenFallido: mandar al usuario a
      // Ajustes por un error nuestro sería mentirle.
      // ignore: avoid_print
      print('[PUSH] Error asegurando permisos/token: $e');
      return ResultadoPush.tokenFallido;
    }
  }

  bool _concedido(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<bool> _obtenerYGuardarToken(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        // ignore: avoid_print
        print('[PUSH] getToken() no devolvió token para $uid');
        return false;
      }
      await saveFcmToken(uid, token);
      // ignore: avoid_print
      print('[PUSH] Token guardado para $uid: ${token.substring(0, 20)}...');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] Error obteniendo token FCM: $e');
      return false;
    }
  }

  /// Guarda el token en `users/{uid}.manager_fcm_tokens`, el array que leen las
  /// funciones de `notifications/`. arrayUnion evita duplicados por sí solo.
  ///
  /// En la MISMA escritura saca ese token de `fcm_tokens` (el array del POS).
  /// Es limpieza de la migración: las versiones anteriores de Sabor Manager
  /// guardaban ahí, y esos teléfonos de administrador seguirían colgados del
  /// campo del POS para siempre si nadie los quita. Va en el mismo `update` y
  /// no en una segunda llamada para que no exista un instante con el token en
  /// los dos arrays, ni un borrado que pueda fallar por su cuenta.
  ///
  /// Por qué esto NO puede borrar un token bueno del POS: el token de FCM se
  /// emite por INSTALACIÓN de app, y Sabor Suite (`com.escalya.saborsuite`) y
  /// Sabor Manager (`com.escalya.sabormanager`) son aplicaciones distintas. Aun
  /// instaladas en el mismo teléfono cada una tiene su token, son cadenas
  /// diferentes, y FCM no reutiliza un token entre instalaciones. Aquí se borra
  /// EXACTAMENTE el token que este aparato acaba de pedir, así que lo único que
  /// puede desaparecer de `fcm_tokens` es algo que escribió este mismo Sabor
  /// Manager. Si alguna vez esto deja de ser cierto (por ejemplo si las dos
  /// apps pasaran a compartir id de aplicación), hay que quitar el arrayRemove:
  /// dejar basura inofensiva es preferible a callar las notificaciones del POS.
  ///
  /// ANTES de guardar, desvincula el token de cualquier OTRA cuenta que lo
  /// tenga (`_desvincularTokenDeOtrasCuentas`). Ese orden es deliberado y está
  /// justificado allí: pase lo que pase entre los dos pasos, nunca queda un
  /// instante con el token colgado de dos tenants.
  Future<void> saveFcmToken(String uid, String token) async {
    // Primero desvincular de otras cuentas, después guardar en la propia.
    // Nunca lanza y nunca se queda colgada: si falla, se sigue igual y el
    // token del usuario actual se guarda de todos modos.
    await _desvincularTokenDeOtrasCuentas(uid, token);

    // Un solo mapa para las dos mutaciones. Si el doc no tuviera `fcm_tokens`,
    // el arrayRemove lo deja como array vacío: para quien lo lee es lo mismo
    // que no tenerlo.
    final datos = <String, dynamic>{
      'manager_fcm_tokens': FieldValue.arrayUnion([token]),
      'fcm_tokens': FieldValue.arrayRemove([token]),
    };
    try {
      await _usersCollection.doc(uid).update(datos);
    } on FirebaseException catch (e) {
      // update() falla si el doc no existe. No debería pasar (el uid ES el id
      // del doc con el que se hizo login), pero si pasa se cae a un set con
      // merge para no perder el token en silencio y quedarnos sin avisos.
      if (e.code == 'not-found') {
        try {
          await _usersCollection.doc(uid).set(datos, SetOptions(merge: true));
        } catch (e2) {
          // ignore: avoid_print
          print('[PUSH] Error guardando token con set/merge: $e2');
        }
        return;
      }
      // ignore: avoid_print
      print('[PUSH] Error guardando token FCM: $e');
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] Error guardando token FCM: $e');
    }
  }

  /// UN APARATO, UNA CUENTA: saca este token de CUALQUIER otro usuario que lo
  /// tenga, para que el teléfono reciba únicamente los avisos de la cuenta con
  /// la que se está usando ahora mismo.
  ///
  /// POR QUÉ EXISTE (no borrar pensando que es redundante)
  ///
  /// El token de FCM es por INSTALACIÓN de la app, no por persona: no cambia
  /// cuando entra otro usuario en el mismo teléfono. `removeCurrentDeviceToken`
  /// ya lo quita al cerrar sesión, pero eso NO alcanza, porque depende de dos
  /// cosas que fallan justo en el caso que importa:
  ///   1. que el usuario cierre sesión de verdad (casi nadie lo hace: se mata
  ///      la app, se desinstala, o se le pasa el teléfono a otro empleado), y
  ///   2. que haya red en ese momento — el borrado corta a los 2 segundos y se
  ///      traga el error a propósito, para no dejar colgado el botón.
  /// Si cualquiera de las dos falla, el token se queda en la cuenta vieja Y se
  /// agrega a la nueva.
  ///
  /// Medido en producción, no es hipotético: el token que empieza por
  /// `eBBQs7JwT7u4Zr` estaba a la vez en "Administrador Demo"
  /// (tenant_1766782843192) y en "Soporte SaborPro" (tenant_1773447631977). Ese
  /// teléfono recibía los cierres de caja, los descuadres y los gastos de los
  /// DOS negocios: una fuga entre tenants. Esta limpieza es la única defensa
  /// que NO depende de que nadie haga nada bien; el borrado al cerrar sesión
  /// queda como camino feliz.
  ///
  /// POR QUÉ VA ANTES DE GUARDAR Y NO DESPUÉS
  ///
  ///   - Dirección segura del fallo. Si el proceso muere, se pierde la red o el
  ///     usuario mata la app entre los dos pasos, el estado intermedio es "el
  ///     token no es de nadie" (el aparato se queda mudo un rato, y el próximo
  ///     arranque lo arregla), nunca "el token está en dos cuentas". Al revés,
  ///     el estado intermedio SERÍA la fuga que se está tapando.
  ///   - Se repara sola. El `arrayUnion` del usuario actual es la ÚLTIMA
  ///     escritura: aunque esta limpieza se equivocara de documento, lo que
  ///     borre de la cuenta propia vuelve a entrar acto seguido. Si corriera
  ///     después, el mismo error dejaría el teléfono callado para siempre, y un
  ///     teléfono callado no se queja: nadie reporta los avisos que no llegan.
  ///   - Menos ruido en la consulta: corriendo antes, el documento propio solo
  ///     aparece si ya tenía el token de una sesión anterior; corriendo después
  ///     aparecería SIEMPRE. En los dos casos se salta por ID (`doc.id == uid`)
  ///     y jamás por posición: pueden venir varios documentos y en cualquier
  ///     orden.
  ///
  /// POR QUÉ TAMBIÉN LIMPIA `fcm_tokens` DE ESOS DOCUMENTOS AJENOS
  ///
  /// Por lo mismo que ya hace `saveFcmToken` con el documento propio: Sabor
  /// Suite (`com.escalya.saborsuite`) y Sabor Manager (`com.escalya.sabormanager`)
  /// son apps distintas y FCM les da tokens distintos aun en el mismo teléfono,
  /// así que este token concreto solo pudo llegar a `fcm_tokens` escrito por una
  /// versión vieja de Sabor Manager, antes de estrenar el campo propio. Dejarlo
  /// ahí sería la misma fuga por la otra puerta: la cuenta vieja seguiría
  /// mandándole a este aparato los avisos que el POS manda a `fcm_tokens`.
  /// Borrarlo no puede callar a un aparato del POS de verdad. Si algún día las
  /// dos apps compartieran id de aplicación, hay que quitar `fcm_tokens` de
  /// este `update` (y del de `saveFcmToken`): basura inofensiva es mejor que un
  /// POS mudo.
  ///
  /// COSTO Y FRECUENCIA
  ///
  /// `array-contains` sobre un campo simple usa el índice automático de un solo
  /// campo: no hace falta índice compuesto, y no se agrega ningún segundo
  /// `where` ni `orderBy` que sí lo pediría. Los ~512 documentos de `users` no
  /// se recorren: Firestore cobra por documento DEVUELTO, o sea 1 lectura
  /// mínima por consulta. Por eso se corre en todos los guardados (login,
  /// regreso a la app y refresco de token) en vez de solo en el primero: así se
  /// reintenta sola si un día falló por falta de red, que es exactamente cuando
  /// el borrado al cerrar sesión también falla. El campo `_desvinculacionHecha`
  /// evita repetirla dentro del mismo proceso cuando ya salió bien.
  Future<void> _desvincularTokenDeOtrasCuentas(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) return;

    final clave = '$uid|$token';
    if (_desvinculacionHecha == clave) return;

    try {
      // Timeout obligatorio: sin servidor el future de un update() de Firestore
      // NUNCA resuelve, y esto corre ANTES de guardar el token propio; sin el
      // corte, quedarse sin red dejaría al usuario sin token guardado y sin
      // avisos. Al vencer se sigue de largo, pero las escrituras que ya se
      // encolaron salen solas cuando vuelva la red.
      await Future(() async {
        // Los dos campos donde este token pudo quedar pegado. `fcm_tokens` va
        // en la búsqueda para alcanzar también a la cuenta que nunca volvió a
        // entrar después de que Sabor Manager estrenara su campo propio: ahí el
        // token vive SOLO en el campo viejo y la consulta al campo nuevo no lo
        // encontraría.
        final ajenos = <String>{};
        // Sin red, get() NO lanza: resuelve con la caché, que además arranca
        // vacía porque la persistencia está apagada (firestore_service.dart).
        // Un vacío servido por caché significa "no pude preguntar", no "no hay
        // nadie", y darlo por bueno dejaría la fuga viva hasta el próximo
        // arranque con red. Por eso se anota si alguna consulta vino de caché.
        var huboCache = false;
        for (final campo in const ['manager_fcm_tokens', 'fcm_tokens']) {
          final resultado =
              await _usersCollection.where(campo, arrayContains: token).get();
          if (resultado.metadata.isFromCache) huboCache = true;
          for (final doc in resultado.docs) {
            // Saltar la cuenta propia por ID, nunca por posición: pueden venir
            // varios documentos (el caso real traía dos) y en cualquier orden.
            if (doc.id == uid) continue;
            ajenos.add(doc.id);
          }
        }

        if (ajenos.isEmpty) {
          // Solo se da por hecha si el servidor de verdad contestó.
          if (!huboCache) _desvinculacionHecha = clave;
          return;
        }

        // TODOS los documentos, no solo el primero: cuando esto aparece suele
        // haber más de una cuenta colgada del mismo teléfono.
        await Future.wait(ajenos.map((otroUid) {
          return _usersCollection.doc(otroUid).update({
            'manager_fcm_tokens': FieldValue.arrayRemove([token]),
            'fcm_tokens': FieldValue.arrayRemove([token]),
          });
        }));

        _desvinculacionHecha = clave;
        // ignore: avoid_print
        print('[PUSH] Token desvinculado de ${ajenos.length} cuenta(s) ajena(s): ${ajenos.join(", ")}');
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Nunca se relanza: esta limpieza es un extra y no puede impedir que se
      // guarde el token del usuario actual ni romper el inicio de sesión. Al no
      // marcar `_desvinculacionHecha`, el próximo guardado la vuelve a intentar.
      // ignore: avoid_print
      print('[PUSH] No se pudo desvincular el token de otras cuentas: $e');
    }
  }

  /// Quita el token de `manager_fcm_tokens` y SOLO de ahí: `fcm_tokens` es del
  /// POS y no le corresponde a esta app administrarlo (ver la cabecera de la
  /// clase). La única excepción es la limpieza puntual de `saveFcmToken`.
  Future<void> removeFcmToken(String uid, String token) async {
    try {
      await _usersCollection.doc(uid).update({
        'manager_fcm_tokens': FieldValue.arrayRemove([token]),
      });
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] Error eliminando token FCM: $e');
    }
  }

  /// Desvincula el token de ESTE dispositivo del usuario que cierra sesión.
  ///
  /// Hay que llamarla ANTES de `AuthService().logout()` y ESPERARLA, mientras el
  /// uid sigue vivo. Si no se llama, `users/{uid}.manager_fcm_tokens` conserva
  /// el token y el teléfono sigue recibiendo aperturas de caja, gastos e
  /// inventario de un tenant al que el usuario ya no pertenece.
  ///
  /// Por qué esperarla y no dispararla sin await: Firestore encola las
  /// escrituras POR USUARIO de Firebase Auth. Si el `signOut()` del logout gana
  /// la carrera, la mutación queda retenida en la cola del usuario anterior y no
  /// sale hasta que ESE usuario vuelva a iniciar sesión — o sea, justo cuando ya
  /// no hace falta borrarla. El timeout de abajo acota la espera.
  Future<void> removeCurrentDeviceToken(String uid) async {
    if (!_isFCMSupported) return;
    try {
      // Timeout obligatorio: sin servidor el future de un update() de Firestore
      // NUNCA resuelve, y sin esto el "Cerrar sesión" se quedaría colgado para
      // siempre. Son 2s y no 5 porque con red esto termina en milisegundos: los
      // segundos de más solo se los come el usuario sin red, mirando una
      // pantalla que no reacciona al botón que acaba de tocar. Perder el borrado
      // del token es mucho menos grave que eso.
      await Future(() async {
        final token = await _messaging.getToken();
        if (token == null || token.isEmpty) return;
        await removeFcmToken(uid, token);
      }).timeout(const Duration(seconds: 2));
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] No se pudo quitar el token al cerrar sesión: $e');
    }
  }

  // ==================== HANDLERS ====================

  /// Con la app en primer plano, FCM no pinta nada por su cuenta: hay que
  /// mostrar la notificación local a mano o el aviso se pierde.
  void _handleForegroundMessage(RemoteMessage message) {
    // ignore: avoid_print
    print('[PUSH] Mensaje en foreground: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    _showLocalNotification(
      title: notification.title ?? 'Sabor Manager',
      body: notification.body ?? '',
      data: message.data,
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _avisosChannelId,
      _avisosChannelName,
      channelDescription: _avisosChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    // Id acotado: notificationId de Android es int de 32 bits y el epoch en
    // milisegundos se pasa de rango.
    final id = DateTime.now().millisecondsSinceEpoch % 100000;

    try {
      await _localNotifications.show(
        id,
        title,
        body,
        details,
        payload: data?['type']?.toString(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] Error mostrando notificación local: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // ignore: avoid_print
    print('[PUSH] Notificación local tocada: ${response.payload}');
    solicitarPestanaAvisos();
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    // ignore: avoid_print
    print('[PUSH] App abierta desde notificación: ${message.data}');
    // Todos los avisos llevan al mismo lugar: la bandeja. Saltar directo al
    // gasto o al cierre concreto suena mejor de lo que es —hay que decidir qué
    // pantalla abre cada uno de los siete tipos, y varios no tienen pantalla
    // propia— y dejaría al usuario sin el contexto de qué más pasó mientras no
    // miraba, que es justo lo que la bandeja resuelve.
    solicitarPestanaAvisos();
  }
}
