/// La parte visual del reporte "Pedidos Cancelados", separada de la pantalla.
///
/// Vive aparte a propósito: la pantalla depende de providers con Firebase y no
/// se puede montar en un test, pero la regla del proyecto es verificar cada UI
/// nueva a 360dp con un widget test que falle si algo desborda. Esta mitad solo
/// necesita un [CancellationsReport] armado a mano, así que sí se puede probar
/// (ver test/presentation/widgets/cancellations_view_test.dart).
///
/// Diseño (2026-11-20): `assets/Desing/Sabor Manager/cancelados.html` de
/// saborpro_app, en su modo oscuro (la misma paleta del detalle de cortesías).
/// Los números NO cambian de significado: sale todo del mismo
/// [CancellationsReport]. El titular sigue siendo lo perdido a precio de venta
/// (incluye lo que no tiene receta) y los porcentajes siguen midiéndose en
/// artículos, no en quetzales (ver [PersonCut.lostRate]).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/cancellation_data.dart';
import 'cortesias_view.dart' show CortesiasColores, cortesiasTexto, kCortesiasBg;

/// Fondo de la pantalla.
Color get kCancelBg => kCortesiasBg;

/// La paleta y el texto del diseño: los mismos del detalle de cortesías.
typedef CancelColores = CortesiasColores;

TextStyle cancelTexto(double size, FontWeight weight, Color color, {double? height}) =>
    cortesiasTexto(size, weight, color, height: height);

typedef _C = CortesiasColores;
const _t = cortesiasTexto;

final _fmtMoney = NumberFormat('#,##0.00', 'en_US');
final _fmtInt = NumberFormat('#,##0', 'en_US');

String _dinero(double v) => '$moneda${_fmtMoney.format(v)}';
String _plural(num n, String uno, String varios) => n == 1 ? uno : varios;
String _pct(double fraccion) => '${(fraccion * 100).round()}%';

/// Un [PartialValue] sin mentir: lo que tiene precio, en dinero; lo que no, en
/// unidades. Nunca "Q0.00" para algo que sí se perdió: eso es exactamente lo
/// que hace que un faltante pase desapercibido.
String _valor(PartialValue v) {
  if (v.isEmpty) return '—';
  if (!v.hasMoney) return v.unpricedLabel;
  return v.hasUnpriced ? '${_dinero(v.amount)} + ${v.unpricedLabel}' : _dinero(v.amount);
}

/// Iniciales para el círculo de cada persona ("Ana Cosme" → "AC").
String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  return partes.take(2).map((p) => p.characters.first.toUpperCase()).join();
}

/// El monto de la derecha de una fila: pegado al borde y, si no cabe, se parte
/// en dos líneas en vez de salirse.
Widget _montoDerecha(String texto, TextStyle estilo) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(texto, textAlign: TextAlign.right, style: estilo),
    );

// "prueba" / "pruebas" como palabra, con un número o un guion bajo pegado
// ("Prueba2", "prueba_3") también: "aprueba" o "comprueba" no son pruebas.
final _reEsPrueba = RegExp(r'(?<![a-záéíóúüñ])pruebas?(?![a-záéíóúüñ])', caseSensitive: false);

bool _esPrueba(CancellationEvent e) {
  final r = e.reason;
  return r != null && _reEsPrueba.hasMatch(r);
}

