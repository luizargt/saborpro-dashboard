import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import 'period_selector.dart';

// ── LOCATION TABS BAR ────────────────────────────────────────────────────────
// Barra horizontal con una pestaña por sucursal ("Todas" + cada una). Solo
// indica/selecciona por toque; el cambio por deslizar vive en
// [LocationSwipeArea], que envuelve el contenido de toda la pantalla.

/// Una pestaña de la barra: [id] null es "Todas".
class LocationTabItem {
  final String? id;
  final String label;

  const LocationTabItem(this.id, this.label);
}

/// La barra tal como se ve, sin saber de dónde salen las sucursales.
///
/// Vive separada de [LocationTabsBar] para poder probarla a 360dp sin Firebase
/// —construir el provider levanta Firestore—, igual que [BiometricLoginButton]
/// con los plugins de biometría.
///
/// Cuando los nombres no caben, la barra se desliza en horizontal en vez de
/// apretujarlos: con tres sucursales de nombre largo, repartir el ancho a la
/// fuerza partía "Santa Rosalía" en dos líneas y la montaba sobre la de al
/// lado. Ningún nombre se parte nunca: o cabe, o la barra rueda.
class LocationTabsView extends StatefulWidget {
  final List<LocationTabItem> items;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const LocationTabsView({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<LocationTabsView> createState() => _LocationTabsViewState();
}

class _LocationTabsViewState extends State<LocationTabsView> {
  /// Aire a cada lado del nombre cuando la barra se desliza.
  static const _padHorizontal = 14.0;

  final _scroll = ScrollController();
  final _tabKeys = <String?, GlobalKey>{};
  bool _primerBuild = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocationTabsView old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      _mostrarSeleccionada(animar: true);
    }
  }

