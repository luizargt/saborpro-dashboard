/// Gastos. Rediseño 2026-11-22 (`gastos.html` de saborpro_app, en su modo oscuro):
/// el total contra el período anterior, cuánto de lo vendido se fue en gastos, a
/// quién se le compra más, en qué insumos se va el dinero, qué subió de precio y
/// dónde sale más barato el mismo insumo, y el listado (que se abre para ver los
/// insumos de cada compra).
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa el
/// período ya armado ([GastosPeriodo]). Se prueba a 360dp en
/// test/presentation/widgets/gastos_view_test.dart.
///
/// OJO: los pares de tarjetas van en un `IntrinsicHeight` (misma altura): nada de
/// lo que llevan dentro puede usar `LayoutBuilder`.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/gastos_data.dart';
import 'inicio_ui.dart';
import 'resumen_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El color de "gasto" del diseño (`--exp`) y su fondo suave.
Color get _exp => _C.exp;
Color get _expTint => _C.expTint;

final _dinero = NumberFormat('#,##0.00', 'en_US');

/// Una sucursal de las que se ven, con el color con que se pinta en su barra.
class GastoSucursal {
  final String id;
  final String nombre;
  final Color color;
  const GastoSucursal(this.id, this.nombre, this.color);

  static List<Color> get paleta => [_C.accent, _C.gift, _C.warn, _C.don, _C.bad, _C.soft];

  static List<GastoSucursal> de(List<(String, String)> sucursales) => [
        for (var i = 0; i < sucursales.length; i++) GastoSucursal(sucursales[i].$1, sucursales[i].$2, paleta[i % paleta.length]),
      ];
}

class GastosBody extends StatefulWidget {
  final GastosPeriodo periodo;

  /// El período anterior, para comparar; nulo si no se pudo leer.
  final GastosPeriodo? anterior;

  /// Cómo se llama el período anterior ("septiembre 2026", "Ayer").
  final String vsEtiqueta;

  /// Lo vendido en el período (la venta bruta del Inicio) y por sucursal; nulo si
  /// no se sabe (la vista de año no trae el desglose por sucursal).
  final double? ventas;
  final Map<String, double>? ventasPorSucursal;

  /// Las sucursales que se ven. Con más de una se dibuja el reparto y cada compra
  /// dice de cuál es.
  final List<GastoSucursal> sucursales;

  /// El signo de la moneda de la vista.
  final String signo;

  const GastosBody({
    super.key,
    required this.periodo,
    required this.anterior,
    required this.vsEtiqueta,
    required this.ventas,
    required this.sucursales,
    required this.signo,
    this.ventasPorSucursal,
  });

  @override
  State<GastosBody> createState() => _GastosBodyState();
}

class _GastosBodyState extends State<GastosBody> {
  final _busqueda = TextEditingController();
  final _llaveBusqueda = GlobalKey();
  final _abiertas = <String>{};
  String _q = '';

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  String _m(double v) => '${widget.signo}${_dinero.format(v)}';

