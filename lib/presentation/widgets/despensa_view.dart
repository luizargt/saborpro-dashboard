/// La Despensa (inventario por sucursal). Rediseño 2026-11-21 (`despensa.html` de
/// saborpro_app, en su modo oscuro): el dinero que hay en la despensa, los
/// filtros por estado y una tabla tipo hoja de cálculo con la primera columna
/// fija: días que alcanza cada ingrediente, o lo que se consumió en 7 días.
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa los
/// ingredientes ya leídos. Se prueba a 360dp en
/// test/presentation/widgets/despensa_view_test.dart.
///
/// OJO: la tabla son dos listas de filas de la MISMA altura (la columna del nombre
/// y los datos) que se desplazan juntas; si una fila cambia de alto, tiene que ser
/// en las dos (`itemExtentBuilder`).
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverLayoutDimensions;
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show signoParaMostrar;
import '../../data/models/despensa_data.dart';
import '../../data/models/inventory_data.dart';
import 'inicio_ui.dart';
import '../navigation/contexto_shell.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

final _dinero = NumberFormat('#,##0.00', 'en_US');
String _q(String signo, double v) => '$signo${_dinero.format(v)}';

/// Una sucursal de las que se ven.
class DespensaSucursal {
  final String id;
  final String nombre;
  final String simbolo;

  const DespensaSucursal(this.id, this.nombre, {this.simbolo = 'Q'});
}

enum ModoDespensa { dias, consumo }

class DespensaBody extends StatefulWidget {
  final List<IngredientStock> items;

  /// Las sucursales que se ven: todas, o la que se eligió arriba.
  final List<DespensaSucursal> sucursales;

  /// Las claves (yyyy-MM-dd) de los últimos 7 días, de la más antigua a la más reciente.
  final List<String> dias;

  /// Cuándo se leyó el inventario y contra qué se mide "hace cuánto".
  final DateTime? actualizado;
  final DateTime ahora;

  final bool cargando;
  final String? error;
  final VoidCallback? onReintentar;
  final VoidCallback? onActualizar;
  final VoidCallback? onDescargar;

  /// Se llama al tocar el dinero de una sucursal (para ver solo esa).
  final ValueChanged<String>? onElegirSucursal;

  /// Hay una sola sucursal elegida arriba (y no "todas").
  final bool sucursalElegida;

  const DespensaBody({
    super.key,
    required this.items,
    required this.sucursales,
    required this.dias,
    required this.ahora,
    this.actualizado,
    this.cargando = false,
    this.error,
    this.onReintentar,
    this.onActualizar,
    this.onDescargar,
    this.onElegirSucursal,
    this.sucursalElegida = false,
  });

  @override
  State<DespensaBody> createState() => _DespensaBodyState();
}

class _DespensaBodyState extends State<DespensaBody> {
  final _vDatos = ScrollController();
  final _vNombres = ScrollController();
  final _hDatos = ScrollController();
  final _hCabecera = ScrollController();
  final _busqueda = TextEditingController();

  String _consulta = '';
  ModoDespensa _modo = ModoDespensa.dias;
  EstadoDespensa? _estado;

  @override
  void initState() {
    super.initState();
    // Los nombres siguen a los datos hacia arriba y abajo; la cabecera, hacia los lados.
    _vDatos.addListener(() {
      if (_vNombres.hasClients && _vNombres.offset != _vDatos.offset) _vNombres.jumpTo(_vDatos.offset);
    });
    _hDatos.addListener(() {
      if (_hCabecera.hasClients && _hCabecera.offset != _hDatos.offset) _hCabecera.jumpTo(_hDatos.offset);
    });
  }

