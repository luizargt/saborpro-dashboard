import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/auth_service.dart';
import '../../data/models/menu_margin_data.dart';

/// De dónde salen el menú, las recetas y los ingredientes. Existe para poder
/// probar el provider sin Firebase.
abstract class FuenteMenu {
  Future<MenuDescargado> descargar(String tenantId);
}

class FuenteMenuFirestore implements FuenteMenu {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Tope para toda la descarga. Sin red, una consulta puede quedarse
  /// esperando indefinidamente; mejor decir "sin conexión" que girar para
  /// siempre. Holgado a propósito: un menú grande en una red lenta no debe
  /// confundirse con "sin conexión".
  static const _tope = Duration(seconds: 30);

  /// Siempre al servidor. Sin red, `.get()` normal devuelve un resultado VACÍO
  /// de la caché sin lanzar nada, y el reporte diría "no hay platillos" en vez
  /// de "no hay conexión".
  static const _servidor = GetOptions(source: Source.server);

  @override
  Future<MenuDescargado> descargar(String tenantId) =>
      _descargar(tenantId).timeout(_tope);

  Future<MenuDescargado> _descargar(String tenantId) async {
    List<DocCrudo> docs(QuerySnapshot<Map<String, dynamic>> s) =>
        [for (final d in s.docs) DocCrudo(d.id, d.data())];

    // El campo del negocio no se llama igual en todas las colecciones
    // (`tenant_id` casi siempre, `tenantId` en recetas): es como los escribe
    // el POS, no algo que se pueda unificar desde aquí.
    Future<List<DocCrudo>> porNegocio(String coleccion, String campo) async =>
        docs(await _db
            .collection(coleccion)
            .where(campo, isEqualTo: tenantId)
            .get(_servidor));

    final r = await Future.wait([
      porNegocio('products', 'tenant_id'),
      porNegocio('recipeItems', 'tenantId'),
      porNegocio('ingredients', 'tenant_id'),
      porNegocio('presentation_locations', 'tenant_id'),
      porNegocio('locations', 'tenant_id'),
    ]);
    final sucursales = r[4];

    // `productLocations` no guarda el negocio: se consulta por sucursal, de a
    // 30 (el máximo de `whereIn`), las tandas en paralelo.
    final ids = [for (final s in sucursales) s.id];
    final tandas = await Future.wait([
      for (var i = 0; i < ids.length; i += 30)
        _db
            .collection('productLocations')
            .where('location_id',
                whereIn: ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30))
            .get(_servidor),
    ]);
    final disponibilidad = [for (final t in tandas) ...docs(t)];

    return MenuDescargado(
      productos: r[0],
      recetas: r[1],
      ingredientes: r[2],
      preciosSucursal: r[3],
      sucursales: sucursales,
      disponibilidad: disponibilidad,
    );
  }
}

/// Costo de receta de cada platillo del menú.
///
/// Baja todo UNA vez por negocio. Cambiar de sucursal no vuelve a pedir nada:
/// se recalcula en memoria. Tampoco depende del período: el reparto de gastos
/// lo pone quien lo muestra, con los números de Rentabilidad.
class MenuMarginProvider extends ChangeNotifier {
  MenuMarginProvider({
    FuenteMenu? fuente,
    Set<String> Function()? sucursalesPermitidas,
  })  : _fuente = fuente ?? FuenteMenuFirestore(),
        _permitidas = sucursalesPermitidas ??
            (() => AuthService().assignedLocationIds.toSet());

  final FuenteMenu _fuente;

  /// Vacío = todas. Es la misma lista con que el dashboard limita lo que ve un
  /// usuario con sucursales asignadas.
  final Set<String> Function() _permitidas;

  String? _tenant;
  MenuCrudo? _menu;
  String? _error;
  bool _cargando = false;
  bool _vivo = true;

  /// Cada descarga lleva un número. Si llega una respuesta de una descarga
  /// anterior (otro negocio, o una recarga ya reemplazada), se tira.
  int _generacion = 0;
  Future<void>? _enCurso;

