import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Identificador de la app en las dos tiendas. Es el mismo en Android e iOS.
const _bundleId = 'com.escalya.sabormanager';

/// Fichas de la app en cada tienda, para el botón "Actualizar".
const _playUrl =
    'https://play.google.com/store/apps/details?id=$_bundleId';
const _appStoreUrl = 'https://apps.apple.com/app/id6805690171';

/// Qué encontró el chequeo contra la tienda.
class StoreUpdateStatus {
  /// La tienda tiene una versión más nueva que la instalada.
  final bool updateAvailable;

  /// A dónde mandar al usuario para actualizar.
  final String? storeUrl;

  /// Versión publicada en la tienda ("1.1.8"), para decirla en el aviso. En iOS
  /// la da la App Store. En Android Play Core no la entrega como texto: sale de
  /// `ultima_version_android` en `app_config/manager_update` (si está anotada y
  /// es más nueva que la instalada; si no, null y el aviso no dice número).
  final String? storeVersion;

  final String currentVersion;

  const StoreUpdateStatus({
    required this.updateAvailable,
    required this.currentVersion,
    this.storeUrl,
    this.storeVersion,
  });

  /// Sin novedad: el caso al que se cae ante cualquier duda.
  factory StoreUpdateStatus.upToDate(String current) =>
      StoreUpdateStatus(updateAvailable: false, currentVersion: current);
}

/// Pregunta a Google Play y a la App Store si hay una versión más nueva.
///
/// Regla que gobierna todo el archivo: **ante la duda, no molestar**. El aviso
/// que dispara este servicio es bloqueante, así que un chequeo que falle no
/// puede dejar a un gerente sin sus reportes. Sin internet, con la tienda
/// caída, con la app instalada por APK en vez de por Play, o con una respuesta
/// que no se entiende, la respuesta siempre es "estás al día".
class StoreUpdateService {
  static final StoreUpdateService _instance = StoreUpdateService._internal();
  factory StoreUpdateService() => _instance;
  StoreUpdateService._internal();

  /// Cuánto esperar a la tienda antes de rendirse. Corto a propósito: es un
  /// chequeo de arranque y no puede demorar la app.
  static const _timeout = Duration(seconds: 6);

