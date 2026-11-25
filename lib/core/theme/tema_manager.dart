/// Claro u oscuro en Sabor Manager.
///
/// POR DEFECTO ES OSCURO, aunque el teléfono esté en claro: así lo pidió el dueño
/// (2026-11-24; del 11-22 al 11-24 fue claro), siempre con la opción de pasar a claro
/// (en el menú de la cuenta). Lo que elige se guarda en el aparato y vuelve igual al
/// abrir la app: quien ya eligió claro sigue en claro.
///
/// CÓMO CAMBIA TODO A LA VEZ: los colores de las pantallas se leen de [paletaActual]
/// (no de `Theme.of(context)`), así que al cambiar de modo se pone la otra paleta y se
/// marca para reconstruir TODO el árbol: sin eso, lo que no escucha al tema se
/// quedaría con los colores viejos. La navegación y el estado de cada pantalla no se
/// pierden.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'paleta.dart';

class TemaManager extends ChangeNotifier {
  TemaManager._();

  /// El único. Es global a propósito: [paletaActual] también lo es.
  static final TemaManager instancia = TemaManager._();

  static const _llave = 'manager_tema';

  /// Lo que se puede elegir. Sin "automático": la decisión del dueño es oscuro por
  /// defecto, y claro si se pide.
  ThemeMode _modo = ThemeMode.dark;

  ThemeMode get modo => _modo;
  bool get oscuro => _modo == ThemeMode.dark;
  Paleta get paleta => oscuro ? Paleta.oscura : Paleta.clara;

  /// Lee la elección guardada. Se llama una vez, ANTES de pintar: si se leyera
  /// después, la app se vería un instante en oscuro y saltaría a claro.
  /// Nunca lanza: sin acceso al almacenamiento queda en oscuro.
  Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      _modo = p.getString(_llave) == 'claro' ? ThemeMode.light : ThemeMode.dark;
    } catch (_) {
      _modo = ThemeMode.dark;
    }
    paletaActual = paleta;
  }

  /// Cambia de modo, lo guarda y repinta todo.
  Future<void> poner(ThemeMode modo) async {
    final nuevo = modo == ThemeMode.light ? ThemeMode.light : ThemeMode.dark;
    if (nuevo == _modo) return;
    _modo = nuevo;
    paletaActual = paleta;
    notifyListeners();
    reconstruirTodo();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_llave, oscuro ? 'oscuro' : 'claro');
    } catch (_) {
      // No poder guardar no es grave: el modo vale hasta cerrar la app.
    }
  }

  /// Para las pruebas: pone el modo sin tocar el almacenamiento ni reconstruir.
  @visibleForTesting
  void ponerSinGuardar(ThemeMode modo) {
    _modo = modo == ThemeMode.light ? ThemeMode.light : ThemeMode.dark;
    paletaActual = paleta;
  }

  /// Marca para reconstruir cada elemento del árbol. Lo que se pinta con un color
  /// leído de [paletaActual] solo se entera si su widget se reconstruye.
  static void reconstruirTodo() {
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(marcar);
  }

  /// Los iconos de la barra de estado: oscuros sobre fondo claro y al revés.
  SystemUiOverlayStyle get barraDeEstado => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: oscuro ? Brightness.light : Brightness.dark,
        statusBarBrightness: oscuro ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: paleta.bg,
        systemNavigationBarIconBrightness: oscuro ? Brightness.light : Brightness.dark,
      );
}
