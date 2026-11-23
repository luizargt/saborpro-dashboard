/// La parte visual del detalle de "Cortesías y donaciones", separada de la
/// pantalla.
///
/// Vive aparte por la misma razón que la de Pedidos Cancelados: la pantalla
/// depende de providers con Firebase y no se puede montar en un test, pero
/// esta mitad solo necesita un [CortesiasReport] armado a mano, así que sí se
/// puede probar a 360dp (ver test/presentation/widgets/cortesias_view_test.dart).
///
/// Diseño (2026-11-19): `assets/Desing/Sabor Manager/cortesias.html` de
/// saborpro_app, en su modo oscuro. Lo que se suma no cambia: todo sale del
/// mismo [CortesiasReport] que cuadra con la tarjeta del Inicio.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/paleta.dart';
import '../../core/utils/formato_dinero.dart';
import '../../data/models/cortesias_data.dart';
import 'inicio_ui.dart' show InicioColores;

/// Fondo de la pantalla.
Color get kCortesiasBg => paletaActual.bg;

/// La paleta de los diseños, en el modo que esté puesto (claro por defecto, oscuro si
/// se elige; ver `TemaManager`).
///
/// Son getters y no constantes: leen [paletaActual] cada vez que se pintan. Por eso no
/// se pueden usar dentro de un `const` (un `const Icon(color: _C.muted)` no compila):
/// el widget se arma sin `const`.
abstract final class CortesiasColores {
  static Color get bg => paletaActual.bg;
  static Color get card => paletaActual.card;
  static Color get subtle => paletaActual.subtle;
  static Color get line => paletaActual.line;
  static Color get lineStrong => paletaActual.lineStrong;
  static Color get ink => paletaActual.ink;
  static Color get muted => paletaActual.muted;
  static Color get soft => paletaActual.soft;
  static Color get accent => paletaActual.accent;
  static Color get tint => paletaActual.tint;
  static Color get gift => paletaActual.ok;
  static Color get giftTint => paletaActual.okTint;
  static Color get don => paletaActual.blue;
  static Color get donTint => paletaActual.blueTint;
  static Color get warn => paletaActual.warn;
  static Color get warnTint => paletaActual.warnTint;
  static Color get bad => paletaActual.bad;
  static Color get badTint => paletaActual.badTint;

  /// El naranja de "gasto / compra" y su fondo.
  static Color get exp => paletaActual.exp;
  static Color get expTint => paletaActual.expTint;

  /// Texto sobre un fondo de color pleno.
  static Color get onAccent => paletaActual.onAccent;

  // La barra de navegación (barra lateral, barra inferior, menú de la cuenta).
  static Color get barra => paletaActual.barra;
  static Color get barra2 => paletaActual.barra2;
  static Color get barraLinea => paletaActual.barraLinea;
  static Color get barraTexto => paletaActual.barraTexto;
  static Color get barraApagado => paletaActual.barraApagado;
  static Color get barraHover => paletaActual.barraHover;
  static Color get barraActivo => paletaActual.barraActivo;
  static Color get barraActivoIcono => paletaActual.barraActivoIcono;
  static Color get barraActivoTexto => paletaActual.barraActivoTexto;
  static Color get barraChip => paletaActual.barraChip;
  static Color get sombra => paletaActual.sombra;
}

typedef _C = CortesiasColores;

/// El texto del diseño: Poppins, con cifras del mismo ancho (los montos se
/// alinean en columna).
TextStyle cortesiasTexto(double size, FontWeight weight, Color color, {double? height}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

const _t = cortesiasTexto;

Color _colorDe(TipoCortesia t) => t == TipoCortesia.donacion ? _C.don : _C.gift;
Color _fondoDe(TipoCortesia t) => t == TipoCortesia.donacion ? _C.donTint : _C.giftTint;

final _fmtMoney = NumberFormat('#,##0.00', 'en_US');
final _fmtCant = NumberFormat('#,##0.##', 'en_US');

String _dinero(double v) => '$moneda${_fmtMoney.format(v)}';
String _cant(double v) => _fmtCant.format(v);
String _plural(num n, String uno, String varios) => n == 1 ? uno : varios;

/// "a las 3:40 p. m." si fue hoy; "el 6 nov a las 3:40 p. m." si no.
String _horaDe(DateTime t) {
  final ahora = DateTime.now();
  final hoy = t.year == ahora.year && t.month == ahora.month && t.day == ahora.day;
  final hora = DateFormat('h:mm a', 'es').format(t);
  return hoy ? 'a las $hora' : 'el ${DateFormat('d MMM', 'es').format(t)} a las $hora';
}

/// El monto de la derecha de una fila: pegado al borde y, si no cabe (seis
/// cifras con letra grande), se parte en dos líneas en vez de salirse. Con un
/// tope de ancho y no como Flexible: un Flexible se queda con media fila y deja
/// el monto a la mitad.
Widget _montoDerecha(String texto, TextStyle estilo) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(texto, textAlign: TextAlign.right, style: estilo),
    );

/// Iniciales para el círculo de cada persona ("Ana Cosme" → "AC").
String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  return partes.take(2).map((p) => p.characters.first.toUpperCase()).join();
}

/// Quién marcó un renglón, como clave: '' cuando el POS no lo guardó.
String _claveDe(CortesiaRenglon r) => r.usuarioId ?? '';

bool _sinMotivo(CortesiaRenglon r) => r.motivo == null;

enum _Filtro { todos, cortesias, donaciones, sinMotivo }