  void _buscar(String q) => setState(() {
        _q = q.trim();
        if (_busqueda.text != q) _busqueda.text = q;
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final pad = ancho < 640 ? 16.0 : 20.0;
      final dos = ancho > 980;
      const gap = SizedBox(height: 14);
      final p = widget.periodo;

      Widget par(Widget a, Widget b, {int fa = 1, int fb = 1}) => dos
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(flex: fa, child: a), const SizedBox(width: 14), Expanded(flex: fb, child: b)],
              ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, gap, b]);

      if (!p.hayAlgo) {
        return _Desplazable(
          pad: pad,
          alto: c,
          hijo: _Tarjeta(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 50),
            child: Center(child: Text('No hay gastos en este período', textAlign: TextAlign.center, style: TextStyle(color: _C.muted, fontSize: 14.5))),
          ),
        );
      }

      final varias = widget.sucursales.length > 1;
      final (sinN, sinTotal) = AnalisisGastos.sinProveedor(p.compras);
      final total = p.total;

      final contenido = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          par(
            _Total(periodo: p, anterior: widget.anterior, vs: widget.vsEtiqueta, sucursales: widget.sucursales, m: _m),
            _VsVentas(
              signo: widget.signo,
              total: total,
              ventas: widget.ventas,
              porSucursal: widget.ventasPorSucursal,
              periodo: p,
              sucursales: widget.sucursales,
              m: _m,
            ),
            fa: 10,
            fb: 14,
          ),
          if (sinN > 0) ...[
            gap,
            _SinProveedor(
              n: sinN,
              total: sinTotal,
              pct: total > 0 ? (sinTotal / total * 100).round() : 0,
              m: _m,
              onVer: () {
                _buscar('Sin proveedor');
                final ctx = _llaveBusqueda.currentContext;
                if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
              },
            ),
          ],
          gap,
          par(
            _Proveedores(compras: p.compras, m: _m),
            _TopInsumos(compras: p.compras, m: _m),
          ),
          gap,
          par(
            _Subieron(subieron: AnalisisGastos.subieron(p.compras, widget.anterior?.compras ?? const []), hayAnterior: widget.anterior != null, m: _m),
            _Comparar(items: AnalisisGastos.comparar(p.compras), m: _m),
          ),
          gap,
          _Buscador(key: _llaveBusqueda, controlador: _busqueda, onCambio: _buscar, onBorrar: () => _buscar('')),
          gap,
          _Listado(
            periodo: p,
            consulta: _q,
            sucursales: widget.sucursales,
            varias: varias,
            abiertas: _abiertas,
            onAbrir: (k) => setState(() => _abiertas.contains(k) ? _abiertas.remove(k) : _abiertas.add(k)),
            m: _m,
          ),
        ],
      );
      return _Desplazable(pad: pad, alto: c, hijo: contenido);
    });
  }
}

/// El cuerpo desplazable; con poco que mostrar, igual llena el alto (el cambio de
/// sucursal entrega restricciones sueltas y lo dejaba centrado).
class _Desplazable extends StatelessWidget {
  final double pad;
  final BoxConstraints alto;
  final Widget hijo;
  const _Desplazable({required this.pad, required this.alto, required this.hijo});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: alto.hasBoundedHeight ? alto.maxHeight : 0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [hijo]),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Tarjeta({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 18)});

  @override
  Widget build(BuildContext context) =>
      Container(padding: padding, decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)), child: child);
}

/// "↑ 12%" / "↓ 5%": subir el gasto va en el color de gasto; bajar, en verde.
class _Cambio extends StatelessWidget {
  final int pct;
  final bool chico;
  const _Cambio(this.pct, {this.chico = false});

  @override
  Widget build(BuildContext context) {
    final sube = pct > 0;
    final igual = pct == 0;
    final color = igual ? _C.muted : (sube ? _exp : _C.gift);
    final fondo = igual ? _C.subtle : (sube ? _expTint : _C.giftTint);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: chico ? 6 : 9, vertical: chico ? 0 : 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(igual ? Icons.remove_rounded : (sube ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded), size: chico ? 12 : 13, color: color),
          const SizedBox(width: 3),
          // Contra un período casi vacío el % es absurdo (miles de millones): se acota.
          Text(pct > 999 ? '>999%' : '${pct.abs()}%', style: _t(chico ? 11.5 : 12.5, FontWeight.w700, color)),
        ],
      ),
    );
  }
}

// ── TOTAL Y REPARTO POR SUCURSAL ─────────────────────────────────────────────

class _Total extends StatelessWidget {
  final GastosPeriodo periodo;
  final GastosPeriodo? anterior;
  final String vs;
  final List<GastoSucursal> sucursales;
  final String Function(double) m;

  const _Total({required this.periodo, required this.anterior, required this.vs, required this.sucursales, required this.m});