  @override
  void dispose() {
    _vDatos.dispose();
    _vNombres.dispose();
    _hDatos.dispose();
    _hCabecera.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  List<String> get _ids => [for (final s in widget.sucursales) s.id];

  /// El mismo signo en todas las sucursales que se ven (o nulo si hay varios).
  String? get _signoUnico {
    final signos = {for (final s in widget.sucursales) signoParaMostrar(s.simbolo)};
    return signos.length == 1 ? signos.single : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth;
      final telefono = ancho < 760;
      final pad = ancho < 640 ? 16.0 : 20.0;
      final filas = Despensa.filas(widget.items, _ids);
      final resumen = ResumenDespensa.de(filas, _ids);
      final enDias = _modo == ModoDespensa.dias;

      final lista = enDias
          ? Despensa.porUrgencia(filas, consulta: _consulta, estado: _estado)
          : Despensa.porConsumo(filas, widget.dias, consulta: _consulta);

      // En el teléfono TODA la pantalla se desplaza junta (las tarjetas, el buscador y
      // los filtros se van hacia arriba y la tabla ocupa el alto que necesita): antes
      // quedaban fijos arriba y de la tabla se veían dos renglones. En pantalla ancha
      // sobra lugar y la tabla sigue con su propio desplazamiento.
      final desplazaTodo = telefono;

      final Widget cuerpo;
      if (widget.cargando) {
        final spinner = Center(child: CircularProgressIndicator(color: _C.accent));
        cuerpo = desplazaTodo ? SizedBox(height: 240, child: spinner) : spinner;
      } else if (widget.error != null) {
        cuerpo = _Error(mensaje: widget.error!, onReintentar: widget.onReintentar);
      } else if (lista.isEmpty) {
        cuerpo = _Vacio(
          texto: !enDias
              ? (_consulta.isEmpty ? 'Ningún ingrediente tuvo consumo en los últimos 7 días' : 'Sin resultados')
              : 'Sin resultados',
        );
      } else {
        cuerpo = _Tabla(
          filas: lista,
          sucursales: widget.sucursales,
          dias: widget.dias,
          modo: _modo,
          ancho: ancho - 2 * pad,
          telefono: telefono,
          signo: _signoUnico,
          vDatos: _vDatos,
          vNombres: _vNombres,
          hDatos: _hDatos,
          hCabecera: _hCabecera,
          agrupar: enDias,
          resumen: resumen,
          alturaCompleta: desplazaTodo,
        );
      }

      final mostrarDinero = enDias && !widget.cargando && widget.error == null;
      final modo = _Pastillas<ModoDespensa>(
        opciones: const [(ModoDespensa.dias, 'Días que alcanza'), (ModoDespensa.consumo, 'Consumo 7 días')],
        elegida: _modo,
        onElegir: (m) => setState(() => _modo = m),
        completo: telefono,
      );
      final filtros = mostrarDinero
          ? _Filtros(
              estado: _estado,
              resumen: resumen,
              telefono: telefono,
              onEstado: (e) => setState(() => _estado = e),
            )
          : null;

      // Lo de arriba de la tabla: el encabezado, el dinero, el buscador y los filtros.
      final arriba = <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 12),
          child: _Encabezado(
            actualizado: widget.actualizado,
            ahora: widget.ahora,
            telefono: telefono,
            onActualizar: widget.onActualizar,
            onDescargar: widget.onDescargar,
          ),
        ),
        if (mostrarDinero)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            child: _Dinero(
              sucursales: widget.sucursales,
              resumen: resumen,
              ancho: ancho - 2 * pad,
              elegida: widget.sucursalElegida,
              onElegir: widget.onElegirSucursal,
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: _Buscador(controlador: _busqueda, onBuscar: (q) => setState(() => _consulta = q), telefono: telefono),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
          child: telefono
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [modo, if (filtros != null) ...[const SizedBox(height: 8), filtros]],
                )
              : Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [modo, if (filtros != null) filtros]),
        ),
        const SizedBox(height: 12),
      ];

      if (desplazaTodo) {
        return SingleChildScrollView(
          // Siempre desplazable: aunque haya pocos ingredientes, todo se mueve igual.
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...arriba,
              Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, 16), child: cuerpo),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...arriba,
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
              child: cuerpo,
            ),
          ),
        ],
      );
    });
  }
}

// ── ENCABEZADO, BÚSQUEDA Y FILTROS ───────────────────────────────────────────