/// Todo el contenido desplazable: el resumen arriba, quién regala y por qué,
/// qué se regala y los pedidos. En pantalla ancha van lado a lado lo que
/// cabe; en el teléfono, uno debajo del otro y los pedidos como tarjetas.
class CortesiasReportBody extends StatefulWidget {
  final CortesiasReport report;

  /// id de usuario → nombre, para decir quién marcó cada cortesía.
  final Map<String, String> nombresUsuario;

  /// id de sucursal → nombre. Vacío cuando se mira una sola sucursal.
  final Map<String, String> nombresSucursal;

  /// El período se leyó incompleto (el Inicio llegó a su tope de pedidos).
  final bool incompleto;

  /// Los montos están convertidos a otra moneda: cada renglón trae decimales
  /// de más y, redondeados por separado, las partes pueden no sumar el total.
  final bool convertido;

  /// Lo que dice la tarjeta del Inicio, solo en la vista de año: ahí sale de
  /// los resúmenes de cada mes y este detalle de los pedidos de ahora, así
  /// que pueden no coincidir. Si no coinciden, se dice.
  final double? totalTarjeta;

  /// Vista de año: a qué hora se bajaron los pedidos de este detalle. La
  /// tarjeta se rehace al cambiar de pestaña o de período y el detalle no, así
  /// que puede ser más viejo que ella.
  final DateTime? bajadoA;

  /// La venta del período (la "Venta Bruta" del Inicio), para decir qué parte
  /// de lo vendido se regaló. null o 0 = no se muestra.
  final double? ventas;

  const CortesiasReportBody({
    super.key,
    required this.report,
    this.nombresUsuario = const {},
    this.nombresSucursal = const {},
    this.incompleto = false,
    this.convertido = false,
    this.totalTarjeta,
    this.bajadoA,
    this.ventas,
  });

  @override
  State<CortesiasReportBody> createState() => _CortesiasReportBodyState();
}

class _CortesiasReportBodyState extends State<CortesiasReportBody> {
  _Filtro _filtro = _Filtro.todos;

  /// La persona elegida en "¿Quién regala?" (ver [_claveDe]), o null.
  String? _quien;
  final _pedidosKey = GlobalKey();

  String _nombreDe(String clave) {
    if (clave.isEmpty) return 'Sin registrar';
    return widget.nombresUsuario[clave] ?? 'Usuario';
  }

  bool _pasa(CortesiaPedido p, _Filtro f) {
    final porTipo = switch (f) {
      _Filtro.todos => true,
      _Filtro.cortesias => p.renglones.any((r) => r.tipo == TipoCortesia.cortesia),
      _Filtro.donaciones => p.renglones.any((r) => r.tipo == TipoCortesia.donacion),
      _Filtro.sinMotivo => p.renglones.any(_sinMotivo),
    };
    final quien = _quien;
    return porTipo && (quien == null || p.renglones.any((r) => _claveDe(r) == quien));
  }