  @override
  Widget build(BuildContext context) {
    final p = periodo;
    final total = p.total;
    final cambio = anterior == null ? null : cambioPct(total, anterior!.total);
    final gastos = p.manuales.length + p.retiros.length;
    final detalle = [
      if (p.compras.isNotEmpty) '${p.compras.length} ${p.compras.length == 1 ? 'compra' : 'compras'}',
      if (gastos > 0) '$gastos ${gastos == 1 ? 'gasto' : 'gastos'}',
    ].join(' · ');
    final porSucursal = sucursales.length > 1 && total > 0;

    return _Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Total gastos del período', style: _t(13.5, FontWeight.w600, _C.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(m(total), maxLines: 1, style: _t(36, FontWeight.w800, _exp, height: 1.2)),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (cambio != null) _Cambio(cambio),
              Text(
                [if (anterior != null && anterior!.total > 0) 'vs $vs (${m(anterior!.total)})', detalle].where((e) => e.isNotEmpty).join(' · '),
                style: _t(13.5, FontWeight.w400, _C.muted),
              ),
            ],
          ),
          if (porSucursal) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  for (var i = 0; i < sucursales.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    if (p.totalEn(sucursales[i].id) > 0)
                      Expanded(
                        flex: (p.totalEn(sucursales[i].id) / total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: sucursales[i].color, child: const SizedBox.expand()),
                      ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final s in sucursales)
                  // Con montos enormes y nombres largos la entrada entera se achica en
                  // vez de salirse de la tarjeta.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted)),
                        ),
                        const SizedBox(width: 6),
                        Text(m(p.totalEn(s.id)), style: _t(12.5, FontWeight.w600, _C.ink)),
                        if (anterior != null && cambioPct(p.totalEn(s.id), anterior!.totalEn(s.id)) != null) ...[
                          const SizedBox(width: 6),
                          _Cambio(cambioPct(p.totalEn(s.id), anterior!.totalEn(s.id))!, chico: true),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── GASTOS CONTRA VENTAS ─────────────────────────────────────────────────────

class _VsVentas extends StatelessWidget {
  final String signo;
  final double total;
  final double? ventas;
  final Map<String, double>? porSucursal;
  final GastosPeriodo periodo;
  final List<GastoSucursal> sucursales;
  final String Function(double) m;

  const _VsVentas({
    required this.signo,
    required this.total,
    required this.ventas,
    required this.porSucursal,
    required this.periodo,
    required this.sucursales,
    required this.m,
  });

  @override
  Widget build(BuildContext context) {
    final r = AnalisisGastos.deCada100(total, ventas);
    if (r == null) {
      return _Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Gastos vs. ventas', style: _t(15, FontWeight.w700, _C.ink)),
            const SizedBox(height: 8),
            Text('No hubo ventas en este período para comparar.', style: _t(14, FontWeight.w400, _C.muted)),
          ],
        ),
      );
    }
    final ven = ventas!;
    final monedas = (r / 10).round().clamp(0, 10);
    Widget caja(String t, String v, {Color? color, bool ok = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w600, _C.muted)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: _t(15, FontWeight.w700, color ?? _C.ink))),
              ],
            ),
          ),
        );
    final despues = ven - total;

    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Gastos vs. ventas', style: _t(15, FontWeight.w700, _C.ink)),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: _t(16, FontWeight.w400, _C.ink, height: 1.4),
              children: [
                const TextSpan(text: 'De cada '),
                TextSpan(text: '${signo}100', style: _t(16, FontWeight.w700, _C.ink, height: 1.4)),
                const TextSpan(text: ' que vendiste, '),
                TextSpan(text: '$signo$r', style: _t(28, FontWeight.w800, _exp, height: 1.2)),
                const TextSpan(text: ' se fueron en gastos'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < 10; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              // Juntas y de 26 como máximo (con poco ancho se achican entre todas).
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 26, maxHeight: 26),
                  child: AspectRatio(aspectRatio: 1, child: DecoratedBox(decoration: BoxDecoration(color: i < monedas ? _exp : _C.subtle, shape: BoxShape.circle))),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            caja('Vendiste', m(ven)),
            const SizedBox(width: 8),
            caja('Gastaste', m(total), color: _exp),
            const SizedBox(width: 8),
            caja('Después de gastos', m(despues), color: despues >= 0 ? _C.gift : _C.bad),
          ]),
          if (sucursales.length > 1 && porSucursal != null) ...[
            const SizedBox(height: 10),
            for (final s in sucursales)
              if ((porSucursal![s.id] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    SizedBox(width: 96, child: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w400, _C.ink))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          height: 6,
                          child: Stack(children: [
                            Positioned.fill(child: ColoredBox(color: _C.subtle)),
                            FractionallySizedBox(
                              widthFactor: ((periodo.totalEn(s.id) / porSucursal![s.id]!) * 2).clamp(0.0, 1.0),
                              child: ColoredBox(color: s.color, child: const SizedBox.expand()),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      child: Text('${(periodo.totalEn(s.id) / porSucursal![s.id]! * 100).round()}%', textAlign: TextAlign.right, style: _t(13, FontWeight.w700, _C.ink)),
                    ),
                  ]),
                ),
          ],
        ],
      ),
    );
  }
}

