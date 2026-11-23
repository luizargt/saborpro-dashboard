/// Piezas que comparten las pantallas de detalle rediseñadas en modo oscuro
/// (Propinas, Cierres de caja...): la tarjeta de resumen de arriba, con sus
/// cifras separadas por líneas, y el aviso ámbar.
///
/// Salen del diseño (`.sum` y `.alert` de propinas.html y cierres-caja.html):
/// cuatro cifras en una fila en pantalla ancha (la primera un poco más ancha),
/// de dos en dos en tablet y teléfono.
///
/// OJO: la tarjeta de resumen usa `IntrinsicHeight` (las cifras de una fila miden
/// lo mismo): nada de lo que se ponga en sus celdas puede llevar `LayoutBuilder`.
library;

import 'package:flutter/material.dart';

import '../../data/models/atencion_inicio.dart' show ParteTexto;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Una cifra del resumen: su rótulo, el valor grande y las líneas chicas de abajo.
class ResumenCelda {
  final String etiqueta;
  final String? valor;
  final Color? _colorValor;
  Color get colorValor => _colorValor ?? _C.ink;

  /// Las líneas chicas bajo el valor ("2 cierres", "vs Ayer"...).
  final List<Widget> sub;

  /// En vez del valor y sus líneas: lo que va bajo el rótulo (la barra de
  /// efectivo y tarjeta, por ejemplo).
  final Widget? cuerpo;

  const ResumenCelda({
    required this.etiqueta,
    this.valor,
    Color? colorValor,
    this.sub = const [],
    this.cuerpo,
  }) : _colorValor = colorValor;
}

class ResumenCard extends StatelessWidget {
  final List<ResumenCelda> celdas;

  /// El ancho que tiene el contenido de la pantalla (decide cuántas van por fila).
  final double ancho;

  const ResumenCard({super.key, required this.celdas, required this.ancho});

  /// El diseño pasa a teléfono (cifras y relleno más chicos) desde aquí.
  static bool esTelefono(double ancho) => ancho < 640;

  /// Una línea chica de las de bajo el valor, con el tamaño que le toca al ancho.
  static Widget linea(String texto, double ancho, {Color? color, FontWeight peso = FontWeight.w400}) =>
      Text(texto, style: _t(esTelefono(ancho) ? 12 : 13, peso, color ?? _C.muted));

  @override
  Widget build(BuildContext context) {
    final telefono = esTelefono(ancho);
    final cuerpos = [for (final c in celdas) _Celda(celda: c, telefono: telefono)];
    final cuatro = ancho > 980 && cuerpos.length == 4;
    return InicioCard(
      padding: EdgeInsets.zero,
      recortar: true,
      child: cuatro
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // La primera, un poco más ancha (1.3fr 1fr 1fr 1fr).
                  for (var i = 0; i < 4; i++)
                    Expanded(flex: i == 0 ? 13 : 10, child: _ConLinea(izquierda: i > 0, child: cuerpos[i])),
                ],
              ),
            )
          // En teléfono y tablet, de dos en dos.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var f = 0; f < cuerpos.length; f += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ConLinea(arriba: f > 0, child: cuerpos[f])),
                        if (f + 1 < cuerpos.length)
                          Expanded(child: _ConLinea(arriba: f > 0, izquierda: true, child: cuerpos[f + 1]))
                        else if (cuerpos.length > 1)
                          const Expanded(child: SizedBox.shrink()),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ConLinea extends StatelessWidget {
  final bool izquierda;
  final bool arriba;
  final Widget child;

  const _ConLinea({this.izquierda = false, this.arriba = false, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: izquierda ? BorderSide(color: _C.line) : BorderSide.none,
          top: arriba ? BorderSide(color: _C.line) : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

class _Celda extends StatelessWidget {
  final ResumenCelda celda;
  final bool telefono;

  const _Celda({required this.celda, required this.telefono});

  @override
  Widget build(BuildContext context) {
    final c = celda;
    return Padding(
      padding: EdgeInsets.all(telefono ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.etiqueta, style: _t(13, FontWeight.w600, _C.muted)),
          if (c.cuerpo != null)
            c.cuerpo!
          else ...[
            const SizedBox(height: 4),
            // Con una cifra enorme la letra se achica en vez de salirse.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                c.valor ?? '',
                maxLines: 1,
                style: _t(telefono ? 21 : 26, FontWeight.w800, c.colorValor, height: 1.2).copyWith(letterSpacing: -0.26),
              ),
            ),
            for (final s in c.sub) ...[const SizedBox(height: 4), s],
          ],
        ],
      ),
    );
  }
}

/// El aviso ámbar del diseño (`.alert`): un ícono en cuadro y una frase con lo
/// importante en negritas.
class AlertaAmbar extends StatelessWidget {
  final List<ParteTexto> partes;
  final IconData icono;

  const AlertaAmbar({super.key, required this.partes, this.icono = Icons.warning_amber_rounded});

  @override
  Widget build(BuildContext context) {
    final base = _t(14.5, FontWeight.w400, _C.ink, height: 1.4);
    final negrita = _t(14.5, FontWeight.w700, _C.ink, height: 1.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12)),
            child: Icon(icono, size: 20, color: _C.warn),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: base,
                children: [for (final p in partes) TextSpan(text: p.texto, style: p.negrita ? negrita : null)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una nota en su propia tarjeta (lo que la pantalla no puede mostrar y por qué).
class AvisoTarjeta extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color? _color;
  Color get color => _color ?? _C.muted;

  const AvisoTarjeta({super.key, required this.icono, required this.texto, Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) {
    return InicioCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45))),
        ],
      ),
    );
  }
}
