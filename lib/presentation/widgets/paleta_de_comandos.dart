/// La paleta de comandos: se abre con el buscador de la barra o con Ctrl/⌘ K, se
/// escribe parte del nombre de una pantalla (sin importar tildes ni mayúsculas) y se
/// salta a ella. Diseño `sidebar-manager.html`.
///
/// Sin providers ni Firebase: se prueba en test/presentation/widgets/
/// paleta_de_comandos_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/destinos.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Abre la paleta y devuelve a dónde se quiso ir (null si se cerró sin elegir).
Future<Destino?> mostrarPaletaDeComandos(BuildContext context, {required Destino actual}) {
  return showGeneralDialog<Destino>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: const Color(0x730A0C1C),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, __) => PaletaDeComandos(actual: actual),
    transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class PaletaDeComandos extends StatefulWidget {
  /// Dónde se está: sale marcado "Estás aquí".
  final Destino actual;

  /// Lo que se puede buscar; por defecto, todo lo de [Destinos.buscar].
  final List<Destino> Function(String consulta)? buscar;

  const PaletaDeComandos({super.key, required this.actual, this.buscar});

  @override
  State<PaletaDeComandos> createState() => _PaletaDeComandosState();
}

class _PaletaDeComandosState extends State<PaletaDeComandos> {
  final _campo = TextEditingController();
  final _foco = FocusNode();
  final _scroll = ScrollController();
  int _sel = 0;

  List<Destino> get _resultados => (widget.buscar ?? Destinos.buscar)(_campo.text);

  @override
  void dispose() {
    _campo.dispose();
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _mover(int delta) {
    final r = _resultados;
    if (r.isEmpty) return;
    setState(() => _sel = (_sel + delta + r.length) % r.length);
  }

  void _abrir(Destino d) => Navigator.of(context).pop(d);

  @override
  Widget build(BuildContext context) {
    final r = _resultados;
    final sel = r.isEmpty ? 0 : _sel.clamp(0, r.length - 1);
    final tam = MediaQuery.sizeOf(context);
    final telefono = tam.width <= kInicioQuiebreTelefono;

    // Los resultados por grupo, en el orden en que salen.
    final filas = <Widget>[];
    String? ultimo;
    for (var i = 0; i < r.length; i++) {
      final d = r[i];
      final g = Destinos.grupoDeBusqueda(d);
      if (g != ultimo) {
        filas.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(g.toUpperCase(), style: _t(11, FontWeight.w700, _C.soft).copyWith(letterSpacing: 0.77)),
        ));
        ultimo = g;
      }
      filas.add(_FilaResultado(destino: d, seleccionado: i == sel, aqui: d == widget.actual, onTap: () => _abrir(d)));
    }

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(telefono ? 10 : 16, telefono ? 10 : tam.height * 0.12, telefono ? 10 : 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 620, maxHeight: tam.height * (telefono ? 0.85 : 0.7)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _C.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: _C.sombra, blurRadius: 60, offset: const Offset(0, 24))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _mover(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _mover(-1),
                        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
                      },
                      child: Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _C.line))),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 20, color: _C.muted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                key: const Key('paleta-buscar'),
                                controller: _campo,
                                focusNode: _foco,
                                autofocus: true,
                                cursorColor: _C.accent,
                                style: _t(16, FontWeight.w400, _C.ink),
                                textInputAction: TextInputAction.go,
                                onChanged: (_) => setState(() => _sel = 0),
                                onSubmitted: (_) {
                                  if (r.isNotEmpty) _abrir(r[sel]);
                                },
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  hintText: 'Busca un reporte o pantalla…',
                                  hintStyle: _t(16, FontWeight.w400, _C.soft),
                                ),
                              ),
                            ),
                            if (!telefono)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(6), border: Border.all(color: _C.line)),
                                child: Text('Esc', style: _t(11, FontWeight.w600, _C.muted, height: 1.3)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: r.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(30),
                              child: Text('No encontramos "${_campo.text.trim()}"', textAlign: TextAlign.center, style: _t(14, FontWeight.w400, _C.muted)),
                            )
                          : ListView(controller: _scroll, shrinkWrap: true, padding: const EdgeInsets.all(8), children: filas),
                    ),
                    if (!telefono)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
                        child: Wrap(
                          spacing: 14,
                          children: [
                            for (final t in const ['Flechas para moverte', 'Enter abrir', 'Esc cerrar']) Text(t, style: _t(12, FontWeight.w400, _C.muted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaResultado extends StatelessWidget {
  final Destino destino;
  final bool seleccionado;
  final bool aqui;
  final VoidCallback onTap;
  const _FilaResultado({required this.destino, required this.seleccionado, required this.aqui, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? _C.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: seleccionado ? _C.card : _C.subtle, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Destinos.icono(destino), size: 17, color: seleccionado ? _C.accent : _C.muted),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(Destinos.nombre(destino), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14.5, FontWeight.w400, _C.ink))),
                if (aqui) Text('Estás aquí', style: _t(12.5, FontWeight.w400, _C.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