  /// Baja hasta los pedidos (después de filtrar desde arriba).
  void _irAPedidos() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _pedidosKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.02);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    // El nombre de la sucursal solo ayuda si hay pedidos de más de una.
    final variasSucursales =
        widget.nombresSucursal.isNotEmpty && {for (final p in r.pedidos) p.locationId}.length > 1;
    // En centavos, con uno de tolerancia: la tarjeta del año suma mes por mes
    // y este detalle de corrido, y con montos convertidos eso solo puede
    // mover el último centavo al redondear. Eso no es "algo cambió".
    final tarjeta = widget.totalTarjeta;
    final noCoincide = tarjeta != null && ((tarjeta * 100).round() - (r.total * 100).round()).abs() > 1;
    final hora = widget.bajadoA;
    final cuando = hora == null ? null : _horaDe(hora);

    // Lo que no dice por qué se regaló.
    final pedidosSinMotivo = r.pedidos.where((p) => p.renglones.any(_sinMotivo)).length;
    final montoSinMotivo = r.pedidos
        .expand((p) => p.renglones)
        .where(_sinMotivo)
        .fold(0.0, (s, x) => s + x.monto);

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 900;
      final pad = c.maxWidth < 640 ? 16.0 : 20.0;

      final quien = _SeccionQuien(
        pedidos: r.pedidos,
        total: r.total,
        nombreDe: _nombreDe,
        elegido: _quien,
        onElegir: (clave) {
          setState(() => _quien = _quien == clave ? null : clave);
          if (_quien != null) _irAPedidos();
        },
      );
      final porque = _SeccionPorQue(pedidos: r.pedidos);

      final lista = SingleChildScrollView(
        // Siempre desplazable: el RefreshIndicator lo necesita aunque haya
        // un solo pedido.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Resumen(report: r, convertido: widget.convertido, ventas: widget.ventas),
            if (cuando != null && !noCoincide) ...[
              const SizedBox(height: 10),
              Text(
                // La hora va al final y "p. m." ya trae su punto: con otro
                // detrás salía "p. m..".
                'Jalá hacia abajo para actualizar los pedidos del año, bajados '
                '$cuando${cuando.endsWith('.') ? '' : '.'}',
                style: _t(12, FontWeight.w400, _C.soft, height: 1.35),
              ),
            ],
            if (noCoincide) ...[
              const SizedBox(height: 16),
              _Notice(
                icon: Icons.info_outline_rounded,
                // No dice cuál de los dos está al día porque puede ser
                // cualquiera: la tarjeta sale de resúmenes que pueden haber
                // quedado viejos, y este detalle, de una descarga que también.
                text: 'La tarjeta del Inicio dice ${_dinero(tarjeta)}. En la '
                    'vista de año sale de los resúmenes guardados de cada mes, '
                    'y este detalle, de los pedidos '
                    '${cuando == null ? 'del año' : 'bajados $cuando'}: si '
                    'entró o cambió un pedido entre una cosa y la otra, o un mes '
                    'no se pudo revisar, no coinciden. Jalá hacia abajo para '
                    'actualizar los dos.',
              ),
            ],
            if (widget.incompleto) ...[
              const SizedBox(height: 16),
              const _Notice(
                icon: Icons.warning_amber_rounded,
                text: 'Este período tiene más pedidos de los que se pueden leer '
                    'de una vez: el detalle (y la tarjeta del Inicio) pueden '
                    'quedar cortos. Elegí un período más corto para verlo completo.',
              ),
            ],
            if (r.vacio) ...[
              const SizedBox(height: 16),
              const _EmptyCard(text: 'No hubo cortesías ni donaciones en este período.'),
            ] else ...[
              if (pedidosSinMotivo > 0) ...[
                const SizedBox(height: 16),
                _AlertaSinMotivo(
                  pedidos: pedidosSinMotivo,
                  monto: montoSinMotivo,
                  onVer: () {
                    setState(() => _filtro = _Filtro.sinMotivo);
                    _irAPedidos();
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (ancho)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: quien),
                      const SizedBox(width: 16),
                      Expanded(child: porque),
                    ],
                  ),
                )
              else ...[
                quien,
                const SizedBox(height: 16),
                porque,
              ],
              const SizedBox(height: 16),
              _SeccionPlatillos(
                platillos: r.platillos,
                dosColumnas: c.maxWidth >= 980,
                muestra: ancho ? 10 : 6,
              ),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: _pedidosKey,
                child: _SeccionPedidos(
                  pedidos: r.pedidos,
                  filtro: _filtro,
                  quien: _quien,
                  nombreDe: _nombreDe,
                  nombresUsuario: widget.nombresUsuario,
                  nombresSucursal: variasSucursales ? widget.nombresSucursal : const {},
                  tabla: ancho,
                  pasa: _pasa,
                  onFiltro: (f) => setState(() => _filtro = f),
                  onQuitarQuien: () => setState(() => _quien = null),
                ),
              ),
            ],
          ],
        ),
      );

      // Sin pedidos (o con pocos) el contenido es más bajo que la pantalla. El
      // cambio de sucursal (un AnimatedSwitcher) entrega restricciones sueltas y
      // un SingleChildScrollView mide lo que mide su contenido: sin esto quedaba
      // CENTRADO en vertical, con un hueco enorme entre las pestañas y la
      // primera tarjeta. Obligándolo a medir al menos el alto disponible, el
      // contenido se queda arriba y la zona de jalar para actualizar cubre todo
      // el alto. (Mismo arreglo que Pedidos cancelados.)
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.hasBoundedHeight ? c.maxHeight : 0),
        child: lista,
      );
    });
  }
}

// ── PIEZAS DE TARJETA ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    // Por el ancho de la pantalla y no con LayoutBuilder: dos tarjetas van
    // lado a lado dentro de un IntrinsicHeight, que no lo admite.
    final telefono = MediaQuery.sizeOf(context).width < 640;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(telefono ? 18 : 22),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      child: child,
    );
  }
}

/// Título de sección: "¿Quién regala?" y a su lado algo chico en gris.
class _Titulo extends StatelessWidget {
  final String texto;
  final String? detalle;
  const _Titulo(this.texto, {this.detalle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 10,
        runSpacing: 2,
        children: [
          Text(texto, style: _t(17, FontWeight.w700, _C.ink)),
          if (detalle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(detalle!, style: _t(13, FontWeight.w400, _C.muted)),
            ),
        ],
      ),
    );
  }
}

/// La barrita de "qué parte del total".
class _Barra extends StatelessWidget {
  final double parte;
  const _Barra(this.parte);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _C.subtle),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: parte.isFinite ? parte.clamp(0.0, 1.0) : 0.0,
              child: ColoredBox(color: _C.gift),
            ),
          ],
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();
  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: _C.line);
}

// ── EL RESUMEN ───────────────────────────────────────────────────────────────

class _Resumen extends StatelessWidget {
  final CortesiasReport report;
  final bool convertido;
  final double? ventas;
  const _Resumen({required this.report, required this.convertido, this.ventas});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final n = r.pedidos.length;
    final vendido = ventas;
    final conVentas = vendido != null && vendido > 0;

    final piezas = <Widget>[
      _Cifra(
        grande: true,
        icono: Icons.card_giftcard_rounded,
        etiqueta: 'Valor regalado',
        valor: _dinero(r.total),
        detalle: r.vacio ? 'Nada regalado en este período.' : null,
      ),
      if (conVentas)
        _Cifra(
          etiqueta: 'De tus ventas',
          valor: '${(r.total / vendido * 100).toStringAsFixed(1)}%',
          detalle: 'Vendiste ${_dinero(vendido)}',
        ),
      _Cifra(
        etiqueta: 'Pedidos con regalo',
        valor: '$n',
        detalle: n == 0
            ? null
            : '${_cant(r.cantidad)} ${_plural(r.cantidad, 'platillo', 'platillos')} · '
                'prom. ${_dinero(r.total / n)}',
      ),
      _Reparto(report: r),
    ];