  /// Trae a la vista la pestaña activa. Sin esto, cambiar de sucursal
  /// deslizando el contenido podía dejar seleccionada una pestaña que quedó
  /// fuera de la pantalla, y el usuario pierde de vista dónde está parado.
  void _mostrarSeleccionada({required bool animar}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[widget.selectedId]?.currentContext;
      if (!mounted || ctx == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animar ? const Duration(milliseconds: 280) : Duration.zero,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  /// Ancho que ocupa una pestaña. Se mide con la tipografía de la activa (la
  /// más gruesa, o sea la más ancha) para que nada se mueva de lugar al
  /// cambiar de sucursal.
  double _anchoDe(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width.ceilToDouble() + _padHorizontal * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (_primerBuild) {
      _primerBuild = false;
      _mostrarSeleccionada(animar: false);
    }

    return SizedBox(
      height: 46,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(height: 1, child: ColoredBox(color: Colors.white12)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final anchos = [
                  for (final item in widget.items)
                    _anchoDe(context, item.label),
                ];
                final total = anchos.fold<double>(0, (a, b) => a + b);
                final caben = total <= constraints.maxWidth;

                final pestanas = <Widget>[
                  for (var i = 0; i < widget.items.length; i++)
                    _LocationTab(
                      key: _tabKeys.putIfAbsent(
                          widget.items[i].id, GlobalKey.new),
                      label: widget.items[i].label,
                      selected: widget.selectedId == widget.items[i].id,
                      // Si caben, cada una toma su parte del ancho como
                      // siempre; si no, cada una ocupa lo suyo y la barra rueda.
                      width: caben ? null : anchos[i],
                      onTap: () => widget.onSelected(widget.items[i].id),
                    ),
                ];

                if (caben) {
                  return Row(
                    children: [for (final p in pestanas) Expanded(child: p)],
                  );
                }
                return SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(children: pestanas),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// La barra conectada al provider: arma las pestañas con las sucursales
/// permitidas y manda la selección de vuelta.
class LocationTabsBar extends StatelessWidget {
  const LocationTabsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    if (provider.locations.length <= 1) return const SizedBox.shrink();

    return LocationTabsView(
      items: [
        const LocationTabItem(null, 'Todas'),
        for (final loc in provider.locations) LocationTabItem(loc.id, loc.name),
      ],
      selectedId: provider.selectedLocationId,
      onSelected: provider.selectLocation,
    );
  }
}

class _LocationTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Null = la pestaña la estira el Expanded de la fila.
  final double? width;

  const _LocationTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: GoogleFonts.inter(
                  color: selected ? Colors.white : Colors.white38,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  // Nunca en dos líneas: si el nombre no cabe, la barra se
                  // desliza; apretujarlo es lo que rompía el encabezado.
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2,
              color: selected ? const Color(0xFF7444fd) : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

// ── LOCATION HEADER BAR ──────────────────────────────────────────────────────
// Encabezado fijo de las pantallas con filtro por sucursal: las pestañas a
// ancho completo en móvil, y compartiendo fila con el selector de fecha cuando
// hay espacio. Va fuera del scroll para no perderse al desplazar el contenido.
class LocationHeaderBar extends StatelessWidget {
  const LocationHeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final hasTabs = provider.locations.length > 1;
    final wide = MediaQuery.of(context).size.width >= 600;

    // En pantalla ancha el selector de fecha vive solo aquí (el shell ancho
    // no tiene AppBar propio), así que debe verse aunque no haya pestañas
    // de sucursal que mostrar.
    if (!wide) {
      if (!hasTabs) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LocationTabsBar(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          if (hasTabs) ...[
            const Expanded(child: LocationTabsBar()),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          const DateSelectorChip(),
        ],
      ),
    );
  }
}

// ── LOCATION SWIPE AREA ──────────────────────────────────────────────────────
// Envuelve el contenido de una pantalla para permitir cambiar de sucursal
// deslizando horizontalmente en cualquier parte (izquierda = siguiente,
// derecha = anterior), sin interferir con el scroll vertical del contenido.
// La animación del cambio NO vive aquí: la hace [LocationContentSwitcher], que
// va por debajo de la barra de pestañas para que la barra se quede quieta.
class LocationSwipeArea extends StatelessWidget {
  final Widget child;

  const LocationSwipeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 200) return;
        if (provider.locations.length <= 1) return;

        final ids = <String?>[null, for (final loc in provider.locations) loc.id];
        final current = ids.indexOf(provider.selectedLocationId);
        final index = current == -1 ? 0 : current;
        final forward = velocity < 0;
        final next = forward
            ? (index + 1) % ids.length
            : (index - 1 + ids.length) % ids.length;
        provider.selectLocation(ids[next]);
      },
      child: child,
    );
  }
}

// ── LOCATION CONTENT SWITCHER ────────────────────────────────────────────────
// Anima el contenido cuando cambia la sucursal.
//
// Va por dentro de la barra de pestañas a propósito: antes la animación
// envolvía la pantalla entera, así que en cada cambio la barra también se iba
// y volvía, y el conjunto se sentía como un salto seco a otra pantalla. Ahora
// la barra se queda fija (su subrayado se desliza) y solo los datos entran,
// con un desplazamiento corto — un empujoncito, no un cambio de página — y un
// fundido encima.
class LocationContentSwitcher extends StatefulWidget {
  final Widget child;

  const LocationContentSwitcher({super.key, required this.child});

  @override
  State<LocationContentSwitcher> createState() =>
      _LocationContentSwitcherState();
}

class _LocationContentSwitcherState extends State<LocationContentSwitcher> {
  /// Cuánto se desplaza el contenido, en fracción del ancho. Corto a
  /// propósito: lo que se pidió es suavidad, no un carrusel.
  static const _recorrido = 0.07;

  String? _anterior;
  bool _haciaAdelante = true;
  bool _visto = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final seleccionada = provider.selectedLocationId;

    if (!_visto) {
      _anterior = seleccionada;
      _visto = true;
    } else if (seleccionada != _anterior) {
      // La dirección la manda el orden de las pestañas, no el gesto: tocar la
      // pestaña de la derecha y deslizar hacia ese mismo lado tienen que verse
      // igual, porque para el usuario son la misma acción.
      final ids = <String?>[null, for (final loc in provider.locations) loc.id];
      final desde = ids.indexOf(_anterior);
      final hasta = ids.indexOf(seleccionada);
      if (desde != -1 && hasta != -1) _haciaAdelante = hasta > desde;
      _anterior = seleccionada;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final childKey = child.key;
        final entra = childKey is ValueKey && childKey.value == seleccionada;
        final dir = _haciaAdelante ? _recorrido : -_recorrido;
        final desplazamiento = Tween<Offset>(
          begin: Offset(entra ? dir : -dir, 0),
          end: Offset.zero,
        );
        return ClipRect(
          child: SlideTransition(
            position: desplazamiento.animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(seleccionada),
        child: widget.child,
      ),
    );
  }
}