// ── SIN PROVEEDOR ────────────────────────────────────────────────────────────

class _SinProveedor extends StatelessWidget {
  final int n;
  final double total;
  final int pct;
  final String Function(double) m;
  final VoidCallback onVer;

  const _SinProveedor({required this.n, required this.total, required this.pct, required this.m, required this.onVer});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _C.warnTint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onVer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.warning_amber_rounded, size: 19, color: _C.warn),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: _t(14, FontWeight.w400, _C.ink, height: 1.4),
                    children: [
                      TextSpan(text: '${m(total)} ($pct%)', style: _t(14, FontWeight.w700, _C.ink, height: 1.4)),
                      TextSpan(text: ' en $n ${n == 1 ? 'compra' : 'compras'} sin proveedor. Sin proveedor no se pueden comparar precios.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('Ver', style: _t(14, FontWeight.w700, _C.warn)),
              Icon(Icons.chevron_right_rounded, size: 18, color: _C.warn),
            ],
          ),
        ),
      ),
    );
  }
}

// ── PROVEEDORES E INSUMOS ────────────────────────────────────────────────────

/// Una fila con barra: número o nada, nombre, monto, % y la barra de abajo.
class _FilaBarra extends StatelessWidget {
  final int? numero;
  final String nombre;
  final bool apagado;
  final String monto;
  final int pct;
  final double fraccion;

  const _FilaBarra({this.numero, required this.nombre, this.apagado = false, required this.monto, required this.pct, required this.fraccion});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (numero != null) SizedBox(width: 22, child: Text('$numero', style: _t(13, FontWeight.w800, _C.soft))),
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14, FontWeight.w600, apagado ? _C.muted : _C.ink).copyWith(fontStyle: apagado ? FontStyle.italic : null),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(monto, maxLines: 1, style: _t(14, FontWeight.w700, _C.ink)),
                    SizedBox(width: 38, child: Text('$pct%', textAlign: TextAlign.right, style: _t(12, FontWeight.w500, _C.muted))),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(left: numero != null ? 22 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: _C.subtle)),
                  FractionallySizedBox(widthFactor: fraccion.clamp(0.0, 1.0), child: ColoredBox(color: _exp, child: SizedBox.expand())),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Proveedores extends StatelessWidget {
  final List<Compra> compras;
  final String Function(double) m;
  const _Proveedores({required this.compras, required this.m});

  @override
  Widget build(BuildContext context) {
    final top = AnalisisGastos.topProveedores(compras);
    final total = compras.fold(0.0, (s, c) => s + c.total);
    final mayor = top.isEmpty ? 1.0 : top.first.$2;
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¿A quién le compras más?', style: _t(15, FontWeight.w700, _C.ink)),
          const SizedBox(height: 8),
          if (top.isEmpty)
            Text('Sin compras', style: _t(14, FontWeight.w400, _C.muted))
          else
            for (final (n, v) in top)
              _FilaBarra(nombre: n, apagado: n == 'Sin proveedor', monto: m(v), pct: total > 0 ? (v / total * 100).round() : 0, fraccion: mayor > 0 ? v / mayor : 0),
        ],
      ),
    );
  }
}

