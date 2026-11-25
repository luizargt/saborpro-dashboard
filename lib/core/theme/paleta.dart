/// Las dos paletas de Sabor Manager, claro y oscuro, con los valores EXACTOS de los
/// diseños (`assets/Desing/Sabor Manager/*.html` de saborpro_app: el `:root` es el
/// claro y `prefers-color-scheme: dark` el oscuro).
///
/// Los colores de las pantallas NO se escriben aquí ni se piden por `BuildContext`:
/// salen de `CortesiasColores` (`InicioColores`), que lee la paleta que esté puesta
/// ([paletaActual]). Por eso cambiar de modo es poner otra paleta y reconstruir la
/// pantalla; ver [TemaManager].
library;

import 'package:flutter/material.dart';

class Paleta {
  /// Fondo de la pantalla.
  final Color bg;

  /// Tarjetas.
  final Color card;

  /// Fondo suave (cajas dentro de una tarjeta, pistas de las barras).
  final Color subtle;

  /// La línea fina que separa filas.
  final Color line;

  /// La línea marcada (la que separa un total).
  final Color lineStrong;

  /// Texto principal, y los apagados.
  final Color ink;
  final Color muted;
  final Color soft;

  /// El morado de la marca y su fondo suave.
  final Color accent;
  final Color tint;

  /// Verde (lo bueno, lo ganado), con su fondo.
  final Color ok;
  final Color okTint;

  /// Ámbar (atención), con su fondo.
  final Color warn;
  final Color warnTint;

  /// Rojo (lo malo, lo perdido), con su fondo.
  final Color bad;
  final Color badTint;

  /// Naranja de "gasto / compra", con su fondo.
  final Color exp;
  final Color expTint;

  /// Azul (lo que queda, lo usado, las donaciones), con su fondo.
  final Color blue;
  final Color blueTint;

  /// Texto sobre un fondo de color pleno (el morado de un botón): blanco en las dos.
  final Color onAccent;

  // ── La barra de navegación (sidebar-manager.html): `--sb…` de los diseños ──

  /// Fondo de la barra y de la barra inferior.
  final Color barra;

  /// Fondo de lo que va sobre ella (el buscador).
  final Color barra2;

  /// Sus líneas.
  final Color barraLinea;

  /// Texto, y texto apagado de sus opciones.
  final Color barraTexto;
  final Color barraApagado;

  /// Al pasar el cursor.
  final Color barraHover;

  /// La opción elegida: fondo, ícono y texto.
  final Color barraActivo;
  final Color barraActivoIcono;
  final Color barraActivoTexto;

  /// Fondo de los contadores sin color y de las teclas.
  final Color barraChip;

  /// La sombra de lo que flota (menú de la cuenta, paleta de comandos, barra inferior).
  final Color sombra;

  final Brightness brillo;

  const Paleta({
    required this.brillo,
    required this.bg,
    required this.card,
    required this.subtle,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.muted,
    required this.soft,
    required this.accent,
    required this.tint,
    required this.ok,
    required this.okTint,
    required this.warn,
    required this.warnTint,
    required this.bad,
    required this.badTint,
    required this.exp,
    required this.expTint,
    required this.blue,
    required this.blueTint,
    required this.barra,
    required this.barra2,
    required this.barraLinea,
    required this.barraTexto,
    required this.barraApagado,
    required this.barraHover,
    required this.barraActivo,
    required this.barraActivoIcono,
    required this.barraActivoTexto,
    required this.barraChip,
    required this.sombra,
    this.onAccent = const Color(0xFFFFFFFF),
  });

  bool get esOscura => brillo == Brightness.dark;

  /// El `:root` de los diseños.
  static const clara = Paleta(
    brillo: Brightness.light,
    bg: Color(0xFFEEF1F5),
    card: Color(0xFFFFFFFF),
    subtle: Color(0xFFF3F2F7),
    line: Color(0xFFE4E2EA),
    // El diseño usa `var(--line-strong, var(--soft))`: en claro no define la fuerte.
    lineStrong: Color(0xFF9A96A6),
    ink: Color(0xFF16131F),
    muted: Color(0xFF6B6778),
    soft: Color(0xFF9A96A6),
    accent: Color(0xFF6C3BF5),
    tint: Color(0xFFEFE9FE),
    ok: Color(0xFF0F8F74),
    okTint: Color(0xFFDFF3EE),
    warn: Color(0xFFA86400),
    warnTint: Color(0xFFFFF1D6),
    bad: Color(0xFFC8372D),
    badTint: Color(0xFFFBE6E3),
    exp: Color(0xFFD9542B),
    expTint: Color(0xFFFDEBE3),
    blue: Color(0xFF2F6FD6),
    blueTint: Color(0xFFE3EDFB),
    barra: Color(0xFFFFFFFF),
    barra2: Color(0xFFF6F5FA),
    barraLinea: Color(0xFFE9E7EF),
    barraTexto: Color(0xFF16131F),
    barraApagado: Color(0xFF6B6778),
    barraHover: Color(0xFFF3F2F7),
    barraActivo: Color(0xFFEFE9FE),
    barraActivoIcono: Color(0xFF6C3BF5),
    barraActivoTexto: Color(0xFF5B2EE0),
    barraChip: Color(0x0F16131F),
    sombra: Color(0x47111427),
  );

  /// El `prefers-color-scheme: dark` de los diseños (lo que el Manager venía usando).
  static const oscura = Paleta(
    brillo: Brightness.dark,
    bg: Color(0xFF0E1220),
    card: Color(0xFF1A1F2E),
    subtle: Color(0xFF222838),
    line: Color(0xFF2C3344),
    lineStrong: Color(0xFF46506A),
    ink: Color(0xFFEEF0F6),
    muted: Color(0xFFA3A9BB),
    soft: Color(0xFF7A8197),
    accent: Color(0xFF9B7BFF),
    tint: Color(0xFF2A2546),
    ok: Color(0xFF4FD1B0),
    okTint: Color(0xFF163A34),
    warn: Color(0xFFF2B84B),
    warnTint: Color(0xFF3A2E14),
    bad: Color(0xFFFF7A6E),
    badTint: Color(0xFF3B1D1C),
    exp: Color(0xFFFF8A5C),
    expTint: Color(0xFF3A2219),
    blue: Color(0xFF7AA8F5),
    blueTint: Color(0xFF1B2A45),
    barra: Color(0xFF090C18),
    barra2: Color(0xFF12162A),
    barraLinea: Color(0x12FFFFFF),
    barraTexto: Color(0xFFE9EBF5),
    barraApagado: Color(0xFF8C92AB),
    barraHover: Color(0x0FFFFFFF),
    barraActivo: Color(0x2E9B7BFF),
    barraActivoIcono: Color(0xFFB9A3FF),
    barraActivoTexto: Color(0xFFFFFFFF),
    barraChip: Color(0x14FFFFFF),
    sombra: Color(0x99000000),
  );
}

/// La paleta que se está usando. La cambia [TemaManager]; las pantallas la leen a
/// través de `CortesiasColores`.
Paleta paletaActual = Paleta.oscura;