    return Container(
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final columnas = c.maxWidth >= 900 ? piezas.length : (c.maxWidth >= 560 ? 2 : 1);
            return _Rejilla(columnas: columnas, primeraMasAncha: columnas == piezas.length, children: piezas);
          }),
          const _Separador(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded, size: 16, color: _C.soft),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // La misma cuenta que la tarjeta del Inicio y que el ticket:
                    // el platillo con sus extras (ver valorCortesia).
                    'A precio de venta, con sus extras, como en el ticket. No suma a '
                    'la venta del período.'
                    '${convertido ? ' Convertido con tu tipo de cambio: por el '
                        'redondeo, las partes pueden no sumar exacto el total.' : ''}',
                    style: _t(12.5, FontWeight.w400, _C.soft, height: 1.4),
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

/// Las cifras del resumen en [columnas], con una línea entre cada una (como
/// las celdas del diseño). Con todas en una fila, la primera es más ancha.
class _Rejilla extends StatelessWidget {
  final int columnas;
  final bool primeraMasAncha;
  final List<Widget> children;
  const _Rejilla({required this.columnas, required this.primeraMasAncha, required this.children});

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];
    for (var i = 0; i < children.length; i += columnas) {
      final fila = children.sublist(i, (i + columnas).clamp(0, children.length));
      if (i > 0) filas.add(const _Separador());
      filas.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < columnas; j++) ...[
              if (j > 0) VerticalDivider(width: 1, thickness: 1, color: _C.line),
              Expanded(
                flex: primeraMasAncha && i + j == 0 ? 13 : 10,
                child: j < fila.length ? fila[j] : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filas);
  }
}

class _Cifra extends StatelessWidget {
  final bool grande;
  final IconData? icono;
  final String etiqueta;
  final String valor;
  final String? detalle;
  const _Cifra({
    this.grande = false,
    this.icono,
    required this.etiqueta,
    required this.valor,
    this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    final telefono = MediaQuery.sizeOf(context).width < 640;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icono != null) ...[
                Icon(icono, size: 18, color: _C.muted),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(etiqueta, style: _t(13, FontWeight.w600, _C.muted))),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: _t(
                grande ? (telefono ? 34 : 40) : 26,
                FontWeight.w800,
                grande ? _C.gift : _C.ink,
                height: 1.15,
              ),
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 4),
            Text(detalle!, style: _t(13, FontWeight.w400, _C.muted)),
          ],
        ],
      ),
    );
  }
}

/// Cortesías contra donaciones: la barra partida y los dos montos.
class _Reparto extends StatelessWidget {
  final CortesiasReport report;
  const _Reparto({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final total = r.totalCortesia + r.totalDonacion;
    final parteCortesia = total > 0 ? r.totalCortesia / total : 0.0;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cortesías y donaciones', style: _t(13, FontWeight.w600, _C.muted)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              width: double.infinity,
              // Container y no ColoredBox: sin hijo, un ColoredBox mide cero y
              // la barra no se veía.
              child: total <= 0
                  ? Container(color: _C.subtle)
                  : Row(
                      children: [
                        if (r.totalCortesia > 0)
                          Expanded(
                            flex: (parteCortesia * 1000).round().clamp(1, 1000),
                            child: Container(color: _C.gift),
                          ),
                        if (r.totalDonacion > 0)
                          Expanded(
                            flex: ((1 - parteCortesia) * 1000).round().clamp(1, 1000),
                            child: Container(color: _C.don),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          _Leyenda(
            color: _C.gift,
            etiqueta: 'Cortesías',
            monto: r.totalCortesia,
            hubo: r.renglonesCortesia > 0,
          ),
          const SizedBox(height: 6),
          _Leyenda(
            color: _C.don,
            etiqueta: 'Donaciones',
            monto: r.totalDonacion,
            hubo: r.renglonesDonacion > 0,
          ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String etiqueta;
  final double monto;

  /// Hubo al menos un renglón de este tipo, aunque sumen cero.
  final bool hubo;
  const _Leyenda({required this.color, required this.etiqueta, required this.monto, required this.hubo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(etiqueta, style: _t(13, FontWeight.w400, _C.muted))),
        const SizedBox(width: 8),
        Text(
          // Un guion solo si no hubo ninguno. Si hubo y suman cero (platillos
          // de precio Q0), va Q0.00: un guion diría que no pasó.
          hubo ? _dinero(monto) : '—',
          style: _t(13, FontWeight.w600, hubo ? _C.ink : _C.soft),
        ),
      ],
    );
  }
}

// ── CORTESÍAS SIN MOTIVO ─────────────────────────────────────────────────────

class _AlertaSinMotivo extends StatelessWidget {
  final int pedidos;
  final double monto;
  final VoidCallback onVer;
  const _AlertaSinMotivo({required this.pedidos, required this.monto, required this.onVer});

  @override
  Widget build(BuildContext context) {
    final texto = Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '$pedidos ${_plural(pedidos, 'cortesía', 'cortesías')} sin motivo',
          style: _t(14.5, FontWeight.w700, _C.ink),
        ),
        TextSpan(text: ' por ', style: _t(14.5, FontWeight.w400, _C.ink)),
        TextSpan(text: _dinero(monto), style: _t(14.5, FontWeight.w700, _C.ink)),
        TextSpan(text: '. Pide que siempre se escriba el porqué.', style: _t(14.5, FontWeight.w400, _C.ink)),
      ]),
    );
    final boton = TextButton(
      onPressed: onVer,
      style: TextButton.styleFrom(
        backgroundColor: _C.card,
        foregroundColor: _C.ink,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(),
      ),
      child: Text('Ver cuáles', style: _t(14, FontWeight.w700, _C.ink)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(20)),
      child: LayoutBuilder(builder: (context, c) {
        final icono = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.warning_amber_rounded, color: _C.warn, size: 22),
        );
        if (c.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [icono, const SizedBox(width: 14), Expanded(child: texto)],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: boton),
            ],
          );
        }
        return Row(
          children: [icono, const SizedBox(width: 14), Expanded(child: texto), const SizedBox(width: 14), boton],
        );
      }),
    );
  }
}

