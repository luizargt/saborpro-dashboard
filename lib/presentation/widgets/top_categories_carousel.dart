import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Carrusel con una tarjeta por clasificación del menú (Comida, Bebidas,
/// Postres, Servicios): el top 3 de categorías de esa clasificación y cuánto
/// dinero genera cada una en el período.
///
/// Rediseño 2026-11-20 (inicio-manager.html, modo oscuro): una barra
/// proporcional en cada fila y la letra del diseño. El diseño las pone en una
/// cuadrícula de dos columnas, pero el dueño pidió que siguieran siendo un
/// CARRUSEL y más angostas: una sola fila de tarjetas de ancho fijo que se
/// desliza cuando no caben, y en el teléfono deja ver un pedazo de la
/// siguiente. Qué categorías salen y cuánto vendieron es lo de siempre.
class TopCategoriesCarousel extends StatelessWidget {
  final Map<String, List<CategorySummary>> categoriesByClassification;

  const TopCategoriesCarousel({
    super.key,
    required this.categoriesByClassification,
  });

  // Mismo orden canónico que usan las pestañas de la tabla de platillos.
  static const _order = ['Comida', 'Bebidas', 'Postres', 'Servicios', 'Otros'];

  static Map<String, ({String label, IconData icon, Color color})> get _meta => {
    'Comida': (label: 'Comidas', icon: Icons.restaurant_rounded, color: _C.accent),
    'Bebidas': (label: 'Bebidas', icon: Icons.local_cafe_rounded, color: _C.gift),
    'Postres': (label: 'Postres', icon: Icons.cake_rounded, color: Color(0xFFF28BC8)),
    'Servicios': (label: 'Servicios', icon: Icons.room_service_rounded, color: _C.warn),
    'Otros': (label: 'Otros', icon: Icons.category_rounded, color: _C.don),
  };

  /// Ancho de cada tarjeta. En teléfono, algo menos que la pantalla para que se
  /// vea un pedazo de la siguiente (eso dice "se desliza"). En ancho, lo que les
  /// toca si se reparten la fila, pero ni más angostas de 300 ni más anchas de
  /// 420: con tres clasificaciones caben todas; con más (o con una pantalla
  /// chica), la fila se desliza.
  static double anchoTarjeta(double disponible, int cuantas) {
    if (disponible <= kInicioQuiebreTelefono) {
      return (disponible * 0.84).clamp(250.0, 340.0);
    }
    final reparto = (disponible - 16.0 * (cuantas - 1)) / (cuantas < 1 ? 1 : cuantas);
    return reparto.clamp(300.0, 420.0);
  }

  @override
  Widget build(BuildContext context) {
    final present = [
      ..._order.where(categoriesByClassification.containsKey),
      ...categoriesByClassification.keys.where((k) => !_order.contains(k)),
    ].where((k) => (categoriesByClassification[k] ?? const []).isNotEmpty).toList();

    if (present.isEmpty) return const SizedBox.shrink();

    final tarjetas = [
      for (final key in present)
        _ClassificationCard(
          label: (_meta[key] ?? (label: key, icon: Icons.category_rounded, color: _C.don)).label,
          icon: (_meta[key] ?? (label: key, icon: Icons.category_rounded, color: _C.don)).icon,
          color: (_meta[key] ?? (label: key, icon: Icons.category_rounded, color: _C.don)).color,
          // Solo el top 3, ya vienen ordenadas de mayor a menor.
          categories: categoriesByClassification[key]!.take(3).toList(),
          totalOfClassification: categoriesByClassification[key]!.fold<double>(0, (s, c) => s + c.total),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Text('Estas categorías son las que más vendes', style: _t(17, FontWeight.w700, _C.ink)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('Top 3 de cada tipo de producto en el período',
              style: _t(13.5, FontWeight.w400, _C.muted)),
        ),
        LayoutBuilder(builder: (context, c) {
          const gap = 16.0;
          final ancho = anchoTarjeta(c.maxWidth, tarjetas.length);
          // Sin altura fija: IntrinsicHeight iguala las tarjetas a la más alta y
          // deja que el contenido mande. Con una altura fija se desbordaba en
          // cuanto un nombre ocupaba más, o el usuario agrandaba la letra.
          final fila = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tarjetas.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(width: ancho, child: tarjetas[i]),
                ],
              ],
            ),
          );
          // El ratón también arrastra: en el navegador de escritorio un
          // carrusel que solo responde al dedo no se puede recorrer.
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: fila,
            ),
          );
        }),
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

  const _ClassificationCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.categories,
    required this.totalOfClassification,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en_US');
    // La barra de cada fila se mide contra la primera (la que más vendió).
    final tope = categories.isEmpty ? 0.0 : categories.first.total;

    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(17, FontWeight.w700, _C.ink)),
                    Text(
                      '$moneda${money.format(totalOfClassification)} en total',
                      style: _t(13, FontWeight.w400, _C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < categories.length; i++)
            _CategoryRow(
              position: i + 1,
              category: categories[i],
              color: color,
              money: money,
              fraccion: tope > 0 ? (categories[i].total / tope).clamp(0.0, 1.0) : 0.0,
              primera: i == 0,
            ),
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
  final double fraccion;
  final bool primera;

  const _CategoryRow({
    required this.position,
    required this.category,
    required this.color,
    required this.money,
    required this.fraccion,
    required this.primera,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: _C.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 24, child: Text('$position', style: _t(15, FontWeight.w800, color))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, _C.ink)),
                Text('${category.quantity} vendidos', style: _t(12.5, FontWeight.w400, _C.muted)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: _C.subtle)),
                        FractionallySizedBox(
                          widthFactor: fraccion,
                          child: ColoredBox(color: color, child: const SizedBox.expand()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // El monto manda sobre el nombre (el nombre se acorta primero), pero con
          // una cifra enorme se achica en vez de salirse de la tarjeta.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$moneda${money.format(category.total)}', maxLines: 1, style: _t(15, FontWeight.w700, _C.ink)),
            ),
          ),
        ],
      ),
    );
  }
}
