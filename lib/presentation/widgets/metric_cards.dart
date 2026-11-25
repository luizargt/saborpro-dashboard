import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import 'inicio_ui.dart';

// Rediseño 2026-11-20 (inicio-manager.html, modo oscuro). Qué se muestra no
// cambia, salvo lo que se dice en cada pieza: las cifras salen de las mismas
// métricas de siempre.

typedef _C = InicioColores;
const _t = inicioTexto;

final _fmt = NumberFormat('#,##0.00', 'en_US');
final _fmtInt = NumberFormat('#,##0', 'en_US');
String _q(double v) => '$moneda${_fmt.format(v)}';

String _cobros(int n) => '$n cobro${n == 1 ? '' : 's'}';

/// Los tres números de arriba (venta bruta, tickets y promedio) y las tarjetas
/// rápidas debajo, juntos. La pantalla los usa por separado para poner en medio
/// lo que requiere atención; esto queda para quien los quiera de una pieza.
class MetricCards extends StatelessWidget {
  final PeriodMetrics metrics;

  /// Abre el detalle de cortesías. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onCourtesyTap;

  /// Abre el detalle de propinas. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onTipsTap;

  /// Abre el detalle de descuentos. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onDiscountTap;

  /// Cobros que llevaron descuento (sale de los pedidos del período).
  final int descuentosCount;

  const MetricCards({
    super.key,
    required this.metrics,
    this.onCourtesyTap,
    this.onTipsTap,
    this.onDiscountTap,
    this.descuentosCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        KpiCards(metrics: metrics),
        const SizedBox(height: 12),
        TarjetasRapidas(
          metrics: metrics,
          onCourtesyTap: onCourtesyTap,
          onTipsTap: onTipsTap,
          onDiscountTap: onDiscountTap,
          descuentosCount: descuentosCount,
        ),
      ],
    );
  }
}

// ── LOS TRES NÚMEROS ─────────────────────────────────────────────────────────

/// Venta bruta, tickets y promedio, cada uno contra el período anterior. Los
/// tres en fila, también en el teléfono (como en la PC): ahí van compactos.
class KpiCards extends StatelessWidget {
  final PeriodMetrics metrics;

  const KpiCards({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return LayoutBuilder(builder: (context, c) {
      final telefono = c.maxWidth <= kInicioQuiebreTelefono;
      final tarjetas = [
        _Kpi(
          etiqueta: 'Venta bruta',
          valor: _q(m.ventaBruta),
          cambio: m.salesChangePercent,
          anterior: _q(m.prevTotalSales),
          telefono: telefono,
          principal: true,
        ),
        _Kpi(
          etiqueta: 'Tickets',
          valor: _fmtInt.format(m.totalOrders),
          cambio: m.ordersChangePercent,
          anterior: _fmtInt.format(m.prevTotalOrders),
          telefono: telefono,
        ),
        _Kpi(
          etiqueta: 'Promedio',
          valor: _q(m.avgTicket),
          cambio: m.avgTicketChangePercent,
          anterior: _q(m.prevAvgTicket),
          telefono: telefono,
        ),
      ];

      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tarjetas.length; i++) ...[
              if (i > 0) SizedBox(width: telefono ? 8 : 12),
              Expanded(child: tarjetas[i]),
            ],
          ],
        ),
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double cambio;

  /// Lo del período anterior, sin rótulo ("Q9,343.50").
  final String anterior;

  /// Compacta: tres en fila en el teléfono.
  final bool telefono;

  /// La primera tarjeta (hoy no cambia nada: las tres van del mismo tamaño).
  final bool principal;

  const _Kpi({
    required this.etiqueta,
    required this.valor,
    required this.cambio,
    required this.anterior,
    required this.telefono,
    this.principal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (telefono) {
      // Tres en fila en 360: cada cosa en su línea y, si no cabe, se achica en vez
      // de cortarse. "vs Q9,343.50" (no "vs anterior: …"): al lado del cambio se
      // entiende, y el rótulo entero no cabe.
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w600, _C.muted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor, maxLines: 1, style: _t(20, FontWeight.w800, _C.ink, height: 1.25).copyWith(letterSpacing: -0.2)),
            ),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _Cambio(cambio, compacto: true)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('vs $anterior', maxLines: 1, style: _t(11.5, FontWeight.w400, _C.muted)),
            ),
          ],
        ),
      );
    }

    const tamano = 32.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: _t(13.5, FontWeight.w600, _C.muted)),
          const SizedBox(height: 4),
          // Con una cifra enorme la letra se achica en vez de salirse de la
          // tarjeta.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: _t(tamano, FontWeight.w800, _C.ink, height: 1.2).copyWith(letterSpacing: -0.01 * tamano),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _Cambio(cambio),
              Text('vs anterior: $anterior', style: _t(13, FontWeight.w400, _C.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// La pastilla del cambio contra el período anterior: verde si subió, roja si
/// bajó y apagada si quedó igual.
class _Cambio extends StatelessWidget {
  final double cambio;
  final bool compacto;
  const _Cambio(this.cambio, {this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final igual = cambio == 0;
    final sube = cambio > 0;
    final color = igual ? _C.soft : (sube ? _C.gift : _C.bad);
    final fondo = igual ? _C.subtle : (sube ? _C.giftTint : _C.badTint);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 7 : 9, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            igual ? Icons.remove_rounded : (sube ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            size: compacto ? 12 : 14,
            color: color,
          ),
          SizedBox(width: compacto ? 2 : 3),
          Text('${cambio.abs().toStringAsFixed(1)}%', style: _t(compacto ? 11.5 : 13, FontWeight.w700, color)),
        ],
      ),
    );
  }
}