// ── ¿QUIÉN REGALA? ───────────────────────────────────────────────────────────

class _AccQuien {
  final String clave;
  double monto = 0;
  final Set<CortesiaPedido> pedidos = {};
  final Set<CortesiaPedido> sinMotivo = {};
  _AccQuien(this.clave);
}

class _SeccionQuien extends StatelessWidget {
  final List<CortesiaPedido> pedidos;
  final double total;
  final String Function(String clave) nombreDe;
  final String? elegido;
  final ValueChanged<String> onElegir;

  const _SeccionQuien({
    required this.pedidos,
    required this.total,
    required this.nombreDe,
    required this.elegido,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    final porQuien = <String, _AccQuien>{};
    for (final p in pedidos) {
      for (final r in p.renglones) {
        final acc = porQuien.putIfAbsent(_claveDe(r), () => _AccQuien(_claveDe(r)));
        acc.monto += r.monto;
        acc.pedidos.add(p);
        if (_sinMotivo(r)) acc.sinMotivo.add(p);
      }
    }
    final lista = porQuien.values.toList()
      ..sort((a, b) {
        final m = b.monto.compareTo(a.monto);
        return m != 0 ? m : b.pedidos.length.compareTo(a.pedidos.length);
      });
    final mayor = lista.isEmpty ? 0.0 : lista.first.monto;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Quién regala?', detalle: 'Toca para ver sus pedidos'),
          for (var i = 0; i < lista.length; i++) ...[
            if (i > 0) const _Separador(),
            _FilaQuien(
              nombre: nombreDe(lista[i].clave),
              pedidos: lista[i].pedidos.length,
              sinMotivo: lista[i].sinMotivo.length,
              monto: lista[i].monto,
              parteDelTotal: total > 0 ? lista[i].monto / total : 0,
              parteDelMayor: mayor > 0 ? lista[i].monto / mayor : 0,
              elegido: elegido == lista[i].clave,
              onTap: () => onElegir(lista[i].clave),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaQuien extends StatelessWidget {
  final String nombre;
  final int pedidos;
  final int sinMotivo;
  final double monto;
  final double parteDelTotal;
  final double parteDelMayor;
  final bool elegido;
  final VoidCallback onTap;

  const _FilaQuien({
    required this.nombre,
    required this.pedidos,
    required this.sinMotivo,
    required this.monto,
    required this.parteDelTotal,
    required this.parteDelMayor,
    required this.elegido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: elegido ? _C.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: elegido ? 8 : 0, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _C.tint, shape: BoxShape.circle),
                child: Text(_iniciales(nombre), style: _t(14, FontWeight.w700, _C.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(nombre, style: _t(15, FontWeight.w600, _C.ink)),
                        if (sinMotivo > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _C.warnTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('$sinMotivo sin motivo', style: _t(11.5, FontWeight.w700, _C.warn)),
                          ),
                      ],
                    ),
                    Text(
                      '$pedidos ${_plural(pedidos, 'pedido', 'pedidos')} · '
                      '${(parteDelTotal * 100).round()}% del total',
                      style: _t(12.5, FontWeight.w400, _C.muted),
                    ),
                    const SizedBox(height: 6),
                    _Barra(parteDelMayor),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _montoDerecha(_dinero(monto), _t(15, FontWeight.w700, _C.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ¿POR QUÉ SE REGALA? ──────────────────────────────────────────────────────

class _AccMotivo {
  final String? motivo;
  double monto = 0;
  final Set<CortesiaPedido> pedidos = {};
  _AccMotivo(this.motivo);
}

class _SeccionPorQue extends StatelessWidget {
  final List<CortesiaPedido> pedidos;
  const _SeccionPorQue({required this.pedidos});

  @override
  Widget build(BuildContext context) {
    final porMotivo = <String?, _AccMotivo>{};
    for (final p in pedidos) {
      for (final r in p.renglones) {
        final acc = porMotivo.putIfAbsent(r.motivo, () => _AccMotivo(r.motivo));
        acc.monto += r.monto;
        acc.pedidos.add(p);
      }
    }
    final lista = porMotivo.values.toList()..sort((a, b) => b.monto.compareTo(a.monto));

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Por qué se regala?'),
          for (var i = 0; i < lista.length; i++) ...[
            if (i > 0) const _Separador(),
            _FilaMotivo(acc: lista[i]),
          ],
        ],
      ),
    );
  }
}

class _FilaMotivo extends StatelessWidget {
  final _AccMotivo acc;
  const _FilaMotivo({required this.acc});

  @override
  Widget build(BuildContext context) {
    final sin = acc.motivo == null;
    final n = acc.pedidos.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: sin ? _C.warnTint : _C.subtle,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              sin ? Icons.warning_amber_rounded : Icons.chat_bubble_outline_rounded,
              size: 18,
              color: sin ? _C.warn : _C.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acc.motivo ?? 'Sin motivo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14.5, FontWeight.w600, _C.ink),
                ),
                Text('$n ${_plural(n, 'pedido', 'pedidos')}', style: _t(12.5, FontWeight.w400, _C.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _montoDerecha(_dinero(acc.monto), _t(14.5, FontWeight.w700, _C.ink)),
        ],
      ),
    );
  }
}

// ── ¿QUÉ SE REGALA? ──────────────────────────────────────────────────────────

class _SeccionPlatillos extends StatefulWidget {
  final List<CortesiaPlatillo> platillos;
  final bool dosColumnas;

  /// Cuántos se ven antes de "Ver los N platillos".
  final int muestra;

  const _SeccionPlatillos({required this.platillos, required this.dosColumnas, required this.muestra});

  @override
  State<_SeccionPlatillos> createState() => _SeccionPlatillosState();
}

class _SeccionPlatillosState extends State<_SeccionPlatillos> {
  bool _todos = false;

  @override
  Widget build(BuildContext context) {
    final lista = widget.platillos;
    final vistos = _todos ? lista : lista.take(widget.muestra).toList();
    final resto = lista.length - vistos.length;
    final mayor = lista.isEmpty ? 0.0 : lista.first.monto;

    Widget fila(CortesiaPlatillo p) => _FilaPlatillo(platillo: p, parte: mayor > 0 ? p.monto / mayor : 0);

    final Widget filas;
    if (widget.dosColumnas) {
      // Por filas, de izquierda a derecha: el primero (el de más monto)
      // arriba a la izquierda, como se lee.
      final pares = <Widget>[];
      for (var i = 0; i < vistos.length; i += 2) {
        pares.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fila(vistos[i])),
            const SizedBox(width: 28),
            Expanded(child: i + 1 < vistos.length ? fila(vistos[i + 1]) : const SizedBox.shrink()),
          ],
        ));
      }
      filas = Column(children: pares);
    } else {
      filas = Column(children: [for (final p in vistos) fila(p)]);
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo(
            '¿Qué se regala?',
            detalle: '${lista.length} ${_plural(lista.length, 'platillo distinto', 'platillos distintos')}',
          ),
          filas,
          if (resto > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _todos = true),
                child: Text('Ver los ${lista.length} platillos', style: _t(13.5, FontWeight.w600, _C.accent)),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilaPlatillo extends StatelessWidget {
  final CortesiaPlatillo platillo;

  /// Contra el de más monto: la barra del primero va llena.
  final double parte;
  const _FilaPlatillo({required this.platillo, required this.parte});

  @override
  Widget build(BuildContext context) {
    final p = platillo;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Text('${_cant(p.cantidad)}×', style: _t(15, FontWeight.w800, _C.muted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w600, _C.ink)),
                Text(
                  'en ${p.pedidos} ${_plural(p.pedidos, 'pedido', 'pedidos')}',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
                const SizedBox(height: 6),
                _Barra(parte),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _montoDerecha(_dinero(p.monto), _t(14.5, FontWeight.w700, _C.gift)),
        ],
      ),
    );
  }
}

// ── PEDIDOS ──────────────────────────────────────────────────────────────────

class _SeccionPedidos extends StatefulWidget {
  final List<CortesiaPedido> pedidos;
  final _Filtro filtro;
  final String? quien;
  final String Function(String clave) nombreDe;
  final Map<String, String> nombresUsuario;
  final Map<String, String> nombresSucursal;