class _Encabezado extends StatelessWidget {
  final DateTime? actualizado;
  final DateTime ahora;
  final bool telefono;
  final VoidCallback? onActualizar;
  final VoidCallback? onDescargar;

  const _Encabezado({
    required this.actualizado,
    required this.ahora,
    required this.telefono,
    this.onActualizar,
    this.onDescargar,
  });

  String get _subtitulo {
    final a = actualizado;
    if (a == null) return 'Cargando...';
    final d = ahora.difference(a);
    if (d.inSeconds < 60) return 'Actualizado hace ${math.max(0, d.inSeconds)}s';
    if (d.inMinutes < 60) return 'Actualizado hace ${d.inMinutes} min';
    return 'Actualizado hace ${d.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, String ayuda, VoidCallback? onTap) => SizedBox(
          width: 46,
          height: 46,
          child: Material(
            color: _C.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Tooltip(message: ayuda, child: Icon(icono, size: 20, color: onTap == null ? _C.soft : _C.ink)),
            ),
          ),
        );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dentro del shell el título "Despensa" ya lo pone el encabezado del shell.
              if (!ContextoShell.enShell(context)) Text('Despensa', maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(telefono ? 22 : 24, FontWeight.w700, _C.ink)),
              Text(_subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13, FontWeight.w500, _C.muted)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        boton(Icons.download_rounded, 'Descargar Excel', onDescargar),
        const SizedBox(width: 6),
        boton(Icons.refresh_rounded, 'Actualizar', onActualizar),
      ],
    );
  }
}

class _Buscador extends StatelessWidget {
  final TextEditingController controlador;
  final ValueChanged<String> onBuscar;
  final bool telefono;

  const _Buscador({required this.controlador, required this.onBuscar, required this.telefono});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: telefono ? 46 : 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.line, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: _C.soft),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('despensa-buscar'),
              controller: controlador,
              onChanged: onBuscar,
              cursorColor: _C.accent,
              style: _t(15.5, FontWeight.w400, _C.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Buscar ingrediente',
                hintStyle: _t(15.5, FontWeight.w400, _C.soft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El grupo de botones redondos del diseño (`.sg`): el elegido va con el fondo claro.
class _Pastillas<T> extends StatelessWidget {
  final List<(T, String)> opciones;
  final T elegida;
  final ValueChanged<T> onElegir;
  final bool completo;

  /// Un punto de color antes del texto de cada opción, si lo tiene.
  final Map<T, Color> puntos;
  final Map<T, int> cuantos;

  const _Pastillas({
    required this.opciones,
    required this.elegida,
    required this.onElegir,
    this.completo = false,
    this.puntos = const {},
    this.cuantos = const {},
  });

  @override
  Widget build(BuildContext context) {
    Widget boton((T, String) o) {
      final activa = o.$1 == elegida;
      final color = activa ? _C.card : _C.muted;
      final contenido = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (puntos[o.$1] != null) ...[
            Container(width: 9, height: 9, decoration: BoxDecoration(color: puntos[o.$1], shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          completo ? Text(o.$2, maxLines: 1, style: _t(14, FontWeight.w600, color)) : Flexible(child: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w600, color))),
          if (cuantos[o.$1] != null) ...[
            const SizedBox(width: 4),
            Text('${cuantos[o.$1]}', style: _t(12, FontWeight.w400, color.withValues(alpha: 0.7))),
          ],
        ],
      );
      final b = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onElegir(o.$1),
        child: Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: completo ? 6 : 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: activa ? _C.ink : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          // En un teléfono angosto el contenido se achica un poco en vez de cortarse.
          child: completo ? FittedBox(fit: BoxFit.scaleDown, child: contenido) : contenido,
        ),
      );
      return completo ? Expanded(child: b) : b;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: completo ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < opciones.length; i++) ...[if (i > 0) const SizedBox(width: 2), boton(opciones[i])],
        ],
      ),
    );
  }
}

class _Filtros extends StatelessWidget {
  final EstadoDespensa? estado;
  final ResumenDespensa resumen;
  final bool telefono;
  final ValueChanged<EstadoDespensa?> onEstado;