class _TopInsumos extends StatelessWidget {
  final List<Compra> compras;
  final String Function(double) m;
  const _TopInsumos({required this.compras, required this.m});

  @override
  Widget build(BuildContext context) {
    final top = AnalisisGastos.topInsumos(compras);
    final total = compras.fold(0.0, (s, c) => s + c.total);
    final mayor = top.isEmpty ? 1.0 : top.first.$2;
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¿En qué se va el dinero?', style: _t(15, FontWeight.w700, _C.ink)),
          const SizedBox(height: 8),
          if (top.isEmpty)
            Text('Sin compras', style: _t(14, FontWeight.w400, _C.muted))
          else
            for (var i = 0; i < top.length; i++)
              _FilaBarra(
                numero: i + 1,
                nombre: top[i].$1,
                monto: m(top[i].$2),
                pct: total > 0 ? (top[i].$2 / total * 100).round() : 0,
                fraccion: mayor > 0 ? top[i].$2 / mayor : 0,
              ),
        ],
      ),
    );
  }
}

// ── PRECIOS ──────────────────────────────────────────────────────────────────

class _Subieron extends StatelessWidget {
  final List<SubidaPrecio> subieron;
  final bool hayAnterior;
  final String Function(double) m;
  const _Subieron({required this.subieron, required this.hayAnterior, required this.m});

  @override
  Widget build(BuildContext context) {
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // El rótulo a la derecha si caben los dos; si no, baja a otra línea.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            runSpacing: 2,
            spacing: 8,
            children: [
              Text('Subieron de precio', style: _t(15, FontWeight.w700, _C.ink)),
              Text('vs compra anterior', style: _t(12.5, FontWeight.w500, _C.muted)),
            ],
          ),
          const SizedBox(height: 8),
          if (subieron.isEmpty)
            Text(
              hayAnterior ? 'Ningún insumo subió de precio.' : 'No se pudo leer el período anterior para comparar precios.',
              style: _t(14, FontWeight.w400, _C.muted),
            )
          else
            for (var i = 0; i < subieron.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: _C.line))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subieron[i].insumo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w600, _C.ink)),
                          Text(
                            '${subieron[i].proveedor}${subieron[i].unidad.isEmpty ? '' : ' · por ${subieron[i].unidad}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _t(12.5, FontWeight.w400, _C.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(m(subieron[i].anterior), style: _t(13.5, FontWeight.w400, _C.soft).copyWith(decoration: TextDecoration.lineThrough)),
                              const SizedBox(width: 4),
                              Text(m(subieron[i].nuevo), style: _t(13.5, FontWeight.w700, _C.ink)),
                            ]),
                          ),
                          const SizedBox(height: 2),
                          _Cambio(subieron[i].pct),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Comparar extends StatelessWidget {
  final List<ComparaPrecio> items;
  final String Function(double) m;
  const _Comparar({required this.items, required this.m});

  @override
  Widget build(BuildContext context) {
    Widget opcion(String quien, double precio, bool mejor) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: mejor ? _C.giftTint : _C.subtle, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(quien, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12, FontWeight.w400, _C.muted)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(m(precio), maxLines: 1, style: _t(14.5, FontWeight.w700, mejor ? _C.gift : _C.ink))),
              ],
            ),
          ),
        );
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Mismo insumo, distinto precio', style: _t(15, FontWeight.w700, _C.ink)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('Nada que comparar en este período.', style: _t(14, FontWeight.w400, _C.muted))
          else
            for (var i = 0; i < items.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: _C.line))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(items[i].insumo, style: _t(14, FontWeight.w600, _C.ink)),
                    const SizedBox(height: 6),
                    Row(children: [opcion(items[i].mejor, items[i].precioMejor, true), const SizedBox(width: 8), opcion(items[i].otro, items[i].precioOtro, false)]),
                    const SizedBox(height: 6),
                    Text(
                      'Ahorras ${m(items[i].ahorro)} por cada ${items[i].cantidad} comprando con ${items[i].mejor}',
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

// ── BÚSQUEDA Y LISTADO ───────────────────────────────────────────────────────

class _Buscador extends StatelessWidget {
  final TextEditingController controlador;
  final ValueChanged<String> onCambio;
  final VoidCallback onBorrar;

  const _Buscador({super.key, required this.controlador, required this.onCambio, required this.onBorrar});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.line, width: 1.5)),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: _C.soft),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('gastos-buscar'),
              controller: controlador,
              onChanged: onCambio,
              cursorColor: _C.accent,
              style: _t(15.5, FontWeight.w400, _C.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Buscar proveedor, insumo o #número',
                hintStyle: _t(15, FontWeight.w400, _C.soft),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controlador,
            builder: (_, v, __) => v.text.isEmpty
                ? const SizedBox(width: 10)
                : IconButton(key: const Key('gastos-borrar'), onPressed: onBorrar, icon: Icon(Icons.close_rounded, size: 18, color: _C.muted), tooltip: 'Borrar'),
          ),
        ],
      ),
    );
  }
}

