/// El detalle de un cierre de caja. Rediseño 2026-11-21 (`cierres-caja.html` de
/// saborpro_app, en su modo oscuro): el encabezado con sus pestañas, el resumen,
/// quién vendió, la tabla de pedidos con sus filtros y los gastos.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla carga los
/// pedidos de la caja y se los pasa ya leídos ([DetalleCaja]). Se prueba a 360dp
/// en test/presentation/widgets/detalle_caja_view_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/cash_register_summary.dart';
import '../../data/models/cierres_caja.dart' show fechaCorta, formatoMonto, inicialesDe;
import '../../data/models/detalle_caja.dart';
import 'resumen_ui.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

final _hora = DateFormat('hh:mm a');

String _q(String signo, double v) => formatoMonto(signo, v);
String _pedidos(int n) => '$n pedido${n == 1 ? '' : 's'}';
bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

enum PestanaCaja { pedidos, gastos }

// ── ENCABEZADO ───────────────────────────────────────────────────────────────

/// Regresar, quién y cuándo, y las pestañas Pedidos / Gastos. En el teléfono las
/// pestañas bajan a su propia línea, a todo el ancho.
class DetalleCajaEncabezado extends StatelessWidget {
  final CashRegisterSummary caja;
  final PestanaCaja pestana;
  final ValueChanged<PestanaCaja> onPestana;
  final VoidCallback onRegresar;

  /// Cuántos pedidos tiene; nulo mientras se cargan (la pestaña no dice cuántos).
  final int? pedidos;
  final int gastos;

  const DetalleCajaEncabezado({
    super.key,
    required this.caja,
    required this.pestana,
    required this.onPestana,
    required this.onRegresar,
    required this.pedidos,
    required this.gastos,
  });

  String get _subtitulo {
    final sucursal = caja.locationName;
    final donde = sucursal != null && sucursal.isNotEmpty ? ' · $sucursal' : '';
    String f(DateTime d) => fechaCorta(d);
    final cerrada = caja.closedAt;
    if (cerrada == null) return 'Abierta desde ${f(caja.openedAt)}, ${_hora.format(caja.openedAt)}$donde';
    // La fecha solo cuando el corte no cae en un solo día natural (o no es de hoy,
    // que es lo que el historial ya dice).
    final dia = '${f(caja.openedAt)} · ';
    final fin = _mismoDia(caja.openedAt, cerrada) ? _hora.format(cerrada) : '${f(cerrada)}, ${_hora.format(cerrada)}';
    return '$dia${_hora.format(caja.openedAt)} → $fin$donde';
  }

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width < 640;
    final regresar = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: _C.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onRegresar,
          child: Tooltip(message: 'Regresar', child: Icon(Icons.arrow_back_rounded, color: _C.ink, size: 22)),
        ),
      ),
    );
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caja.userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _t(telefono ? 18 : 20, FontWeight.w700, _C.ink),
        ),
        Text(_subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w400, _C.muted)),
      ],
    );
    final pestanas = _Pestanas(
      pestana: pestana,
      onPestana: onPestana,
      pedidos: pedidos,
      gastos: gastos,
      completo: telefono,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: telefono
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [regresar, const SizedBox(width: 10), Expanded(child: titulo)]),
                const SizedBox(height: 10),
                pestanas,
              ],
            )
          : Row(children: [regresar, const SizedBox(width: 14), Expanded(child: titulo), const SizedBox(width: 14), pestanas]),
    );
  }
}

class _Pestanas extends StatelessWidget {
  final PestanaCaja pestana;
  final ValueChanged<PestanaCaja> onPestana;
  final int? pedidos;
  final int gastos;
  final bool completo;

  const _Pestanas({
    required this.pestana,
    required this.onPestana,
    required this.pedidos,
    required this.gastos,
    required this.completo,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton(PestanaCaja p, String texto) {
      final activa = p == pestana;
      final b = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPestana(p),
        child: Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: completo ? 8 : 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: activa ? _C.ink : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(14.5, FontWeight.w600, activa ? _C.card : _C.muted),
          ),
        ),
      );
      return completo ? Expanded(child: b) : b;
    }

    final botones = [
      boton(PestanaCaja.pedidos, pedidos == null ? 'Pedidos' : 'Pedidos ($pedidos)'),
      const SizedBox(width: 6),
      boton(PestanaCaja.gastos, 'Gastos ($gastos)'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: completo ? MainAxisSize.max : MainAxisSize.min, children: botones),
    );
  }
}

