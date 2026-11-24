/// El encabezado del teléfono: UNA sola línea con el logo, el nombre de la vista y
/// sus botones de acción (el selector de fecha, descargar...).
///
/// Antes eran dos: una barra con el negocio, la lupa y la foto de perfil, y debajo
/// el título de la vista. En un teléfono cada línea de más es inventario o ventas que
/// no se ven, así que quedó una. La cuenta vive en "Más" y la búsqueda también.
///
/// Sin providers ni Firebase: se prueba en
/// test/presentation/widgets/encabezado_movil_test.dart.
library;

import 'package:flutter/material.dart';

import 'barra_lateral.dart' show LogoManager;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

class EncabezadoMovil extends StatelessWidget {
  /// El nombre de la vista ("Inicio", "Despensa"...).
  final String titulo;

  /// Los botones de la derecha, en orden. Cada uno trae su tamaño.
  final List<Widget> acciones;

  const EncabezadoMovil({super.key, required this.titulo, this.acciones = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: _C.barra, border: Border(bottom: BorderSide(color: _C.barraLinea))),
      child: Row(
        children: [
          const LogoManager(lado: 34),
          const SizedBox(width: 10),
          Expanded(
            // Hasta dos líneas: "Compras vs Ventas" o "Cortesías y donaciones" no
            // caben en una con la fecha y el botón de descarga al lado.
            child: Semantics(
              header: true,
              child: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(18, FontWeight.w700, _C.barraTexto, height: 1.2)),
            ),
          ),
          for (final a in acciones) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}
