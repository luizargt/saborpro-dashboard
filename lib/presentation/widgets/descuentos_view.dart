/// La parte visual del detalle de "Descuentos", separada de la pantalla.
///
/// Vive aparte por la misma razón que la de Cortesías: la pantalla depende de
/// providers con Firebase y no se puede montar en un test, pero esta mitad solo
/// necesita un [DescuentosReport] armado a mano, así que sí se puede probar a
/// 360dp (ver test/presentation/widgets/descuentos_view_test.dart).
///
/// Diseño (2026-11-23): `assets/Desing/Sabor Manager/descuentos.html` de
/// saborpro_app. Lo que se suma no cambia: todo sale del mismo
/// [DescuentosReport] que cuadra con la tarjeta del Inicio.
///
/// LO QUE EL DISEÑO TRAE Y ESTA VISTA NO PUEDE DECIR (el POS no lo guarda; ver
/// descuentos_data.dart): si el descuento fue en porcentaje o en monto fijo, y si
/// fue a la cuenta o a un producto. Por eso no están "¿A qué se aplicó?" ni los
/// filtros "A la cuenta" / "A un producto", y el porcentaje que se muestra es el
/// que sale de la cuenta. Tampoco está la flecha "vs ayer": no se tiene lo
/// descontado el período anterior (igual que en Cortesías).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/descuentos_data.dart';
import 'cortesias_view.dart' show CortesiasColores, cortesiasTexto;

typedef _C = CortesiasColores;
const _t = cortesiasTexto;

/// El color de lo descontado: el azul del diseño (el que Cortesías usa para las
/// donaciones).
Color get _descuento => _C.don;
Color get _descuentoFondo => _C.donTint;

final _fmtMoney = NumberFormat('#,##0.00', 'en_US');
final _fmtCant = NumberFormat('#,##0.##', 'en_US');

String _dinero(double v) => '$moneda${_fmtMoney.format(v)}';
String _cant(double v) => _fmtCant.format(v);
String _plural(num n, String uno, String varios) => n == 1 ? uno : varios;

/// "10%" y, si no es redondo, "7.5%".
String _pct(double v) {
  final r = v.round();
  return (v - r).abs() < 0.05 ? '$r%' : '${v.toStringAsFixed(1)}%';
}

/// El monto de la derecha de una fila: pegado al borde y, si no cabe (seis
/// cifras con letra grande), se parte en dos líneas en vez de salirse.
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

/// Un ícono para el motivo, por lo que dice. Los motivos los escribe el cajero
/// (o vienen de los descuentos predeterminados de la sucursal), así que se
/// reconocen por palabras y lo demás lleva un globo de texto.
IconData _iconoDeMotivo(String? motivo) {
  if (motivo == null) return Icons.warning_amber_rounded;
  final m = motivo.toLowerCase();
  bool tiene(List<String> palabras) => palabras.any(m.contains);
  if (tiene(['frecuente', 'fiel', 'vip'])) return Icons.star_outline_rounded;
  if (tiene(['error', 'equivoc', 'queja', 'reclamo', 'mal estado', 'demora'])) return Icons.restaurant_rounded;
  if (tiene(['promo', 'oferta', 'especial', 'cupón', 'cupon', 'happy'])) return Icons.campaign_outlined;
  if (tiene(['empleado', 'personal', 'staff', 'trabajador'])) return Icons.person_outline_rounded;
  if (tiene(['cumple'])) return Icons.cake_outlined;
  return Icons.chat_bubble_outline_rounded;
}

enum _Filtro { todos, sinMotivo, altos }

/// Todo el contenido desplazable: el resumen arriba, quién descuenta y por qué,
/// a qué platillos y los pedidos. En pantalla ancha van lado a lado lo que cabe;
/// en el teléfono, uno debajo del otro y los pedidos como tarjetas.
class DescuentosReportBody extends StatefulWidget {
  final DescuentosReport report;

  /// id de usuario → nombre, para decir quién cobró cada pedido (los pedidos
  /// que ya traen su nombre no lo necesitan).
  final Map<String, String> nombresUsuario;