// ── CUERPO ───────────────────────────────────────────────────────────────────

class DetalleCajaBody extends StatefulWidget {
  final CashRegisterSummary caja;
  final DetalleCaja detalle;
  final List<GastoCaja> gastos;
  final PestanaCaja pestana;

  /// Los pedidos todavía se están leyendo.
  final bool cargando;

  /// No se pudieron leer los pedidos. Se dice: no se muestra como "sin pedidos",
  /// porque la caja pudo tener cientos.
  final bool error;
  final VoidCallback? onReintentar;

  /// El signo de la moneda de la sucursal de la caja.
  final String signo;

  const DetalleCajaBody({
    super.key,
    required this.caja,
    required this.detalle,
    required this.gastos,
    required this.pestana,
    required this.signo,
    this.cargando = false,
    this.error = false,
    this.onReintentar,
  });

  @override
  State<DetalleCajaBody> createState() => _DetalleCajaBodyState();
}

class _DetalleCajaBodyState extends State<DetalleCajaBody> {
  String _filtro = FiltroPedidos.todos;
  String? _usuario;

  @override
  void didUpdateWidget(DetalleCajaBody old) {
    super.didUpdateWidget(old);
    // Si llegaron otros pedidos y el filtro ya no existe, se vuelve a "Todos".
    if (!identical(old.detalle, widget.detalle) && !widget.detalle.filtros.any((f) => f.id == _filtro)) {
      _filtro = FiltroPedidos.todos;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final pad = ancho < 640 ? 16.0 : 20.0;
      const gap = SizedBox(height: 16);

      Widget contenido;
      if (widget.cargando) {
        contenido = Padding(
          padding: EdgeInsets.symmetric(vertical: 100),
          child: Center(child: CircularProgressIndicator(color: _C.accent)),
        );
      } else if (widget.pestana == PestanaCaja.gastos) {
        contenido = _TarjetaGastos(gastos: widget.gastos, signo: widget.signo, ancho: ancho);
      } else if (widget.error) {
        contenido = _ErrorPedidos(onReintentar: widget.onReintentar);
      } else if (widget.detalle.pedidos.isEmpty) {
        contenido = const _Vacio(titulo: 'Sin pedidos en esta caja', texto: 'No hay cobros en el tiempo que estuvo abierta.');
      } else {
        final d = widget.detalle;
        final t = d.totales;
        final s = widget.signo;
        final usuarios = d.usuarios;
        final lista = d.filtrar(_filtro, usuario: _usuario);
        contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResumenCard(
              ancho: ancho,
              celdas: [
                ResumenCelda(
                  etiqueta: 'Total pagado',
                  valor: _q(s, t.total),
                  sub: [ResumenCard.linea('${_pedidos(t.pedidos)} · prom. ${_q(s, d.promedio)}', ancho)],
                ),
                ResumenCelda(
                  etiqueta: 'Descuentos',
                  valor: _q(s, -t.descuentos),
                  colorValor: t.descuentos > 0 ? _C.bad : _C.muted,
                  sub: [ResumenCard.linea(_pedidos(d.conDescuento), ancho)],
                ),
                ResumenCelda(
                  etiqueta: 'Propinas',
                  valor: _q(s, t.propinas),
                  colorValor: t.propinas > 0 ? _C.gift : _C.muted,
                  sub: [ResumenCard.linea('${d.propinaPct.round()}% del subtotal', ancho)],
                ),
                ResumenCelda(
                  etiqueta: 'Cortesías',
                  valor: _q(s, t.cortesias),
                  colorValor: t.cortesias > 0 ? _C.warn : _C.muted,
                  sub: [ResumenCard.linea(_pedidos(d.conCortesia), ancho)],
                ),
              ],
            ),
            // Con un solo usuario la tarjeta diría "100%" de la misma persona.
            if (usuarios.length > 1) ...[
              gap,
              _QuienVendio(
                usuarios: usuarios,
                total: t.total,
                signo: s,
                elegido: _usuario,
                onElegir: (u) => setState(() => _usuario = _usuario == u ? null : u),
              ),
            ],
            gap,
            _TarjetaPedidos(
              detalle: d,
              lista: lista,
              filtro: _filtro,
              usuario: _usuario,
              signo: s,
              caja: widget.caja,
              ancho: ancho,
              onFiltro: (f) => setState(() => _filtro = f),
              onQuitarUsuario: () => setState(() => _usuario = null),
            ),
          ],
        );
      }

