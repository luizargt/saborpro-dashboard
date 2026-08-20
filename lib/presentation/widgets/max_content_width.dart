import 'package:flutter/material.dart';

/// Limita el ancho del contenido y lo centra.
///
/// En monitores anchos, dejar que todo se estire vuelve la lectura incómoda:
/// las barras cruzan la pantalla entera y el monto queda lejísimos de su
/// etiqueta. Un ancho máximo mantiene la relación entre columnas legible.
///
/// No aplica a vistas de tabla ancha (como Despensa), donde el espacio extra
/// sí se aprovecha para mostrar más columnas.
class MaxContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 1600,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
