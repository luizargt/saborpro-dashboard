import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';
import '../../core/services/export_service.dart';

String _paymentLabel(String method) {
  switch (method.toLowerCase()) {
    case 'cash':
      return 'Efectivo';
    case 'card':
      return 'Tarjeta';
    case 'split':
      return 'Dividido';
    case 'transfer':
      return 'Transferencia';
    default:
      if (method.isEmpty) return method;
      return method[0].toUpperCase() + method.substring(1);
  }
}

class ProductsList extends StatefulWidget {
  final List<ProductSummary> products;
  final Map<String, List<ProductSummary>> productsByMethod;
  final String prevLabel;
  final double tips;
  final double discounts;
  final double totalSales;

  const ProductsList({
    super.key,
    required this.products,
    this.productsByMethod = const {},
    required this.prevLabel,
    this.tips = 0,
    this.discounts = 0,
    this.totalSales = 0,
  });

  @override
  State<ProductsList> createState() => _ProductsListState();
}

class _ProductsListState extends State<ProductsList> {
  String? _selectedCategory;
  String? _selectedPaymentMethod;

  // La clasificación ya no cuenta como "filtro activo" del botón: es una
  // pestaña visible, no algo escondido en el bottom sheet.
  bool get _hasActiveFilters => _selectedPaymentMethod != null;
  int get _activeFilterCount => _selectedPaymentMethod != null ? 1 : 0;

