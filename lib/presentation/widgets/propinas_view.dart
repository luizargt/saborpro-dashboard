/// El detalle de Propinas. Rediseño de pantalla nueva (propinas.html de
/// saborpro_app, en su modo oscuro): resumen, alerta, quién recibe propina, a qué
/// hora se deja más, por tipo de servicio, por tamaño de cuenta, por zona y por
/// método de pago.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa el
/// [PropinasReporte] ya armado. Se prueba a 360dp en
/// test/presentation/widgets/propinas_view_test.dart.
///
/// OJO: los pares de tarjetas van en un `IntrinsicHeight` (a la misma altura,
/// como la rejilla del diseño), así que nada de lo que hay dentro puede usar
/// `LayoutBuilder`: en depuración lanza y en producción el alto sale en cero.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show moneda;
import '../../data/models/atencion_inicio.dart' show ParteTexto;
import '../../data/models/propinas_data.dart';
import 'inicio_ui.dart';
import 'resumen_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

final _fmt = NumberFormat('#,##0.00', 'en_US');
final _fmt0 = NumberFormat('#,##0', 'en_US');
String _q(double v) => '$moneda${_fmt.format(v)}';
String _q0(double v) => '$moneda${_fmt0.format(v)}';
String _pct(double v) => '${v.toStringAsFixed(1)}%';
String _pedidos(int n) => '$n pedido${n == 1 ? '' : 's'}';

class PropinasReportBody extends StatelessWidget {
  final PropinasReporte reporte;

  /// Todas las propinas del período: las de los pedidos y las metidas a la caja.
  /// Es la cifra que dice el Inicio.
  final double totalPeriodo;

  /// De [totalPeriodo], lo que se metió a la caja como ingreso (no es de ningún
  /// pedido y no está en los desgloses).
  final double enCaja;

  /// Contra qué período se compara ("Ayer", "9–15 nov").
  final String vsEtiqueta;

  /// Falso en la vista de año: no están los pedidos y solo se sabe el total.
  final bool conDetalle;

  /// El período se leyó incompleto (el Inicio llegó a su tope de pedidos).
  final bool incompleto;

  const PropinasReportBody({
    super.key,
    required this.reporte,
    required this.totalPeriodo,
    this.enCaja = 0,
    this.vsEtiqueta = '',
    this.conDetalle = true,
    this.incompleto = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final pad = ancho < 640 ? 16.0 : 20.0;
      final dos = ancho > 980;
      const gap = SizedBox(height: 16);
      final r = reporte;
      final tasa = r.tasa;
      final alerta = r.meseroConPocaPropina;
      // Lo que mide la gráfica de horas por dentro: el ancho de su tarjeta (la mitad
      // del ancho si van de dos en dos) menos el relleno de la tarjeta. Se calcula
      // aquí y no con un LayoutBuilder dentro de la tarjeta: los pares van en un
      // IntrinsicHeight, donde un LayoutBuilder no puede ir.
      final relleno = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono ? 18.0 : 22.0;
      final anchoTarjeta = dos ? (ancho - 2 * pad - 16) / 2 : ancho - 2 * pad;
      final anchoGrafica = anchoTarjeta - 2 * relleno;

      final lista = SingleChildScrollView(
        // Siempre desplazable: el RefreshIndicator lo necesita aunque no haya
        // casi nada que mostrar.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Resumen(
              reporte: r,
              totalPeriodo: totalPeriodo,
              enCaja: enCaja,
              vsEtiqueta: vsEtiqueta,
              completo: conDetalle && r.hayPedidos,
              ancho: ancho,
            ),
            if (incompleto && conDetalle) ...[
              gap,
              AvisoTarjeta(
                icono: Icons.warning_amber_rounded,
                color: _C.warn,
                texto: 'Este período tiene más pedidos de los que se pueden leer de una vez: '
                    'el detalle (y la tarjeta del Inicio) pueden quedar cortos. '
                    'Elegí un período más corto para verlo completo.',
              ),
            ],
            if (!conDetalle) ...[
              gap,
              const AvisoTarjeta(
                icono: Icons.info_outline_rounded,
                texto: 'En la vista de año no se leen los pedidos, así que solo se sabe el total. '
                    'Elegí un mes para ver quién recibió la propina, a qué hora y por tipo de servicio.',
              ),
            ] else if (!r.hayPedidos) ...[
              gap,
              const InicioCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: _TextoCentrado('No hubo ventas en este período.')),
                ),
              ),
            ] else ...[
              if (alerta != null) ...[gap, _Alerta(mesero: alerta, promedio: tasa)],
              gap,
              _Par(dos: dos, a: _CardMeseros(reporte: r), b: _CardHoras(reporte: r, ancho: anchoGrafica)),
              gap,
              _Par(
                dos: dos,
                a: _CardGrupo(
                  titulo: 'Por tipo de servicio',
                  grupos: r.porTipo,
                  promedio: tasa,
                  icono: _iconoTipo,
                ),
                b: _CardGrupo(
                  titulo: 'Según el tamaño de la cuenta',
                  grupos: r.porTamano,
                  promedio: tasa,
                  icono: (_) => Icons.receipt_long_rounded,
                ),
              ),
              gap,
              _Par(
                dos: dos,
                a: r.porZona != null && r.porZona!.isNotEmpty
                    ? _CardGrupo(
                        titulo: 'Por zona',
                        nota: 'Solo pedidos en mesa',
                        grupos: r.porZona!,
                        promedio: tasa,
                        icono: (_) => Icons.place_outlined,
                      )
                    : null,
                b: _CardMetodo(reporte: r),
              ),
            ],
          ],
        ),
      );

      // Con poco que mostrar el contenido es más bajo que la pantalla. El cambio
      // de sucursal (un AnimatedSwitcher) entrega restricciones sueltas y un
      // SingleChildScrollView mide lo que mide su contenido: sin esto quedaba
      // CENTRADO en vertical, con un hueco enorme bajo las pestañas.
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
        child: lista,
      );
    });
  }
}