// ── LAS TARJETAS RÁPIDAS ─────────────────────────────────────────────────────

class _Datos {
  final String etiqueta;
  final String valor;
  final String detalle;
  final Color color;
  final VoidCallback? onTap;

  const _Datos({
    required this.etiqueta,
    required this.valor,
    required this.detalle,
    required this.color,
    this.onTap,
  });
}

/// Propinas, cortesías, descuentos y cobro de envío: una tarjeta por columna. En el
/// teléfono también van en fila, como en la PC (tres en una fila; con cuatro, dos y
/// dos), en su versión compacta.
///
/// Solo llevan flecha las que se pueden abrir (hoy, propinas, cortesías y
/// descuentos): una flecha que no lleva a ningún lado engaña.
class TarjetasRapidas extends StatelessWidget {
  final PeriodMetrics metrics;
  final VoidCallback? onCourtesyTap;
  final VoidCallback? onTipsTap;
  final VoidCallback? onDiscountTap;
  final int descuentosCount;

  const TarjetasRapidas({
    super.key,
    required this.metrics,
    this.onCourtesyTap,
    this.onTipsTap,
    this.onDiscountTap,
    this.descuentosCount = 0,
  });

  List<_Datos> _tarjetas() {
    final m = metrics;
    // Cortesías y descuentos viven dentro de los renglones del ticket: en la
    // vista de año no se pueden calcular y mostrarlos en cero sería mentir.
    final conDetalle = m.detailAvailable;

    String propinas() {
      if (m.tipsCount > 0) return _cobros(m.tipsCount);
      // Solo cuando TODAS son de las metidas a la caja como ingreso (no son
      // cobros). Con propinas de tickets y sin saber en cuántos cobros (la vista
      // de año las suma en el servidor), decirlo sería falso.
      if (m.tips <= 0 && m.tipsOutsideSales > 0) return 'Metidas a la caja';
      if (m.allTips > 0) return '';
      return 'Sin propinas';
    }

    return [
      if (conDetalle || m.allTips > 0)
        _Datos(
          etiqueta: 'Propinas',
          valor: _q(m.allTips),
          detalle: propinas(),
          color: _C.warn,
          onTap: onTipsTap,
        ),
      if (conDetalle)
        _Datos(
          etiqueta: 'Cortesías / Donaciones',
          valor: _q(m.courtesyTotal),
          detalle: m.courtesyCount > 0 ? _cobros(m.courtesyCount) : 'Ninguna',
          color: _C.gift,
          onTap: onCourtesyTap,
        ),
      if (conDetalle)
        _Datos(
          etiqueta: 'Descuentos',
          valor: _q(m.discounts),
          // Con descuento y sin saber en cuántos cobros (quien arma esto no
          // contó los pedidos), no se dice nada: "Ningún descuento" junto a un
          // monto sería una contradicción.
          detalle: m.discounts <= 0
              ? 'Ningún descuento'
              : (descuentosCount > 0 ? _cobros(descuentosCount) : ''),
          color: _C.don,
          onTap: onDiscountTap,
        ),
      if (m.deliveryFees > 0)
        _Datos(
          etiqueta: 'Cobro Envío Domicilio',
          valor: _q(m.deliveryFees),
          detalle: m.deliveryCount > 0 ? _cobros(m.deliveryCount) : '',
          color: _C.accent,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = _tarjetas();
    if (tarjetas.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final telefono = ancho <= kInicioQuiebreTelefono;
      final hueco = telefono ? 8.0 : 12.0;

      // Teléfono: hasta tres en una fila (con cuatro, dos y dos). Pantalla ancha: 2
      // columnas hasta 1100 de ancho; después, una por tarjeta (hasta 4).
      final int columnas = telefono
          ? (tarjetas.length <= 3 ? tarjetas.length : 2)
          : (ancho >= 1100 ? tarjetas.length.clamp(1, 4) : 2);
      final filas = <List<_Datos>>[];
      for (var i = 0; i < tarjetas.length; i += columnas) {
        filas.add(tarjetas.sublist(i, (i + columnas).clamp(0, tarjetas.length)));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var f = 0; f < filas.length; f++) ...[
            if (f > 0) SizedBox(height: hueco),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columnas; i++) ...[
                    if (i > 0) SizedBox(width: hueco),
                    Expanded(
                      child: i < filas[f].length ? _TarjetaColumna(filas[f][i], compacta: telefono) : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Punto extends StatelessWidget {
  final Color color;
  final double tamano;
  const _Punto(this.color, {this.tamano = 10});

  @override
  Widget build(BuildContext context) =>
      Container(width: tamano, height: tamano, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

Widget get _flecha => Icon(Icons.chevron_right_rounded, color: _C.soft, size: 20);

/// La etiqueta arriba, la cifra grande y el detalle debajo.
///
/// Compacta (teléfono, tres en fila): la etiqueta puede ir en dos líneas
/// ("Cortesías / Donaciones") y la flecha baja junto a la cifra, para dejarle a la
/// etiqueta todo el ancho; la cifra y el detalle van abajo, así quedan alineados
/// entre las tarjetas de la fila aunque una etiqueta ocupe dos líneas.
class _TarjetaColumna extends StatelessWidget {
  final _Datos d;
  final bool compacta;
  const _TarjetaColumna(this.d, {this.compacta = false});

  @override
  Widget build(BuildContext context) {
    if (compacta) {
      return InicioToque(
        onTap: d.onTap,
        radio: 18,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 13, 6, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 4), child: _Punto(d.color, tamano: 8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d.etiqueta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _t(12.5, FontWeight.w400, _C.muted, height: 1.25),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(d.valor, maxLines: 1, style: _t(18, FontWeight.w800, d.color, height: 1.25)),
                    ),
                  ),
                  if (d.onTap != null) Icon(Icons.chevron_right_rounded, color: _C.soft, size: 18),
                ],
              ),
              // La línea del detalle siempre ocupa su lugar (aunque vaya vacía): si no,
              // la cifra de esa tarjeta quedaría más abajo que las de al lado.
              Text(d.detalle.isEmpty ? ' ' : d.detalle, style: _t(11.5, FontWeight.w500, _C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }

    return InicioToque(
      onTap: d.onTap,
      radio: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Punto(d.color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    d.etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(14.5, FontWeight.w400, _C.muted),
                  ),
                ),
                if (d.onTap != null) _flecha,
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(d.valor, maxLines: 1, style: _t(24, FontWeight.w800, d.color, height: 1.25)),
            ),
            if (d.detalle.isNotEmpty)
              Text(d.detalle, style: _t(12.5, FontWeight.w500, _C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