  /// id de sucursal → nombre. Vacío cuando se mira una sola sucursal.
  final Map<String, String> nombresSucursal;

  /// El período se leyó incompleto (el Inicio llegó a su tope de pedidos).
  final bool incompleto;

  /// Los montos están convertidos a otra moneda: con decimales de más, las
  /// partes redondeadas pueden no sumar el total.
  final bool convertido;

  /// La venta del período (la "Venta Bruta" del Inicio, que ya viene con el
  /// descuento restado), para decir qué parte se descontó. null o 0 = no se
  /// muestra.
  final double? ventas;

  const DescuentosReportBody({
    super.key,
    required this.report,
    this.nombresUsuario = const {},
    this.nombresSucursal = const {},
    this.incompleto = false,
    this.convertido = false,
    this.ventas,
  });

  @override
  State<DescuentosReportBody> createState() => _DescuentosReportBodyState();
}

class _DescuentosReportBodyState extends State<DescuentosReportBody> {
  _Filtro _filtro = _Filtro.todos;

  /// La persona elegida en "¿Quién da descuentos?" (ver [DescuentoPedido.clave]).
  String? _quien;
  final _pedidosKey = GlobalKey();

  /// clave de persona → nombre: el que guardó el pedido o, si no, el que se
  /// buscó por su id.
  Map<String, String> _nombres() {
    final m = <String, String>{};
    for (final p in widget.report.pedidos) {
      final nombre = p.usuarioNombre ?? (p.usuarioId == null ? null : widget.nombresUsuario[p.usuarioId]);
      if (nombre != null) m.putIfAbsent(p.clave, () => nombre);
    }
    return m;
  }

