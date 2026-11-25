/// "Requiere tu atención" y "Cajas abiertas" del Inicio (rediseño 2026-11-20,
/// inicio-manager.html). Lo que cada fila dice lo arma [AtencionInicio] con
/// datos que el Inicio ya tiene; aquí solo se dibuja.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show moneda;
import '../../data/models/atencion_inicio.dart';
import '../../data/models/cash_register_summary.dart';
import '../../data/models/cuentas_abiertas.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

// ── REQUIERE TU ATENCIÓN ─────────────────────────────────────────────────────

/// La lista de lo que el dueño no debería dejar pasar. Si no hay nada, no se
/// dibuja: una tarjeta vacía que dice "todo bien" todos los días se aprende a
/// ignorar y deja de servir el día que sí trae algo.
///
/// En pantalla ancha va junto a "Ventas por método de pago" y del mismo alto
/// ([llenarAlto]): los avisos que no caben se desplazan por dentro de la tarjeta.
class AtencionCard extends StatefulWidget {
  final List<ItemAtencion> items;
  final ValueChanged<ItemAtencion> onTap;

  /// Toma el alto que le dan (no el de sus filas) y desplaza las filas por dentro.
  final bool llenarAlto;

  const AtencionCard({super.key, required this.items, required this.onTap, this.llenarAlto = false});

  @override
  State<AtencionCard> createState() => _AtencionCardState();
}

class _AtencionCardState extends State<AtencionCard> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    final lado = telefono ? 16.0 : 20.0;
    final llenar = widget.llenarAlto;
    // Con desplazamiento, la barra va en un canal propio a la derecha (no encima de
    // las flechas): la tarjeta deja menos margen y la lista lo recupera por dentro.
    const canal = 12.0;

    final encabezado = Padding(
      padding: EdgeInsets.only(bottom: 8, right: llenar ? canal : 0),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Requiere tu atención',
              style: _t(16, FontWeight.w700, _C.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 24),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _C.bad, borderRadius: BorderRadius.circular(999)),
            // Incidencias, no filas: "4 cierres más" cuentan 4.
            child: Text(
              '${items.fold<int>(0, (s, i) => s + i.cuantos)}',
              style: _t(12.5, FontWeight.w700, InicioColores.onAccent, height: 1.0),
            ),
          ),
        ],
      ),
    );

    final filas = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _FilaAtencion(item: items[i], primera: i == 0, onTap: () => widget.onTap(items[i])),
      ],
    );

    return Container(
      padding: EdgeInsets.fromLTRB(lado, 18, llenar ? lado - canal : lado, llenar ? 14 : 10),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          encabezado,
          if (llenar)
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                // Se ve siempre que haya más de lo que cabe: así se nota que sigue.
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(right: canal),
                  child: filas,
                ),
              ),
            )
          else
            filas,
        ],
      ),
    );
  }
}

class _FilaAtencion extends StatelessWidget {
  final ItemAtencion item;
  final bool primera;
  final VoidCallback onTap;

  const _FilaAtencion({required this.item, required this.primera, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final alta = item.gravedad == GravedadAtencion.alta;
    final color = alta ? _C.bad : _C.warn;
    final fondo = alta ? _C.badTint : _C.warnTint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: _C.subtle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: primera ? null : Border(top: BorderSide(color: _C.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.warning_amber_rounded, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          for (final p in item.partes)
                            TextSpan(
                              text: p.texto,
                              style: _t(14.5, p.negrita ? FontWeight.w700 : FontWeight.w400, _C.ink, height: 1.35),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(item.seccion, style: _t(12, FontWeight.w400, _C.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: _C.soft),
            ],
          ),
        ),
      ),
    );
  }
}

// ── CAJAS ABIERTAS ───────────────────────────────────────────────────────────

/// "Marta desde 8:02 a. m." — y, si hay más de una, "y 1 más". Con una caja
/// que viene de otro día se dice el día, no solo la hora.
String subtituloCajasAbiertas(List<CashRegisterSummary> abiertas, {DateTime? ahora}) {
  if (abiertas.isEmpty) return 'Ninguna abierta';
  final hoy = DateUtils.dateOnly(ahora ?? DateTime.now());
  final r = ([...abiertas]..sort((a, b) => a.openedAt.compareTo(b.openedAt))).first;
  final desde = DateUtils.dateOnly(r.openedAt) == hoy
      // "8:02 a. m.", como el diseño y como el resto del Manager (jm usa 24 horas en español).
      ? DateFormat('h:mm a', 'es').format(r.openedAt)
      : 'el ${DateFormat('d MMM', 'es').format(r.openedAt)}';
  final base = '${r.userName} desde $desde';
  final mas = abiertas.length - 1;
  return mas > 0 ? '$base y $mas más' : base;
}