/// Las partes de un texto con lo que coincide con la búsqueda resaltado. Compara
/// sin acentos ni mayúsculas, carácter a carácter (el largo no cambia).
List<InlineSpan> _partes(String texto, String consulta, TextStyle estilo) {
  String plano(String t) => t.toLowerCase().split('').map((c) => const {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'}[c] ?? c).join();
  final q = plano(consulta.trim().replaceFirst(RegExp(r'^#'), ''));
  final i = q.isEmpty ? -1 : plano(texto).indexOf(q);
  if (i < 0 || i + q.length > texto.length) return [TextSpan(text: texto, style: estilo)];
  return [
    TextSpan(text: texto.substring(0, i), style: estilo),
    TextSpan(text: texto.substring(i, i + q.length), style: estilo.copyWith(backgroundColor: _C.accent.withValues(alpha: 0.35), color: _C.ink)),
    TextSpan(text: texto.substring(i + q.length), style: estilo),
  ];
}

/// Un texto con lo que coincide con la búsqueda resaltado.
Widget _resaltado(String texto, String consulta, TextStyle estilo, {int? maxLines}) {
  final partes = _partes(texto, consulta, estilo);
  if (partes.length == 1) return Text(texto, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: estilo);
  return Text.rich(TextSpan(children: partes), maxLines: maxLines, overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis);
}

class _Listado extends StatelessWidget {
  final GastosPeriodo periodo;
  final String consulta;
  final List<GastoSucursal> sucursales;
  final bool varias;
  final Set<String> abiertas;
  final ValueChanged<String> onAbrir;
  final String Function(double) m;

  const _Listado({
    required this.periodo,
    required this.consulta,
    required this.sucursales,
    required this.varias,
    required this.abiertas,
    required this.onAbrir,
    required this.m,
  });

  String _sucursal(String? id) {
    for (final s in sucursales) {
      if (s.id == id) return s.nombre;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final compras = AnalisisGastos.buscar(periodo.compras, consulta);
    final manuales = AnalisisGastos.buscarGastos(periodo.manuales, consulta);
    final retiros = AnalisisGastos.buscarGastos(periodo.retiros, consulta);
    if (compras.isEmpty && manuales.isEmpty && retiros.isEmpty) {
      return _Tarjeta(
        padding: const EdgeInsets.all(30),
        child: Center(child: Text('No encontramos “$consulta” en este período', textAlign: TextAlign.center, style: _t(14.5, FontWeight.w400, _C.muted))),
      );
    }

    Widget grupo(IconData icono, String titulo, int n, double total, List<Widget> filas, {Color? color, Color? fondo}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Container(width: 30, height: 30, decoration: BoxDecoration(color: fondo ?? _expTint, borderRadius: BorderRadius.circular(9)), child: Icon(icono, size: 17, color: color ?? _exp)),
                  const SizedBox(width: 10),
                  // El título toma lo que sobra (con Spacer + Flexible se repartían el
                  // espacio a medias y el total no llegaba al borde derecho).
                  Expanded(
                    child: Row(children: [
                      Flexible(child: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(16, FontWeight.w700, _C.ink))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
                        child: Text('$n', style: _t(12.5, FontWeight.w700, _C.muted)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(m(total), maxLines: 1, style: _t(16, FontWeight.w700, _C.ink))),
                  ),
                ],
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)),
              child: Column(children: filas),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compras.isNotEmpty)
          grupo(
            Icons.inventory_2_outlined,
            'Compras / insumos',
            compras.length,
            compras.fold(0.0, (s, c) => s + c.compra.total),
            [
              for (var i = 0; i < compras.length; i++)
                _FilaCompra(
                  coincide: compras[i],
                  consulta: consulta,
                  sucursal: varias ? _sucursal(compras[i].compra.sucursal) : '',
                  primera: i == 0,
                  abierta: abiertas.contains(compras[i].compra.llave),
                  onTap: () => onAbrir(compras[i].compra.llave),
                  m: m,
                ),
            ],
          ),
        if (manuales.isNotEmpty) ...[
          if (compras.isNotEmpty) const SizedBox(height: 16),
          grupo(
            Icons.receipt_long_outlined,
            'Gastos operacionales',
            manuales.length,
            manuales.fold(0.0, (s, g) => s + g.monto),
            [for (var i = 0; i < manuales.length; i++) _FilaGasto(gasto: manuales[i], consulta: consulta, sucursal: varias ? _sucursal(manuales[i].sucursal) : '', primera: i == 0, m: m)],
          ),
        ],
        if (retiros.isNotEmpty) ...[
          if (compras.isNotEmpty || manuales.isNotEmpty) const SizedBox(height: 16),
          grupo(
            Icons.account_balance_wallet_outlined,
            'Retiros de caja',
            retiros.length,
            retiros.fold(0.0, (s, g) => s + g.monto),
            [for (var i = 0; i < retiros.length; i++) _FilaGasto(gasto: retiros[i], consulta: consulta, sucursal: varias ? _sucursal(retiros[i].sucursal) : '', primera: i == 0, m: m)],
          ),
        ],
      ],
    );
  }
}

