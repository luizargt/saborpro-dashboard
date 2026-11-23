/// Lo que se puede descargar en Excel y el estado de cada descarga (la que está en
/// curso y las que ya salieron). La lógica de CÓMO se genera cada archivo vive en el
/// shell (usa los providers); aquí solo está lo que se ve y se puede probar.
library;

import 'package:flutter/material.dart';

/// Un reporte descargable.
class ItemDescarga {
  final String id;
  final IconData icono;
  final String nombre;
  final String descripcion;

  const ItemDescarga(this.id, this.icono, this.nombre, this.descripcion);
}

class DescargasController extends ChangeNotifier {
  DescargasController({required this.items, required Future<void> Function(ItemDescarga) ejecutar}) : _ejecutar = ejecutar;

  final List<ItemDescarga> items;
  final Future<void> Function(ItemDescarga) _ejecutar;

  final _hechas = <String>{};
  String? _descargando;
  String? _error;
  bool _vivo = true;

  /// Los que ya salieron con lo que está elegido (mes y sucursal).
  Set<String> get hechas => Set.unmodifiable(_hechas);

  /// El que se está generando ahora; null si ninguno.
  String? get descargando => _descargando;

  /// El mensaje del último intento que falló.
  String? get error => _error;

  bool get ocupado => _descargando != null;

  /// Genera uno. Una descarga a la vez: un segundo toque mientras se genera no hace
  /// nada (generar el mismo Excel dos veces juntas solo duplica lecturas).
  Future<void> descargar(ItemDescarga item) async {
    if (_descargando != null) return;
    _descargando = item.id;
    _error = null;
    _avisar();
    try {
      await _ejecutar(item);
      _hechas.add(item.id);
    } catch (e) {
      _error = 'No se pudo generar "${item.nombre}". Intenta de nuevo.';
      debugPrint('[DESCARGAS] ${item.id}: $e');
    } finally {
      _descargando = null;
      _avisar();
    }
  }

  /// Cambió el mes o la sucursal: lo que ya salió era de otro período y deja de
  /// marcarse "Listo".
  void reiniciar() {
    if (_hechas.isEmpty && _error == null) return;
    _hechas.clear();
    _error = null;
    _avisar();
  }

  void _avisar() {
    if (_vivo) notifyListeners();
  }

  @override
  void dispose() {
    _vivo = false;
    super.dispose();
  }
}