String _claveMotivo(String? r) =>
    (r ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Alguien "salta a la vista" cuando marca perdido bastante más seguido que la
/// casa. Se exige un mínimo de casos para no señalar a quien anuló dos cosas y
/// tuvo mala suerte.
bool _destaca(CancellationsReport r, PersonCut p) {
  if (p.itemsLost < 3) return false;
  final umbral = (r.houseLostRate * 1.5).clamp(0.2, 1.0);
  return p.lostRate > umbral;
}

/// Lo que dice la lista cuando no tiene ninguna fila. No puede decir "ninguna
/// cancelación" a secas si el resumen de arriba trae montos o si la consulta se
/// quedó corta: se leería como una contradicción.
String _textoVacio(CancellationsReport r) {
  if (r.truncated) {
    return 'Ninguna cancelación en lo que se pudo leer de este periodo.';
  }
  if (r.saleWaste.items > 0 || r.cancelledValueOrders > 0) {
    return 'La lista no trae filas pero el resumen de arriba sí tiene montos: '
        'faltan los datos de esos pedidos para mostrarlos.';
  }
  return 'Ninguna cancelación en este periodo.';
}

enum _Estado { todos, merma, regreso, sinReceta, sinCocina }

/// Todo el contenido desplazable: el resumen arriba, los avisos, quién declara
/// merma y por qué se cancela, y las cancelaciones. En pantalla ancha van lado
/// a lado lo que cabe y las cancelaciones en tabla; en el teléfono, uno debajo
/// del otro y las cancelaciones como tarjetas.
class CancellationsReportBody extends StatefulWidget {
  final CancellationsReport report;

  const CancellationsReportBody({super.key, required this.report});

  @override
  State<CancellationsReportBody> createState() => _CancellationsReportBodyState();
}

class _CancellationsReportBodyState extends State<CancellationsReportBody> {
  _Estado _estado = _Estado.todos;

  /// La persona elegida (en "¿Quién declara merma?" o en el aviso), o null.
  String? _quien;
  bool _soloPruebas = false;
  final _tablaKey = GlobalKey();

  @override
  void didUpdateWidget(covariant CancellationsReportBody old) {
    super.didUpdateWidget(old);
    // Con otro período o sucursal puede que la persona ya no esté.
    final q = _quien;
    if (q != null && !widget.report.people.any((p) => p.userName == q)) _quien = null;
  }

  bool _cumple(CancellationEvent e, _Estado f) => switch (f) {
        _Estado.todos => true,
        // Merma de inventario, o un renglón que se declaró perdido aunque no
        // tenga receta (no hay costo que mostrar, pero se perdió).
        _Estado.merma => (e.movedInventory && !e.wasted.isEmpty) || e.items.any((i) => i.declaredLost),
        _Estado.regreso => e.movedInventory && !e.returned.isEmpty,
        _Estado.sinReceta => e.impact == InventoryImpact.sinReceta,
        _Estado.sinCocina => e.impact == InventoryImpact.sinCocina,
      };

  bool _pasa(CancellationEvent e, _Estado f) {
    final q = _quien;
    // Por cualquiera que haya firmado algo de la cancelación, no solo el
    // primero: así el pedido aparece para cada persona de su fila.
    return _cumple(e, f) && (q == null || e.signedBy(q)) && (!_soloPruebas || _esPrueba(e));
  }

  /// Baja hasta las cancelaciones (después de filtrar desde arriba).
  void _irALaTabla() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tablaKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.02);
    });
  }

  void _filtrar({_Estado estado = _Estado.todos, String? quien, bool pruebas = false}) {
    setState(() {
      _estado = estado;
      _quien = quien;
      _soloPruebas = pruebas;
    });
    _irALaTabla();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;

    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 900;
      final pad = c.maxWidth < 640 ? 16.0 : 20.0;

      final quien = _SeccionQuien(
        report: r,
        elegido: _quien,
        onElegir: (nombre) {
          setState(() => _quien = _quien == nombre ? null : nombre);
          if (_quien != null) _irALaTabla();
        },
      );
      final porque = _SeccionPorQue(events: r.events);

      final lista = SingleChildScrollView(
        // Siempre desplazable: el RefreshIndicator lo necesita aunque haya una
        // sola cancelación.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Resumen(report: r),
            if (r.truncated) ...[
              const SizedBox(height: 16),
              const _Notice(
                icon: Icons.warning_amber_rounded,
                text: 'Hay más movimientos de los que se pueden leer de una vez. '
                    'Los totales de abajo se quedan cortos: acortá el periodo para '
                    'verlo completo.',
              ),
            ],
            if (r.withoutPaidOrders) ...[
              const SizedBox(height: 16),
              const _Notice(
                icon: Icons.info_outline_rounded,
                // La vista de año pide los totales a Firestore y no baja los
                // pedidos: lo anulado dentro de pedidos ya cobrados no se lee.
                text: 'En la vista de año no se leen los pedidos cobrados: lo perdido '
                    'y lo anulado a precio de venta pueden quedar cortos. Elegí un '
                    'mes para verlos completos.',
              ),
            ],
            if (r.unpricedIngredients > 0) ...[
              const SizedBox(height: 16),
              _Notice(
                icon: Icons.help_outline_rounded,
                text: '${r.unpricedIngredients} '
                    '${r.unpricedIngredients == 1 ? "ingrediente no tiene" : "ingredientes no tienen"} '
                    'precio de compra. Lo que se perdió de ellos se cuenta en '
                    'unidades, no en quetzales: no es que valgan cero.',
              ),
            ],
            if (r.isEmpty) ...[
              const SizedBox(height: 16),
              _EmptyCard(text: _textoVacio(r)),
            ] else ...[
              _Alertas(
                report: r,
                onPersona: (nombre) => _filtrar(quien: nombre),
                onSinReceta: () => _filtrar(estado: _Estado.sinReceta),
                onPruebas: () => _filtrar(pruebas: true),
              ),
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
              KeyedSubtree(
                key: _tablaKey,
                child: _SeccionCancelaciones(
                  events: r.events,
                  estado: _estado,
                  quien: _quien,
                  soloPruebas: _soloPruebas,
                  tabla: ancho,
                  pasa: _pasa,
                  hayEnEstado: (f) => r.events.any((e) => _cumple(e, f)),
                  // "Todos" es sin filtro alguno: también quita a la persona y
                  // las pruebas, como en el diseño.
                  onEstado: (f) => setState(() {
                    _estado = f;
                    if (f == _Estado.todos) {
                      _quien = null;
                      _soloPruebas = false;
                    }
                  }),
                  onQuitarQuien: () => setState(() => _quien = null),
                  onQuitarPruebas: () => setState(() => _soloPruebas = false),
                ),
              ),
            ],
          ],
        ),
      );

      // Con poco que mostrar (sin cancelaciones) el contenido es más bajo que la
      // pantalla. El cambio de sucursal (un AnimatedSwitcher) entrega
      // restricciones sueltas y un SingleChildScrollView mide lo que mide su
      // contenido: sin esto quedaba CENTRADO en vertical, con un hueco enorme
      // entre las pestañas y la primera tarjeta. Obligándolo a medir al menos el
      // alto disponible, el contenido se queda arriba y la zona de jalar para
      // actualizar cubre todo el alto.
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
    // Por el ancho de la pantalla y no con LayoutBuilder: dos tarjetas van lado
    // a lado dentro de un IntrinsicHeight, que no lo admite.
    final telefono = MediaQuery.sizeOf(context).width < 640;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(telefono ? 18 : 22),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      child: child,
    );
  }
}

/// Título de sección: "¿Quién declara merma?".
class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) => Text(texto, style: _t(17, FontWeight.w700, _C.ink));
}