  String? _currentVersion;

  Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      return _currentVersion = info.version;
    } catch (_) {
      return _currentVersion = '';
    }
  }

  Future<StoreUpdateStatus> check() async {
    // Web queda fuera: no hay tienda a la que mandar a nadie, y el navegador
    // ya sirve siempre la última versión desplegada.
    if (kIsWeb) return StoreUpdateStatus.upToDate('');

    final current = await currentVersion();
    try {
      final config = await _config();
      if (!config.habilitado) {
        return StoreUpdateStatus.upToDate(current);
      }
      if (Platform.isAndroid) return await _checkPlay(current, versionAnotada: config.versionAndroid);
      if (Platform.isIOS) return await _checkAppStore(current);
    } catch (_) {
      // Cualquier fallo cae acá y se traduce en "no molestar".
    }
    return StoreUpdateStatus.upToDate(current);
  }

  /// Apagador de emergencia.
  ///
  /// El aviso es bloqueante, así que si alguna vez se dispara mal el usuario
  /// actualiza, vuelve y lo sigue viendo: un bucle del que no se sale, y que
  /// tampoco se arregla publicando otra versión porque nadie llegaría a
  /// instalarla. Poniendo `force_update_enabled: false` en
  /// `app_config/manager_update` todos quedan libres en el siguiente arranque,
  /// sin tocar código ni pasar por revisión de tienda.
  ///
  /// Si el documento no existe, o Firestore no responde, el aviso queda
  /// encendido: es el comportamiento pedido, y apagarlo ante cualquier fallo
  /// de red volvería inútil la función.
  ///
  /// El mismo documento trae `ultima_version_android` ("1.1.8"): el número que
  /// el aviso dice en Android, porque Play no lo da. Se anota al publicar en Play.
  Future<({bool habilitado, String? versionAndroid})> _config() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('manager_update')
          .get()
          .timeout(_timeout);
      if (!doc.exists) return (habilitado: true, versionAndroid: null);
      final data = doc.data();
      final v = data?['ultima_version_android'];
      return (
        habilitado: data?['force_update_enabled'] as bool? ?? true,
        versionAndroid: v is String && v.trim().isNotEmpty ? v.trim() : null,
      );
    } catch (_) {
      return (habilitado: true, versionAndroid: null);
    }
  }

  /// Android: Play Core.
  ///
  /// Solo responde si la app se instaló desde Play. En un APK cargado a mano
  /// (o en una tablet sin servicios de Google) lanza, y eso está bien: nadie
  /// que instaló por fuera de la tienda debería quedar bloqueado por ella.
  ///
  /// QUIÉN decide si hay versión nueva es Play (no el número anotado en
  /// Firestore): así nunca se bloquea a nadie con una versión que Play todavía no
  /// le ofrece (revisión, lanzamiento por etapas).
  Future<StoreUpdateStatus> _checkPlay(String current, {String? versionAnotada}) async {
    final info = await InAppUpdate.checkForUpdate().timeout(_timeout);
    final hay =
        info.updateAvailability == UpdateAvailability.updateAvailable;
    return StoreUpdateStatus(
      updateAvailable: hay,
      currentVersion: current,
      storeUrl: hay ? _playUrl : null,
      storeVersion: hay ? versionParaMostrar(current, versionAnotada) : null,
    );
  }

  /// El número anotado solo se dice si es más nuevo que el instalado: uno viejo
  /// (se olvidó cambiarlo al publicar) diría "Nueva versión" de algo que ya se tiene.
  @visibleForTesting
  static String? versionParaMostrar(String instalada, String? anotada) =>
      anotada != null && VersionComparator.isOlder(instalada, anotada) ? anotada : null;

  /// iOS: el lookup público de iTunes, que es la vía oficial y estable.
  Future<StoreUpdateStatus> _checkAppStore(String current) async {
    final uri = Uri.parse(
        'https://itunes.apple.com/lookup?bundleId=$_bundleId');

    final client = HttpClient()..connectionTimeout = _timeout;
    String cuerpo;
    try {
      final req = await client.getUrl(uri).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) return StoreUpdateStatus.upToDate(current);
      cuerpo = await res.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }

    final json = jsonDecode(cuerpo);
    final results = (json is Map) ? json['results'] : null;
    // Una app que todavía no salió a la venta devuelve la lista vacía. No es
    // un error: simplemente no hay contra qué comparar.
    if (results is! List || results.isEmpty) {
      return StoreUpdateStatus.upToDate(current);
    }

    final ficha = results.first;
    final storeVersion = (ficha is Map) ? ficha['version'] as String? : null;
    if (storeVersion == null) return StoreUpdateStatus.upToDate(current);

    final hay = VersionComparator.isOlder(current, storeVersion);
    return StoreUpdateStatus(
      updateAvailable: hay,
      currentVersion: current,
      storeVersion: storeVersion,
      // La ficha por id y SIN país: `trackViewUrl` trae la tienda de EE. UU.
      // ("/us/app/…") y el lookup sin país responde con la de EE. UU.; sin país,
      // la App Store abre la ficha en la tienda del teléfono (Guatemala, etc.).
      storeUrl: hay ? _appStoreUrl : null,
    );
  }
}

/// Compara versiones tipo "1.2.10".
class VersionComparator {
  /// ¿[instalada] es anterior a [tienda]?
  ///
  /// Se pregunta "más vieja", no "distinta", y la diferencia importa: quien
  /// prueba una build interna más nueva que la publicada tiene una versión
  /// distinta a la de la tienda, y tratarla como desactualizada lo dejaría
  /// encerrado para siempre — actualizar lo llevaría a una versión anterior a
  /// la que ya tiene, así que el aviso nunca desaparecería.
  static bool isOlder(String instalada, String tienda) {
    final a = _partes(instalada);
    final b = _partes(tienda);
    if (a.isEmpty || b.isEmpty) return false; // ilegible: no molestar

    final largo = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < largo; i++) {
      // "1.2" y "1.2.0" son la misma versión: lo que falta se lee como cero.
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }

  /// Parte el texto en números. Se queda con el tramo numérico inicial, así
  /// "1.2.0-beta.3" y "1.2.0 (build 4)" se leen como 1.2.0 en vez de romper.
  static List<int> _partes(String version) {
    final limpia = version.trim();
    if (limpia.isEmpty) return const [];
    final partes = <int>[];
    for (final tramo in limpia.split('.')) {
      final match = RegExp(r'^\d+').firstMatch(tramo.trim());
      if (match == null) break;
      partes.add(int.parse(match.group(0)!));
    }
    return partes;
  }
}
