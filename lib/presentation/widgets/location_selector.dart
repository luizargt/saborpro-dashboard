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
        return Padding(
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
        );
      },
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
