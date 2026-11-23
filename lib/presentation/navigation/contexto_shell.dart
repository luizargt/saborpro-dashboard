/// Marca lo que está DENTRO del shell (la barra lateral o la barra inferior).
///
/// Los reportes y demás pantallas se abren de dos maneras: dentro del shell (desde la
/// navegación) o como una pantalla suelta que se empuja encima (desde un enlace,
/// por ejemplo "Ver ganancia real en Rentabilidad"). Dentro del shell el encabezado
/// (migas, título y fecha) lo pone el shell; suelta, cada pantalla trae el suyo con su
/// flecha de regresar. Esto es lo que le dice a cada pantalla en cuál está.
library;

import 'package:flutter/widgets.dart';

class ContextoShell extends InheritedWidget {
  const ContextoShell({super.key, required super.child});

  /// ¿Esta pantalla está dentro del shell? Sin escuchar: nunca cambia mientras vive.
  static bool enShell(BuildContext context) => context.getInheritedWidgetOfExactType<ContextoShell>() != null;

  @override
  bool updateShouldNotify(ContextoShell oldWidget) => false;
}