/// Cuántas cajas hay abiertas ahora y quién las abrió.
class CajasAbiertasCard extends StatelessWidget {
  final List<CashRegisterSummary> abiertas;
  final VoidCallback? onTap;

  const CajasAbiertasCard({super.key, required this.abiertas, this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TarjetaAhora(
      icono: Icons.point_of_sale_rounded,
      colorIcono: _C.gift,
      fondoIcono: _C.giftTint,
      etiqueta: 'Cajas abiertas',
      numero: '${abiertas.length}',
      detalle: subtituloCajasAbiertas(abiertas),
      onTap: onTap,
    );
  }
}

// ── CUENTAS ABIERTAS ─────────────────────────────────────────────────────────

/// Cuántas cuentas hay pendientes de cobro y cuánto suman: lo que el POS
/// muestra en "Por cobrar". Sin flecha: no hay a dónde llevar (el Manager no
/// tiene una lista de cuentas), y una flecha que no lleva a ningún lado engaña.
class CuentasAbiertasCard extends StatelessWidget {
  final CuentasPorCobrar resumen;

  const CuentasAbiertasCard({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final n = resumen.cuantas;
    final detalle = n == 0 ? 'Nada por cobrar' : '${AtencionInicio.monto(moneda, resumen.monto)} por cobrar';
    return _TarjetaAhora(
      icono: Icons.table_restaurant_rounded,
      colorIcono: _C.accent,
      fondoIcono: _C.tint,
      etiqueta: 'Cuentas abiertas',
      numero: '$n',
      detalle: detalle,
      onTap: null,
    );
  }
}

/// La tarjeta de "lo que pasa ahora". En pantalla ancha: el ícono a la izquierda y
/// el texto al lado. En el teléfono van dos en una fila (como en la PC), así que se
/// apila: el ícono (y la flecha) arriba, debajo qué es, el número y el detalle.
class _TarjetaAhora extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final Color fondoIcono;
  final String etiqueta;
  final String numero;
  final String detalle;
  final VoidCallback? onTap;

  const _TarjetaAhora({
    required this.icono,
    required this.colorIcono,
    required this.fondoIcono,
    required this.etiqueta,
    required this.numero,
    required this.detalle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compacta = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    final flecha = Icon(Icons.chevron_right_rounded, size: compacta ? 18 : 20, color: _C.soft);

    if (compacta) {
      return InicioToque(
        onTap: onTap,
        radio: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: fondoIcono, borderRadius: BorderRadius.circular(11)),
                    child: Icon(icono, size: 18, color: colorIcono),
                  ),
                  if (onTap != null) flecha,
                ],
              ),
              const SizedBox(height: 10),
              Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(numero, maxLines: 1, style: _t(22, FontWeight.w800, _C.ink, height: 1.3)),
              ),
              Text(detalle, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w400, _C.muted)),
            ],
          ),
        ),
      );
    }

    return InicioToque(
      onTap: onTap,
      radio: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: fondoIcono, borderRadius: BorderRadius.circular(14)),
              child: Icon(icono, size: 22, color: colorIcono),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(etiqueta, style: _t(13, FontWeight.w400, _C.muted)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: numero, style: _t(22, FontWeight.w800, _C.ink, height: 1.3)),
                        TextSpan(text: ' · $detalle', style: _t(13, FontWeight.w400, _C.muted)),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              flecha,
            ],
          ],
        ),
      ),
    );
  }
}

/// Las tarjetas de "lo que pasa ahora" (cuentas y cajas abiertas): lado a lado,
/// también en el teléfono (como en la PC; ahí cada tarjeta se apila por dentro).
/// Con una sola, ocupa el ancho completo.
class FilaAhora extends StatelessWidget {
  final List<Widget> tarjetas;

  const FilaAhora({super.key, required this.tarjetas});

  @override
  Widget build(BuildContext context) {
    if (tarjetas.isEmpty) return const SizedBox.shrink();
    if (tarjetas.length == 1) return tarjetas.single;
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i > 0) SizedBox(width: telefono ? 10 : 12),
            Expanded(child: tarjetas[i]),
          ],
        ],
      ),
    );
  }
}