      final scroll = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
        // A todo el ancho (la tarjeta de "sin pedidos" se achicaba al texto).
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [contenido]),
      );
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
        child: scroll,
      );
    });
  }
}

class _ErrorPedidos extends StatelessWidget {
  final VoidCallback? onReintentar;
  const _ErrorPedidos({this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return InicioCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: [
          Text('No se pudieron leer los pedidos', textAlign: TextAlign.center, style: _t(17, FontWeight.w700, _C.ink)),
          const SizedBox(height: 4),
          Text('Revisá tu conexión e intentá de nuevo.', textAlign: TextAlign.center, style: _t(14.5, FontWeight.w400, _C.muted)),
          if (onReintentar != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onReintentar,
              child: Text('Reintentar', style: _t(14.5, FontWeight.w700, _C.accent)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  final String titulo;
  final String texto;
  const _Vacio({required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) {
    return InicioCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
      child: Column(
        children: [
          Text(titulo, textAlign: TextAlign.center, style: _t(17, FontWeight.w700, _C.ink)),
          const SizedBox(height: 4),
          Text(texto, textAlign: TextAlign.center, style: _t(14.5, FontWeight.w400, _C.muted)),
        ],
      ),
    );
  }
}

// ── ¿QUIÉN VENDIÓ? ───────────────────────────────────────────────────────────

class _QuienVendio extends StatelessWidget {
  final List<UsuarioCaja> usuarios;
  final double total;
  final String signo;
  final String? elegido;
  final ValueChanged<String> onElegir;

  const _QuienVendio({
    required this.usuarios,
    required this.total,
    required this.signo,
    required this.elegido,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    final mayor = usuarios.first.total;
    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InicioTituloTarjeta(titulo: '¿Quién vendió?', nota: 'Toca para ver sus pedidos'),
          for (var i = 0; i < usuarios.length; i++)
            _FilaUsuario(
              usuario: usuarios[i],
              fraccion: mayor > 0 ? usuarios[i].total / mayor : 0,
              parte: total > 0 ? (usuarios[i].total / total * 100).round() : 0,
              signo: signo,
              primera: i == 0,
              elegida: elegido == usuarios[i].nombre,
              onTap: () => onElegir(usuarios[i].nombre),
            ),
        ],
      ),
    );
  }
}

class _FilaUsuario extends StatelessWidget {
  final UsuarioCaja usuario;
  final double fraccion;
  final int parte;
  final String signo;
  final bool primera;
  final bool elegida;
  final VoidCallback onTap;

  const _FilaUsuario({
    required this.usuario,
    required this.fraccion,
    required this.parte,
    required this.signo,
    required this.primera,
    required this.elegida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    return Container(
      decoration: BoxDecoration(border: primera || elegida ? null : Border(top: BorderSide(color: _C.line))),
      child: Material(
        color: elegida ? _C.tint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: elegida ? 8 : 0, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _C.tint, shape: BoxShape.circle),
                  child: Text(inicialesDe(u.nombre), style: _t(14, FontWeight.w700, _C.accent, height: 1.0)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(u.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, _C.ink)),
                      Text(
                        '${_pedidos(u.pedidos)} · propinas ${_q(signo, u.propinas)}',
                        style: _t(12.5, FontWeight.w400, _C.muted),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            height: 6,
                            child: Stack(children: [
                              Positioned.fill(child: ColoredBox(color: _C.subtle)),
                              FractionallySizedBox(
                                widthFactor: fraccion.clamp(0.0, 1.0),
                                child: ColoredBox(color: _C.gift, child: SizedBox.expand()),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(_q(signo, u.total), maxLines: 1, style: _t(15, FontWeight.w700, _C.ink)),
                      ),
                      Text('$parte%', style: _t(12, FontWeight.w400, _C.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── PEDIDOS ──────────────────────────────────────────────────────────────────

Color _colorMetodo(String llave) => switch (llave) {
      'cash' => _C.gift,
      'card' => _C.don,
      'transfer' || 'mixto' => _C.accent,
      'pedidosya' || 'ubereats' => _C.warn,
      _ => _C.muted,
    };

Color _fondoMetodo(String llave) => switch (llave) {
      'cash' => _C.giftTint,
      'card' => _C.donTint,
      'transfer' || 'mixto' => _C.tint,
      'pedidosya' || 'ubereats' => _C.warnTint,
      _ => _C.subtle,
    };

class _InsigniaMetodo extends StatelessWidget {
  final PedidoCaja pedido;
  const _InsigniaMetodo(this.pedido);

  @override
  Widget build(BuildContext context) {
    final k = pedido.llaveMetodo;
    // Un método propio puede tener un nombre larguísimo: la insignia se acota y
    // el nombre se corta con puntos suspensivos en vez de salirse de la fila.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _fondoMetodo(k), borderRadius: BorderRadius.circular(999)),
        child: Text(
          k == 'mixto' ? 'Mixto' : pedido.metodoNombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _t(12, FontWeight.w700, _colorMetodo(k)),
        ),
      ),
    );
  }
}

class _TarjetaPedidos extends StatelessWidget {
  final DetalleCaja detalle;
  final List<PedidoCaja> lista;
  final String filtro;
  final String? usuario;
  final String signo;
  final CashRegisterSummary caja;
  final double ancho;
  final ValueChanged<String> onFiltro;
  final VoidCallback onQuitarUsuario;

  const _TarjetaPedidos({
    required this.detalle,
    required this.lista,
    required this.filtro,
    required this.usuario,
    required this.signo,
    required this.caja,
    required this.ancho,
    required this.onFiltro,
    required this.onQuitarUsuario,
  });

  @override
  Widget build(BuildContext context) {
    // La tabla de nueve columnas pide ancho; debajo de esto cada pedido es una
    // tarjeta (como el diseño en teléfono; el diseño la deja desplazarse de lado).
    final tabla = ancho >= 900;
    final totales = TotalesPedidos.de(lista);

    final chips = [
      if (usuario != null) _Chip(texto: '$usuario ✕', activo: true, onTap: onQuitarUsuario),
      for (final f in detalle.filtros)
        _Chip(texto: f.nombre, cuantos: f.cuantos, activo: filtro == f.id, onTap: () => onFiltro(f.id)),
    ];

    final titulo = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      children: [
        Text('Pedidos', style: _t(17, FontWeight.w700, _C.ink, height: 1.25)),
        Text('${lista.length} de ${detalle.pedidos.length}', style: _t(13, FontWeight.w400, _C.muted)),
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(tabla ? 22 : 18, tabla ? 22 : 18, tabla ? 22 : 18, 14),
            child: tabla
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      titulo,
                      const SizedBox(width: 16),
                      Expanded(child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: chips)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titulo,
                      const SizedBox(height: 12),
                      // Una sola fila que se desliza de lado: los filtros no quitan alto.
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 6), chips[i]]]),
                      ),
                    ],
                  ),
          ),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: Center(child: Text('Ningún pedido con este filtro', style: _t(14.5, FontWeight.w400, _C.muted))),
            )
          else if (tabla)
            _Tabla(lista: lista, totales: totales, signo: signo, caja: caja)
          else
            _TarjetasDePedidos(lista: lista, totales: totales, signo: signo, caja: caja),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final int? cuantos;
  final bool activo;
  final VoidCallback onTap;

  const _Chip({required this.texto, this.cuantos, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // El nombre de un método propio o de un usuario puede ser larguísimo.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: activo ? _C.ink : _C.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: activo ? _C.ink : _C.line, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(13.5, FontWeight.w600, activo ? _C.card : _C.ink),
                ),
              ),
              if (cuantos != null) ...[
                const SizedBox(width: 6),
                Text('$cuantos', style: _t(12, FontWeight.w400, activo ? _C.card.withValues(alpha: 0.7) : _C.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuándo se cobró: la hora y, si no es el día en que se abrió la caja, la fecha.
String _cuando(PedidoCaja p, CashRegisterSummary caja) {
  final f = p.pagadoA;
  if (f == null) return '—';
  final hora = _hora.format(f);
  return _mismoDia(f, caja.openedAt) ? hora : '${fechaCorta(f)} · $hora';
}

/// La hora de la tabla ancha; si el cobro es de otro día que el de la apertura de la
/// caja (un turno que pasa de medianoche), la fecha va debajo, chica.
class _CeldaHora extends StatelessWidget {
  final PedidoCaja pedido;
  final CashRegisterSummary caja;
  const _CeldaHora(this.pedido, this.caja);

  @override
  Widget build(BuildContext context) {
    final f = pedido.pagadoA;
    if (f == null) return Text('—', style: _t(14.5, FontWeight.w400, _C.soft));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_hora.format(f), maxLines: 1, style: _t(14.5, FontWeight.w400, _C.ink)),
        if (!_mismoDia(f, caja.openedAt)) Text(fechaCorta(f), style: _t(12.5, FontWeight.w400, _C.muted)),
      ],
    );
  }
}

// Las columnas de la tabla ancha (proporciones; el diseño las deja a su medida).
const _anchos = [11, 17, 9, 11, 11, 10, 10, 13, 12];

class _Tabla extends StatelessWidget {
  final List<PedidoCaja> lista;
  final TotalesPedidos totales;
  final String signo;
  final CashRegisterSummary caja;

  const _Tabla({required this.lista, required this.totales, required this.signo, required this.caja});

  static const _alto = 520.0;

  @override
  Widget build(BuildContext context) {
    Widget col(int i, Widget w, {bool der = false}) => Expanded(
          flex: _anchos[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Align(alignment: der ? Alignment.centerRight : Alignment.centerLeft, child: w),
          ),
        );

    Widget encabezado(String t, int i, {bool der = false}) => col(
          i,
          Text(t.toUpperCase(), maxLines: 1, style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6)),
          der: der,
        );

    Text monto(double v, {Color? color, FontWeight peso = FontWeight.w400, bool signoMenos = false}) => Text(
          v == 0 ? '—' : _q(signo, signoMenos ? -v : v),
          maxLines: 1,
          style: _t(14.5, peso, v == 0 ? _C.soft : (color ?? _C.ink)),
        );

    final cabecera = Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line), bottom: BorderSide(color: _C.line))),
      child: Row(
        children: [
          encabezado('Hora', 0),
          encabezado('Usuario', 1),
          encabezado('#Pedido', 2),
          encabezado('Subtotal', 3, der: true),
          encabezado('Descuento', 4, der: true),
          encabezado('Propina', 5, der: true),
          encabezado('Cortesía', 6, der: true),
          encabezado('Total pagado', 7, der: true),
          encabezado('Método', 8),
        ],
      ),
    );

