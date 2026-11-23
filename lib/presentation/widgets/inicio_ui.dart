/// Piezas compartidas de la pantalla de Inicio (rediseño 2026-11-20, de
/// `assets/Desing/Sabor Manager/inicio-manager.html` de saborpro_app, en su modo
/// oscuro). La paleta y la letra son las mismas del detalle de cortesías, de
/// cancelados y de avisos: no se duplican aquí.
library;

import 'package:flutter/material.dart';

import 'cortesias_view.dart' show CortesiasColores, cortesiasTexto, kCortesiasBg;

/// Fondo de la pantalla.
Color get kInicioBg => kCortesiasBg;

/// La línea marcada del diseño (`--line-strong`): la que separa el total.
Color get kInicioLineaFuerte => CortesiasColores.lineStrong;

typedef InicioColores = CortesiasColores;

/// Letra del Inicio: Poppins, con cifras tabulares (las columnas de dinero se
/// alinean).
const inicioTexto = cortesiasTexto;

/// Desde aquí el diseño pasa a su versión de teléfono (`max-width: 760px`).
const kInicioQuiebreTelefono = 760.0;

/// La tarjeta de siempre: fondo `card`, esquinas de 24 y 22 de relleno (18 en
/// teléfono).
class InicioCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Recorta lo que se salga de las esquinas (las tarjetas que traen filas de
  /// borde a borde).
  final bool recortar;

  const InicioCard({super.key, required this.child, this.padding, this.recortar = false});

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    return Container(
      padding: padding ?? EdgeInsets.all(telefono ? 18 : 22),
      clipBehavior: recortar ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: InicioColores.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

/// El título de una tarjeta (17/700), con una nota chica al lado y, si hace
/// falta, algo a la derecha. En teléfono lo que no cabe baja a la línea de
/// abajo en vez de apretarse.
class InicioTituloTarjeta extends StatelessWidget {
  final String titulo;
  final String? nota;
  final Widget? derecha;

  const InicioTituloTarjeta({super.key, required this.titulo, this.nota, this.derecha});

  @override
  Widget build(BuildContext context) {
    final t = Text(titulo, style: inicioTexto(17, FontWeight.w700, InicioColores.ink, height: 1.25));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              runSpacing: 2,
              children: [
                t,
                if (nota != null) Text(nota!, style: inicioTexto(13, FontWeight.w400, InicioColores.muted)),
              ],
            ),
          ),
          if (derecha != null) ...[const SizedBox(width: 10), derecha!],
        ],
      ),
    );
  }
}

/// Una fila de tarjeta tocable con el aspecto del diseño: fondo `card`,
/// onda del toque y esquinas redondeadas. Sin `onTap` no se puede tocar (y no
/// lleva onda).
class InicioToque extends StatelessWidget {
  final VoidCallback? onTap;
  final double radio;
  final Widget child;

  const InicioToque({super.key, required this.onTap, required this.radio, required this.child});

  @override
  Widget build(BuildContext context) {
    // Material + InkWell y no el color en un Container: con el color en el
    // Container la onda del toque quedaba tapada y no se notaba que se tocó.
    return Material(
      color: InicioColores.card,
      borderRadius: BorderRadius.circular(radio),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: InicioColores.subtle,
        child: child,
      ),
    );
  }
}

/// El interruptor redondo del diseño (`.seg`): un fondo suave con la opción
/// elegida en relieve.
class InicioSegmentos<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T elegido;
  final ValueChanged<T> onElegir;

  /// Reparte el ancho en partes iguales (las pestañas de la tabla de platillos).
  final bool completo;

  const InicioSegmentos({
    super.key,
    required this.opciones,
    required this.elegido,
    required this.onElegir,
    this.completo = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton((T, String) o) {
      final activa = o.$1 == elegido;
      final texto = Text(
        o.$2,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: inicioTexto(13.5, FontWeight.w600, activa ? InicioColores.ink : InicioColores.muted),
      );
      return GestureDetector(
        onTap: () => onElegir(o.$1),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: completo ? 42 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activa ? InicioColores.card : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: activa
                ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))]
                : null,
          ),
          child: texto,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: InicioColores.subtle, borderRadius: BorderRadius.circular(999)),
      child: completo
          ? Row(children: [for (final o in opciones) Expanded(child: boton(o))])
          : Row(mainAxisSize: MainAxisSize.min, children: [for (final o in opciones) boton(o)]),
    );
  }
}