/// La barrita de "qué parte".
class _Barra extends StatelessWidget {
  final double parte;
  final Color color;
  const _Barra(this.parte, {required this.color});

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
              child: ColoredBox(color: color),
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
  final CancellationsReport report;
  const _Resumen({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;

    // El titular es lo perdido a PRECIO DE VENTA y no el costo de ingredientes.
    // Dos razones: es el número que el dueño lee sin que nadie se lo explique,
    // y es el único que incluye los productos SIN RECETA, que no generan
    // movimiento y por eso faltaban en todo el reporte. El costo queda en
    // "Inventario", donde se puede comparar.
    final huboPerdida = r.saleWaste.items > 0 || r.itemsLost > 0;
    // Hubo merma en inventario pero no se leyó ningún pedido para ponerle
    // precio de venta (vista de año): se sabe que se perdió algo y no cuánto.
    final sinPrecioDeVenta = r.saleWaste.items == 0 && r.itemsLost > 0;
    // Q0.00 solo cuando de verdad no se perdió nada. Si hubo desperdicio pero
    // no se pudo poner precio, va un guion: un cero se lee como "no pasó nada",
    // que es justo lo contrario.
    final perdido = (r.saleWaste.items > 0 && r.saleWaste.amount == 0) || sinPrecioDeVenta
        ? '—'
        : _dinero(r.saleWaste.amount);

    // El valor de lo anulado sale de los pedidos. Si hay cancelaciones pero no
    // se pudo leer ningún pedido (vista de año), no se sabe: guion, no Q0.00.
    final valorDesconocido = r.cancelledValueOrders == 0 && r.events.isNotEmpty;
    final sinPrecio = r.events.where((e) => e.value == null).length;

    final piezas = <Widget>[
      _Cifra(
        grande: true,
        icono: Icons.delete_outline_rounded,
        etiqueta: 'Producto perdido',
        valor: perdido,
        colorValor: _C.bad,
        detalle: !huboPerdida
            ? 'Nadie declaró producto perdido.'
            : sinPrecioDeVenta
                ? 'Sin el precio de venta de los pedidos'
                : 'A precio de venta, lo que se declaró perdido',
      ),
      _Cifra(
        etiqueta: 'Valor cancelado',
        valor: valorDesconocido ? '—' : _dinero(r.cancelledValue),
        detalle: valorDesconocido
            ? 'Sin el precio de esos pedidos'
            : '${r.cancelledValueOrders} ${_plural(r.cancelledValueOrders, 'pedido', 'pedidos')} '
                'a precio de venta',
        aviso: !valorDesconocido && sinPrecio > 0
            ? 'Sin precio: $sinPrecio ${_plural(sinPrecio, 'cancelación', 'cancelaciones')} de la lista'
            : null,
      ),
      _Cifra(
        etiqueta: 'Se declaró perdido',
        valor: r.itemsCancelled == 0 ? '—' : _pct(r.houseLostRate),
        // En artículos y no en quetzales: con más de la mitad de los
        // ingredientes sin precio de compra, un porcentaje en dinero mentiría.
        // Cuentan los artículos a los que se les preguntó qué regresaba a la
        // despensa, tengan receta o no; los que nunca se preguntaron no.
        detalle: r.itemsCancelled == 0
            ? 'Ningún artículo con pregunta de despensa'
            : '${_fmtInt.format(r.itemsLost)} de ${_fmtInt.format(r.itemsCancelled)} '
                'artículos con pregunta de despensa',
      ),
      _CeldaInventario(report: r),
    ];

    // Lo que costaron los ingredientes de TODO lo anulado y, de eso, lo que se
    // perdió. No es "el costo de lo perdido": el titular de arriba es el precio
    // de venta, y juntos podrían leerse como lo mismo.
    final costo = r.totalReturned + r.totalWasted;
    final costoTexto = costo.isEmpty
        ? ''
        : 'Costo de los ingredientes de lo anulado: ${_valor(costo)}'
            '${r.totalWasted.isEmpty ? '' : ', de los que se perdieron ${_valor(r.totalWasted)}'}. ';

    return Container(
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final columnas = c.maxWidth >= 900 ? piezas.length : (c.maxWidth >= 560 ? 2 : 1);
            return _Rejilla(
              columnas: columnas,
              primeraMasAncha: columnas == piezas.length,
              children: piezas,
            );
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // En muted y no en soft: soft sobre la tarjeta da 4.2:1,
                      // menos que lo que pide un texto de este tamaño.
                      Text(
                        '${costoTexto}Los pedidos sin receta no se pueden devolver al inventario.',
                        style: _t(12.5, FontWeight.w400, _C.muted, height: 1.4),
                      ),
                      if (r.saleWaste.hayInvisible) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_dinero(r.saleWaste.withoutRecipeAmount)} '
                          'son ${_fmtInt.format(r.saleWaste.withoutRecipeItems)} '
                          '${_plural(r.saleWaste.withoutRecipeItems, 'producto', 'productos')} '
                          'sin receta: no bajan inventario ni tienen costo.',
                          style: _t(12.5, FontWeight.w400, _C.muted, height: 1.4),
                        ),
                      ],
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

/// Las cifras del resumen en [columnas], con una línea entre cada una (como las
/// celdas del diseño). Con todas en una fila, la primera es más ancha.
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
  final Color? _colorValor;
  Color get colorValor => _colorValor ?? _C.ink;
  final String? detalle;

  /// Una línea de aviso (en ámbar) bajo el detalle.
  final String? aviso;

  const _Cifra({
    this.grande = false,
    this.icono,
    required this.etiqueta,
    required this.valor,
    Color? colorValor,
    this.detalle,
    this.aviso,
  }) : _colorValor = colorValor;

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
              style: _t(grande ? (telefono ? 34 : 40) : 26, FontWeight.w800, colorValor, height: 1.15),
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 4),
            Text(detalle!, style: _t(13, FontWeight.w400, _C.muted)),
          ],
          if (aviso != null) ...[
            const SizedBox(height: 4),
            Text(aviso!, style: _t(12.5, FontWeight.w600, _C.warn)),
          ],
        ],
      ),
    );
  }
}

