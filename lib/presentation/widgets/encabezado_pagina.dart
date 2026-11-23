/// El encabezado que el shell pone sobre cada pantalla (diseño `sidebar-manager.html`):
/// una línea chica con el grupo (o el saludo en Inicio), el título grande y, a la
/// derecha, las acciones (configurar avisos, descargar, el selector de fecha).
///
/// Sin providers ni Firebase: se prueba en test/presentation/widgets/
/// encabezado_pagina_test.dart.
library;

import 'package:flutter/material.dart';

import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

class EncabezadoPagina extends StatelessWidget {
  final String miga;
  final String titulo;

  /// Lo que va a la derecha, en orden.
  final List<Widget> acciones;

  const EncabezadoPagina({super.key, required this.miga, required this.titulo, this.acciones = const []});

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    final pad = telefono ? 16.0 : 28.0;
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(miga, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w500, _C.muted, height: 1.3)),
        Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(telefono ? 21 : 24, FontWeight.w700, _C.ink, height: 1.2)),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, telefono ? 14 : 16, pad, telefono ? 8 : 12),
      child: Row(
        children: [
          Expanded(child: texto),
          for (final a in acciones) ...[const SizedBox(width: 12), a],
        ],
      ),
    );
  }
}

/// Un botón del encabezado: ícono con o sin texto. En el teléfono solo el ícono.
class BotonEncabezado extends StatelessWidget {
  final IconData icono;
  final String ayuda;
  final String? texto;
  final VoidCallback onTap;

  const BotonEncabezado({super.key, required this.icono, required this.ayuda, required this.onTap, this.texto});

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    final conTexto = texto != null && !telefono;
    return Tooltip(
      message: ayuda,
      child: Semantics(
        button: true,
        label: ayuda,
        child: Material(
          color: _C.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: _C.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              width: conTexto ? null : 44,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: conTexto ? 14 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icono, size: 18, color: _C.muted),
                    if (conTexto) ...[const SizedBox(width: 8), Text(texto!, style: _t(14, FontWeight.w600, _C.ink))],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
