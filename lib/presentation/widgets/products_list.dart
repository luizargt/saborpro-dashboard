import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/export_service.dart';
import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/hospedaje_inicio.dart' show kClasificacionHospedaje;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

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

// Anchos de las columnas de la tabla. El nombre toma lo que sobra.
const _anchoCant = 56.0;
const _anchoTotal = 96.0;
const _anchoVar = 76.0;

/// "Platillos vendidos": la tabla de lo vendido en el período, con pestañas por
/// clasificación del menú, la variación contra el período anterior y el Excel.
/// Rediseño 2026-11-20 (inicio-manager.html, modo oscuro); lo que se filtra, se
/// suma y se exporta es lo de siempre.
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
    // Los cargos del hospedaje: en un hotel sin comida es la primera pestaña, y
    // en uno con restaurante va después de lo del menú.
    kClasificacionHospedaje,
    'Servicios',
    'Otros',
  ];

  /// Etiqueta de la pestaña. El valor guardado es 'Comida' pero en la pestaña
  /// se lee mejor en plural, igual que las demás.
  static String _tabLabel(String category) => category == 'Comida' ? 'Comidas' : category;

  /// Clasificaciones presentes en los datos, en el orden canónico. Las que no
  /// estén en la lista conocida se agregan al final en vez de descartarse.
  List<String> _orderedCategories(List<String> present) {
    final known = _classificationOrder.where(present.contains).toList();
    final unknown = present.where((c) => !_classificationOrder.contains(c)).toList()..sort();
    return [...known, ...unknown];
  }

  /// Clasificación de un producto. Los que vienen sin clasificar caen en
  /// "Otros": sin la pestaña "Todo" desaparecerían de la tabla por completo.
  static String _catOf(ProductSummary p) => p.category.isEmpty ? 'Otros' : p.category;

  /// Mueve la pestaña una posición dentro de las clasificaciones disponibles.
  void _shiftTab(List<String> tabs, String? current, int delta) {
    final index = current == null ? -1 : tabs.indexOf(current);
    if (index == -1) return;
    final next = index + delta;
    if (next < 0 || next >= tabs.length) return;
    setState(() => _selectedCategory = tabs[next]);
  }

  /// Sustantivo para el conteo del pie de tabla, según la pestaña activa.
  static String _countNoun(String? category) => switch (category) {
        'Bebidas' => 'bebidas',
        'Postres' => 'postres',
        'Servicios' => 'servicios',
        kClasificacionHospedaje => 'conceptos',
        'Otros' => 'productos',
        _ => 'platillos',
      };

  String _title(String? category, String? paymentMethod) {
    final base = switch (category) {
      'Bebidas' => 'Bebidas vendidas',
      'Postres' => 'Postres vendidos',
      'Servicios' => 'Servicios vendidos',
      kClasificacionHospedaje => 'Hospedaje vendido',
      'Otros' => 'Otros vendidos',
      _ => 'Platillos vendidos',
    };
    if (paymentMethod != null) {
      return '$base · ${_paymentLabel(paymentMethod)}';
    }
    return base;
  }

  void _showFiltersSheet(List<String> paymentMethods) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      useSafeArea: true,
      builder: (ctx) => _FiltersSheet(
        paymentMethods: paymentMethods,
        selectedPaymentMethod: _selectedPaymentMethod,
        onPaymentMethodChanged: (val) => setState(() => _selectedPaymentMethod = val),
        onClear: () => setState(() => _selectedPaymentMethod = null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');
    final telefono = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono;

    final baseProducts = _selectedPaymentMethod != null
        ? (widget.productsByMethod[_selectedPaymentMethod] ?? widget.products)
        : widget.products;

    final categories = baseProducts.map(_catOf).toSet().toList()..sort();
    final orderedCategories = _orderedCategories(categories);

    // Sin pestaña "Todo", siempre hay una clasificación activa. Si la guardada
    // ya no existe en el período actual se cae a la primera, sin dejar la
    // tabla vacía. Queda null solo si el menú no tiene ninguna clasificación.
    final tabs = orderedCategories;
    final active = (_selectedCategory != null && tabs.contains(_selectedCategory))
        ? _selectedCategory
        : (tabs.isNotEmpty ? tabs.first : null);

    final filtered = active == null ? baseProducts : baseProducts.where((p) => _catOf(p) == active).toList();

    final paymentMethods = widget.productsByMethod.keys.toList()..sort();

    return GestureDetector(
      // Deslizar sobre la tabla cambia de clasificación. Este gesto queda por
      // dentro del de sucursales (LocationSwipeArea): Flutter le da prioridad
      // al detector más interno, así que aquí manda la clasificación.
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: tabs.length > 1
          ? (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              _shiftTab(tabs, active, v < 0 ? 1 : -1);
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InicioTituloTarjeta(
            titulo: _title(active, _selectedPaymentMethod),
            nota: widget.tips > 0 ? 'Propinas no incluidas' : null,
            derecha: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // En teléfono no cabe: el diseño lo esconde.
                if (!telefono)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('vs ${widget.prevLabel}', style: _t(13.5, FontWeight.w400, _C.muted)),
                  ),
                if (widget.products.isNotEmpty) ...[
                  _BotonFiltro(
                    activo: _hasActiveFilters,
                    cuantos: _activeFilterCount,
                    onTap: () => _showFiltersSheet(paymentMethods),
                  ),
                  const SizedBox(width: 8),
                  _BotonExcel(
                    conTexto: !telefono,
                    onTap: () => ExportService.exportProducts(widget.products, widget.prevLabel),
                  ),
                ],
              ],
            ),
          ),
          // Pestañas por clasificación del menú. Solo aparecen si hay más de una
          // clasificación con ventas: con una sola no habría nada que elegir.
          if (tabs.length > 1) ...[
            InicioSegmentos<String>(
              completo: true,
              opciones: [for (final c in tabs) (c, _tabLabel(c))],
              elegido: active ?? tabs.first,
              onElegir: (c) => setState(() => _selectedCategory = c),
            ),
            const SizedBox(height: 12),
          ],
          // Encabezado de la tabla
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _C.line))),
            child: Row(
              children: [
                Expanded(child: Text('NOMBRE', style: _encabezado)),
                SizedBox(width: _anchoCant, child: Text('CANT.', textAlign: TextAlign.right, style: _encabezado)),
                SizedBox(width: _anchoTotal, child: Text('TOTAL', textAlign: TextAlign.right, style: _encabezado)),
                SizedBox(width: _anchoVar, child: Text('VAR.', textAlign: TextAlign.right, style: _encabezado)),
              ],
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  widget.products.isEmpty ? 'Sin ventas en este período' : 'Sin productos con estos filtros',
                  textAlign: TextAlign.center,
                  style: _t(14, FontWeight.w400, _C.muted),
                ),
              ),
            )
          else ...[
            ...filtered.map((p) => _ProductRow(product: p, fmt: fmt)),
            _FooterRow(
              label: 'Total (${filtered.length} ${_countNoun(active)})',
              qty: filtered.fold<int>(0, (s, p) => s + p.quantity),
              amount: filtered.fold<double>(0, (s, p) => s + p.total),
              fmt: fmt,
              labelColor: _C.ink,
              amountColor: _C.ink,
              bold: true,
            ),
            // Estos totales son del período completo, no de una clasificación. Solo
            // aplican cuando el menú no tiene clasificaciones (sin pestañas).
            if (active == null && _selectedPaymentMethod == null) ...[
              if (widget.tips > 0)
                _FooterRow(
                  label: '+ Propinas',
                  amount: widget.tips,
                  fmt: fmt,
                  labelColor: _C.warn,
                  amountColor: _C.warn,
                ),
              if (widget.discounts > 0)
                _FooterRow(
                  label: '− Descuentos',
                  amount: -widget.discounts,
                  fmt: fmt,
                  labelColor: _C.bad,
                  amountColor: _C.bad,
                ),
              if (widget.totalSales > 0)
                _FooterRow(
                  label: 'Total cobrado',
                  amount: widget.totalSales,
                  fmt: fmt,
                  labelColor: _C.ink,
                  amountColor: _C.accent,
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

TextStyle get _encabezado => _t(12, FontWeight.w600, _C.muted).copyWith(letterSpacing: 0.6);

// ─── Botones de la cabecera ───────────────────────────────────────────────────

/// El botón de filtros (44×44): se enciende en el color de acento cuando hay un
/// filtro puesto.
class _BotonFiltro extends StatelessWidget {
  final bool activo;
  final int cuantos;
  final VoidCallback onTap;

  const _BotonFiltro({required this.activo, required this.cuantos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Filtrar',
      child: Material(
        color: activo ? _C.tint : _C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: activo ? _C.accent : _C.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            height: 44,
            width: activo ? 58 : 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune_rounded, size: 19, color: activo ? _C.accent : _C.ink),
                if (activo) ...[
                  const SizedBox(width: 4),
                  Text('$cuantos', style: _t(12, FontWeight.w700, _C.accent)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonExcel extends StatelessWidget {
  final bool conTexto;
  final VoidCallback onTap;

  const _BotonExcel({required this.conTexto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Descargar Excel',
      child: Material(
        color: _C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _C.line, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            height: 44,
            constraints: const BoxConstraints(minWidth: 44),
            padding: EdgeInsets.symmetric(horizontal: conTexto ? 16 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_rounded, size: 18, color: _C.ink),
                if (conTexto) ...[
                  const SizedBox(width: 8),
                  Text('Excel', style: _t(14, FontWeight.w600, _C.ink)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Sheet de Filtros ──────────────────────────────────────────────────

class _FiltersSheet extends StatefulWidget {
  final List<String> paymentMethods;
  final String? selectedPaymentMethod;
  final ValueChanged<String?> onPaymentMethodChanged;
  final VoidCallback onClear;

  const _FiltersSheet({
    required this.paymentMethods,
    required this.selectedPaymentMethod,
    required this.onPaymentMethodChanged,
    required this.onClear,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _pm;

  @override
  void initState() {
    super.initState();
    _pm = widget.selectedPaymentMethod;
  }

  bool get _hasFilters => _pm != null;

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
            decoration: BoxDecoration(color: _C.line, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Título
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filtros', style: _t(17, FontWeight.w700, _C.ink)),
              if (_hasFilters)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _pm = null;
                    });
                    widget.onClear();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Limpiar todo', style: _t(13.5, FontWeight.w600, _C.accent)),
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
            child: Text('Método de pago', style: _t(13, FontWeight.w600, _C.muted)),
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
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _C.ink : _C.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _C.ink : _C.line, width: 1.5),
        ),
        child: Text(label, style: _t(13.5, FontWeight.w600, selected ? _C.card : _C.ink)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: topBorder ? BorderSide(color: kInicioLineaFuerte, width: 2) : BorderSide(color: _C.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: _t(14.5, bold ? FontWeight.w700 : FontWeight.w600, labelColor)),
          ),
          SizedBox(
            width: _anchoCant,
            child: qty != null
                ? _Cifra(Text('$qty', maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)))
                : const SizedBox(),
          ),
          SizedBox(
            width: _anchoTotal,
            child: _Cifra(
              Text(
                amount < 0 ? '−$moneda${fmt.format(amount.abs())}' : '$moneda${fmt.format(amount)}',
                maxLines: 1,
                style: _t(14.5, FontWeight.w700, amountColor),
              ),
            ),
          ),
          const SizedBox(width: _anchoVar),
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
    final changeColor = isNeutral ? _C.soft : (isPositive ? _C.gift : _C.bad);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _C.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              product.name,
              style: _t(14.5, FontWeight.w400, _C.ink, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _anchoCant,
            child: _Cifra(
              Text('${product.quantity}', maxLines: 1, style: _t(14.5, FontWeight.w400, _C.muted)),
            ),
          ),
          SizedBox(
            width: _anchoTotal,
            child: _Cifra(
              Text('$moneda${fmt.format(product.total)}', maxLines: 1, style: _t(14.5, FontWeight.w700, _C.ink)),
            ),
          ),
          SizedBox(
            width: _anchoVar,
            // Un producto nuevo contra un período casi vacío da porcentajes de
            // seis cifras: se achica en vez de salirse de la columna.
            child: _Cifra(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isNeutral)
                    Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 13, color: changeColor),
                  const SizedBox(width: 2),
                  Text(
                    isNeutral ? '—' : '${change.abs().toStringAsFixed(0)}%',
                    maxLines: 1,
                    style: _t(13, FontWeight.w700, changeColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una cifra de la tabla pegada a la derecha de su columna: si no cabe, se
/// achica.
class _Cifra extends StatelessWidget {
  final Widget child;
  const _Cifra(this.child);

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: child);
}