class _FilaCompra extends StatelessWidget {
  final CoincideCompra coincide;
  final String consulta;
  final String sucursal;
  final bool primera;
  final bool abierta;
  final VoidCallback onTap;
  final String Function(double) m;

  const _FilaCompra({
    required this.coincide,
    required this.consulta,
    required this.sucursal,
    required this.primera,
    required this.abierta,
    required this.onTap,
    required this.m,
  });

  @override
  Widget build(BuildContext context) {
    final c = coincide.compra;
    final n = c.lineas.length;
    // Lo que va después del número: "4 insumos · Chiquimula".
    final resto = [
      if (n > 0) '$n ${n == 1 ? 'insumo' : 'insumos'}',
      if (sucursal.isNotEmpty) sucursal,
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: _expTint, borderRadius: BorderRadius.circular(11)), child: Icon(Icons.inventory_2_outlined, size: 18, color: _exp)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _resaltado(
                          c.nombre,
                          consulta,
                          _t(14.5, FontWeight.w600, c.proveedor == null ? _C.muted : _C.ink).copyWith(fontStyle: c.proveedor == null ? FontStyle.italic : null),
                          maxLines: 2,
                        ),
                        if (coincide.lineas != null)
                          Text('Incluye: ${coincide.lineas!.map((l) => l.insumo).join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w600, _C.accent)),
                        Text.rich(
                          TextSpan(children: [
                            if (c.numero != null) ..._partes('#${c.numero}', consulta, _t(12.5, FontWeight.w700, _C.accent)),
                            ..._partes('${c.numero != null && resto.isNotEmpty ? ' · ' : ''}$resto', consulta, _t(12.5, FontWeight.w400, _C.muted)),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(m(c.total), maxLines: 1, style: _t(15, FontWeight.w700, _C.ink))),
                      ),
                      Text(AnalisisGastos.fechaLista(c.fecha), style: _t(12, FontWeight.w400, _C.muted)),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(abierta ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: _C.soft),
                ],
              ),
            ),
          ),
          if (abierta)
            Container(
              color: _C.subtle,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.lineas.isEmpty)
                    Text('Esta compra no trae el detalle de sus insumos.', style: _t(13, FontWeight.w400, _C.muted))
                  else ...[
                    Row(children: [
                      Expanded(flex: 5, child: Text('INSUMO', style: _t(11.5, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.5))),
                      Expanded(flex: 3, child: Text('CANTIDAD', style: _t(11.5, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.5))),
                      Expanded(flex: 3, child: Text('COSTO', textAlign: TextAlign.right, style: _t(11.5, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.5))),
                    ]),
                    for (final l in c.lineas)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 5, child: _resaltado(l.insumo, consulta, _t(13.5, FontWeight.w400, _C.ink))),
                          Expanded(flex: 3, child: Text(l.cantidadTexto, style: _t(13.5, FontWeight.w400, _C.muted))),
                          Expanded(
                            flex: 3,
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(m(l.costo), maxLines: 1, style: _t(13.5, FontWeight.w600, _C.ink))),
                          ),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 10),
                  Text(c.notas ?? 'Compra recibida en la despensa', style: _t(12, FontWeight.w500, _C.soft)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilaGasto extends StatelessWidget {
  final GastoLinea gasto;
  final String consulta;
  final String sucursal;
  final bool primera;
  final String Function(double) m;

  const _FilaGasto({required this.gasto, required this.consulta, required this.sucursal, required this.primera, required this.m});

  @override
  Widget build(BuildContext context) {
    final g = gasto;
    final partes = [
      if (g.concepto != g.categoria) g.categoria,
      if (g.esRetiro && g.cajero != null) 'Caja de ${g.cajero}',
      if (g.usuario != null) g.usuario!,
      if (sucursal.isNotEmpty) sucursal,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: _expTint, borderRadius: BorderRadius.circular(11)),
            child: Icon(g.esRetiro ? Icons.point_of_sale_outlined : Icons.receipt_long_outlined, size: 18, color: _exp),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resaltado(g.concepto, consulta, _t(14.5, FontWeight.w600, _C.ink), maxLines: 2),
                if (partes.isNotEmpty) _resaltado(partes.join(' · '), consulta, _t(12.5, FontWeight.w400, _C.muted), maxLines: 2),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(m(g.monto), maxLines: 1, style: _t(15, FontWeight.w700, _C.ink))),
              ),
              Text(AnalisisGastos.fechaLista(g.fecha), style: _t(12, FontWeight.w400, _C.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un aviso a todo el ancho (lo usa la pantalla para los estados de error).
class GastosAviso extends StatelessWidget {
  final String texto;
  const GastosAviso(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => AvisoTarjeta(icono: Icons.info_outline_rounded, texto: texto);
}
