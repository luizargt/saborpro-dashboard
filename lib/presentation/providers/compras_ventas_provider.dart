import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/date_range.dart';
import '../../data/models/compras_ventas.dart';

/// Un documento leído: su id y sus campos.
typedef DocLeido = ({String id, Map<String, dynamic> datos});

/// De dónde salen las fotos de la bodega, los ingredientes y sus categorías.
/// Existe para poder probar el provider sin Firebase.
abstract class FuenteComprasVentas {
  /// Las fotos de `inventorySnapshots` de esas fechas ("2026-10-01").
  Future<List<Map<String, dynamic>>> leerFotos(String tenantId, List<String> fechas);
  Future<List<DocLeido>> leerIngredientes(String tenantId);
  Future<List<DocLeido>> leerCategorias(String tenantId);

  /// Las sucursales del negocio (todas, también las que no se ven): de ahí se sabe
  /// cuál es la bodega central.
  Future<List<DocLeido>> leerSucursales(String tenantId);
}

class FuenteComprasVentasFirestore implements FuenteComprasVentas {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Sin red, una consulta puede quedarse esperando para siempre: mejor decir que
  /// no se pudo que girar sin fin. Holgado a propósito.
  static const _tope = Duration(seconds: 30);

  @override
  Future<List<Map<String, dynamic>>> leerFotos(String tenantId, List<String> fechas) async {
    if (fechas.isEmpty) return const [];
    final snap = await _db
        .collection('inventorySnapshots')
        .where('tenant_id', isEqualTo: tenantId)
        .where('fecha', whereIn: fechas)
        .get()
        .timeout(_tope);
    return [for (final d in snap.docs) d.data()];
  }

  @override
  Future<List<DocLeido>> leerIngredientes(String tenantId) async {
    final snap = await _db.collection('ingredients').where('tenant_id', isEqualTo: tenantId).get().timeout(_tope);
    return [for (final d in snap.docs) (id: d.id, datos: d.data())];
  }

  @override
  Future<List<DocLeido>> leerCategorias(String tenantId) async {
    final snap = await _db.collection('ingredientCategories').where('tenant_id', isEqualTo: tenantId).get().timeout(_tope);
    return [for (final d in snap.docs) (id: d.id, datos: d.data())];
  }

  @override
  Future<List<DocLeido>> leerSucursales(String tenantId) async {
    final snap = await _db.collection('locations').where('tenant_id', isEqualTo: tenantId).get().timeout(_tope);
    return [for (final d in snap.docs) (id: d.id, datos: d.data())];
  }
}

/// Lo que "Compras vs Ventas" necesita además de los números de Rentabilidad: las
/// fotos de la bodega del inicio y del fin del mes, la bodega de hoy y la categoría
/// de cada ingrediente.
///
/// Un fallo al leer las fotos NO tumba el reporte: lo demás se calcula igual y la
/// pantalla dice que falta saber la bodega.
class ComprasVentasProvider extends ChangeNotifier {
  ComprasVentasProvider({FuenteComprasVentas? fuente}) : _fuente = fuente ?? FuenteComprasVentasFirestore();

  final FuenteComprasVentas _fuente;

  FotoBodega? _inicio;
  FotoBodega? _fin;
  FotoBodega? _vivo;
  Map<String, String> _categoriaDeIngrediente = const {};
  bool _cargando = false;
  bool _vivoLeido = false;
  bool _fotosLeidas = false;
  bool _fotosFallaron = false;
  String? _clave;
  String? _tenant;
  DateRange? _rango;
  bool _activo = true;

  /// Cada carga lleva un número: la respuesta de una carga vieja se tira.
  int _generacion = 0;

  /// La foto del primer día del mes (el "Tenías"); null si no hay.
  FotoBodega? get inicio => _inicio;

  /// La foto del primer día del mes siguiente (el "Te queda" de un mes cerrado).
  FotoBodega? get fin => _fin;

  /// La bodega de hoy; null mientras no se lee, o si falló.
  FotoBodega? get vivo => _vivo;

  /// id de ingrediente → nombre de su categoría.
  Map<String, String> get categoriaDeIngrediente => _categoriaDeIngrediente;

  bool get cargando => _cargando;

  /// Ya se intentó leer la bodega de hoy (con o sin éxito).
  bool get vivoLeido => _vivoLeido;

  /// Ya se intentó leer las fotos (con o sin éxito). Distingue "no hay foto" de
  /// "todavía no se ha leído".
  bool get fotosLeidas => _fotosLeidas;

  /// La lectura de las fotos falló (sin red, sin permiso, tardó demasiado): no es
  /// lo mismo que "todavía no hay foto de ese mes", y la pantalla lo dice.
  bool get fotosFallaron => _fotosFallaron;