  final _memo = <String, List<MargenPlatillo>>{};

  bool get cargando => _cargando;

  /// Ya hay un menú que mostrar (aunque se esté actualizando).
  bool get listo => _menu != null;

  /// Se está actualizando un menú que ya se muestra: la pantalla debe dejar
  /// la lista a la vista en vez de cambiarla por un spinner.
  bool get refrescando => _cargando && _menu != null;
  String? get error => _error;
  int get descartados => _menu?.descartados ?? 0;

  /// El costo de cada platillo en la sucursal. Null mientras no hay menú.
  List<MargenPlatillo>? platillosPara(String? sucursalId) {
    final menu = _menu;
    if (menu == null) return null;
    final permitidas = _permitidas();
    final clave = '${sucursalId ?? "*"}|${(permitidas.toList()..sort()).join(",")}';
    return _memo[clave] ??= calcularMargenes(
      menu,
      sucursalId: sucursalId,
      sucursalesPermitidas: permitidas,
    );
  }

  /// Descarga si todavía no hay menú de este negocio. Barata de llamar en cada
  /// reconstrucción: tras un fallo no reintenta sola (se reintenta con
  /// [recargar]), así que no puede entrar en bucle.
  Future<void> cargarSiHaceFalta(String tenantId) {
    if (!_vivo) return Future.value();
    if (_tenant == tenantId && (_menu != null || _cargando || _error != null)) {
      return _enCurso ?? Future.value();
    }
    return _descargar(tenantId);
  }

  /// "Deslizar para actualizar" o "Reintentar". Deja el menú anterior a la
  /// vista mientras llega el nuevo.
  Future<void> recargar() {
    final tenant = _tenant;
    // Tras salir de la pantalla (p. ej. a media actualización) no hay a quién
    // mostrarle nada: no se baja el menú entero para nadie.
    if (tenant == null || !_vivo) return Future.value();
    return _descargar(tenant);
  }

  Future<void> _descargar(String tenantId) {
    if (_tenant != tenantId) {
      // Otro negocio: lo que hay en memoria no le corresponde.
      _menu = null;
      _memo.clear();
    }
    _tenant = tenantId;
    _error = null;
    _cargando = true;
    final generacion = ++_generacion;
    _avisar();

    final f = _traer(tenantId, generacion);
    _enCurso = f;
    return f;
  }

  Future<void> _traer(String tenantId, int generacion) async {
    try {
      final crudo = await _fuente.descargar(tenantId);
      if (!_vivo || generacion != _generacion) return;
      _menu = interpretarMenu(crudo);
      _memo.clear();
      _error = null;
    } catch (e, stack) {
      if (!_vivo || generacion != _generacion) return;
      _error = mensajeDeError(e);
      debugPrint('[UTILIDAD PLATILLOS] $e\n$stack');
    } finally {
      if (_vivo && generacion == _generacion) {
        _cargando = false;
        _enCurso = null;
        _avisar();
      }
    }
  }

  void _avisar() {
    if (_vivo) notifyListeners();
  }

  @override
  void dispose() {
    // Sin esto, salir de la pantalla con la descarga en vuelo avisaba a un
    // provider ya liberado.
    _vivo = false;
    super.dispose();
  }
}

/// Un error que el dueño pueda entender y sobre el que pueda hacer algo.
@visibleForTesting
String mensajeDeError(Object e) {
  if (e is TimeoutException ||
      (e is FirebaseException && e.code == 'unavailable')) {
    return 'Sin conexión con el servidor. Revisá tu internet y volvé a '
        'intentar.';
  }
  if (e is FirebaseException && e.code == 'permission-denied') {
    return 'Tu usuario no tiene permiso para leer el menú.';
  }
  // El detalle técnico va al final, como en Rentabilidad: en web la consola no
  // siempre está a mano y soporte lo necesita.
  return 'No se pudo cargar el menú. Volvé a intentar; si sigue, avisá a '
      'soporte.\n\n$e';
}