/// Qué pasó con el inventario: lo que regresó contra la merma (en costo de
/// ingredientes) y cuántos pedidos no lo tocaron.
class _CeldaInventario extends StatelessWidget {
  final CancellationsReport report;
  const _CeldaInventario({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    // La barra reparte solo lo que tiene precio de compra; lo que no, va en las
    // leyendas, en unidades.
    final regreso = r.totalReturned.amount;
    final merma = r.totalWasted.amount;
    // Si un lado es solo unidades sin precio, repartir por dinero mentiría (lo
    // regresado saldría 100% aunque se perdieran 20 botellas): barra neutra, y
    // las leyendas dicen cuánto es de cada cosa.
    final soloUnidades = (r.totalReturned.hasUnpriced && !r.totalReturned.hasMoney) ||
        (r.totalWasted.hasUnpriced && !r.totalWasted.hasMoney);
    final total = soloUnidades ? 0.0 : regreso + merma;
    final sinTocar = r.cancelledBeforeKitchen + r.cancelledWithoutRecipe;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Inventario', style: _t(13, FontWeight.w600, _C.muted)),
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
                        if (regreso > 0)
                          Expanded(
                            flex: (regreso / total * 1000).round().clamp(1, 1000),
                            child: Container(color: _C.gift),
                          ),
                        if (merma > 0)
                          Expanded(
                            flex: (merma / total * 1000).round().clamp(1, 1000),
                            child: Container(color: _C.bad),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          _Leyenda(color: _C.gift, etiqueta: 'Regresó a despensa', valor: _valor(r.totalReturned)),
          const SizedBox(height: 6),
          _Leyenda(color: _C.bad, etiqueta: 'Merma', valor: _valor(r.totalWasted)),
          const SizedBox(height: 6),
          _Leyenda(
            color: _C.lineStrong,
            etiqueta: 'Sin tocar inventario',
            valor: sinTocar == 0 ? '—' : '$sinTocar ${_plural(sinTocar, 'pedido', 'pedidos')}',
          ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String etiqueta;
  final String valor;
  const _Leyenda({required this.color, required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(etiqueta, style: _t(13, FontWeight.w400, _C.muted))),
        const SizedBox(width: 8),
        _montoDerecha(valor, _t(13, FontWeight.w600, valor == '—' ? _C.soft : _C.ink)),
      ],
    );
  }
}

// ── AVISOS ───────────────────────────────────────────────────────────────────

enum _Tono { rojo, info, ambar }

class _Trozo {
  final String texto;
  final bool negrita;
  const _Trozo(this.texto, {this.negrita = false});
}

/// Lo que merece atención, de lo más grave a lo menos: quién destaca, qué no
/// se puede saber y qué son pruebas. Cada aviso lleva un botón que filtra la
/// lista de abajo.
class _Alertas extends StatelessWidget {
  final CancellationsReport report;
  final ValueChanged<String> onPersona;
  final VoidCallback onSinReceta;
  final VoidCallback onPruebas;

  const _Alertas({
    required this.report,
    required this.onPersona,
    required this.onSinReceta,
    required this.onPruebas,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    final alertas = <Widget>[];

    // Quien más destaca (las personas ya vienen de más a menos % perdido).
    final destacada = r.people.where((p) => _destaca(r, p)).firstOrNull;
    if (destacada != null) {
      final n = destacada.events;
      alertas.add(_Alerta(
        tono: _Tono.rojo,
        trozos: [
          _Trozo(destacada.userName, negrita: true),
          const _Trozo(' declaró '),
          _Trozo('${destacada.itemsLost} de ${destacada.itemsCancelled}', negrita: true),
          _Trozo(' artículos como perdidos en $n ${_plural(n, 'cancelación', 'cancelaciones')}: '
              '${_pct(destacada.lostRate)} no regresó (promedio de la casa ${_pct(r.houseLostRate)}).'),
        ],
        boton: 'Ver sus cancelaciones',
        onTap: () => onPersona(destacada.userName),
      ));
    }

    // Pedidos que llegaron a cocina y no tienen receta: no se sabe si lo que
    // se hizo volvió a la despensa.
    final sinReceta = r.events.where((e) => e.impact == InventoryImpact.sinReceta).toList();
    if (sinReceta.isNotEmpty) {
      final productos = {for (final e in sinReceta) for (final i in e.items) i.name}.length;
      alertas.add(_Alerta(
        tono: _Tono.info,
        trozos: [
          _Trozo('${sinReceta.length} ${_plural(sinReceta.length, 'pedido sin receta', 'pedidos sin receta')}',
              negrita: true),
          _Trozo(' ($productos ${_plural(productos, 'producto', 'productos')}): '
              'no se sabe si regresaron al inventario.'),
        ],
        boton: 'Ver cuáles',
        onTap: onSinReceta,
      ));
    }

    // Las pruebas hechas en el sistema real inflan este reporte.
    final pruebas = r.events.where(_esPrueba).toList();
    if (pruebas.isNotEmpty) {
      final conPrecio = pruebas.every((e) => e.value != null);
      final monto = pruebas.fold(0.0, (s, e) => s + (e.value ?? 0));
      alertas.add(_Alerta(
        tono: _Tono.ambar,
        trozos: [
          _Trozo(
              '${pruebas.length} ${_plural(pruebas.length, 'cancelación de prueba', 'cancelaciones de prueba')}',
              negrita: true),
          _Trozo('${conPrecio ? ' por ${_dinero(monto)}' : ''}. '
              'Las pruebas en el sistema real inflan este reporte.'),
        ],
        boton: 'Ver',
        onTap: onPruebas,
      ));
    }

    if (alertas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < alertas.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            alertas[i],
          ],
        ],
      ),
    );
  }
}

