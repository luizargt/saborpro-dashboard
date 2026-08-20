import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';

/// Carrusel con una tarjeta por clasificación del menú (Comida, Bebidas,
/// Postres, Servicios). Cada tarjeta muestra el top 3 de categorías de esa
/// clasificación y cuánto dinero genera cada una en el período.
class TopCategoriesCarousel extends StatelessWidget {
  final Map<String, List<CategorySummary>> categoriesByClassification;

  const TopCategoriesCarousel({
    super.key,
    required this.categoriesByClassification,
  });

  // Mismo orden canónico que usan las pestañas de la tabla de platillos.
  static const _order = ['Comida', 'Bebidas', 'Postres', 'Servicios', 'Otros'];

  static const _meta = {
    'Comida': (label: 'Comidas', icon: Icons.restaurant_rounded, color: Color(0xFF8B5CF6)),
    'Bebidas': (label: 'Bebidas', icon: Icons.local_cafe_rounded, color: Color(0xFF0D9488)),
    'Postres': (label: 'Postres', icon: Icons.cake_rounded, color: Color(0xFFEC4899)),
    'Servicios': (label: 'Servicios', icon: Icons.room_service_rounded, color: Color(0xFFF59E0B)),
    'Otros': (label: 'Otros', icon: Icons.category_rounded, color: Color(0xFF3B82F6)),
  };

  @override
  Widget build(BuildContext context) {
    final present = [
      ..._order.where(categoriesByClassification.containsKey),
      ...categoriesByClassification.keys.where((k) => !_order.contains(k)),
    ].where((k) => (categoriesByClassification[k] ?? const []).isNotEmpty).toList();

    if (present.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estas categorías son las que más vendes',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Top 3 de cada tipo de producto en el período',
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 12),
        // Sin altura fija: IntrinsicHeight iguala las tarjetas a la más alta y
        // deja que el contenido mande. Con una altura fija se desbordaba en
        // cuanto un nombre de categoría ocupaba más, o el usuario agrandaba la
        // letra del sistema.
        LayoutBuilder(
          builder: (context, constraints) {
            const cardWidth = 250.0;
            const gap = 12.0;
            final needed = present.length * cardWidth + (present.length - 1) * gap;
            // Si caben todas, se reparten el ancho disponible en vez de dejar
            // un hueco a la derecha; si no, se desliza como carrusel.
            final fits = needed <= constraints.maxWidth;

            final cards = [
              for (var i = 0; i < present.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Builder(builder: (context) {
                  final key = present[i];
                  final meta = _meta[key] ??
                      (label: key, icon: Icons.category_rounded, color: const Color(0xFF3B82F6));
                  final card = _ClassificationCard(
                    label: meta.label,
                    icon: meta.icon,
                    color: meta.color,
                    // Solo el top 3, ya vienen ordenadas de mayor a menor.
                    categories: categoriesByClassification[key]!.take(3).toList(),
                    totalOfClassification: categoriesByClassification[key]!
                        .fold<double>(0, (s, c) => s + c.total),
                    width: fits ? null : cardWidth,
                  );
                  return fits ? Expanded(child: card) : card;
                }),
              ],
            ];

            final row = IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cards,
              ),
            );

            return fits
                ? row
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: row,
                  );
          },
        ),
      ],
    );
  }
}

class _ClassificationCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final List<CategorySummary> categories;
  final double totalOfClassification;
  /// null = deja que el padre decida el ancho (Expanded en pantalla ancha).
  final double? width;

  const _ClassificationCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.categories,
    required this.totalOfClassification,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en_US');

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Q${money.format(totalOfClassification)} en total',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _CategoryRow(
              position: i + 1,
              category: categories[i],
              color: color,
              money: money,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final int position;
  final CategorySummary category;
  final Color color;
  final NumberFormat money;

  const _CategoryRow({
    required this.position,
    required this.category,
    required this.color,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 16,
          child: Text(
            '$position',
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.name,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${category.quantity} vendidos',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Q${money.format(category.total)}',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