  const _Filtros({required this.estado, required this.resumen, required this.telefono, required this.onEstado});

  @override
  Widget build(BuildContext context) {
    // `null` es "Todos". Se usa un envoltorio porque la pastilla pide un valor no nulo.
    final opciones = <(EstadoDespensa?, String)>[
      (null, 'Todos'),
      (EstadoDespensa.agotado, 'Agotado'),
      (EstadoDespensa.pronto, 'Pronto'),
      (EstadoDespensa.bien, 'Bien'),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: telefono ? null : 1,
      child: _Pastillas<EstadoDespensa?>(
        opciones: opciones,
        elegida: estado,
        onElegir: onEstado,
        completo: telefono,
        puntos: {
          EstadoDespensa.agotado: _C.bad,
          EstadoDespensa.pronto: _C.warn,
          EstadoDespensa.bien: _C.gift,
        },
        cuantos: {
          null: resumen.total,
          EstadoDespensa.agotado: resumen.agotados,
          EstadoDespensa.pronto: resumen.pronto,
          EstadoDespensa.bien: resumen.bien,
        },
      ),
    );
  }
}

// ── DINERO EN INVENTARIO ─────────────────────────────────────────────────────

class _Dinero extends StatelessWidget {
  final List<DespensaSucursal> sucursales;
  final ResumenDespensa resumen;
  final double ancho;
  final bool elegida;
  final ValueChanged<String>? onElegir;

  const _Dinero({
    required this.sucursales,
    required this.resumen,
    required this.ancho,
    required this.elegida,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    // El dinero de cada moneda por separado: no se suman quetzales con dólares.
    final porSigno = <String, double>{};
    for (final s in sucursales) {
      final signo = signoParaMostrar(s.simbolo);
      porSigno.update(signo, (v) => v + (resumen.valorPorSucursal[s.id] ?? 0), ifAbsent: () => resumen.valorPorSucursal[s.id] ?? 0);
    }
    final unaMoneda = porSigno.length == 1;
    final totalUnico = unaMoneda ? porSigno.values.single : 0.0;
    final telefono = ancho < 760;

    final principal = _Chip(
      compacto: telefono,
      principal: true,
      etiqueta: elegida && sucursales.length == 1 ? 'Dinero en inventario · ${sucursales.single.nombre}' : 'Dinero en inventario',
      valor: unaMoneda
          ? _q(porSigno.keys.single, totalUnico)
          : porSigno.entries.map((e) => _q(e.key, e.value)).join(' · '),
      pie: 'a precio de costo',
      aviso: resumen.sinPrecio > 0
          ? '${resumen.sinPrecio} ${resumen.sinPrecio == 1 ? 'ingrediente sin precio de compra' : 'ingredientes sin precio de compra'}: no se cuenta${resumen.sinPrecio == 1 ? '' : 'n'}'
          : null,
      icono: Icons.account_balance_wallet_outlined,
    );

    final porSucursal = [
      if (!elegida && sucursales.length > 1)
        for (final s in sucursales)
          _Chip(
            compacto: telefono,
            etiqueta: s.nombre,
            valor: _q(signoParaMostrar(s.simbolo), resumen.valorPorSucursal[s.id] ?? 0),
            // Cuánto del total de su moneda es de esta sucursal.
            parte: () {
              final total = porSigno[signoParaMostrar(s.simbolo)] ?? 0;
              return total > 0 ? ((resumen.valorPorSucursal[s.id] ?? 0) / total).clamp(0.0, 1.0) : 0.0;
            }(),
            onTap: onElegir == null ? null : () => onElegir!(s.id),
          ),
    ];

    if (porSucursal.isEmpty) return principal;
    if (telefono) {
      // En teléfono, todo en una sola fila que se desliza (el alto vale oro).
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 230, child: principal),
              for (final c in porSucursal) ...[const SizedBox(width: 8), SizedBox(width: 150, child: c)],
            ],
          ),
        ),
      );
    }
    // Pantalla ancha: el principal (1.4) y hasta tres sucursales por fila; el resto, debajo.
    final filas = <List<Widget>>[];
    var i = 0;
    while (i < porSucursal.length) {
      final cuantas = filas.isEmpty ? math.min(3, porSucursal.length - i) : math.min(4, porSucursal.length - i);
      filas.add(porSucursal.sublist(i, i + cuantas));
      i += cuantas;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var f = 0; f < filas.length; f++) ...[
          if (f > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (f == 0) ...[Expanded(flex: 14, child: principal), const SizedBox(width: 12)],
                for (var k = 0; k < filas[f].length; k++) ...[
                  if (k > 0) const SizedBox(width: 12),
                  Expanded(flex: 10, child: filas[f][k]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final bool compacto;
  final bool principal;
  final String etiqueta;
  final String valor;
  final String? pie;
  final String? aviso;
  final IconData? icono;
  final double? parte;
  final VoidCallback? onTap;

  const _Chip({
    this.compacto = false,
    this.principal = false,
    required this.etiqueta,
    required this.valor,
    this.pie,
    this.aviso,
    this.icono,
    this.parte,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contenido = Padding(
      padding: compacto ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icono != null) ...[Icon(icono, size: 18, color: _C.muted), const SizedBox(width: 8)],
              Expanded(child: Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(13.5, FontWeight.w600, _C.muted))),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, maxLines: 1, style: _t(principal ? (compacto ? 24 : 30) : (compacto ? 18 : 22), FontWeight.w800, principal ? _C.accent : _C.ink, height: 1.2)),
          ),
          if (pie != null) Text(pie!, style: _t(12.5, FontWeight.w400, _C.muted)),
          if (aviso != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(aviso!, style: _t(12.5, FontWeight.w600, _C.warn))),
          if (parte != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 6,
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: _C.subtle)),
                    FractionallySizedBox(widthFactor: parte!.clamp(0.0, 1.0), child: ColoredBox(color: _C.accent, child: SizedBox.expand())),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
    return Material(
      color: _C.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? contenido : InkWell(onTap: onTap, hoverColor: _C.subtle, child: contenido),
    );
  }
}

