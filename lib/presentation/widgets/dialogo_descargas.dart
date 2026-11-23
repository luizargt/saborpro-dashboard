/// "Descargar reportes": en pantalla ancha un diálogo al centro; en el teléfono, una
/// hoja desde abajo. Diseño `sidebar-manager.html`. Se elige el mes y la sucursal, se
/// busca el reporte y se descarga en Excel.
///
/// Sin providers ni Firebase: el mes lo pone quien lo usa ([selectorPeriodo]) y lo que se
/// descarga lo hace el [DescargasController]. Se prueba en test/presentation/widgets/
/// dialogo_descargas_test.dart.
library;

import 'package:flutter/material.dart';

import '../controllers/descargas_controller.dart';
import '../navigation/destinos.dart';
import 'barra_inferior.dart' show mostrarHojaManager;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Una sucursal para elegir: id null es "Todas".
typedef OpcionSucursal = ({String? id, String nombre});

class ContenidoDescargas extends StatefulWidget {
  final DescargasController controlador;

  /// El selector del mes (en la app, el mismo del encabezado).
  final Widget selectorPeriodo;
  final List<OpcionSucursal> sucursales;
  final String? sucursalElegida;
  final ValueChanged<String?> onSucursal;
  final VoidCallback onCerrar;

  /// En el teléfono el botón de cada fila es solo el ícono, y no se dibuja el "Excel".
  final bool telefono;

  const ContenidoDescargas({
    super.key,
    required this.controlador,
    required this.selectorPeriodo,
    required this.sucursales,
    required this.sucursalElegida,
    required this.onSucursal,
    required this.onCerrar,
    this.telefono = false,
  });

  @override
  State<ContenidoDescargas> createState() => _ContenidoDescargasState();
}

class _ContenidoDescargasState extends State<ContenidoDescargas> {
  final _campo = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  List<ItemDescarga> get _visibles {
    final q = Destinos.sinTildes(_q.trim());
    return [
      for (final i in widget.controlador.items)
        if (q.isEmpty || Destinos.sinTildes('${i.nombre} ${i.descripcion}').contains(q)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final visibles = _visibles;
        final buscador = c.items.length > 5;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Descargar reportes', style: _t(19, FontWeight.w700, _C.ink, height: 1.3))),
                Tooltip(
                  message: 'Cerrar',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onCerrar,
                    child: SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, size: 19, color: _C.muted)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: widget.selectorPeriodo),
            if (widget.sucursales.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in widget.sucursales) ...[
                      _Chip(texto: s.nombre, activo: s.id == widget.sucursalElegida, onTap: () => widget.onSucursal(s.id)),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ],
            if (buscador) ...[
              const SizedBox(height: 10),
              Container(
                height: 46,
                padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(13), border: Border.all(color: _C.line, width: 1.5)),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 18, color: _C.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('descargas-buscar'),
                        controller: _campo,
                        onChanged: (v) => setState(() => _q = v),
                        cursorColor: _C.accent,
                        style: _t(15, FontWeight.w400, _C.ink),
                        decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: 'Buscar reporte…', hintStyle: _t(15, FontWeight.w400, _C.soft)),
                      ),
                    ),
                    if (_q.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() {
                          _campo.clear();
                          _q = '';
                        }),
                        child: Icon(Icons.close_rounded, size: 18, color: _C.muted),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Flexible(
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.line)),
                clipBehavior: Clip.antiAlias,
                child: visibles.isEmpty
                    ? Padding(padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16), child: Text('No hay reportes con "${_q.trim()}"', textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)))
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: visibles.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: _C.line),
                        itemBuilder: (_, i) => _FilaDescarga(item: visibles[i], controlador: c, telefono: widget.telefono),
                      ),
              ),
            ),
            if (c.error != null) ...[
              const SizedBox(height: 10),
              Text(c.error!, style: _t(12.5, FontWeight.w600, _C.bad, height: 1.4)),
            ],
            const SizedBox(height: 10),
            Text('Se descarga con el mes y la sucursal que elegiste arriba.', style: _t(12.5, FontWeight.w400, _C.muted, height: 1.4)),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final bool activo;
  final VoidCallback onTap;
  const _Chip({required this.texto, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activo,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: activo ? _C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: activo ? _C.ink : _C.line, width: 1.5),
          ),
          child: Text(texto, maxLines: 1, style: _t(13.5, FontWeight.w600, activo ? _C.card : _C.muted)),
        ),
      ),
    );
  }
}

class _FilaDescarga extends StatelessWidget {
  final ItemDescarga item;
  final DescargasController controlador;
  final bool telefono;
  const _FilaDescarga({required this.item, required this.controlador, required this.telefono});

  @override
  Widget build(BuildContext context) {
    final lista = controlador.hechas.contains(item.id);
    final cargando = controlador.descargando == item.id;
    final otra = controlador.ocupado && !cargando;

    final Widget boton;
    if (cargando) {
      boton = Container(
        width: telefono ? 44 : 118,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _C.tint, borderRadius: BorderRadius.circular(12)),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: _C.accent)),
      );
    } else {
      boton = Semantics(
        button: true,
        label: 'Descargar ${item.nombre}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: otra ? null : () => controlador.descargar(item),
          child: Container(
            height: 44,
            width: telefono ? 44 : null,
            padding: EdgeInsets.symmetric(horizontal: telefono ? 0 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lista ? _C.giftTint : (otra ? _C.subtle : _C.accent),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(lista ? Icons.check_rounded : Icons.file_download_outlined, size: 17, color: lista ? _C.gift : (otra ? _C.soft : _C.onAccent)),
                if (!telefono) ...[
                  const SizedBox(width: 6),
                  Text(lista ? 'Listo' : 'Descargar', style: _t(13.5, FontWeight.w700, lista ? _C.gift : (otra ? _C.soft : _C.onAccent))),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _C.tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(item.icono, size: 19, color: _C.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w600, _C.ink, height: 1.3)),
                Text(item.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis, style: _t(12.5, FontWeight.w400, _C.muted, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!telefono) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _C.giftTint, borderRadius: BorderRadius.circular(6)),
              child: Text('Excel', style: _t(11, FontWeight.w700, _C.gift, height: 1.3)),
            ),
            const SizedBox(width: 12),
          ],
          boton,
        ],
      ),
    );
  }
}

/// Abre las descargas: un diálogo en pantalla ancha, una hoja en el teléfono.
Future<void> mostrarDescargas(
  BuildContext context, {
  required DescargasController controlador,
  required Widget selectorPeriodo,
  required List<OpcionSucursal> sucursales,
  required String? Function() sucursalElegida,
  required ValueChanged<String?> onSucursal,
}) {
  final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;

  Widget contenido(BuildContext ctx, void Function() cerrar) => StatefulBuilder(
        builder: (ctx, setState) => ContenidoDescargas(
          controlador: controlador,
          selectorPeriodo: selectorPeriodo,
          sucursales: sucursales,
          sucursalElegida: sucursalElegida(),
          onSucursal: (id) {
            onSucursal(id);
            setState(() {});
          },
          onCerrar: cerrar,
          telefono: telefono,
        ),
      );

  if (telefono) {
    return mostrarHojaManager<void>(context, builder: (ctx) => contenido(ctx, () => Navigator.of(ctx).pop()));
  }
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x730A0C1C),
    builder: (ctx) => Dialog(
      backgroundColor: _C.card,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: SingleChildScrollView(child: contenido(ctx, () => Navigator.of(ctx).pop())),
        ),
      ),
    ),
  );
}
