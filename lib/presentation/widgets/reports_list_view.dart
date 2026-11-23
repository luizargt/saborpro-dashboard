/// La lista de reportes (pestaña "Reportes"). Rediseño 2026-11-20
/// (assets/Desing/Sabor Manager/reportes.html de saborpro_app, en su modo
/// oscuro): buscador, grupos y una tarjeta por reporte con su dato de "ahora".
///
/// Es la parte que se ve, sin providers ni Firebase: la pantalla le pasa los
/// reportes ya armados (con a dónde lleva cada uno y su dato) y aquí solo se
/// busca, se agrupa y se dibuja. Se prueba a 360dp en
/// test/presentation/widgets/reports_list_view_test.dart.
library;

import 'package:flutter/material.dart';

import '../../data/models/datos_reportes.dart';
import 'inicio_ui.dart';
import 'max_content_width.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// El color del ícono de una tarjeta (los `c-g`, `c-y`… del diseño).
enum TonoReporte { verde, azul, ambar, rojo, morado }

/// Un reporte de la lista.
class ReporteItem {
  /// El grupo en que se muestra ("Dinero"). Los grupos salen en el orden en que
  /// aparece su primer reporte.
  final String grupo;
  final String titulo;
  final String descripcion;
  final IconData icono;
  final TonoReporte tono;

  /// Palabras extra para el buscador ("ganancia utilidad margen").
  final String palabras;
  final VoidCallback onTap;

  /// El dato de "ahora" bajo la descripción. Nulo = la tarjeta no lo lleva.
  final DatoReporte? dato;

  const ReporteItem({
    required this.grupo,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.tono,
    this.palabras = '',
    required this.onTap,
    this.dato,
  });
}

/// Minúsculas y sin acentos, para que "cortesia" encuentre "Cortesías".
String sinAcentos(String t) {
  const de = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const a = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final b = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i == -1 ? c : a[i]);
  }
  return b.toString().toLowerCase();
}

class ReportsListView extends StatefulWidget {
  final List<ReporteItem> reportes;

  const ReportsListView({super.key, required this.reportes});

  @override
  State<ReportsListView> createState() => _ReportsListViewState();
}

class _ReportsListViewState extends State<ReportsListView> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _coincide(ReporteItem r, String q) =>
      sinAcentos('${r.titulo} ${r.descripcion} ${r.palabras} ${r.grupo}').contains(q);

  @override
  Widget build(BuildContext context) {
    final consulta = _query.trim();
    final q = sinAcentos(consulta);
    final visibles = q.isEmpty ? widget.reportes : widget.reportes.where((r) => _coincide(r, q)).toList();

    final grupos = <String>[];
    for (final r in visibles) {
      if (!grupos.contains(r.grupo)) grupos.add(r.grupo);
    }

    return MaxContentWidth(
      maxWidth: 1240,
      child: LayoutBuilder(builder: (context, c) {
        final telefono = c.maxWidth <= kInicioQuiebreTelefono;
        final pad = telefono ? 16.0 : 20.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Encabezado(telefono: telefono, controller: _controller, onChanged: (v) => setState(() => _query = v)),
            Expanded(
              child: visibles.isEmpty
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
                      children: [_SinResultados(consulta: consulta)],
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
                      children: [
                        for (var i = 0; i < grupos.length; i++) ...[
                          if (i > 0) const SizedBox(height: 22),
                          _Grupo(titulo: grupos[i], reportes: [for (final r in visibles) if (r.grupo == grupos[i]) r]),
                        ],
                      ],
                    ),
            ),
          ],
        );
      }),
    );
  }
}

// ── ENCABEZADO Y BUSCADOR ────────────────────────────────────────────────────

class _Encabezado extends StatelessWidget {
  final bool telefono;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _Encabezado({required this.telefono, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pad = telefono ? 16.0 : 20.0;
    final titulo = Text(
      'Reportes',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _t(telefono ? 22 : 24, FontWeight.w700, _C.ink, height: 1.2),
    );
    final buscador = _Buscador(controller: controller, onChanged: onChanged);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, telefono ? 12 : 14, pad, 12),
      child: telefono
          // En el teléfono el buscador baja y toma todo el ancho.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [titulo, const SizedBox(height: 12), buscador],
            )
          // En ancho va pegado al título, sin cruzar la pantalla con dos
          // palabras adentro.
          : Row(
              children: [
                titulo,
                const SizedBox(width: 14),
                Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: buscador)),
              ],
            ),
    );
  }
}

class _Buscador extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _Buscador({required this.controller, required this.onChanged});

  @override
  State<_Buscador> createState() => _BuscadorState();
}