// ── LA TABLA ─────────────────────────────────────────────────────────────────

sealed class _Renglon {
  const _Renglon();
}

class _Grupo extends _Renglon {
  final EstadoDespensa estado;
  final int cuantos;
  const _Grupo(this.estado, this.cuantos);
}

class _Dato extends _Renglon {
  final FilaDespensa fila;
  const _Dato(this.fila);
}

class _Columna {
  final String titulo;
  final double ancho;
  final Widget Function(FilaDespensa f) celda;
  final bool total;
  const _Columna(this.titulo, this.ancho, this.celda, {this.total = false});
}

class _Tabla extends StatelessWidget {
  final List<FilaDespensa> filas;
  final List<DespensaSucursal> sucursales;
  final List<String> dias;
  final ModoDespensa modo;

  /// Lo que mide el contenido (sin los márgenes de la pantalla).
  final double ancho;
  final bool telefono;

  /// El signo si todas las sucursales que se ven usan el mismo; si no, no se
  /// muestra la columna de valor.
  final String? signo;
  final ScrollController vDatos;
  final ScrollController vNombres;
  final ScrollController hDatos;
  final ScrollController hCabecera;

  /// Con los renglones de grupo ("Agotado", "Pronto"...) entre las filas.
  final bool agrupar;
  final ResumenDespensa resumen;

  /// La tabla mide lo que miden todos sus renglones y NO se desplaza por dentro: la
  /// pantalla entera se desplaza (teléfono). Sin esto, ocupa el alto que le sobre y
  /// se desplaza ella sola.
  final bool alturaCompleta;

  const _Tabla({
    required this.filas,
    required this.sucursales,
    required this.dias,
    required this.modo,
    required this.ancho,
    required this.telefono,
    required this.signo,
    required this.vDatos,
    required this.vNombres,
    required this.hDatos,
    required this.hCabecera,
    required this.agrupar,
    required this.resumen,
    this.alturaCompleta = false,
  });