  /// "Tenías" y "Te queda" solo existen con un mes elegido: las fotos son del día 1.
  static bool aplica(DateRange r) => r.mode == PeriodMode.month;

  /// Las dos fechas de foto de un mes: el día 1 y el día 1 del mes siguiente.
  @visibleForTesting
  static List<String> fechasDeFoto(DateRange r) {
    if (!aplica(r)) return const [];
    final a = DateTime(r.start.year, r.start.month, 1);
    final b = DateTime(r.start.year, r.start.month + 1, 1);
    return [llaveDeDia(a), llaveDeDia(b)];
  }

  /// Lee si cambió el negocio o el mes; si no, no hace nada (barato de llamar en
  /// cada reconstrucción, y tras un fallo no reintenta sola: eso es [recargar]).
  Future<void> cargarSiHaceFalta(String tenantId, DateRange rango) {
    final clave = '$tenantId|${fechasDeFoto(rango).join(',')}|${aplica(rango)}';
    if (clave == _clave) return Future.value();
    return _cargar(tenantId, rango, clave);
  }

  /// "Deslizar para actualizar": vuelve a leer todo.
  Future<void> recargar() {
    final t = _tenant;
    final r = _rango;
    if (t == null || r == null || !_activo) return Future.value();
    final clave = '$t|${fechasDeFoto(r).join(',')}|${aplica(r)}';
    return _cargar(t, r, clave);
  }

  Future<void> _cargar(String tenantId, DateRange rango, String clave) async {
    final generacion = ++_generacion;
    _clave = clave;
    if (_tenant != tenantId) {
      // Otro negocio: lo que había no le corresponde.
      _vivo = null;
      _vivoLeido = false;
      _categoriaDeIngrediente = const {};
    }
    _tenant = tenantId;
    _rango = rango;
    _inicio = null;
    _fin = null;
    _fotosLeidas = false;
    _fotosFallaron = false;
    _cargando = true;
    _avisar();

    final fechas = fechasDeFoto(rango);

    // Las tres lecturas son independientes y ninguna debe tumbar a las otras.
    Future<T?> seguro<T>(Future<T> f) async {
      try {
        return await f;
      } catch (e, st) {
        debugPrint('[COMPRAS VS VENTAS] $e\n$st');
        return null;
      }
    }

    final r = await Future.wait<Object?>([
      seguro(_fuente.leerFotos(tenantId, fechas)),
      seguro(_fuente.leerIngredientes(tenantId)),
      seguro(_fuente.leerCategorias(tenantId)),
      seguro(_fuente.leerSucursales(tenantId)),
    ]);
    if (!_activo || generacion != _generacion) return;

    final fotos = r[0] as List<Map<String, dynamic>>?;
    final ingredientes = r[1] as List<DocLeido>?;
    final categorias = r[2] as List<DocLeido>?;
    final sucursales = r[3] as List<DocLeido>?;

    if (fotos != null) {
      for (final f in fotos) {
        final foto = FotoBodega.desde(f);
        if (foto == null) continue;
        if (fechas.isNotEmpty && foto.fecha == fechas[0]) _inicio = foto;
        if (fechas.length > 1 && foto.fecha == fechas[1]) _fin = foto;
      }
    }
    // "Leídas" es que ya se intentó, salga como salga: si falló, la pantalla lo dice
    // en vez de quedarse esperando para siempre.
    _fotosLeidas = true;
    _fotosFallaron = fotos == null;

    if (ingredientes != null) {
      final nombreDeCategoria = <String, String>{};
      for (final c in categorias ?? const <DocLeido>[]) {
        final n = c.datos['name'];
        if (n is String && n.trim().isNotEmpty) nombreDeCategoria[c.id] = n.trim();
      }
      final vivos = <IngredienteVivo>[];
      final catDe = <String, String>{};
      for (final d in ingredientes) {
        final i = IngredienteVivo.desde(d.id, d.datos);
        if (i == null) continue;
        vivos.add(i);
        final n = nombreDeCategoria[i.categoriaId];
        if (n != null) catDe[i.id] = n;
      }
      _categoriaDeIngrediente = catDe;
      // La bodega central no vende: la foto del servidor la marca, y la de hoy
      // también, o "Tenías" (sin ella) y "Te queda hoy" (con ella) no se podrían
      // comparar.
      final centrales = <String, bool>{
        for (final l in sucursales ?? const <DocLeido>[]) l.id: l.datos['is_central_warehouse'] == true,
      };
      _vivo = valorarBodega(
        ingredientes: vivos,
        nombreDeCategoria: nombreDeCategoria,
        centrales: centrales,
        hoy: DateTime.now(),
      );
    }
    _vivoLeido = true;

    _cargando = false;
    _avisar();
  }

  void _avisar() {
    if (_activo) notifyListeners();
  }

  @override
  void dispose() {
    _activo = false;
    super.dispose();
  }
}