class _BuscadorState extends State<_Buscador> {
  bool _enFoco = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        // El borde se enciende con el foco, como en el diseño.
        border: Border.all(color: _enFoco ? _C.accent : _C.line, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 22, color: _C.soft),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onFocusChange: (f) => setState(() => _enFoco = f),
              child: TextField(
                controller: widget.controller,
                onChanged: widget.onChanged,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                cursorColor: _C.accent,
                style: _t(15.5, FontWeight.w400, _C.ink),
                decoration: InputDecoration(
                  hintText: 'Buscar reporte',
                  hintStyle: _t(15.5, FontWeight.w400, _C.soft),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinResultados extends StatelessWidget {
  final String consulta;
  const _SinResultados({required this.consulta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      child: Column(
        children: [
          Text('No encontré “$consulta”', textAlign: TextAlign.center, style: _t(17, FontWeight.w700, _C.ink)),
          const SizedBox(height: 6),
          Text('Prueba con otra palabra.', textAlign: TextAlign.center, style: _t(15, FontWeight.w400, _C.muted)),
        ],
      ),
    );
  }
}

// ── GRUPOS Y TARJETAS ────────────────────────────────────────────────────────

class _Grupo extends StatelessWidget {
  final String titulo;
  final List<ReporteItem> reportes;

  const _Grupo({required this.titulo, required this.reportes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            titulo.toUpperCase(),
            style: _t(13, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.78),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          // Como `repeat(auto-fill, minmax(300px, 1fr))` del diseño: todas las
          // columnas que quepan con 300 como mínimo (una sola en teléfono).
          const gap = 12.0;
          final columnas = c.maxWidth <= kInicioQuiebreTelefono
              ? 1
              : ((c.maxWidth + gap) / (300 + gap)).floor().clamp(1, 6);
          final filas = <List<ReporteItem>>[
            for (var i = 0; i < reportes.length; i += columnas)
              reportes.sublist(i, (i + columnas).clamp(0, reportes.length)),
          ];
          // Las de una misma fila a la misma altura (la rejilla del diseño las
          // estira), con casillas vacías para que las anchas no cambien.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var f = 0; f < filas.length; f++) ...[
                if (f > 0) const SizedBox(height: gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < columnas; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Expanded(child: i < filas[f].length ? _Tarjeta(filas[f][i]) : const SizedBox.shrink()),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        }),
      ],
    );
  }
}

(Color, Color) _coloresDe(TonoReporte t) => switch (t) {
      TonoReporte.verde => (_C.gift, _C.giftTint),
      TonoReporte.azul => (_C.don, _C.donTint),
      TonoReporte.ambar => (_C.warn, _C.warnTint),
      TonoReporte.rojo => (_C.bad, _C.badTint),
      TonoReporte.morado => (_C.accent, _C.tint),
    };

class _Tarjeta extends StatefulWidget {
  final ReporteItem r;
  const _Tarjeta(this.r);

  @override
  State<_Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<_Tarjeta> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final (color, fondo) = _coloresDe(r.tono);
    final dato = r.dato;

    return Material(
      color: _C.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: r.onTap,
        onHover: (h) => setState(() => _encima = h),
        // El realce del diseño es un borde de acento por dentro, no un fondo.
        hoverColor: Colors.transparent,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _encima ? _C.accent : Colors.transparent, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16)),
                      child: Icon(r.icono, size: 24, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.titulo, style: _t(17, FontWeight.w700, _C.ink, height: 1.3)),
                          const SizedBox(height: 2),
                          Text(r.descripcion, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.4)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.chevron_right_rounded, size: 20, color: _C.soft),
                    ),
                  ],
                ),
                if (dato != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                for (final p in dato.partes)
                                  TextSpan(
                                    text: p.texto,
                                    style: p.negrita
                                        ? _t(15, FontWeight.w700, _C.ink)
                                        : _t(13.5, FontWeight.w400, _C.muted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (dato.bandera != null) ...[
                          const SizedBox(width: 8),
                          // Pegada al borde derecho, como en el diseño. El tope
                          // (sale de la pantalla y NO de un LayoutBuilder, porque
                          // la tarjeta va en un IntrinsicHeight) evita que una
                          // cifra enorme se salga de la tarjeta: el texto cede.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (MediaQuery.sizeOf(context).width * 0.45).clamp(0.0, 220.0),
                            ),
                            child: _Bandera(dato.bandera!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bandera extends StatelessWidget {
  final BanderaReporte b;
  const _Bandera(this.b);

  @override
  Widget build(BuildContext context) {
    final (color, fondo) = switch (b.tono) {
      TonoBandera.rojo => (_C.bad, _C.badTint),
      TonoBandera.ambar => (_C.warn, _C.warnTint),
      TonoBandera.verde => (_C.gift, _C.giftTint),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      // `Center` con widthFactor y no `alignment` en el Container: ese alineado
      // ocuparía todo el ancho que le den, y la banderita se ensancharía.
      child: Center(
        widthFactor: 1,
        child: Text(
          b.texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _t(12, FontWeight.w700, color, height: 1.0),
        ),
      ),
    );
  }
}
