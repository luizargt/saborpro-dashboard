import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// "Resumen financiero": de la venta bruta al total cobrado, y debajo lo que
/// costó. Rediseño 2026-11-20 (inicio-manager.html, modo oscuro); las filas y las
/// cuentas son las de siempre. Va dentro de la tarjeta del gráfico, sin fondo
/// propio.
class SummaryTable extends StatelessWidget {
  final PeriodMetrics metrics;
  const SummaryTable({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    String q(double v) => '$moneda${fmt.format(v)}';
    final m = metrics;

    final filas = <Widget>[
      _Fila(
        etiqueta: 'Ventas brutas',
        nota: 'sin propinas ni envío',
        valor: q(m.grossSales),
        estilo: _Estilo.fuerte,
        sinLinea: true,
      ),
      _Fila(
        prefijo: '−',
        etiqueta: 'Descuentos',
        valor: q(m.discounts),
        estilo: m.discounts > 0 ? _Estilo.resta : _Estilo.normal,
      ),
      if (m.refunds > 0) _Fila(prefijo: '−', etiqueta: 'Reembolsos', valor: q(m.refunds), estilo: _Estilo.resta),
      if (m.tips > 0) _Fila(prefijo: '+', etiqueta: 'Propinas', valor: q(m.tips), estilo: _Estilo.suma),
      if (m.deliveryFees > 0)
        _Fila(prefijo: '+', etiqueta: 'Costos de envío', valor: q(m.deliveryFees), estilo: _Estilo.suma),
      _Fila(etiqueta: 'Total cobrado', valor: q(m.totalSales), estilo: _Estilo.total),
      // Entraron a la caja como ingreso: no son parte de lo cobrado.
      if (m.tipsOutsideSales > 0)
        _Fila(
          etiqueta: 'Propinas fuera de ventas',
          nota: 'metidas a la caja',
          valor: q(m.tipsOutsideSales),
          estilo: _Estilo.normal,
        ),
      if (m.totalCosts > 0) ...[
        const _Seccion('Costos y gastos'),
        if (m.purchaseCosts > 0)
          _Fila(etiqueta: 'Compras / insumos', valor: q(m.purchaseCosts), estilo: _Estilo.resta),
        if (m.operationalExpenses > 0)
          _Fila(etiqueta: 'Gastos operacionales', valor: q(m.operationalExpenses), estilo: _Estilo.resta),
        _Fila(
          etiqueta: 'Utilidad estimada',
          valor: q(m.operatingProfit),
          estilo: m.operatingProfit < 0 ? _Estilo.resta : _Estilo.suma,
          negrita: true,
        ),
      ],
      _Fila(etiqueta: 'Número de tickets', valor: '${m.totalOrders}', estilo: _Estilo.dato, separado: true),
      _Fila(etiqueta: 'Ticket promedio', valor: q(m.avgTicket), estilo: _Estilo.dato),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filas);
  }
}

enum _Estilo {
  /// Una cifra más: tinta, sin color.
  normal,

  /// La venta bruta: en negritas.
  fuerte,

  /// Lo que resta (descuentos, reembolsos, costos): rojo.
  resta,

  /// Lo que suma (propinas, envío, utilidad): verde.
  suma,

  /// El total cobrado: el de la línea marcada, en el color de acento.
  total,

  /// Tickets y promedio: la etiqueta apagada.
  dato,
}

class _Seccion extends StatelessWidget {
  final String titulo;
  const _Seccion(this.titulo);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
      child: Text(
        titulo.toUpperCase(),
        style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta;
  final String? nota;
  final String? prefijo;
  final String valor;
  final _Estilo estilo;
  final bool negrita;

  /// Un poco de aire antes (después del total, arranca el bloque de datos).
  final bool separado;

  /// La primera fila no lleva la línea de arriba.
  final bool sinLinea;

  const _Fila({
    required this.etiqueta,
    required this.valor,
    required this.estilo,
    this.nota,
    this.prefijo,
    this.negrita = false,
    this.separado = false,
    this.sinLinea = false,
  });

  @override
  Widget build(BuildContext context) {
    final total = estilo == _Estilo.total;
    final dato = estilo == _Estilo.dato;
    final fuerte = estilo == _Estilo.fuerte || total || negrita;

    final colorValor = switch (estilo) {
      _Estilo.resta => _C.bad,
      _Estilo.suma => _C.gift,
      _Estilo.total => _C.accent,
      _ => _C.ink,
    };
    final tamValor = total ? 19.0 : (fuerte ? 17.0 : 15.5);

    return Container(
      margin: EdgeInsets.only(top: separado ? 10 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      decoration: BoxDecoration(
        border: sinLinea
            ? null
            : Border(
                top: total
                    ? BorderSide(color: kInicioLineaFuerte, width: 2)
                    : BorderSide(color: _C.line),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (prefijo != null)
                      SizedBox(width: 16, child: Text(prefijo!, style: _t(15.5, FontWeight.w700, _C.muted))),
                    Flexible(
                      child: Text(
                        etiqueta,
                        style: _t(
                          15.5,
                          fuerte ? FontWeight.w700 : FontWeight.w400,
                          dato ? _C.muted : _C.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                if (nota != null) Text(nota!, style: _t(12.5, FontWeight.w500, _C.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // La cifra manda sobre la etiqueta, pero con una cantidad enorme se
          // achica en vez de salirse de la tarjeta.
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                style: _t(tamValor, fuerte || dato ? FontWeight.w700 : FontWeight.w600, colorValor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