  bool _pasa(DescuentoPedido p, _Filtro f) {
    final porTipo = switch (f) {
      _Filtro.todos => true,
      _Filtro.sinMotivo => p.sinMotivo,
      _Filtro.altos => p.alto,
    };
    final quien = _quien;
    return porTipo && (quien == null || p.clave == quien);
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
    final nombres = _nombres();
    String nombreDe(String clave) {
      if (clave.isEmpty) return 'Sin registrar';
      return nombres[clave] ?? 'Usuario';
    }

    // El nombre de la sucursal solo ayuda si hay pedidos de más de una.
    final variasSucursales =
        widget.nombresSucursal.isNotEmpty && {for (final p in r.pedidos) p.locationId}.length > 1;

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 900;
      final pad = c.maxWidth < 640 ? 16.0 : 20.0;

      final quien = _SeccionQuien(
        pedidos: r.pedidos,
        nombreDe: nombreDe,
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
              const _EmptyCard(text: 'No hubo descuentos en este período.'),
            ] else ...[
              if (r.sinMotivo > 0 || r.altos > 0) ...[
                const SizedBox(height: 16),
                _Alerta(
                  sinMotivo: r.sinMotivo,
                  montoSinMotivo: r.montoSinMotivo,
                  altos: r.altos,
                  onSinMotivo: () {
                    setState(() => _filtro = _Filtro.sinMotivo);
                    _irAPedidos();
                  },
                  onAltos: () {
                    setState(() => _filtro = _Filtro.altos);
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
                  nombreDe: nombreDe,
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
      // primera tarjeta. (Mismo arreglo que Cortesías y Pedidos cancelados.)
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
  const _Card({super.key, required this.child, this.padding});

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

/// Título de sección: "¿Quién da descuentos?" y a su lado algo chico en gris.
class _Titulo extends StatelessWidget {
  final String texto;
  final String? detalle;
  final String? nota;
  const _Titulo(this.texto, {this.detalle, this.nota});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
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
          if (nota != null) ...[
            const SizedBox(height: 4),
            Text(nota!, style: _t(12.5, FontWeight.w400, _C.soft, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// La barrita de "qué parte del mayor".
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
              child: ColoredBox(color: _descuento),
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

/// El porcentaje en una pastillita: azul, y con aro rojo cuando es alto.
class _Porcentaje extends StatelessWidget {
  final double? valor;
  final bool alto;
  const _Porcentaje(this.valor, {this.alto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _descuentoFondo,
        borderRadius: BorderRadius.circular(999),
        border: alto ? Border.all(color: _C.bad, width: 1.5) : null,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(valor == null ? '—' : _pct(valor!), style: _t(12, FontWeight.w700, _descuento)),
      ),
    );
  }
}

// ── EL RESUMEN ───────────────────────────────────────────────────────────────

class _Resumen extends StatelessWidget {
  final DescuentosReport report;
  final bool convertido;
  final double? ventas;
  const _Resumen({required this.report, required this.convertido, this.ventas});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final n = r.pedidos.length;
    final vendido = ventas;
    final conVentas = vendido != null && vendido > 0;
    final alto = r.masAlto;

    final piezas = <Widget>[
      _Cifra(
        grande: true,
        icono: Icons.sell_rounded,
        etiqueta: 'Total descontado',
        valor: _dinero(r.total),
        detalle: r.vacio ? 'Ningún descuento en este período.' : null,
      ),
      if (conVentas)
        _Cifra(
          etiqueta: 'De tus ventas',
          valor: '${(r.total / vendido * 100).toStringAsFixed(1)}%',
          detalle: 'Vendiste ${_dinero(vendido)}',
        ),
      _Cifra(
        etiqueta: 'Pedidos con descuento',
        valor: '$n',
        detalle: n == 0 ? null : 'Descuento promedio ${_pct(r.porcentajePromedio)} · ${_dinero(r.total / n)}',
      ),
      if (alto != null)
        _Cifra(
          etiqueta: 'El descuento más alto',
          valor: _pct(alto.porcentaje),
          detalle: '${_dinero(alto.descuento)} · ${alto.lugar}',
        ),
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
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded, size: 16, color: _C.soft),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Es dinero que dejaste de cobrar. Tus ventas ya vienen con el '
                    'descuento restado.'
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
                grande ? _descuento : _C.ink,
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

// ── LA ALERTA ────────────────────────────────────────────────────────────────

class _Alerta extends StatelessWidget {
  final int sinMotivo;
  final double montoSinMotivo;
  final int altos;
  final VoidCallback onSinMotivo;
  final VoidCallback onAltos;

  const _Alerta({
    required this.sinMotivo,
    required this.montoSinMotivo,
    required this.altos,
    required this.onSinMotivo,
    required this.onAltos,
  });

  @override
  Widget build(BuildContext context) {
    final alto = '${kDescuentoAlto.round()}%';
    final spans = <InlineSpan>[
      if (sinMotivo > 0) ...[
        TextSpan(
          text: '$sinMotivo ${_plural(sinMotivo, 'descuento', 'descuentos')} sin motivo',
          style: _t(14.5, FontWeight.w700, _C.ink),
        ),
        TextSpan(text: ' por ', style: _t(14.5, FontWeight.w400, _C.ink)),
        TextSpan(text: _dinero(montoSinMotivo), style: _t(14.5, FontWeight.w700, _C.ink)),
      ],
      if (sinMotivo > 0 && altos > 0) TextSpan(text: ' y ', style: _t(14.5, FontWeight.w400, _C.ink)),
      if (altos > 0)
        TextSpan(
          // Solo con altos, "2 descuentos de 30% o más"; después de lo anterior,
          // "y 2 de 30% o más".
          text: sinMotivo > 0
              ? '$altos de $alto o más'
              : '$altos ${_plural(altos, 'descuento', 'descuentos')} de $alto o más',
          style: _t(14.5, FontWeight.w700, _C.ink),
        ),
      TextSpan(text: '. Revisa si estaban autorizados.', style: _t(14.5, FontWeight.w400, _C.ink)),
    ];

    Widget boton(String texto, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: _C.card,
            foregroundColor: _C.ink,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: const StadiumBorder(),
          ),
          child: Text(texto, style: _t(14, FontWeight.w700, _C.ink)),
        );
    final botones = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (sinMotivo > 0) boton('Sin motivo', onSinMotivo),
        if (altos > 0) boton('$alto o más', onAltos),
      ],
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
        final texto = Text.rich(TextSpan(children: spans));
        if (c.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [icono, const SizedBox(width: 14), Expanded(child: texto)],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: botones),
            ],
          );
        }
        return Row(
          children: [icono, const SizedBox(width: 14), Expanded(child: texto), const SizedBox(width: 14), botones],
        );
      }),
    );
  }
}

// ── ¿QUIÉN DA DESCUENTOS? ────────────────────────────────────────────────────

class _AccQuien {
  final String clave;
  double monto = 0;
  double cuenta = 0;
  final Set<DescuentoPedido> pedidos = {};
  final Set<DescuentoPedido> sinMotivo = {};
  _AccQuien(this.clave);

  /// Lo descontado entre lo que valían sus cuentas.
  double get promedio => cuenta > 0 ? monto / cuenta * 100 : 0;
}

class _SeccionQuien extends StatelessWidget {
  final List<DescuentoPedido> pedidos;
  final String Function(String clave) nombreDe;
  final String? elegido;
  final ValueChanged<String> onElegir;

  const _SeccionQuien({
    required this.pedidos,
    required this.nombreDe,
    required this.elegido,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    final porQuien = <String, _AccQuien>{};
    for (final p in pedidos) {
      final acc = porQuien.putIfAbsent(p.clave, () => _AccQuien(p.clave));
      acc.monto += p.descuento;
      acc.cuenta += p.cuenta;
      acc.pedidos.add(p);
      if (p.sinMotivo) acc.sinMotivo.add(p);
    }
    final lista = porQuien.values.toList()
      ..sort((a, b) {
        final m = b.monto.compareTo(a.monto);
        return m != 0 ? m : b.pedidos.length.compareTo(a.pedidos.length);
      });
    final mayor = lista.isEmpty ? 0.0 : lista.first.monto;

    return _Card(
      key: const ValueKey('seccion-quien'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Quién da descuentos?', detalle: 'Toca para ver sus pedidos'),
          for (var i = 0; i < lista.length; i++) ...[
            if (i > 0) const _Separador(),
            _FilaQuien(
              nombre: nombreDe(lista[i].clave),
              pedidos: lista[i].pedidos.length,
              sinMotivo: lista[i].sinMotivo.length,
              monto: lista[i].monto,
              promedio: lista[i].promedio,
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
  final double promedio;
  final double parteDelMayor;
  final bool elegido;
  final VoidCallback onTap;

  const _FilaQuien({
    required this.nombre,
    required this.pedidos,
    required this.sinMotivo,
    required this.monto,
    required this.promedio,
    required this.parteDelMayor,
    required this.elegido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final alto = promedio >= kDescuentoAlto;
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
                            decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(999)),
                            child: Text('$sinMotivo sin motivo', style: _t(11.5, FontWeight.w700, _C.warn)),
                          ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          '$pedidos ${_plural(pedidos, 'pedido', 'pedidos')} · promedio',
                          style: _t(12.5, FontWeight.w400, _C.muted),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(
                            color: alto ? _C.badTint : _C.subtle,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _pct(promedio),
                            style: _t(11.5, FontWeight.w700, alto ? _C.bad : _C.muted),
                          ),
                        ),
                      ],
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

// ── ¿POR QUÉ SE DESCUENTA? ───────────────────────────────────────────────────

class _AccMotivo {
  /// Como lo escribió el primero que lo usó; null = sin motivo.
  final String? motivo;
  double monto = 0;
  final Set<DescuentoPedido> pedidos = {};
  _AccMotivo(this.motivo);
}

class _SeccionPorQue extends StatelessWidget {
  final List<DescuentoPedido> pedidos;
  const _SeccionPorQue({required this.pedidos});

  @override
  Widget build(BuildContext context) {
    // "Cliente frecuente" y "cliente frecuente" son el mismo motivo.
    final porMotivo = <String?, _AccMotivo>{};
    for (final p in pedidos) {
      final acc = porMotivo.putIfAbsent(p.motivo?.toLowerCase(), () => _AccMotivo(p.motivo));
      acc.monto += p.descuento;
      acc.pedidos.add(p);
    }
    final lista = porMotivo.values.toList()..sort((a, b) => b.monto.compareTo(a.monto));

    return _Card(
      key: const ValueKey('seccion-por-que'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Por qué se descuenta?'),
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
            child: Icon(_iconoDeMotivo(acc.motivo), size: 18, color: sin ? _C.warn : _C.muted),
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

// ── ¿A QUÉ SE LE HACE DESCUENTO? ─────────────────────────────────────────────

class _SeccionPlatillos extends StatefulWidget {
  final List<DescuentoPlatillo> platillos;
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

    Widget fila(DescuentoPlatillo p) => _FilaPlatillo(platillo: p, parte: mayor > 0 ? p.monto / mayor : 0);

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
      key: const ValueKey('seccion-platillos'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo(
            '¿A qué se le hace descuento?',
            detalle: '${lista.length} ${_plural(lista.length, 'platillo distinto', 'platillos distintos')}',
            // El POS descuenta de la cuenta, no de un platillo: lo que se ve acá
            // es una estimación, y es mejor decirlo que dejar que se lea como un
            // dato guardado.
            nota: 'El descuento de cada cuenta se reparte entre sus platillos según '
                'lo que valía cada uno.',
          ),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Los pedidos con descuento no traen el detalle de sus platillos.',
                style: _t(13.5, FontWeight.w400, _C.muted),
              ),
            )
          else
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
  final DescuentoPlatillo platillo;

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
          _montoDerecha(_dinero(p.monto), _t(14.5, FontWeight.w700, _descuento)),
        ],
      ),
    );
  }
}

// ── PEDIDOS ──────────────────────────────────────────────────────────────────

class _SeccionPedidos extends StatefulWidget {
  final List<DescuentoPedido> pedidos;
  final _Filtro filtro;
  final String? quien;
  final String Function(String clave) nombreDe;
  final Map<String, String> nombresSucursal;

  /// Pantalla ancha: tabla. Teléfono: una tarjeta por pedido.
  final bool tabla;
  final bool Function(DescuentoPedido p, _Filtro f) pasa;
  final ValueChanged<_Filtro> onFiltro;
  final VoidCallback onQuitarQuien;

  const _SeccionPedidos({
    required this.pedidos,
    required this.filtro,
    required this.quien,
    required this.nombreDe,
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
        for (final (f, nombre) in [
          (_Filtro.todos, 'Todos'),
          (_Filtro.sinMotivo, 'Sin motivo'),
          (_Filtro.altos, '${kDescuentoAlto.round()}% o más'),
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
        child: Text('No hay pedidos con este filtro.', textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
      );
    } else if (widget.tabla) {
      cuerpo = _TablaPedidos(
        pedidos: vistos,
        nombreDe: widget.nombreDe,
        nombresSucursal: widget.nombresSucursal,
      );
    } else {
      cuerpo = Column(
        children: [
          for (var i = 0; i < vistos.length; i++) ...[
            if (i > 0) const _Separador(),
            _PedidoTile(
              pedido: vistos[i],
              nombreDe: widget.nombreDe,
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
  final String quien;

  _DatosPedido(DescuentoPedido p, String Function(String clave) nombreDe, String? sucursal)
      : hora = p.fecha == null ? 'Sin fecha' : DateFormat('h:mm a', 'es').format(p.fecha!),
        fecha = p.fecha == null ? '' : DateFormat('EEE d MMM', 'es').format(p.fecha!),
        donde = p.lugar,
        detalleDonde = [p.numero, p.cliente, sucursal].whereType<String>().where((s) => s.isNotEmpty).toList(),
        quien = nombreDe(p.clave);
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
        Flexible(child: Text('Sin motivo', overflow: TextOverflow.ellipsis, style: _t(13.5, FontWeight.w600, _C.warn))),
      ],
    );
  }
}

/// Los platillos de la cuenta: "1× Hamburguesa  Q80.00".
class _Renglones extends StatelessWidget {
  final DescuentoPedido pedido;
  final double letra;
  const _Renglones({required this.pedido, this.letra = 14.5});

  @override
  Widget build(BuildContext context) {
    if (pedido.renglones.isEmpty) {
      return Text('—', style: _t(letra, FontWeight.w400, _C.soft));
    }
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
                  child: Wrap(
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
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La cuenta con su descuento: lo que valía tachado y, abajo, lo que quedó.
class _CuentaAntesDespues extends StatelessWidget {
  final DescuentoPedido pedido;
  const _CuentaAntesDespues({required this.pedido});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _dinero(pedido.cuenta),
          style: _t(12.5, FontWeight.w500, _C.soft).copyWith(decoration: TextDecoration.lineThrough),
        ),
        Text(_dinero(pedido.despues), style: _t(14.5, FontWeight.w600, _C.ink)),
      ],
    );
  }
}

class _TablaPedidos extends StatelessWidget {
  final List<DescuentoPedido> pedidos;
  final String Function(String clave) nombreDe;
  final Map<String, String> nombresSucursal;

  const _TablaPedidos({required this.pedidos, required this.nombreDe, required this.nombresSucursal});

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
        2: FlexColumnWidth(2.6),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.8),
        5: FlexColumnWidth(1.2),
        6: FlexColumnWidth(1.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: borde,
          children: [
            encabezado('Hora'),
            encabezado('Mesa · Pedido'),
            encabezado('Platillos'),
            encabezado('Descuento'),
            encabezado('Quién · Motivo'),
            encabezado('Cuenta', derecha: true),
            encabezado('Descontado', derecha: true),
          ],
        ),
        for (var i = 0; i < pedidos.length; i++)
          () {
            final p = pedidos[i];
            final d = _DatosPedido(p, nombreDe, nombresSucursal[p.locationId]);
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
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Porcentaje(p.tienePorcentaje ? p.porcentaje : null, alto: p.alto),
                    if (p.alto)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('alto', style: _t(12.5, FontWeight.w700, _C.bad)),
                      ),
                  ],
                )),
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.quien, style: _t(14.5, FontWeight.w400, _C.ink)),
                    if (p.motivo != null)
                      Text(p.motivo!, style: _t(13.5, FontWeight.w400, _C.muted))
                    else
                      const _MarcaSinMotivo(),
                  ],
                )),
                celda(_CuentaAntesDespues(pedido: p), derecha: true),
                celda(Text('−${_dinero(p.descuento)}', style: _t(14.5, FontWeight.w700, _descuento)), derecha: true),
              ],
            );
          }(),
      ],
    );
  }
}