  @override
  void didUpdateWidget(ProductsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products != widget.products) {
      _selectedCategory = null;
      _selectedPaymentMethod = null;
    }
  }

  // Orden canónico de las clasificaciones del menú (COMIDA/BEBIDA/POSTRES/
  // SERVICIOS/OTRO en Firestore). Se muestran como pestañas, y solo las que
  // realmente tienen ventas en el período.
  static const _classificationOrder = [
    'Comida',
    'Bebidas',
    'Postres',
    'Servicios',
    'Otros',
  ];

  /// Etiqueta de la pestaña. El valor guardado es 'Comida' pero en la pestaña
  /// se lee mejor en plural, igual que las demás.
  static String _tabLabel(String category) =>
      category == 'Comida' ? 'Comidas' : category;

  /// Clasificaciones presentes en los datos, en el orden canónico. Las que no
  /// estén en la lista conocida se agregan al final en vez de descartarse.
  List<String> _orderedCategories(List<String> present) {
    final known = _classificationOrder.where(present.contains).toList();
    final unknown = present.where((c) => !_classificationOrder.contains(c)).toList()..sort();
    return [...known, ...unknown];
  }

  /// Mueve la pestaña una posición. `tabs` incluye null ("Todo") al inicio.
  void _shiftTab(List<String?> tabs, int delta) {
    final current = tabs.indexOf(_selectedCategory);
    if (current == -1) return;
    final next = current + delta;
    if (next < 0 || next >= tabs.length) return;
    setState(() => _selectedCategory = tabs[next]);
  }

  /// Sustantivo para el conteo del pie de tabla, según la pestaña activa.
  static String _countNoun(String? category) => switch (category) {
        'Bebidas' => 'bebidas',
        'Postres' => 'postres',
        'Servicios' => 'servicios',
        'Otros' => 'productos',
        _ => 'platillos',
      };

  String _title(String? category, String? paymentMethod) {
    final base = switch (category) {
      'Bebidas' => 'Bebidas vendidas',
      'Postres' => 'Postres vendidos',
      'Servicios' => 'Servicios vendidos',
      'Otros' => 'Otros vendidos',
      _ => 'Platillos vendidos',
    };
    if (paymentMethod != null) {
      return '$base · ${_paymentLabel(paymentMethod)}';
    }
    return base;
  }

  void _showFiltersSheet(List<String> categories, List<String> paymentMethods) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      useSafeArea: true,
      builder: (ctx) => _FiltersSheet(
        categories: categories,
        paymentMethods: paymentMethods,
        selectedCategory: _selectedCategory,
        selectedPaymentMethod: _selectedPaymentMethod,
        onCategoryChanged: (val) => setState(() => _selectedCategory = val),
        onPaymentMethodChanged: (val) => setState(() => _selectedPaymentMethod = val),
        onClear: () => setState(() {
          _selectedCategory = null;
          _selectedPaymentMethod = null;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');

    final baseProducts = _selectedPaymentMethod != null
        ? (widget.productsByMethod[_selectedPaymentMethod] ?? widget.products)
        : widget.products;

    final categories = baseProducts
        .map((p) => p.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Si la categoría seleccionada ya no existe en la lista filtrada, la limpiamos
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedCategory = null);
      });
    }

    final filtered = _selectedCategory == null
        ? baseProducts
        : baseProducts.where((p) => p.category == _selectedCategory).toList();

    final paymentMethods = widget.productsByMethod.keys.toList()..sort();

    final orderedCategories = _orderedCategories(categories);
    // null = "Todo": sin él se perdería la vista completa, que es la que trae
    // los totales de propinas, descuentos y total cobrado.
    final tabs = <String?>[null, ...orderedCategories];

    return GestureDetector(
      // Deslizar sobre la tabla cambia de clasificación. Este gesto queda por
      // dentro del de sucursales (LocationSwipeArea): Flutter le da prioridad
      // al detector más interno, así que aquí manda la clasificación.
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: orderedCategories.length > 1
          ? (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              _shiftTab(tabs, v < 0 ? 1 : -1);
            }
          : null,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _title(_selectedCategory, _selectedPaymentMethod),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                Text(
                  'vs ${widget.prevLabel}',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(width: 8),
                // Botón filtro
                if (widget.products.isNotEmpty)
                  Tooltip(
                    message: 'Filtrar',
                    child: InkWell(
                      onTap: () => _showFiltersSheet(categories, paymentMethods),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _hasActiveFilters
                              ? const Color(0xFF7444fd).withValues(alpha: 0.15)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _hasActiveFilters
                                ? const Color(0xFF7444fd)
                                : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: _hasActiveFilters
                                  ? const Color(0xFF7444fd)
                                  : Colors.white,
                              size: 16,
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$_activeFilterCount',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF7444fd),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (widget.products.isNotEmpty)
                  Tooltip(
                    message: 'Descargar Excel',
                    child: InkWell(
                      onTap: () => ExportService.exportProducts(widget.products, widget.prevLabel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_rounded, color: Colors.white70, size: 16),
                            SizedBox(width: 4),
                            Text('Excel', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (widget.tips > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Propinas no incluidas',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
          ),
        ],
        // Pestañas por clasificación del menú. Solo aparecen si hay más de una
        // clasificación con ventas: con una sola no habría nada que elegir.
        if (orderedCategories.length > 1) ...[
          const SizedBox(height: 10),
          _CategoryTabs(
            tabs: tabs,
            selected: _selectedCategory,
            labelFor: (c) => c == null ? 'Todo' : _tabLabel(c),
            onChanged: (c) => setState(() => _selectedCategory = c),
          ),
        ],
        const SizedBox(height: 4),
        // Header tabla
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Nombre', style: GoogleFonts.inter(color: Colors.white60, fontSize: 11)),
              ),
              SizedBox(
                width: 50,
                child: Text('Cant.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white60, fontSize: 11)),
              ),
              SizedBox(
                width: 80,
                child: Text('Total', textAlign: TextAlign.right, style: GoogleFonts.inter(color: Colors.white60, fontSize: 11)),
              ),
              SizedBox(
                width: 52,
                child: Text('Var.', textAlign: TextAlign.right, style: GoogleFonts.inter(color: Colors.white60, fontSize: 11)),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.products.isEmpty
                    ? 'Sin ventas en este período'
                    : 'Sin productos con estos filtros',
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
              ),
            ),
          )
        else ...[
          ...filtered.map((p) => _ProductRow(product: p, fmt: fmt)),
          _FooterRow(
            label: 'Total (${filtered.length} ${_countNoun(_selectedCategory)})',
            qty: filtered.fold<int>(0, (s, p) => s + p.quantity),
            amount: filtered.fold<double>(0, (s, p) => s + p.total),
            fmt: fmt,
            labelColor: Colors.white70,
            amountColor: Colors.white70,
          ),
          if (_selectedCategory == null && _selectedPaymentMethod == null) ...[
            if (widget.tips > 0)
              _FooterRow(
                label: '+ Propinas',
                amount: widget.tips,
                fmt: fmt,
                labelColor: const Color(0xFFF59E0B),
                amountColor: const Color(0xFFF59E0B),
              ),
            if (widget.discounts > 0)
              _FooterRow(
                label: '− Descuentos',
                amount: -widget.discounts,
                fmt: fmt,
                labelColor: const Color(0xFFEF4444),
                amountColor: const Color(0xFFEF4444),
              ),
            if (widget.totalSales > 0)
              _FooterRow(
                label: 'Total cobrado',
                amount: widget.totalSales,
                fmt: fmt,
                labelColor: Colors.white,
                amountColor: const Color(0xFF7444fd),
                bold: true,
                topBorder: true,
              ),
          ],
        ],
      ],
      ),
    );
  }
}