  /// Pantalla ancha: tabla. Teléfono: una tarjeta por pedido.
  final bool tabla;
  final bool Function(CortesiaPedido p, _Filtro f) pasa;
  final ValueChanged<_Filtro> onFiltro;
  final VoidCallback onQuitarQuien;

  const _SeccionPedidos({
    required this.pedidos,
    required this.filtro,
    required this.quien,
    required this.nombreDe,
    required this.nombresUsuario,
    required this.nombresSucursal,
    required this.tabla,
    required this.pasa,
    required this.onFiltro,
    required this.onQuitarQuien,
  });

  @override
  State<_SeccionPedidos> createState() => _SeccionPedidosState();
}

class _SeccionPedidosState extends State<_SeccionPedidos> {
  static const _kMuestra = 20;
  bool _todos = false;

  @override
  void didUpdateWidget(covariant _SeccionPedidos old) {
    super.didUpdateWidget(old);
    // Otro filtro, otra lista: se vuelve a ver desde los primeros.
    if (old.filtro != widget.filtro || old.quien != widget.quien) _todos = false;
  }

  @override
  Widget build(BuildContext context) {
    final todos = widget.pedidos;
    final lista = todos.where((p) => widget.pasa(p, widget.filtro)).toList();
    final vistos = _todos ? lista : lista.take(_kMuestra).toList();
    final resto = lista.length - vistos.length;
    final quien = widget.quien;

    final filtros = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (quien != null)
          _Chip(
            texto: widget.nombreDe(quien),
            elegido: true,
            alQuitar: true,
            onTap: widget.onQuitarQuien,
          ),
        for (final (f, nombre) in const [
          (_Filtro.todos, 'Todos'),
          (_Filtro.cortesias, 'Cortesías'),
          (_Filtro.donaciones, 'Donaciones'),
          (_Filtro.sinMotivo, 'Sin motivo'),
        ])
          _Chip(
            texto: nombre,
            cuenta: todos.where((p) => widget.pasa(p, f)).length,
            elegido: widget.filtro == f,
            onTap: () => widget.onFiltro(f),
          ),
      ],
    );