/// Un pedido en el teléfono: lo mismo que una fila de la tabla, apilado.
class _PedidoTile extends StatelessWidget {
  final DescuentoPedido pedido;
  final String Function(String clave) nombreDe;
  final String? sucursal;

  const _PedidoTile({required this.pedido, required this.nombreDe, this.sucursal});

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final d = _DatosPedido(p, nombreDe, sucursal);
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
              _montoDerecha('−${_dinero(p.descuento)}', _t(16, FontWeight.w700, _descuento)),
            ],
          ),
          const SizedBox(height: 2),
          Text(donde, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(12)),
            child: _Renglones(pedido: p, letra: 14),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final quien = Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _Porcentaje(p.tienePorcentaje ? p.porcentaje : null, alto: p.alto),
                Text(d.quien, style: _t(13.5, FontWeight.w500, _C.ink)),
                if (p.motivo != null)
                  Text(p.motivo!, style: _t(13.5, FontWeight.w400, _C.muted))
                else
                  const _MarcaSinMotivo(),
              ],
            );
            final cuenta = _CuentaAntesDespues(pedido: p);
            // En un teléfono angosto (o con letra grande) quién y por qué no
            // dejan sitio a la cuenta al lado: baja a su propia línea.
            if (c.maxWidth < 460) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  quien,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: cuenta),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [Expanded(child: quien), const SizedBox(width: 10), cuenta],
            );
          }),
        ],
      ),
    );
  }
}

// ── AVISOS ───────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _C.warn, size: 18),
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
