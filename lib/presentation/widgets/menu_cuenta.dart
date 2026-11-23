/// El menú de la cuenta: en pantalla ancha es un panel que sale sobre el nombre (abajo
/// de la barra lateral); en el teléfono es la hoja "Más". Diseño `sidebar-manager.html`.
///
/// Sin providers ni Firebase. Lo que el diseño no traía pero la app ya tenía
/// (apariencia, biometría, moneda y tipo de cambio) entra por [extras].
library;

import 'package:flutter/material.dart';

import '../navigation/destinos.dart';
import 'barra_lateral.dart' show AvatarManager, inicialDe, textoSucursales;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Una fila "ícono + nombre" que se toca.
class FilaMenu extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool actual;
  final bool peligro;
  final String? sub;

  /// En la hoja del teléfono las filas son más grandes y llevan flecha.
  final bool grande;

  const FilaMenu({
    super.key,
    required this.icono,
    required this.texto,
    required this.onTap,
    this.actual = false,
    this.peligro = false,
    this.sub,
    this.grande = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = peligro ? _C.bad : _C.ink;
    if (grande) {
      return Material(
        color: actual ? _C.tint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: peligro ? _C.badTint : _C.subtle, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icono, size: 19, color: peligro ? _C.bad : _C.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, color, height: 1.3)),
                        if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted, height: 1.3)),
                      ],
                    ),
                  ),
                  if (!peligro) Icon(Icons.chevron_right_rounded, size: 18, color: _C.soft),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: actual ? _C.subtle : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: _C.subtle,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(icono, size: 18, color: peligro ? _C.bad : _C.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w500, color))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El panel que sale sobre el nombre en la barra lateral.
class PanelCuenta extends StatelessWidget {
  final String nombre;
  final String rol;
  final int sucursales;

  /// "v1.1.5 (3)"; vacío si no se sabe.
  final String version;

  final Destino actual;
  final VoidCallback onDescargas;
  final VoidCallback onNotificaciones;
  final VoidCallback onCerrarSesion;

  /// Lo que la app trae además de lo del diseño (apariencia, biometría, moneda).
  final List<Widget> extras;

  const PanelCuenta({
    super.key,
    required this.nombre,
    required this.rol,
    required this.sucursales,
    required this.version,
    required this.actual,
    required this.onDescargas,
    required this.onNotificaciones,
    required this.onCerrarSesion,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line),
        boxShadow: [BoxShadow(color: _C.sombra, blurRadius: 60, offset: const Offset(0, 24))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _C.line))),
            child: Row(
              children: [
                AvatarManager(inicial: inicialDe(nombre)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w700, _C.ink, height: 1.3)),
                      Text('$rol · ${textoSucursales(sucursales)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w400, _C.muted, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          FilaMenu(icono: Destinos.icono(Destino.descargas), texto: Destinos.nombre(Destino.descargas), onTap: onDescargas),
          FilaMenu(
            icono: Destinos.icono(Destino.notificaciones),
            texto: Destinos.nombre(Destino.notificaciones),
            actual: actual == Destino.notificaciones,
            onTap: onNotificaciones,
          ),
          ...extras,
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
            child: FilaMenu(icono: Icons.logout_rounded, texto: 'Cerrar sesión', peligro: true, onTap: onCerrarSesion),
          ),
          if (version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              child: Text('Sabor Manager $version', maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11, FontWeight.w400, _C.soft)),
            ),
        ],
      ),
    );
  }
}

/// La hoja "Más" del teléfono.
class HojaMas extends StatelessWidget {
  final String nombre;
  final String rol;
  final int sucursales;
  final String version;
  final Destino actual;
  final VoidCallback onDescargas;
  final VoidCallback onNotificaciones;
  final VoidCallback onCerrarSesion;
  final List<Widget> extras;

  const HojaMas({
    super.key,
    required this.nombre,
    required this.rol,
    required this.sucursales,
    required this.version,
    required this.actual,
    required this.onDescargas,
    required this.onNotificaciones,
    required this.onCerrarSesion,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
          child: Row(
            children: [
              AvatarManager(inicial: inicialDe(nombre), lado: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(16, FontWeight.w700, _C.ink, height: 1.3)),
                    Text('$rol · ${textoSucursales(sucursales)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
        FilaMenu(grande: true, icono: Destinos.icono(Destino.descargas), texto: Destinos.nombre(Destino.descargas), sub: 'Reportes en Excel', onTap: onDescargas),
        FilaMenu(
          grande: true,
          icono: Destinos.icono(Destino.notificaciones),
          texto: Destinos.nombre(Destino.notificaciones),
          sub: Destinos.descripcion(Destino.notificaciones),
          actual: actual == Destino.notificaciones,
          onTap: onNotificaciones,
        ),
        ...extras,
        FilaMenu(grande: true, icono: Icons.logout_rounded, texto: 'Cerrar sesión', peligro: true, onTap: onCerrarSesion),
        if (version.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Sabor Manager $version', textAlign: TextAlign.center, style: _t(11, FontWeight.w400, _C.soft)),
          ),
      ],
    );
  }
}