// ─── Pestañas por clasificación ───────────────────────────────────────────────

/// Barra de pestañas subrayadas, del mismo estilo que las de sucursal. Es
/// deslizable en horizontal para que quepan cinco clasificaciones aun en un
/// teléfono angosto.
class _CategoryTabs extends StatelessWidget {
  final List<String?> tabs;
  final String? selected;
  final String Function(String?) labelFor;
  final ValueChanged<String?> onChanged;

  const _CategoryTabs({
    required this.tabs,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(height: 1, child: ColoredBox(color: Colors.white12)),
          ),
          // Cada pestaña ocupa una fracción igual del ancho, así el subrayado
          // abarca todo su segmento y el área táctil es cómoda para el dedo.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                for (final tab in tabs)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(tab),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Text(
                              labelFor(tab),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: selected == tab
                                    ? Colors.white
                                    : Colors.white60,
                                fontSize: 12,
                                fontWeight: selected == tab
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 2,
                            color: selected == tab
                                ? const Color(0xFF7444fd)
                                : Colors.transparent,
                          ),
                        ],
                      ),
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

// ─── Bottom Sheet de Filtros ──────────────────────────────────────────────────

class _FiltersSheet extends StatefulWidget {
  final List<String> categories;
  final List<String> paymentMethods;
  final String? selectedCategory;
  final String? selectedPaymentMethod;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final VoidCallback onClear;

  const _FiltersSheet({
    required this.categories,
    required this.paymentMethods,
    required this.selectedCategory,
    required this.selectedPaymentMethod,
    required this.onCategoryChanged,
    required this.onPaymentMethodChanged,
    required this.onClear,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _cat;
  late String? _pm;

  @override
  void initState() {
    super.initState();
    _cat = widget.selectedCategory;
    _pm = widget.selectedPaymentMethod;
  }

  bool get _hasFilters => _cat != null || _pm != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Título
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtros',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_hasFilters)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _cat = null;
                      _pm = null;
                    });
                    widget.onClear();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Limpiar todo',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF7444fd),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // La clasificación (Comidas/Bebidas/Postres/Servicios) ya no vive aquí:
        // ahora son las pestañas de la tabla. Tener los dos controles para el
        // mismo filtro solo confundía.
        // Sección Método de pago
        if (widget.paymentMethods.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text(
              'Método de pago',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'Todos',
                  selected: _pm == null,
                  onTap: () {
                    setState(() => _pm = null);
                    widget.onPaymentMethodChanged(null);
                  },
                ),
                ...widget.paymentMethods.map((method) => _Chip(
                      label: _paymentLabel(method),
                      selected: _pm == method,
                      onTap: () {
                        setState(() => _pm = method);
                        widget.onPaymentMethodChanged(method);
                      },
                    )),
              ],
            ),
          ),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 28),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF7444fd) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF7444fd) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Filas de la tabla ────────────────────────────────────────────────────────

class _FooterRow extends StatelessWidget {
  final String label;
  final int? qty;
  final double amount;
  final NumberFormat fmt;
  final Color labelColor;
  final Color amountColor;
  final bool bold;
  final bool topBorder;

  const _FooterRow({
    required this.label,
    required this.amount,
    required this.fmt,
    required this.labelColor,
    required this.amountColor,
    this.qty,
    this.bold = false,
    this.topBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      color: amountColor,
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: topBorder
              ? const BorderSide(color: Color(0x33FFFFFF), width: 1)
              : BorderSide.none,
        ),
        color: topBorder ? const Color(0x0AFFFFFF) : Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: labelColor,
                fontSize: bold ? 13 : 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: qty != null
                ? Text('$qty',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700))
                : const SizedBox(),
          ),
          SizedBox(
            width: 80,
            child: Text(
              amount < 0 ? '−Q${fmt.format(amount.abs())}' : 'Q${fmt.format(amount)}',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ProductSummary product;
  final NumberFormat fmt;

  const _ProductRow({required this.product, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final change = product.changePercent;
    final isPositive = change > 0;
    final isNeutral = change == 0;
    final changeColor = isNeutral
        ? Colors.white60
        : isPositive
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              product.name,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${product.quantity}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Q${fmt.format(product.total)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isNeutral)
                  Icon(
                    isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 10,
                    color: changeColor,
                  ),
                const SizedBox(width: 2),
                Text(
                  isNeutral ? '—' : '${change.abs().toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                    color: changeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