class _Alerta extends StatelessWidget {
  final _Tono tono;
  final List<_Trozo> trozos;
  final String boton;
  final VoidCallback onTap;

  const _Alerta({required this.tono, required this.trozos, required this.boton, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (fondo, colorIcono) = switch (tono) {
      _Tono.rojo => (_C.badTint, _C.bad),
      _Tono.info => (_C.subtle, _C.muted),
      _Tono.ambar => (_C.warnTint, _C.warn),
    };
    final texto = Text.rich(
      TextSpan(children: [
        for (final t in trozos)
          TextSpan(text: t.texto, style: _t(14.5, t.negrita ? FontWeight.w700 : FontWeight.w400, _C.ink)),
      ]),
    );
    final boton = TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: _C.card,
        foregroundColor: _C.ink,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(),
      ),
      child: Text(this.boton, style: _t(14, FontWeight.w700, _C.ink)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: LayoutBuilder(builder: (context, c) {
        final icono = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.warning_amber_rounded, color: colorIcono, size: 22),
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

// ── ¿QUIÉN DECLARA MERMA? ────────────────────────────────────────────────────

/// El corte por persona.
///
/// Es la parte más importante del reporte: el dueño decidió que cualquiera
/// pueda declarar merma sin PIN ni permiso, así que el único control que queda
/// es a posteriori. Lo que delata a alguien no es cuánto canceló, sino qué
/// PORCENTAJE de lo que canceló declaró perdido: cancelar mucho puede ser el
/// turno; marcar "no regresa" mucho más que el resto, no.
class _SeccionQuien extends StatelessWidget {
  final CancellationsReport report;
  final String? elegido;
  final ValueChanged<String> onElegir;

  const _SeccionQuien({required this.report, required this.elegido, required this.onElegir});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final casa = (r.houseLostRate * 100).round();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Quién declara merma?'),
          const SizedBox(height: 6),
          Text(
            'Declarar merma no pide permiso. Esta es la única revisión que queda.',
            style: _t(13, FontWeight.w400, _C.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (r.people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Nadie canceló nada en este periodo.', style: _t(14, FontWeight.w400, _C.muted)),
            ),
          for (var i = 0; i < r.people.length; i++) ...[
            if (i > 0) const _Separador(),
            _FilaPersona(
              persona: r.people[i],
              casa: casa,
              elegida: elegido == r.people[i].userName,
              onTap: () => onElegir(r.people[i].userName),
            ),
          ],
          if (r.itemsCancelled > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Promedio de la casa: $casa% de lo anulado se declaró perdido.',
              style: _t(13, FontWeight.w400, _C.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaPersona extends StatelessWidget {
  final PersonCut persona;

  /// El % de la casa, redondeado: el color del porcentaje de cada quien sale de
  /// compararlo con este.
  final int casa;
  final bool elegida;
  final VoidCallback onTap;

  const _FilaPersona({
    required this.persona,
    required this.casa,
    required this.elegida,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final pct = (p.lostRate * 100).round();
    // En rojo solo con una muestra que diga algo: 1 de 1 es 100% y es mala
    // suerte, no un patrón (el mismo mínimo de tres de [_destaca]).
    final alto = pct > casa && p.itemsLost >= 3;
    final n = p.events;

    return Material(
      color: elegida ? _C.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: elegida ? 8 : 0, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _C.tint, shape: BoxShape.circle),
                child: Text(_iniciales(p.userName), style: _t(14, FontWeight.w700, _C.accent)),
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
                        Text(p.userName, style: _t(15, FontWeight.w600, _C.ink)),
                        // Sin artículos que hayan pasado por inventario no hay
                        // porcentaje que dar.
                        if (p.itemsCancelled > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: alto ? _C.badTint : _C.giftTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$pct% perdido',
                              style: _t(11.5, FontWeight.w700, alto ? _C.bad : _C.gift),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 14,
                      runSpacing: 2,
                      children: [
                        _Dato(
                          negrita: '$n',
                          texto: ' ${_plural(n, 'cancelación', 'cancelaciones')}',
                        ),
                        _Dato(texto: 'Regresó ', negrita: _valor(p.returned)),
                        // De cuántos sale el porcentaje: 100% de 1 artículo no
                        // es lo mismo que 100% de 30.
                        if (p.itemsCancelled > 0)
                          _Dato(
                            negrita: '${p.itemsLost} de ${p.itemsCancelled}',
                            texto: ' ${_plural(p.itemsCancelled, 'artículo perdido', 'artículos perdidos')}',
                          ),
                        if (p.eventsWithoutInventory > 0)
                          Text(
                            '${p.eventsWithoutInventory} sin efecto en inventario',
                            style: _t(12.5, FontWeight.w400, _C.muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // La barra es el % declarado perdido, que es lo que ordena
                    // la lista: la más larga es la de quien más marca "no
                    // regresa".
                    _Barra(p.lostRate, color: _C.bad),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 120 y no 150: con letra grande y un monto mixto ("Q44.00 + 6 u")
              // la columna de la derecha le quitaba el ancho a la del medio y
              // "cancelaciones" se partía a media palabra.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Declaró productos perdidos pero ninguno tiene costo (sin
                    // receta): un guion diría que no declaró nada.
                    Text(
                      p.wasted.isEmpty && p.itemsLost > 0 ? 'sin costo' : _valor(p.wasted),
                      textAlign: TextAlign.right,
                      style: _t(
                        p.wasted.isEmpty && p.itemsLost > 0 ? 13 : 15,
                        FontWeight.w700,
                        p.wasted.isEmpty && p.itemsLost == 0 ? _C.muted : _C.bad,
                      ),
                    ),
                    Text('merma', style: _t(12, FontWeight.w400, _C.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 cancelaciones" o "Regresó Q31.00", con la parte importante en negrita.
class _Dato extends StatelessWidget {
  final String texto;
  final String negrita;
  const _Dato({required this.texto, required this.negrita});

  @override
  Widget build(BuildContext context) {
    final normal = _t(12.5, FontWeight.w400, _C.muted);
    final fuerte = _t(12.5, FontWeight.w600, _C.ink);
    // La negrita va primero cuando el texto empieza con espacio ("3" + "
    // cancelaciones") y después cuando no ("Regresó " + "Q31.00").
    final primeroNegrita = texto.startsWith(' ');
    return Text.rich(TextSpan(children: [
      if (primeroNegrita) TextSpan(text: negrita, style: fuerte),
      TextSpan(text: texto, style: normal),
      if (!primeroNegrita) TextSpan(text: negrita, style: fuerte),
    ]));
  }
}

// ── ¿POR QUÉ SE CANCELA? ─────────────────────────────────────────────────────

class _AccMotivo {
  final String titulo;
  final bool sinMotivo;
  final bool prueba;
  final List<CancellationEvent> events = [];
  _AccMotivo(this.titulo, {required this.sinMotivo, required this.prueba});

  /// null si de alguna cancelación no se sabe cuánto valía.
  double? get valor {
    var total = 0.0;
    for (final e in events) {
      final v = e.value;
      if (v == null) return null;
      total += v;
    }
    return total;
  }
}

class _SeccionPorQue extends StatefulWidget {
  final List<CancellationEvent> events;
  const _SeccionPorQue({required this.events});

  @override
  State<_SeccionPorQue> createState() => _SeccionPorQueState();
}

class _SeccionPorQueState extends State<_SeccionPorQue> {
  static const _kMuestra = 8;
  bool _todos = false;

  @override
  Widget build(BuildContext context) {
    // Por el motivo escrito, sin distinguir mayúsculas ni espacios de más.
    final porMotivo = <String, _AccMotivo>{};
    for (final e in widget.events) {
      final clave = _claveMotivo(e.reason);
      final acc = porMotivo.putIfAbsent(clave, () {
        final texto = (e.reason ?? '').trim();
        return _AccMotivo(
          texto.isEmpty ? 'Sin motivo anotado' : texto,
          sinMotivo: texto.isEmpty,
          prueba: _esPrueba(e),
        );
      });
      acc.events.add(e);
    }
    // De más a menos valor; los que no se pueden valorar, al final.
    final lista = porMotivo.values.toList()
      ..sort((a, b) {
        final va = a.valor ?? -1, vb = b.valor ?? -1;
        final v = vb.compareTo(va);
        return v != 0 ? v : b.events.length.compareTo(a.events.length);
      });
    final vistos = _todos ? lista : lista.take(_kMuestra).toList();
    final resto = lista.length - vistos.length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('¿Por qué se cancela?'),
          const SizedBox(height: 8),
          for (var i = 0; i < vistos.length; i++) ...[
            if (i > 0) const _Separador(),
            _FilaMotivo(acc: vistos[i]),
          ],
          if (resto > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _todos = true),
                child: Text('Ver los ${lista.length} motivos', style: _t(13.5, FontWeight.w600, _C.accent)),
              ),
            ),
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
    final aviso = acc.prueba || acc.sinMotivo;
    final n = acc.events.length;
    final unica = n == 1 ? acc.events.first : null;
    final valor = acc.valor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: aviso ? _C.warnTint : _C.subtle,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              aviso ? Icons.warning_amber_rounded : Icons.chat_bubble_outline_rounded,
              size: 18,
              color: aviso ? _C.warn : _C.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(acc.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w600, _C.ink)),
                Text(
                  unica != null ? '${unica.tableLabel} · ${unica.userName}' : '$n cancelaciones',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _montoDerecha(
            valor == null ? '—' : _dinero(valor),
            _t(14.5, FontWeight.w700, valor == null ? _C.soft : _C.ink),
          ),
        ],
      ),
    );
  }
}

// ── CANCELACIONES ────────────────────────────────────────────────────────────

class _SeccionCancelaciones extends StatefulWidget {
  final List<CancellationEvent> events;
  final _Estado estado;
  final String? quien;
  final bool soloPruebas;

  /// Pantalla ancha: tabla. Teléfono: una tarjeta por cancelación.
  final bool tabla;
  final bool Function(CancellationEvent e, _Estado f) pasa;

  /// Si alguna cancelación (de todas, sin otros filtros) cae en ese estado: los
  /// estados que nunca ocurrieron no ofrecen botón.
  final bool Function(_Estado f) hayEnEstado;
  final ValueChanged<_Estado> onEstado;
  final VoidCallback onQuitarQuien;
  final VoidCallback onQuitarPruebas;

  const _SeccionCancelaciones({
    required this.events,
    required this.estado,
    required this.quien,
    required this.soloPruebas,
    required this.tabla,
    required this.pasa,
    required this.hayEnEstado,
    required this.onEstado,
    required this.onQuitarQuien,
    required this.onQuitarPruebas,
  });

  @override
  State<_SeccionCancelaciones> createState() => _SeccionCancelacionesState();
}

class _SeccionCancelacionesState extends State<_SeccionCancelaciones> {
  static const _kMuestra = 20;
  bool _todas = false;

  /// Las cancelaciones con la lista de platillos desplegada.
  final _abiertas = <String>{};

  @override
  void didUpdateWidget(covariant _SeccionCancelaciones old) {
    super.didUpdateWidget(old);
    // Otro filtro, otra lista: se vuelve a ver desde las primeras.
    if (old.estado != widget.estado || old.quien != widget.quien || old.soloPruebas != widget.soloPruebas) {
      _todas = false;
    }
  }

  void _alternar(String id) => setState(() => _abiertas.contains(id) ? _abiertas.remove(id) : _abiertas.add(id));

  @override
  Widget build(BuildContext context) {
    final todos = widget.events;
    final lista = todos.where((e) => widget.pasa(e, widget.estado)).toList();
    final vistos = _todas ? lista : lista.take(_kMuestra).toList();
    final resto = lista.length - vistos.length;

    final filtros = Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: widget.tabla ? WrapAlignment.end : WrapAlignment.start,
      children: [
        if (widget.quien != null)
          _Chip(texto: widget.quien!, elegido: true, alQuitar: true, onTap: widget.onQuitarQuien),
        if (widget.soloPruebas)
          _Chip(texto: 'Pruebas', elegido: true, alQuitar: true, onTap: widget.onQuitarPruebas),
        for (final (f, nombre) in const [
          (_Estado.todos, 'Todos'),
          (_Estado.merma, 'Merma'),
          (_Estado.regreso, 'Regresó'),
          (_Estado.sinReceta, 'Sin receta'),
          (_Estado.sinCocina, 'No llegó a cocina'),
        ])
          // Los dos últimos solo si alguna vez pasó: no tiene caso ofrecer un
          // botón que siempre dice cero.
          if (f.index <= _Estado.regreso.index || widget.hayEnEstado(f) || widget.estado == f)
            _Chip(
              texto: nombre,
              cuenta: todos.where((e) => widget.pasa(e, f)).length,
              // "Todos" solo está elegido sin la persona ni las pruebas: con
              // ellas, los que se ven elegidos son sus botones con equis.
              elegido: f == _Estado.todos
                  ? widget.estado == f && widget.quien == null && !widget.soloPruebas
                  : widget.estado == f,
              onTap: () => widget.onEstado(f),
            ),
      ],
    );

    final encabezado = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 2,
      children: [
        Text('Cancelaciones', style: _t(17, FontWeight.w700, _C.ink)),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('${lista.length} de ${todos.length}', style: _t(13, FontWeight.w400, _C.muted)),
        ),
      ],
    );

    final Widget cuerpo;
    if (lista.isEmpty) {
      cuerpo = Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Text('No hay cancelaciones con este filtro.',
            textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
      );
    } else if (widget.tabla) {
      cuerpo = _TablaCancelaciones(events: vistos, abiertas: _abiertas, onAlternar: _alternar);
    } else {
      cuerpo = Column(
        children: [
          for (var i = 0; i < vistos.length; i++) ...[
            if (i > 0) const _Separador(),
            _CancelacionTile(
              event: vistos[i],
              abierta: _abiertas.contains(vistos[i].orderId),
              onAlternar: () => _alternar(vistos[i].orderId),
            ),
          ],
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.tabla)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                encabezado,
                const SizedBox(width: 16),
                Expanded(child: filtros),
              ],
            )
          else ...[
            encabezado,
            const SizedBox(height: 12),
            filtros,
          ],
          const SizedBox(height: 10),
          cuerpo,
          if (resto > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _todas = true),
                child: Text(
                  resto == 1 ? 'Ver la otra cancelación' : 'Ver las otras $resto cancelaciones',
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

/// Lo que se muestra de una cancelación en la tabla y en la tarjeta.
class _Datos {
  final String hora;
  final String fecha;
  final String mesa;
  final String pedido;
  final String quien;
  final String? motivo;

  /// "Q80.00", o un guion si no se pudo leer el pedido.
  final String valor;

  _Datos(CancellationEvent e)
      : hora = DateFormat('HH:mm').format(e.at),
        fecha = DateFormat('d MMM', 'es').format(e.at),
        mesa = e.tableLabel,
        pedido = e.orderLabel,
        // Quien abrió la cancelación y, si otros firmaron algún renglón, ellos
        // también: así cada persona del corte se ve en las filas que filtra.
        quien = [
          e.userName,
          ...e.authors.where((a) => a != e.userName && a != 'Sin identificar'),
        ].join(', '),
        motivo = (e.reason ?? '').trim().isEmpty ? null : e.reason!.trim(),
        valor = e.value == null ? '—' : _dinero(e.value!);
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  const _Etiqueta(this.texto, {required this.color, required this.fondo});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: _t(12, FontWeight.w700, color, height: 1.25)),
    );
  }
}

/// Qué pasó con el inventario en esta cancelación: lo que regresó, la merma, o
/// por qué no lo tocó. Una cancelación puede tener las dos (parte regresó, parte
/// se perdió).
List<Widget> _etiquetasDeInventario(CancellationEvent e) {
  // Un renglón sin receta que se declaró perdido: no hay costo que poner, pero
  // se perdió y el titular lo cuenta. Sin esta etiqueta la fila diría solo "Sin
  // receta" y ningún botón explicaría esos pesos.
  final perdidoSinCosto = e.items.any((i) => i.declaredLost && i.wasted.isEmpty);
  final perdido = _Etiqueta('Declarado perdido', color: _C.bad, fondo: _C.badTint);

  if (!e.movedInventory) {
    return [
      _Etiqueta(
        e.impact == InventoryImpact.sinReceta ? 'Sin receta' : e.impact.label,
        color: _C.muted,
        fondo: _C.subtle,
      ),
      if (perdidoSinCosto) perdido,
    ];
  }
  final tags = <Widget>[
    if (!e.wasted.isEmpty) _Etiqueta('Merma ${_valor(e.wasted)}', color: _C.bad, fondo: _C.badTint),
    if (!e.returned.isEmpty) _Etiqueta('Regresó ${_valor(e.returned)}', color: _C.gift, fondo: _C.giftTint),
    if (e.wasted.isEmpty && perdidoSinCosto) perdido,
  ];
  return tags.isEmpty ? [_Etiqueta(e.impact.label, color: _C.muted, fondo: _C.subtle)] : tags;
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
        Flexible(child: Text('Sin motivo anotado', style: _t(13.5, FontWeight.w600, _C.warn))),
      ],
    );
  }
}

/// Los platillos de una cancelación: "1× Hamburguesa clásica", con los tres
/// primeros a la vista y "+ N más" para el resto.
class _Renglones extends StatelessWidget {
  static const _kVisibles = 3;

  final CancellationEvent event;
  final bool abierta;
  final VoidCallback onAlternar;
  final double letra;

  const _Renglones({required this.event, required this.abierta, required this.onAlternar, this.letra = 14.5});

  @override
  Widget build(BuildContext context) {
    final items = event.items;
    if (items.isEmpty) {
      return Text('Sin detalle de artículos', style: _t(letra, FontWeight.w400, _C.muted));
    }
    final vistos = abierta ? items : items.take(_kVisibles).toList();
    // Con varios renglones, el que se declaró perdido lo dice: la etiqueta de
    // inventario es de toda la cancelación. Si la cancelación no tocó
    // inventario también, aunque sea un solo renglón: ahí la etiqueta no habla
    // de pérdida.
    final marcar = items.length > 1 || !event.movedInventory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in vistos)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 28),
                  child: Text(i.qty > 0 ? '${i.qty}×' : '·', style: _t(letra, FontWeight.w600, _C.muted)),
                ),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: i.name, style: _t(letra, FontWeight.w400, _C.ink)),
                    if (marcar && i.declaredLost)
                      TextSpan(text: '  perdido', style: _t(12, FontWeight.w600, _C.bad)),
                  ])),
                ),
              ],
            ),
          ),
        if (items.length > _kVisibles)
          InkWell(
            onTap: onAlternar,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              // Alto para el dedo: con 4 de relleno el botón medía 27dp.
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Text(
                abierta ? 'Ver menos' : '+ ${items.length - _kVisibles} más',
                style: _t(13, FontWeight.w600, _C.accent),
              ),
            ),
          ),
      ],
    );
  }
}