IconData _iconoTipo(String nombre) => switch (nombre) {
      'Mesa' => Icons.table_restaurant_rounded,
      'Para llevar' => Icons.shopping_bag_outlined,
      'Domicilio' => Icons.delivery_dining_rounded,
      'Venta rápida' => Icons.flash_on_rounded,
      'Habitación' => Icons.hotel_rounded,
      _ => Icons.receipt_long_rounded,
    };

/// Dos tarjetas a la misma altura y, con poco ancho, una debajo de otra. Con una
/// sola, ocupa todo el ancho.
class _Par extends StatelessWidget {
  final bool dos;
  final Widget? a;
  final Widget? b;

  const _Par({required this.dos, required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final primera = a;
    final segunda = b;
    final partes = <Widget>[if (primera != null) primera, if (segunda != null) segunda];
    if (partes.length == 1) return partes.single;
    if (!dos) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [partes[0], const SizedBox(height: 16), partes[1]],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: partes[0]), const SizedBox(width: 16), Expanded(child: partes[1])],
      ),
    );
  }
}

class _TextoCentrado extends StatelessWidget {
  final String texto;
  const _TextoCentrado(this.texto);

  @override
  Widget build(BuildContext context) =>
      Text(texto, textAlign: TextAlign.center, style: _t(14.5, FontWeight.w400, _C.muted));
}

// ── RESUMEN ──────────────────────────────────────────────────────────────────

class _Resumen extends StatelessWidget {
  final PropinasReporte reporte;
  final double totalPeriodo;
  final double enCaja;
  final String vsEtiqueta;

  /// Con las cuatro cifras; si no, solo la del total.
  final bool completo;
  final double ancho;

  const _Resumen({
    required this.reporte,
    required this.totalPeriodo,
    required this.enCaja,
    required this.vsEtiqueta,
    required this.completo,
    required this.ancho,
  });

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    final telefono = ResumenCard.esTelefono(ancho);
    final cambio = r.cambioPct;