  static const _altoFila = 40.0;
  static const _altoGrupo = 36.0;
  static const _altoCabecera = 40.0;

  List<_Renglon> _renglones() {
    if (!agrupar) return [for (final f in filas) _Dato(f)];
    final out = <_Renglon>[];
    EstadoDespensa? ultimo;
    for (final f in filas) {
      final e = f.peor;
      if (e != null && e != ultimo) {
        out.add(_Grupo(e, filas.where((x) => x.peor == e).length));
        ultimo = e;
      }
      out.add(_Dato(f));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final anchoNombre = telefono ? 150.0 : 240.0;
    final enDias = modo == ModoDespensa.dias;
    final ids = [for (final s in sucursales) s.id];

    // Las columnas y su ancho mínimo; si sobra lugar se reparte entre todas.
    final mayor = Despensa.maximoDiario(filas, dias);
    final columnas = <_Columna>[
      if (enDias) ...[
        for (final s in sucursales) _Columna(s.nombre, 118, (f) => _CeldaStock(f.celda(s.id))),
        if (sucursales.length > 1)
          _Columna('Total', 96, (f) => _CeldaTotal(textoCantidad(f.total)), total: true),
        if (signo != null) _Columna('Valor', 112, (f) => _CeldaValor(f.valor, signo!)),
      ] else ...[
        for (final d in dias) _Columna(_etiquetaDia(d), 84, (f) => _CeldaConsumo(f.consumoDia(d), mayor)),
        _Columna('Total', 90, (f) => _CeldaTotal(textoCantidad(f.consumo7(dias))), total: true),
      ],
    ];
    final minimo = columnas.fold<double>(0, (a, c) => a + c.ancho);
    final disponible = ancho - anchoNombre - 2; // el borde de la tarjeta
    final extra = math.max(0.0, disponible - minimo) / math.max(1, columnas.length);
    final anchos = [for (final c in columnas) c.ancho + extra];
    final anchoDatos = anchos.fold<double>(0, (a, b) => a + b);
    final renglones = _renglones();

    double alto(int i, SliverLayoutDimensions _) => renglones[i] is _Grupo ? _altoGrupo : _altoFila;

    Widget nombre(_Renglon r) => switch (r) {
          _Grupo(:final estado, :final cuantos) => _NombreGrupo(estado: estado, cuantos: cuantos, telefono: telefono),
          _Dato(:final fila) => _CeldaNombre(fila: fila, telefono: telefono),
        };

    Widget datos(_Renglon r) => switch (r) {
          _Grupo() => ColoredBox(color: _C.subtle, child: SizedBox.expand()),
          _Dato(:final fila) => Row(
              children: [
                for (var i = 0; i < columnas.length; i++)
                  SizedBox(
                    width: anchos[i],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: columnas[i].total ? _C.subtle : null,
                        border: Border(
                          left: columnas[i].total ? BorderSide(color: _C.lineStrong) : BorderSide.none,
                          right: BorderSide(color: _C.line),
                          bottom: BorderSide(color: _C.line),
                        ),
                      ),
                      child: columnas[i].celda(fila),
                    ),
                  ),
              ],
            ),
        };

