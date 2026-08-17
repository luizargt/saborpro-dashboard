import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';

class LocationSelector extends StatelessWidget {
  const LocationSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    if (provider.locations.length <= 1) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showPicker(context, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: provider.selectedLocationId != null
                ? const Color(0xFF7444fd)
                : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_outlined, color: Colors.white54, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                provider.selectedLocationName,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, DashboardProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Seleccionar sucursal',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                _LocationTile(
                  name: 'Todas las sucursales',
                  selected: provider.selectedLocationId == null,
                  onTap: () {
                    Navigator.pop(context);
                    provider.selectLocation(null);
                  },
                ),
                ...provider.locations.map((loc) => _LocationTile(
                      name: loc.name,
                      selected: provider.selectedLocationId == loc.id,
                      onTap: () {
                        Navigator.pop(context);
                        provider.selectLocation(loc.id);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── LOCATION TABS BAR ────────────────────────────────────────────────────────
// Barra horizontal con una pestaña por sucursal ("Todas" + cada una). Solo
// indica/selecciona por toque; el cambio por deslizar vive en
// [LocationSwipeArea], que envuelve el contenido de toda la pantalla.
class LocationTabsBar extends StatelessWidget {
  const LocationTabsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    if (provider.locations.length <= 1) return const SizedBox.shrink();

    final items = <(String?, String)>[
      (null, 'Todas'),
      for (final loc in provider.locations) (loc.id, loc.name),
    ];

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
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _LocationTab(
                      label: item.$2,
                      selected: provider.selectedLocationId == item.$1,
                      onTap: () => provider.selectLocation(item.$1),
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

class _LocationTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LocationTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 2,
            color: selected ? const Color(0xFF7444fd) : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

// ── LOCATION SWIPE AREA ──────────────────────────────────────────────────────
// Envuelve el contenido de una pantalla para permitir cambiar de sucursal
// deslizando horizontalmente en cualquier parte (izquierda = siguiente,
// derecha = anterior), sin interferir con el scroll vertical del contenido.
// El cambio anima con un deslizamiento + fade en vez de saltar de golpe.
class LocationSwipeArea extends StatefulWidget {
  final Widget child;

  const LocationSwipeArea({super.key, required this.child});

  @override
  State<LocationSwipeArea> createState() => _LocationSwipeAreaState();
}

class _LocationSwipeAreaState extends State<LocationSwipeArea> {
  bool _forward = true;

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
        setState(() => _forward = forward);
        provider.selectLocation(ids[next]);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final childKey = child.key;
          final isEntering =
              childKey is ValueKey && childKey.value == provider.selectedLocationId;
          final dir = _forward ? 1.0 : -1.0;
          final offsetTween = Tween<Offset>(
            begin: Offset(isEntering ? dir : -dir, 0),
            end: Offset.zero,
          );
          return ClipRect(
            child: SlideTransition(
              position: offsetTween.animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(provider.selectedLocationId),
          child: widget.child,
        ),
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _LocationTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        name,
        style: GoogleFonts.inter(
          color: selected ? const Color(0xFF7444fd) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Color(0xFF7444fd), size: 18)
          : null,
      onTap: onTap,
    );
  }
}