    return ResumenCard(
      ancho: ancho,
      celdas: [
        ResumenCelda(
          etiqueta: 'Propinas del período',
          valor: _q(totalPeriodo),
          colorValor: _C.gift,
          sub: [
            if (cambio != null) _Variacion(cambio: cambio, vs: vsEtiqueta, telefono: telefono),
            // Lo metido a la caja no es de ningún pedido: se dice, para que el total
            // cuadre con la suma de lo de abajo.
            if (enCaja > 0)
              Text(
                'Incluye ${_q(enCaja)} metidas a la caja',
                style: _t(telefono ? 12 : 12.5, FontWeight.w400, _C.muted),
              ),
          ],
        ),
        if (completo) ...[
          ResumenCelda(
            etiqueta: 'Propina promedio',
            valor: _pct(r.tasa),
            sub: [ResumenCard.linea('sobre ventas de ${_q(r.ventas)}', ancho)],
          ),
          ResumenCelda(
            etiqueta: 'Por pedido',
            valor: _q(r.porPedido),
            sub: [ResumenCard.linea(_pedidos(r.pedidos), ancho)],
          ),
          ResumenCelda(
            etiqueta: 'Sin propina',
            valor: '${r.sinPropina}',
            // Más de uno de cada diez sin propina ya es algo que mirar.
            colorValor: r.pctSinPropina > 10 ? _C.warn : _C.ink,
            sub: [ResumenCard.linea('${r.pctSinPropina.round()}% de los pedidos', ancho)],
          ),
        ],
      ],
    );
  }
}

/// "↑ 25% vs Ayer". La flecha es un ícono y no el carácter: no todas las letras
/// la traen y dependería de una fuente de respaldo. Con menos de medio punto de
/// diferencia dice que quedó igual, en vez de "↑ 0%".
class _Variacion extends StatelessWidget {
  final double cambio;
  final String vs;
  final bool telefono;

  const _Variacion({required this.cambio, required this.vs, required this.telefono});

  @override
  Widget build(BuildContext context) {
    final igual = cambio.abs() < 0.5;
    final sube = cambio > 0;
    final color = igual ? _C.muted : (sube ? _C.gift : _C.bad);
    final texto = igual ? 'Igual que $vs' : '${cambio.abs().toStringAsFixed(0)}% vs $vs';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(igual ? Icons.remove_rounded : (sube ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            size: 14, color: color),
        const SizedBox(width: 2),
        Flexible(child: Text(texto, style: _t(telefono ? 12 : 13, FontWeight.w700, color))),
      ],
    );
  }
}

// ── AVISOS ───────────────────────────────────────────────────────────────────

class _Alerta extends StatelessWidget {
  final GrupoPropina mesero;
  final double promedio;

  const _Alerta({required this.mesero, required this.promedio});

  @override
  Widget build(BuildContext context) {
    return AlertaAmbar(
      partes: [
        ParteTexto(mesero.nombre, negrita: true),
        ParteTexto(
          ' recibe ${_pct(mesero.tasa)} de propina, menos que el promedio (${_pct(promedio)}).'
          '${mesero.sinPropina > 0 ? ' ${mesero.sinPropina} de sus pedidos salieron sin propina.' : ''}',
        ),
      ],
    );
  }
}

// ── ¿QUIÉN RECIBE PROPINA? ───────────────────────────────────────────────────

class _CardMeseros extends StatelessWidget {
  final PropinasReporte reporte;
  const _CardMeseros({required this.reporte});

  /// Con muchos meseros la lista no se vuelve interminable.
  static const _tope = 15;

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    final mostrados = r.meseros.take(_tope).toList();
    final total = r.meseros.fold<double>(0, (s, m) => s + m.propinas);
    final mayor = mostrados.isEmpty ? 0.0 : mostrados.first.propinas;

    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InicioTituloTarjeta(titulo: '¿Quién recibe propina?'),
          for (var i = 0; i < mostrados.length; i++)
            _FilaMesero(
              mesero: mostrados[i],
              mayor: mayor,
              total: total,
              promedio: r.tasa,
              primera: i == 0,
            ),
          if (r.meseros.length > _tope)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'y ${r.meseros.length - _tope} más con menos propina',
                style: _t(13, FontWeight.w400, _C.muted),
              ),
            ),
        ],
      ),
    );
  }
}

String _iniciales(String nombre) {
  final p = nombre.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final i = p.map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  return i.isEmpty ? '?' : i;
}

class _FilaMesero extends StatelessWidget {
  final GrupoPropina mesero;
  final double mayor;
  final double total;
  final double promedio;
  final bool primera;

  const _FilaMesero({
    required this.mesero,
    required this.mayor,
    required this.total,
    required this.promedio,
    required this.primera,
  });