    final Widget cuerpo;
    if (lista.isEmpty) {
      cuerpo = Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Text('No hay pedidos con este filtro.',
            textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
      );
    } else if (widget.tabla) {
      cuerpo = _TablaPedidos(
        pedidos: vistos,
        nombresUsuario: widget.nombresUsuario,
        nombresSucursal: widget.nombresSucursal,
      );
    } else {
      cuerpo = Column(
        children: [
          for (var i = 0; i < vistos.length; i++) ...[
            if (i > 0) const _Separador(),
            _PedidoTile(
              pedido: vistos[i],
              nombresUsuario: widget.nombresUsuario,
              sucursal: widget.nombresSucursal[vistos[i].locationId],
            ),
          ],
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text('Pedidos', style: _t(17, FontWeight.w700, _C.ink)),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('${lista.length} de ${todos.length}', style: _t(13, FontWeight.w400, _C.muted)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          filtros,
          const SizedBox(height: 10),
          cuerpo,
          if (resto > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _todos = true),
                child: Text(
                  resto == 1 ? 'Ver el otro pedido' : 'Ver los otros $resto pedidos',
                  style: _t(13.5, FontWeight.w600, _C.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final int? cuenta;
  final bool elegido;
  final bool alQuitar;
  final VoidCallback onTap;

  const _Chip({
    required this.texto,
    this.cuenta,
    required this.elegido,
    this.alQuitar = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = elegido ? _C.card : _C.ink;
    return Material(
      color: elegido ? _C.ink : _C.card,
      shape: StadiumBorder(side: BorderSide(color: elegido ? _C.ink : _C.line, width: 1.5)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(texto, overflow: TextOverflow.ellipsis, style: _t(13.5, FontWeight.w600, color))),
                if (cuenta != null) ...[
                  const SizedBox(width: 6),
                  Text('$cuenta', style: _t(12, FontWeight.w500, color.withValues(alpha: 0.7))),
                ],
                if (alQuitar) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.close_rounded, size: 15, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se muestra de un pedido en la tabla y en la tarjeta.
class _DatosPedido {
  final String hora;
  final String fecha;
  final String donde;
  final List<String> detalleDonde;
  final List<TipoCortesia> tipos;
  final List<String> quienes;
  final List<String> motivos;
  final bool sinMotivo;

  _DatosPedido(CortesiaPedido p, Map<String, String> nombresUsuario, String? sucursal)
      : hora = p.fecha == null ? 'Sin fecha' : DateFormat('h:mm a', 'es').format(p.fecha!),
        fecha = p.fecha == null ? '' : DateFormat('EEE d MMM', 'es').format(p.fecha!),
        donde = p.lugar,
        detalleDonde = [p.numero, p.cliente, sucursal]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList(),
        tipos = (p.tipos.toList()..sort((a, b) => a.index.compareTo(b.index))),
        quienes = [
          for (final id in p.usuarios)
            if (nombresUsuario[id] != null) nombresUsuario[id]!,
        ],
        motivos = p.motivos,
        sinMotivo = p.renglones.any(_sinMotivo);
}

class _Etiqueta extends StatelessWidget {
  final TipoCortesia tipo;
  const _Etiqueta(this.tipo);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: _fondoDe(tipo), borderRadius: BorderRadius.circular(999)),
      // widthFactor 1: del ancho del texto (con alignment el Container se
      // estiraba a todo lo ancho).
      child: Center(widthFactor: 1, child: Text(tipo.etiqueta, style: _t(12, FontWeight.w700, _colorDe(tipo)))),
    );
  }
}

class _MarcaSinMotivo extends StatelessWidget {
  const _MarcaSinMotivo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, size: 15, color: _C.warn),
        const SizedBox(width: 6),
        Text('Sin motivo', style: _t(13.5, FontWeight.w600, _C.warn)),
      ],
    );
  }
}

/// Los platillos regalados de un pedido: "1× Hamburguesa  Q80.00" y sus extras.
class _Renglones extends StatelessWidget {
  final CortesiaPedido pedido;
  final double letra;
  const _Renglones({required this.pedido, this.letra = 14.5});

  @override
  Widget build(BuildContext context) {
    final mezcla = pedido.tipos.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in pedido.renglones)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 26),
                  child: Text('${_cant(r.cantidad)}×', style: _t(letra, FontWeight.w600, _C.muted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(r.nombre, style: _t(letra, FontWeight.w400, _C.ink)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 1),
                            child: Text(_dinero(r.monto), style: _t(12.5, FontWeight.w400, _C.muted)),
                          ),
                        ],
                      ),
                      // Sin esto, "2 × Hamburguesa  Q146.00" con el platillo a
                      // Q55 parece un error: lo que falta ver son los extras.
                      // Sin "Con": muchos extras ya lo dicen ("Sin cebolla").
                      if (r.extras.isNotEmpty)
                        Text(
                          r.extras.join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: _t(12.5, FontWeight.w400, _C.muted, height: 1.3),
                        ),
                      // El pedido mezcla cortesías y donaciones: cada renglón
                      // dice cuál es.
                      if (mezcla)
                        Text(r.tipo.etiqueta, style: _t(11.5, FontWeight.w600, _colorDe(r.tipo))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TablaPedidos extends StatelessWidget {
  final List<CortesiaPedido> pedidos;
  final Map<String, String> nombresUsuario;
  final Map<String, String> nombresSucursal;

  const _TablaPedidos({required this.pedidos, required this.nombresUsuario, required this.nombresSucursal});

  @override
  Widget build(BuildContext context) {
    Widget encabezado(String texto, {bool derecha = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            texto.toUpperCase(),
            textAlign: derecha ? TextAlign.right : TextAlign.left,
            style: _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6),
          ),
        );
    Widget celda(Widget child, {bool derecha = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Align(alignment: derecha ? Alignment.topRight : Alignment.topLeft, child: child),
        );
    final borde = BoxDecoration(border: Border(bottom: BorderSide(color: _C.line)));

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.1),
        1: FlexColumnWidth(1.3),
        2: FlexColumnWidth(2.8),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.8),
        5: FlexColumnWidth(1.1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: borde,
          children: [
            encabezado('Hora'),
            encabezado('Mesa · Pedido'),
            encabezado('Platillos'),
            encabezado('Tipo'),
            encabezado('Quién · Motivo'),
            encabezado('Regalado', derecha: true),
          ],
        ),
        for (var i = 0; i < pedidos.length; i++)
          () {
            final p = pedidos[i];
            final d = _DatosPedido(p, nombresUsuario, nombresSucursal[p.locationId]);
            return TableRow(
              decoration: i == pedidos.length - 1 ? null : borde,
              children: [
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.hora, style: _t(14.5, FontWeight.w600, _C.ink)),
                    if (d.fecha.isNotEmpty) Text(d.fecha, style: _t(12.5, FontWeight.w400, _C.muted)),
                  ],
                )),
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.donde, style: _t(14.5, FontWeight.w400, _C.ink)),
                    for (final x in d.detalleDonde) Text(x, style: _t(12.5, FontWeight.w400, _C.muted)),
                  ],
                )),
                celda(_Renglones(pedido: p)),
                celda(Wrap(spacing: 4, runSpacing: 4, children: [for (final t in d.tipos) _Etiqueta(t)])),
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.quienes.isNotEmpty) Text(d.quienes.join(', '), style: _t(14.5, FontWeight.w400, _C.ink)),
                    for (final m in d.motivos) Text(m, style: _t(13.5, FontWeight.w400, _C.muted)),
                    if (d.sinMotivo) const _MarcaSinMotivo(),
                  ],
                )),
                celda(Text(_dinero(p.monto), style: _t(14.5, FontWeight.w700, _C.ink)), derecha: true),
              ],
            );
          }(),
      ],
    );
  }
}

