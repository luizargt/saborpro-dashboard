/// La barra lateral de Sabor Manager (pantallas anchas). Diseño 2026-11-22
/// (`sidebar-manager.html` de saborpro_app): el negocio, el buscador, las secciones
/// con sus lugares y contadores, y la cuenta abajo. Se puede contraer a una columna
/// de solo íconos (76 de ancho).
///
/// Es la parte que se ve, sin providers ni Firebase: el shell le pasa lo que hay que
/// mostrar y le avisa lo que se toca. Se prueba en test/presentation/widgets/
/// barra_lateral_test.dart.
library;

import 'package:flutter/material.dart';

import '../navigation/destinos.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El rojo de los contadores y puntos (`#E5484D` en el diseño, igual en claro y oscuro).
const kRojoContador = Color(0xFFE5484D);

/// Cuánto ocupa la barra.
abstract final class AnchoBarra {
  static const completa = 280.0;
  static const contraida = 76.0;
  static double de(bool contraida) => contraida ? AnchoBarra.contraida : completa;
}

/// "3 sucursales" / "1 sucursal".
String textoSucursales(int n) => n == 1 ? '1 sucursal' : '$n sucursales';

/// La inicial del avatar: la primera letra del nombre, en mayúscula.
String inicialDe(String? nombre) {
  final n = nombre?.trim() ?? '';
  return n.isEmpty ? '?' : n.characters.first.toUpperCase();
}

class BarraLateral extends StatelessWidget {
  final Destino actual;
  final bool contraida;

  /// Avisos sin leer (contador rojo) y productos agotados (contador ámbar).
  final int avisosSinLeer;
  final int agotados;

  /// Los lugares que llevan un puntito rojo ("hay algo que revisar").
  final Set<Destino> puntos;

  final int sucursales;
  final String nombre;
  final String rol;

  /// La tecla del buscador ("Ctrl K" o "⌘ K").
  final String atajo;

  final ValueChanged<Destino> onElegir;
  final VoidCallback onBuscar;
  final VoidCallback onCuenta;

  /// El menú de la cuenta está abierto.
  final bool cuentaAbierta;

  const BarraLateral({
    super.key,
    required this.actual,
    required this.contraida,
    required this.avisosSinLeer,
    required this.agotados,
    required this.puntos,
    required this.sucursales,
    required this.nombre,
    required this.rol,
    required this.onElegir,
    required this.onBuscar,
    required this.onCuenta,
    this.cuentaAbierta = false,
    this.atajo = 'Ctrl K',
  });