    Widget fila(PedidoCaja p, bool ultima) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(border: ultima ? null : Border(bottom: BorderSide(color: _C.line))),
          child: Row(
            children: [
              col(0, _CeldaHora(p, caja)),
              col(1, Text(p.usuario, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w400, _C.ink))),
              col(2, Text(p.numero, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w700, _C.ink))),
              col(3, monto(p.subtotal), der: true),
              col(4, monto(p.descuento, color: _C.bad, signoMenos: true), der: true),
              col(5, monto(p.propina, color: _C.gift), der: true),
              col(6, monto(p.cortesia, color: _C.warn), der: true),
              col(7, monto(p.total, peso: FontWeight.w700), der: true),
              col(8, _InsigniaMetodo(p)),
            ],
          ),
        );

    final pie = Container(
      color: _C.subtle,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: null,
      child: Row(
        children: [
          Expanded(
            flex: _anchos[0] + _anchos[1] + _anchos[2],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Text(_pedidos(totales.pedidos), style: _t(14.5, FontWeight.w700, _C.ink)),
            ),
          ),
          col(3, Text(_q(signo, totales.subtotal), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)), der: true),
          col(4, Text(_q(signo, -totales.descuentos), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.bad)), der: true),
          col(5, Text(_q(signo, totales.propinas), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.gift)), der: true),
          col(6, Text(_q(signo, totales.cortesias), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.warn)), der: true),
          col(7, Text(_q(signo, totales.total), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)), der: true),
          const Expanded(flex: 12, child: SizedBox.shrink()),
        ],
      ),
    );

    // Con muchos pedidos la tabla se desplaza por dentro, con su encabezado y su
    // total siempre a la vista (como el diseño).
    final filas = lista.length > 9
        ? SizedBox(
            height: _alto,
            child: ListView.builder(
              itemCount: lista.length,
              itemBuilder: (_, i) => fila(lista[i], i == lista.length - 1),
            ),
          )
        : Column(children: [for (var i = 0; i < lista.length; i++) fila(lista[i], i == lista.length - 1)]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cabecera, filas, pie]);
  }
}