    final cabecera = Container(
      height: _altoCabecera,
      decoration: BoxDecoration(color: _C.subtle, border: Border(bottom: BorderSide(color: _C.lineStrong))),
      child: Row(
        children: [
          Container(
            width: anchoNombre,
            padding: const EdgeInsets.only(left: 20, right: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: _C.lineStrong))),
            child: Text('INGREDIENTE', style: _t(12, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.36)),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: hCabecera,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < columnas.length; i++)
                    Container(
                      width: anchos[i],
                      height: _altoCabecera,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        border: Border(
                          left: columnas[i].total ? BorderSide(color: _C.lineStrong) : BorderSide.none,
                          right: BorderSide(color: _C.line),
                        ),
                      ),
                      child: Text(
                        columnas[i].titulo.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(12, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.36),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final cuerpoTabla = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: anchoNombre,
          child: ListView.builder(
            controller: vNombres,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: renglones.length,
            itemExtentBuilder: alto,
            itemBuilder: (_, i) => nombre(renglones[i]),
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            // En la web el ratón no arrastra de lado por defecto.
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
            ),
            child: SingleChildScrollView(
              controller: hDatos,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: anchoDatos,
                child: ListView.builder(
                  controller: vDatos,
                  // Con la pantalla desplazándose entera, aquí no se desplaza nada.
                  physics: alturaCompleta ? const NeverScrollableScrollPhysics() : null,
                  itemCount: renglones.length,
                  itemExtentBuilder: alto,
                  itemBuilder: (_, i) => datos(renglones[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // El alto de todos los renglones, para la tabla que no se desplaza por dentro.
    final altoTodo = renglones.fold<double>(0, (a, r) => a + (r is _Grupo ? _altoGrupo : _altoFila));

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.lineStrong),
      ),
      child: Column(
        mainAxisSize: alturaCompleta ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabecera,
          if (alturaCompleta) SizedBox(height: altoTodo, child: cuerpoTabla) else Expanded(child: cuerpoTabla),
          _Leyenda(enDias: enDias, sucursalUnica: ids.length == 1, telefono: telefono),
        ],
      ),
    );
  }

  static String _etiquetaDia(String clave) {
    final d = DateTime.tryParse(clave);
    if (d == null) return clave;
    try {
      return DateFormat('E d', 'es').format(d);
    } catch (_) {
      return DateFormat('E d').format(d);
    }
  }
}

Color _colorEstado(EstadoDespensa e) => switch (e) {
      EstadoDespensa.agotado => _C.bad,
      EstadoDespensa.pronto => _C.warn,
      EstadoDespensa.bien => _C.gift,
    };

class _NombreGrupo extends StatelessWidget {
  final EstadoDespensa estado;
  final int cuantos;
  final bool telefono;
  const _NombreGrupo({required this.estado, required this.cuantos, required this.telefono});

  @override
  Widget build(BuildContext context) {
    final texto = switch (estado) {
      EstadoDespensa.agotado => 'Agotado',
      EstadoDespensa.pronto => telefono ? 'Pronto' : 'Pronto · <$diasPronto días',
      EstadoDespensa.bien => 'Bien',
    };
    final color = _colorEstado(estado);
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 12),
      decoration: BoxDecoration(
        color: _C.subtle,
        border: Border(bottom: BorderSide(color: _C.line), right: BorderSide(color: _C.lineStrong)),
      ),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(texto.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w700, color).copyWith(letterSpacing: 0.6)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(999)),
            child: Text('$cuantos', style: _t(12.5, FontWeight.w700, _C.muted)),
          ),
        ],
      ),
    );
  }
}

String _unidad(String unit) {
  switch (unit.toLowerCase()) {
    case 'kilogramos':
      return 'kg';
    case 'gramos':
      return 'g';
    case 'litros':
      return 'L';
    case 'mililitros':
      return 'mL';
    case 'unidades':
    case 'unidad':
    case 'u':
    case '':
      // En unidades no se dice: es lo de siempre.
      return '';
    default:
      return unit.length > 5 ? unit.substring(0, 4) : unit;
  }
}

class _CeldaNombre extends StatelessWidget {
  final FilaDespensa fila;
  final bool telefono;
  const _CeldaNombre({required this.fila, required this.telefono});