class _TablaCancelaciones extends StatelessWidget {
  final List<CancellationEvent> events;
  final Set<String> abiertas;
  final ValueChanged<String> onAlternar;

  const _TablaCancelaciones({required this.events, required this.abiertas, required this.onAlternar});

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
      // Hora y valor del ancho de su contenido: un monto grande (o con letra
      // grande) no debe partirse en dos líneas. El resto se reparte.
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(1.1),
        2: FlexColumnWidth(2.5),
        3: FlexColumnWidth(1.4),
        4: FlexColumnWidth(2.2),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: borde,
          children: [
            encabezado('Hora'),
            encabezado('Mesa · Pedido'),
            encabezado('Platillos'),
            encabezado('Inventario'),
            encabezado('Quién · Motivo'),
            encabezado('Valor venta', derecha: true),
          ],
        ),
        for (var i = 0; i < events.length; i++)
          () {
            final e = events[i];
            final d = _Datos(e);
            return TableRow(
              decoration: i == events.length - 1 ? null : borde,
              children: [
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.hora, style: _t(14.5, FontWeight.w600, _C.ink)),
                    Text(d.fecha, style: _t(12.5, FontWeight.w400, _C.muted)),
                  ],
                )),
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.mesa, style: _t(14.5, FontWeight.w400, _C.ink)),
                    Text(d.pedido, style: _t(12.5, FontWeight.w400, _C.muted)),
                  ],
                )),
                celda(_Renglones(
                  event: e,
                  abierta: abiertas.contains(e.orderId),
                  onAlternar: () => onAlternar(e.orderId),
                )),
                celda(Wrap(spacing: 4, runSpacing: 4, children: _etiquetasDeInventario(e))),
                celda(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.quien, style: _t(14.5, FontWeight.w400, _C.ink)),
                    if (d.motivo != null)
                      Text(d.motivo!, style: _t(13.5, FontWeight.w400, _C.muted))
                    else
                      const _MarcaSinMotivo(),
                  ],
                )),
                celda(
                  Text(d.valor, style: _t(14.5, FontWeight.w700, d.valor == '—' ? _C.soft : _C.ink)),
                  derecha: true,
                ),
              ],
            );
          }(),
      ],
    );
  }
}

/// Una cancelación en el teléfono: lo mismo que una fila de la tabla, apilado.
class _CancelacionTile extends StatelessWidget {
  final CancellationEvent event;
  final bool abierta;
  final VoidCallback onAlternar;

  const _CancelacionTile({required this.event, required this.abierta, required this.onAlternar});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final d = _Datos(e);

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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(d.fecha, style: _t(12.5, FontWeight.w400, _C.muted)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // "Venta" y no "Total": es lo que valía a precio de venta, no lo
              // que se cobró.
              _montoDerecha(
                d.valor == '—' ? '—' : 'Venta ${d.valor}',
                _t(14, FontWeight.w700, d.valor == '—' ? _C.soft : _C.ink),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${d.mesa} · ${d.pedido}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted)),
          const SizedBox(height: 10),
          _Renglones(event: e, abierta: abierta, onAlternar: onAlternar, letra: 14),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              ..._etiquetasDeInventario(e),
              Text(d.quien, style: _t(13.5, FontWeight.w500, _C.ink)),
              if (d.motivo != null)
                Text(d.motivo!, style: _t(13.5, FontWeight.w400, _C.muted))
              else
                const _MarcaSinMotivo(),
            ],
          ),
        ],
      ),
    );
  }
}