/// Un pedido en el teléfono: lo mismo que una fila de la tabla, apilado.
class _PedidoTile extends StatelessWidget {
  final CortesiaPedido pedido;
  final Map<String, String> nombresUsuario;
  final String? sucursal;

  const _PedidoTile({required this.pedido, required this.nombresUsuario, this.sucursal});

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final d = _DatosPedido(p, nombresUsuario, sucursal);
    final donde = [d.donde, ...d.detalleDonde].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(d.hora, style: _t(14.5, FontWeight.w600, _C.ink)),
                    if (d.fecha.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Text(d.fecha, style: _t(12.5, FontWeight.w400, _C.muted)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // "Regalado" y no "Total": se leía como el total del ticket.
              _montoDerecha('Regalado ${_dinero(p.monto)}', _t(14, FontWeight.w700, _C.ink)),
            ],
          ),
          const SizedBox(height: 2),
          Text(donde, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted)),
          const SizedBox(height: 10),
          _Renglones(pedido: p, letra: 14),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in d.tipos) _Etiqueta(t),
              if (d.quienes.isNotEmpty) Text(d.quienes.join(', '), style: _t(13.5, FontWeight.w500, _C.ink)),
              for (final m in d.motivos) Text(m, style: _t(13.5, FontWeight.w400, _C.muted)),
              if (d.sinMotivo) const _MarcaSinMotivo(),
            ],
          ),
        ],
      ),
    );
  }
}

// ── AVISOS ───────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? _color;
  Color get color => _color ?? _C.warn;

  const _Notice({required this.icon, required this.text, Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color == _C.warn ? _C.warnTint : _C.badTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: _t(13, FontWeight.w400, _C.ink, height: 1.45))),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Text(text, textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
    );
  }
}

// ── VISTA DE AÑO ─────────────────────────────────────────────────────────────

/// Lo que se ve en la vista de año antes de bajar los pedidos.
///
/// En año el Inicio no tiene los pedidos en memoria (los totales los suma
/// Firestore), y para ver cada cortesía hay que bajarlos todos: en el negocio
/// más grande son ~20.000 pedidos y 69 MB, que en un teléfono pueden trabar la
/// app. Por eso no se bajan solos al abrir la pantalla: se piden con un botón,
/// sabiendo lo que cuesta, igual que el Excel.
class PanelDetalleAnio extends StatelessWidget {
  final VoidCallback onCargar;
  final bool cargando;
  final String? error;

  const PanelDetalleAnio({
    super.key,
    required this.onCargar,
    this.cargando = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, color: _C.gift, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Detalle del año', style: _t(17, FontWeight.w700, _C.ink))),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                cargando
                    ? 'Bajando los pedidos del año… En un negocio grande '
                        'puede tardar unos minutos.'
                    : 'Para ver cada cortesía del año hay que bajar todos los '
                        'pedidos del año. En un negocio grande puede tardar '
                        'unos minutos, y en el teléfono más. Para algo rápido, '
                        'elegí un mes.',
                style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45),
              ),
              if (error != null && !cargando) ...[
                const SizedBox(height: 12),
                _Notice(icon: Icons.error_outline_rounded, color: _C.bad, text: error!),
              ],
              const SizedBox(height: 16),
              if (cargando)
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: CircularProgressIndicator(color: _C.accent),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onCargar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.accent,
                      foregroundColor: InicioColores.onAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      error != null ? 'Intentar de nuevo' : 'Cargar el detalle del año',
                      textAlign: TextAlign.center,
                      style: _t(14, FontWeight.w600, InicioColores.onAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