  @override
  Widget build(BuildContext context) {
    final e = fila.peor;
    final unidad = _unidad(fila.item.unit);
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _C.line), right: BorderSide(color: _C.lineStrong))),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: e == null ? _C.soft : _colorEstado(e), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            // El nombre entero importa más que la unidad: va pegada, en gris. Dos
            // líneas en teléfono (como el diseño), una en pantalla ancha.
            child: Text.rich(
              TextSpan(
                text: fila.item.name,
                style: _t(telefono ? 13 : 14, FontWeight.w600, _C.ink, height: 1.15),
                children: [if (unidad.isNotEmpty) TextSpan(text: ' · $unidad', style: _t(11, FontWeight.w400, _C.muted))],
              ),
              maxLines: telefono ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que hay de un ingrediente en una sucursal y para cuántos días alcanza.
class _CeldaStock extends StatelessWidget {
  final CeldaDespensa? celda;
  const _CeldaStock(this.celda);

  @override
  Widget build(BuildContext context) {
    final c = celda;
    if (c == null) {
      return Container(alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('—', style: _t(15, FontWeight.w400, _C.soft)));
    }
    final (Color? fondo, Color texto, String sub) = switch (c.estado) {
      EstadoDespensa.agotado => (_C.badTint, _C.bad, 'Agotado'),
      EstadoDespensa.pronto => (_C.warnTint, _C.warn, textoDias(c.dias ?? 0)),
      EstadoDespensa.bien => (null, _C.ink, c.dias == null ? 'Sin consumo' : textoDias(c.dias!)),
    };
    final colorSub = c.estado == EstadoDespensa.bien ? (c.dias == null ? _C.muted : _C.gift) : texto;
    return Container(
      color: fondo,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerRight,
      // Con letra grande o cifras enormes se achica en vez de salirse.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(textoCantidad(c.stock), maxLines: 1, style: _t(15, FontWeight.w700, texto)),
            const SizedBox(width: 8),
            Text(sub, maxLines: 1, style: _t(12, FontWeight.w600, colorSub.withValues(alpha: 0.9))),
          ],
        ),
      ),
    );
  }
}

class _CeldaTotal extends StatelessWidget {
  final String texto;
  const _CeldaTotal(this.texto);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(texto, maxLines: 1, style: _t(15, FontWeight.w700, _C.accent)),
        ),
      );
}

class _CeldaValor extends StatelessWidget {
  final double? valor;
  final String signo;
  const _CeldaValor(this.valor, this.signo);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(valor == null ? '—' : _q(signo, valor!), maxLines: 1, style: _t(14, FontWeight.w600, valor == null ? _C.soft : _C.muted)),
        ),
      );
}

class _CeldaConsumo extends StatelessWidget {
  final double cantidad;
  final double maximo;
  const _CeldaConsumo(this.cantidad, this.maximo);

  @override
  Widget build(BuildContext context) {
    if (cantidad <= 0) {
      return Container(alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('—', style: _t(15, FontWeight.w400, _C.soft)));
    }
    return Container(
      color: Color.lerp(_C.card, _C.accent, Despensa.intensidad(cantidad, maximo)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(textoCantidad(cantidad), maxLines: 1, style: _t(15, FontWeight.w700, _C.ink)),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final bool enDias;
  final bool sucursalUnica;
  final bool telefono;
  const _Leyenda({required this.enDias, required this.sucursalUnica, required this.telefono});

  @override
  Widget build(BuildContext context) {
    Widget punto(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted))),
          ],
        );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: telefono ? 8 : 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: enDias
            ? [
                punto(_C.bad, 'Agotado'),
                punto(_C.warn, 'Menos de $diasPronto días'),
                punto(_C.gift, 'Alcanza bien'),
                Text(
                  // Los días salen del consumo de los últimos 30 días (ver InventoryProvider).
                  telefono
                      ? 'Según el consumo de 30 días'
                      : 'Días calculados con el consumo de los últimos 30 días${sucursalUnica ? '' : ' · — no se maneja en esa sucursal'}',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
              ]
            : [
                Text(
                  telefono ? 'Más oscuro = más consumo' : 'Unidades usadas por día · Más oscuro = más consumo · Ordenado de mayor a menor',
                  style: _t(12.5, FontWeight.w400, _C.muted),
                ),
              ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  final String texto;
  const _Vacio({required this.texto});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Text(texto, textAlign: TextAlign.center, style: _t(14.5, FontWeight.w400, _C.muted)),
      );
}

class _Error extends StatelessWidget {
  final String mensaje;
  final VoidCallback? onReintentar;
  const _Error({required this.mensaje, this.onReintentar});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(30),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensaje, textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
            if (onReintentar != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onReintentar, child: Text('Reintentar', style: _t(14.5, FontWeight.w700, _C.accent))),
            ],
          ],
        ),
      );
}