  @override
  Widget build(BuildContext context) {
    final m = mesero;
    final alta = m.tasa >= promedio;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _C.tint, shape: BoxShape.circle),
            child: Text(_iniciales(m.nombre), style: _t(14, FontWeight.w700, _C.accent, height: 1.0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, _C.ink)),
                Text(
                  '${_pedidos(m.pedidos)} · vendió ${_q(m.ventas)}',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Pildora('${_pct(m.tasa)} de propina', alta: alta),
                    if (m.sinPropina > 0) _Pildora('${m.sinPropina} sin propina', alta: false),
                  ],
                ),
                _Barra(fraccion: mayor > 0 ? m.propinas / mayor : 0, color: _C.gift),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(_q(m.propinas), maxLines: 1, style: _t(15, FontWeight.w700, _C.gift)),
                ),
                Text(
                  '${total > 0 ? (m.propinas / total * 100).round() : 0}% del total',
                  textAlign: TextAlign.right,
                  style: _t(12, FontWeight.w400, _C.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pildora extends StatelessWidget {
  final String texto;
  final bool alta;
  const _Pildora(this.texto, {required this.alta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: alta ? _C.giftTint : _C.warnTint, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: _t(11.5, FontWeight.w700, alta ? _C.gift : _C.warn, height: 1.3)),
    );
  }
}

/// La barra fina de las filas: lleno de [color] sobre el fondo suave.
class _Barra extends StatelessWidget {
  final double fraccion;
  final Color color;
  const _Barra({required this.fraccion, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: _C.subtle)),
              FractionallySizedBox(
                widthFactor: fraccion.clamp(0.0, 1.0),
                child: ColoredBox(color: color, child: const SizedBox.expand()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ¿A QUÉ HORA? ─────────────────────────────────────────────────────────────

class _CardHoras extends StatelessWidget {
  final PropinasReporte reporte;

  /// Lo que mide la gráfica por dentro (ver [PropinasReportBody]).
  final double ancho;

  const _CardHoras({required this.reporte, required this.ancho});

  /// "1 PM". Con 24 (el final de la hora 23) da "12 AM", no "12 PM".
  static String _hora12(int h) {
    final x = h % 24;
    return '${((x + 11) % 12) + 1} ${x < 12 ? 'AM' : 'PM'}';
  }

  static String _etiqueta(int h) => '${((h + 11) % 12) + 1}${h < 12 ? 'a' : 'p'}';

  @override
  Widget build(BuildContext context) {
    final horas = reporte.horas;
    final pico = reporte.horaPico;
    final mayor = pico?.propinas ?? 0.0;
    // Si no caben todos los rótulos ("12p", "10a" miden unos 24 px con la letra
    // normal) se muestra uno de cada tantos. A la medida de cada barra y a la
    // letra que tenga el teléfono.
    final letra = MediaQuery.textScalerOf(context).scale(11) / 11;
    final porBarra = horas.isEmpty ? ancho : ancho / horas.length;
    final paso = porBarra <= 0 ? 1 : math.max(1, (24 * letra / porBarra).ceil());

    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InicioTituloTarjeta(
            titulo: '¿A qué hora se deja más propina?',
            nota: pico == null ? null : 'La mejor hora: ${_hora12(pico.hora)} – ${_hora12(pico.hora + 1)}',
          ),
          SizedBox(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < horas.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: horas.length > 14 ? 1.5 : 2.5),
                        child: _Barra24(
                          hora: horas[i],
                          mayor: mayor,
                          pico: pico != null && horas[i].hora == pico.hora,
                          etiqueta: i % paso == 0 ? _etiqueta(horas[i].hora) : '',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Barra24 extends StatelessWidget {
  final HoraPropina hora;
  final double mayor;
  final bool pico;
  final String etiqueta;

  const _Barra24({required this.hora, required this.mayor, required this.pico, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    final alto = mayor > 0 ? (hora.propinas / mayor * 160).clamp(3.0, 160.0) : 3.0;
    return Tooltip(
      message: '${_CardHoras._hora12(hora.hora)}: ${_q(hora.propinas)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // El valor se ve solo en la hora pico (el resto, al pasar el ratón o
          // mantener el dedo).
          if (pico)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_q0(hora.propinas), maxLines: 1, style: _t(11, FontWeight.w700, _C.ink)),
            ),
          if (pico) const SizedBox(height: 4),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 34),
            height: alto,
            decoration: BoxDecoration(
              color: pico ? _C.accent : _C.gift.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 14,
            child: etiqueta.isEmpty
                ? null
                : OverflowBox(
                    maxWidth: 40,
                    child: Text(etiqueta, maxLines: 1, style: _t(11, FontWeight.w400, _C.muted, height: 1.2)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── GRUPOS (TIPO, TAMAÑO, ZONA) ──────────────────────────────────────────────

class _CardGrupo extends StatelessWidget {
  final String titulo;
  final String? nota;
  final List<GrupoPropina> grupos;
  final double promedio;
  final IconData Function(String nombre) icono;

  const _CardGrupo({
    required this.titulo,
    this.nota,
    required this.grupos,
    required this.promedio,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    final mayor = grupos.fold<double>(0, (m, g) => g.tasa > m ? g.tasa : m);
    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InicioTituloTarjeta(titulo: titulo, nota: nota),
          for (var i = 0; i < grupos.length; i++)
            _FilaGrupo(grupo: grupos[i], mayorTasa: mayor, promedio: promedio, icono: icono(grupos[i].nombre), primera: i == 0),
        ],
      ),
    );
  }
}

class _FilaGrupo extends StatelessWidget {
  final GrupoPropina grupo;
  final double mayorTasa;
  final double promedio;
  final IconData icono;
  final bool primera;

  const _FilaGrupo({
    required this.grupo,
    required this.mayorTasa,
    required this.promedio,
    required this.icono,
    required this.primera,
  });

  @override
  Widget build(BuildContext context) {
    final g = grupo;
    final color = g.tasa >= promedio ? _C.gift : _C.warn;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _C.subtle, shape: BoxShape.circle),
            child: Icon(icono, size: 19, color: _C.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(g.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, _C.ink)),
                Text(
                  '${_pedidos(g.pedidos)} · propina ${_q(g.propinas)}${g.sinPropina > 0 ? ' · ${g.sinPropina} sin propina' : ''}',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
                _Barra(fraccion: mayorTasa > 0 ? g.tasa / mayorTasa : 0, color: color),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(_pct(g.tasa), maxLines: 1, style: _t(15, FontWeight.w700, color)),
                ),
                Text('de propina', style: _t(12, FontWeight.w400, _C.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TARJETA Y EFECTIVO ───────────────────────────────────────────────────────

class _CardMetodo extends StatelessWidget {
  final PropinasReporte reporte;
  const _CardMetodo({required this.reporte});

  static Color _color(String nombre) => switch (nombre) {
        'Tarjeta' => _C.don,
        'Efectivo' => _C.gift,
        _ => _C.accent,
      };

  @override
  Widget build(BuildContext context) {
    final r = reporte;
    final total = r.porMetodo.fold<double>(0, (s, g) => s + g.propinas);
    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InicioTituloTarjeta(titulo: 'Tarjeta y efectivo'),
          // Cuánto de la propina entró por cada método.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final g in r.porMetodo)
                    if (total > 0 && g.propinas > 0)
                      Expanded(flex: (g.propinas / total * 1000).round().clamp(1, 1000), child: ColoredBox(color: _color(g.nombre), child: const SizedBox.expand())),
                  if (total <= 0) Expanded(child: ColoredBox(color: _C.subtle, child: SizedBox.expand())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < r.porMetodo.length; i++)
            _FilaMetodo(grupo: r.porMetodo[i], total: total, primera: i == 0),
        ],
      ),
    );
  }
}

class _FilaMetodo extends StatelessWidget {
  final GrupoPropina grupo;
  final double total;
  final bool primera;

  const _FilaMetodo({required this.grupo, required this.total, required this.primera});

  @override
  Widget build(BuildContext context) {
    final g = grupo;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: _CardMetodo._color(g.nombre), borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(g.nombre, style: _t(15, FontWeight.w600, _C.ink)),
                Text(
                  '${_pedidos(g.pedidos)} · ${_pct(g.tasa)} de propina',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(_q(g.propinas), maxLines: 1, style: _t(15, FontWeight.w700, _C.ink)),
                ),
                Text(
                  '${total > 0 ? (g.propinas / total * 100).round() : 0}% del total',
                  textAlign: TextAlign.right,
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