  @override
  Widget build(BuildContext context) {
    final rail = contraida;
    return Container(
      width: AnchoBarra.de(rail),
      decoration: BoxDecoration(
        color: _C.barra,
        border: Border(right: BorderSide(color: _C.barraLinea)),
      ),
      // El color llega hasta los bordes; lo que se aparta de las barras del sistema es
      // el contenido.
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(rail ? 10 : 12, 14, rail ? 10 : 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Negocio(rail: rail, sucursales: sucursales),
              const SizedBox(height: 10),
              _Buscador(rail: rail, atajo: atajo, onTap: onBuscar),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final s in SeccionNav.values) ...[
                      _TituloSeccion(rail: rail, texto: Destinos.tituloDeSeccion(s), primera: s == SeccionNav.general),
                      for (final d in Destinos.deSeccion(s))
                        _ItemBarra(
                          destino: d,
                          rail: rail,
                          activo: actual == d || (d == Destino.avisos && actual == Destino.notificaciones),
                          contador: switch (d) {
                            Destino.avisos => avisosSinLeer,
                            Destino.despensa => agotados,
                            _ => 0,
                          },
                          contadorRojo: d == Destino.avisos,
                          punto: puntos.contains(d),
                          onTap: () => onElegir(d),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.barraLinea))),
                padding: const EdgeInsets.only(top: 10),
                child: _Cuenta(rail: rail, nombre: nombre, rol: rol, abierta: cuentaAbierta, onTap: onCuenta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El logo de las barras: el de Sabor Manager (`SaborManagerLogo.png`, tres columnas
/// moradas y la última coral, sobre transparente).
///
/// El PNG trae margen alrededor (las columnas ocupan ~60 % del cuadro), así que se
/// dibuja ampliado dentro de un cuadro de [lado]: lo de afuera es transparente y no
/// tapa nada.
class LogoManager extends StatelessWidget {
  final double lado;
  const LogoManager({super.key, this.lado = 38});

  static const _ampliacion = 1.45;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: lado,
        height: lado,
        child: Transform.scale(
          scale: _ampliacion,
          child: Image.asset(
            'assets/images/SaborManagerLogo.png',
            width: lado,
            height: lado,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _Negocio extends StatelessWidget {
  final bool rail;
  final int sucursales;
  const _Negocio({required this.rail, required this.sucursales});

  @override
  Widget build(BuildContext context) {
    if (rail) return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LogoManager()));
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          const LogoManager(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sabor Manager', maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w700, _C.barraTexto, height: 1.3)),
                Text(textoSucursales(sucursales), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.5, FontWeight.w400, _C.barraApagado, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Buscador extends StatelessWidget {
  final bool rail;
  final String atajo;
  final VoidCallback onTap;
  const _Buscador({required this.rail, required this.atajo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Buscar',
      child: Material(
        color: _C.barra2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _C.barraLinea)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: EdgeInsets.only(left: rail ? 0 : 12, right: rail ? 0 : 10),
              child: Row(
                mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(Icons.search_rounded, size: 17, color: _C.barraApagado),
                  if (!rail) ...[
                    const SizedBox(width: 10),
                    Expanded(child: Text('Buscar…', maxLines: 1, style: _t(13.5, FontWeight.w400, _C.barraApagado))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _C.barraChip, borderRadius: BorderRadius.circular(6), border: Border.all(color: _C.barraLinea)),
                      child: Text(atajo, maxLines: 1, style: _t(11, FontWeight.w600, _C.barraApagado, height: 1.3)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final bool rail;
  final String texto;
  final bool primera;
  const _TituloSeccion({required this.rail, required this.texto, required this.primera});

  @override
  Widget build(BuildContext context) {
    if (rail) {
      // Una rayita en vez del título.
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
        child: Center(child: Container(width: 18, height: 1, color: _C.barraLinea)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12, primera ? 4 : 14, 12, 6),
      child: Text(
        texto.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _t(11, FontWeight.w700, _C.barraApagado, height: 1.3).copyWith(letterSpacing: 0.88),
      ),
    );
  }
}

class _ItemBarra extends StatefulWidget {
  final Destino destino;
  final bool rail;
  final bool activo;
  final int contador;
  final bool contadorRojo;
  final bool punto;
  final VoidCallback onTap;

  const _ItemBarra({
    required this.destino,
    required this.rail,
    required this.activo,
    required this.contador,
    required this.contadorRojo,
    required this.punto,
    required this.onTap,
  });

  @override
  State<_ItemBarra> createState() => _ItemBarraState();
}

class _ItemBarraState extends State<_ItemBarra> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final activo = widget.activo;
    final nombre = Destinos.nombre(widget.destino);
    final colorTexto = activo ? _C.barraActivoTexto : (_encima ? _C.barraTexto : _C.barraApagado);
    final colorIcono = activo ? _C.barraActivoIcono : colorTexto;
    final rail = widget.rail;

    Widget? contador;
    if (widget.contador > 0) {
      final rojo = widget.contadorRojo;
      // En la columna angosta solo van los rojos: un contador ámbar ya no cabe.
      if (!rail || rojo) {
        contador = Container(
          // Alto fijo: con `alignment` el contenedor se estira a todo el alto de la fila.
          height: rail ? 16 : 20,
          constraints: BoxConstraints(minWidth: rail ? 16 : 22),
          padding: EdgeInsets.symmetric(horizontal: rail ? 4 : 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rojo ? kRojoContador : _C.warnTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.contador > 99 ? '99+' : '${widget.contador}',
            maxLines: 1,
            style: _t(rail ? 9.5 : 11, FontWeight.w700, rojo ? const Color(0xFFFFFFFF) : _C.warn, height: 1.1),
          ),
        );
      }
    } else if (widget.punto) {
      contador = Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(color: kRojoContador, shape: BoxShape.circle),
      );
    }

    final fila = Container(
      height: rail ? 42 : 40,
      decoration: BoxDecoration(
        color: activo ? _C.barraActivo : (_encima ? _C.barraHover : Colors.transparent),
        borderRadius: BorderRadius.circular(11),
      ),
      padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (activo)
            Positioned(
              // El Stack queda dentro del relleno de la fila (12 a cada lado cuando no es
              // columna angosta): la rayita se pega al borde de la barra, no a la fila.
              left: rail ? -6 : -16,
              top: 10,
              bottom: 10,
              child: Container(
                width: 3,
                decoration: BoxDecoration(color: _C.barraActivoIcono, borderRadius: const BorderRadius.horizontal(right: Radius.circular(3))),
              ),
            ),
          Positioned.fill(
            child: rail
                ? Center(child: Icon(Destinos.icono(widget.destino), size: 20, color: colorIcono))
                : Row(
                    children: [
                      Icon(Destinos.icono(widget.destino), size: 20, color: colorIcono),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(14, activo ? FontWeight.w600 : FontWeight.w500, colorTexto, height: 1.3),
                        ),
                      ),
                      if (contador != null) ...[const SizedBox(width: 8), contador],
                    ],
                  ),
          ),
          // En la columna angosta, el contador se pega a la esquina del ícono.
          if (rail && contador != null)
            Positioned(
              top: widget.punto && widget.contador == 0 ? 8 : 3,
              right: widget.punto && widget.contador == 0 ? 12 : 6,
              child: contador,
            ),
        ],
      ),
    );

    final item = MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Semantics(
        button: true,
        selected: activo,
        label: nombre,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: fila,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      // El nombre de cada opción, al pasar el cursor, cuando solo se ve el ícono.
      child: rail ? Tooltip(message: nombre, preferBelow: false, child: item) : item,
    );
  }
}

class _Cuenta extends StatefulWidget {
  final bool rail;
  final String nombre;
  final String rol;
  final bool abierta;
  final VoidCallback onTap;
  const _Cuenta({required this.rail, required this.nombre, required this.rol, required this.abierta, required this.onTap});

  @override
  State<_Cuenta> createState() => _CuentaState();
}

class _CuentaState extends State<_Cuenta> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final rail = widget.rail;
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Semantics(
        button: true,
        label: 'Cuenta de ${widget.nombre}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 8, vertical: 6),
            decoration: BoxDecoration(
              color: widget.abierta || _encima ? _C.barraHover : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                AvatarManager(inicial: inicialDe(widget.nombre)),
                if (!rail) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13.5, FontWeight.w600, _C.barraTexto, height: 1.3)),
                        Text(widget.rol, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11.5, FontWeight.w400, _C.barraApagado, height: 1.3)),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, size: 16, color: _C.barraApagado),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El círculo con la inicial (degradado coral, como el diseño).
class AvatarManager extends StatelessWidget {
  final String inicial;
  final double lado;
  const AvatarManager({super.key, required this.inicial, this.lado = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: lado,
      height: lado,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF8A73), Color(0xFFF0624D)]),
      ),
      child: Text(inicial, style: _t(lado * 0.4, FontWeight.w700, const Color(0xFFFFFFFF), height: 1.1)),
    );
  }
}

/// El botoncito redondo que contrae o expande la barra: va pegado a su borde derecho.
class BotonContraer extends StatelessWidget {
  final bool contraida;
  final VoidCallback onTap;
  const BotonContraer({super.key, required this.contraida, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: contraida ? 'Expandir menú' : 'Contraer menú',
      child: Semantics(
        button: true,
        label: contraida ? 'Expandir menú' : 'Contraer menú',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // El área de toque es más grande que el círculo que se ve.
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _C.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: _C.line),
                  boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Icon(contraida ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 16, color: _C.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