/// Cada pedido como una tarjeta (teléfono y tablet): el número y el total arriba,
/// la hora y el método, quién, y lo que no es cero (descuento, propina, cortesía).
class _TarjetasDePedidos extends StatelessWidget {
  final List<PedidoCaja> lista;
  final TotalesPedidos totales;
  final String signo;
  final CashRegisterSummary caja;

  const _TarjetasDePedidos({required this.lista, required this.totales, required this.signo, required this.caja});

  @override
  Widget build(BuildContext context) {
    Widget dato(String etiqueta, String valor, Color color) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text.rich(
            TextSpan(
              style: _t(13, FontWeight.w400, _C.muted),
              children: [
                TextSpan(text: '$etiqueta ', style: _t(13, FontWeight.w500, _C.muted)),
                TextSpan(text: valor, style: _t(13, FontWeight.w400, color)),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in lista)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text(p.numero, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(16, FontWeight.w700, _C.ink))),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_q(signo, p.total), maxLines: 1, style: _t(18, FontWeight.w700, _C.ink)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: Text(_cuando(p, caja), style: _t(13, FontWeight.w400, _C.muted))),
                      const SizedBox(width: 10),
                      _InsigniaMetodo(p),
                    ],
                  ),
                  Text(p.usuario, style: _t(13.5, FontWeight.w400, _C.muted)),
                  if (p.descuento > 0) dato('Descuento', _q(signo, -p.descuento), _C.bad),
                  if (p.propina > 0) dato('Propina', _q(signo, p.propina), _C.gift),
                  if (p.cortesia > 0) dato('Cortesía', _q(signo, p.cortesia), _C.warn),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line, width: 2))),
            child: Row(
              children: [
                Expanded(child: Text(_pedidos(totales.pedidos), style: _t(14.5, FontWeight.w700, _C.ink))),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(_q(signo, totales.total), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)),
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

// ── GASTOS ───────────────────────────────────────────────────────────────────

class _TarjetaGastos extends StatelessWidget {
  final List<GastoCaja> gastos;
  final String signo;
  final double ancho;

  const _TarjetaGastos({required this.gastos, required this.signo, required this.ancho});

  @override
  Widget build(BuildContext context) {
    if (gastos.isEmpty) {
      return const _Vacio(titulo: 'Sin gastos', texto: 'No se registraron gastos en esta caja.');
    }
    final total = gastos.fold(0.0, (s, g) => s + g.monto);
    final tabla = ancho >= 640;

    String cuando(GastoCaja g) => g.fecha == null ? '—' : '${fechaCorta(g.fecha!)} · ${_hora.format(g.fecha!)}';

    Widget fila(GastoCaja g, bool ultima) {
      final detalle = g.concepto == g.categoria ? null : g.categoria;
      if (!tabla) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: ultima ? null : Border(bottom: BorderSide(color: _C.line))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.concepto, style: _t(14.5, FontWeight.w600, _C.ink)),
                    Text(
                      [if (detalle != null) detalle, if (g.usuario != null) g.usuario!, cuando(g)].join(' · '),
                      style: _t(12.5, FontWeight.w400, _C.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(_q(signo, g.monto), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)),
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(border: ultima ? null : Border(bottom: BorderSide(color: _C.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 14, child: Text(cuando(g), style: _t(14.5, FontWeight.w400, _C.ink))),
            Expanded(
              flex: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.concepto, style: _t(14.5, FontWeight.w600, _C.ink)),
                  if (detalle != null) Text(detalle, style: _t(12.5, FontWeight.w400, _C.muted)),
                ],
              ),
            ),
            Expanded(flex: 20, child: Text(g.usuario ?? '—', style: _t(14.5, FontWeight.w400, g.usuario == null ? _C.soft : _C.ink))),
            Expanded(
              flex: 14,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(_q(signo, g.monto), maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(tabla ? 22 : 18, tabla ? 22 : 18, tabla ? 22 : 18, 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              children: [
                Text('Gastos', style: _t(17, FontWeight.w700, _C.ink, height: 1.25)),
                Text(_q(signo, total), style: _t(13, FontWeight.w400, _C.muted)),
              ],
            ),
          ),
          if (tabla)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line), bottom: BorderSide(color: _C.line))),
              child: Row(
                children: [
                  for (final (flex, texto, der) in const [(14, 'Hora', false), (30, 'Concepto', false), (20, 'Usuario', false), (14, 'Monto', true)])
                    Expanded(
                      flex: flex,
                      child: Text(
                        texto.toUpperCase(),
                        textAlign: der ? TextAlign.right : TextAlign.left,
                        style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: tabla ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [for (var i = 0; i < gastos.length; i++) fila(gastos[i], i == gastos.length - 1)],
            ),
          ),
          SizedBox(height: tabla ? 0 : 6),
        ],
      ),
    );
  }
}
