import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../data/models/inventory_data.dart';
import '../../../presentation/providers/inventory_provider.dart';
import '../../../core/services/location_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _vDataController = ScrollController();
  final _vNameController = ScrollController();
  final _hDataController = ScrollController();
  final _hHeaderController = ScrollController();
  final _searchController = TextEditingController();

  String _query = '';
  StockStatus? _filter;

  static const _nameColW = 190.0;
  static const _dataColW = 90.0;
  static const _rowH = 44.0;
  static const _headerH = 42.0;

  @override
  void initState() {
    super.initState();
    _vDataController.addListener(() {
      if (_vNameController.hasClients &&
          _vNameController.offset != _vDataController.offset) {
        _vNameController.jumpTo(_vDataController.offset);
      }
    });
    _hDataController.addListener(() {
      if (_hHeaderController.hasClients &&
          _hHeaderController.offset != _hDataController.offset) {
        _hHeaderController.jumpTo(_hDataController.offset);
      }
    });
  }

  @override
  void dispose() {
    _vDataController.dispose();
    _vNameController.dispose();
    _hDataController.dispose();
    _hHeaderController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<IngredientStock> _filtered(List<IngredientStock> all) {
    var list = all;
    if (_query.isNotEmpty) {
      list = list
          .where((i) => i.name.toLowerCase().contains(_query.toLowerCase()))
          .toList();
    }
    if (_filter != null) {
      list = list.where((i) => i.worstStatus == _filter).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<InventoryProvider>();
    final items = _filtered(prov.items);
    final locs = prov.locations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(provider: prov),
        _SummaryStrip(provider: prov),
        _SearchAndFilter(
          controller: _searchController,
          filter: _filter,
          onSearch: (q) => setState(() => _query = q),
          onFilter: (s) => setState(() => _filter = s),
        ),
        if (prov.loading)
          const Expanded(child: _LoadingState())
        else if (prov.error != null)
          Expanded(child: _ErrorState(error: prov.error!, onRetry: prov.load))
        else if (items.isEmpty)
          const Expanded(child: _EmptyState())
        else
          Expanded(
            child: _InventoryTable(
              items: items,
              locations: locs,
              vDataController: _vDataController,
              vNameController: _vNameController,
              hDataController: _hDataController,
              hHeaderController: _hHeaderController,
              nameColW: _nameColW,
              dataColW: _dataColW,
              rowH: _rowH,
              headerH: _headerH,
            ),
          ),
      ],
    );
  }
}

// ── HEADER ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final InventoryProvider provider;
  const _Header({required this.provider});

  @override
  Widget build(BuildContext context) {
    final updated = provider.lastUpdated;
    String subtitle = 'Cargando...';
    if (updated != null) {
      final diff = DateTime.now().difference(updated);
      subtitle = diff.inSeconds < 60
          ? 'Actualizado hace ${diff.inSeconds}s'
          : 'Actualizado hace ${diff.inMinutes} min';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventario',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white38, size: 20),
            onPressed: provider.load,
            tooltip: 'Actualizar',
          ),
        ],
      ),
    );
  }
}

// ── SUMMARY STRIP ─────────────────────────────────────────────────────────────
class _SummaryStrip extends StatelessWidget {
  final InventoryProvider provider;
  const _SummaryStrip({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          _StatusPill(
            count: provider.criticalCount,
            label: 'Críticos',
            color: const Color(0xFFEF4444),
          ),
          const SizedBox(width: 8),
          _StatusPill(
            count: provider.lowCount,
            label: 'Bajo stock',
            color: const Color(0xFFF97316),
          ),
          const SizedBox(width: 8),
          _StatusPill(
            count: provider.okCount,
            label: 'Disponible',
            color: const Color(0xFF22C55E),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatusPill(
      {required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: GoogleFonts.inter(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── SEARCH AND FILTER ─────────────────────────────────────────────────────────
class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  final StockStatus? filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<StockStatus?> onFilter;

  const _SearchAndFilter({
    required this.controller,
    required this.filter,
    required this.onSearch,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          // Search
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar ingrediente...',
                  hintStyle:
                      GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white24, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter chips
          _FilterChip(
            label: 'Todos',
            active: filter == null,
            onTap: () => onFilter(null),
          ),
          const SizedBox(width: 4),
          _FilterChip(
            label: '🔴',
            active: filter == StockStatus.critical,
            color: const Color(0xFFEF4444),
            onTap: () => onFilter(
                filter == StockStatus.critical ? null : StockStatus.critical),
          ),
          const SizedBox(width: 4),
          _FilterChip(
            label: '🟡',
            active: filter == StockStatus.low,
            color: const Color(0xFFF97316),
            onTap: () =>
                onFilter(filter == StockStatus.low ? null : StockStatus.low),
          ),
          const SizedBox(width: 4),
          _FilterChip(
            label: '🟢',
            active: filter == StockStatus.ok,
            color: const Color(0xFF22C55E),
            onTap: () =>
                onFilter(filter == StockStatus.ok ? null : StockStatus.ok),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label,
      required this.active,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF7444fd);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.withOpacity(0.18) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? c.withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active ? c : Colors.white38,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── TABLE ─────────────────────────────────────────────────────────────────────
class _InventoryTable extends StatelessWidget {
  final List<IngredientStock> items;
  final List<LocationModel> locations;
  final ScrollController vDataController;
  final ScrollController vNameController;
  final ScrollController hDataController;
  final ScrollController hHeaderController;
  final double nameColW;
  final double dataColW;
  final double rowH;
  final double headerH;

  const _InventoryTable({
    required this.items,
    required this.locations,
    required this.vDataController,
    required this.vNameController,
    required this.hDataController,
    required this.hHeaderController,
    required this.nameColW,
    required this.dataColW,
    required this.rowH,
    required this.headerH,
  });

  @override
  Widget build(BuildContext context) {
    final totalW = (locations.length + 1) * dataColW; // +1 for Total col

    return Column(
      children: [
        // ── Sticky header ──────────────────────────────────────────────────
        Container(
          height: headerH,
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(
              bottom: BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
          child: Row(
            children: [
              // Fixed: ingredient label
              SizedBox(
                width: nameColW,
                child: _HeaderCell(
                  label: 'Ingrediente',
                  width: nameColW,
                  fixed: true,
                ),
              ),
              // Right shadow on name column
              _ColumnShadow(right: true),
              // Scrollable location headers
              Expanded(
                child: SingleChildScrollView(
                  controller: hHeaderController,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: totalW,
                    child: Row(
                      children: [
                        ...locations.map((l) => _HeaderCell(
                              label: _abbrev(l.name),
                              width: dataColW,
                            )),
                        _HeaderCell(
                          label: 'Total',
                          width: dataColW,
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Body rows ──────────────────────────────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed name column
              SizedBox(
                width: nameColW,
                child: ListView.builder(
                  controller: vNameController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemExtent: rowH,
                  itemBuilder: (_, i) => _NameCell(
                    item: items[i],
                    rowIndex: i,
                    height: rowH,
                  ),
                ),
              ),
              // Right shadow on name column
              _ColumnShadow(right: true),
              // Scrollable data columns
              Expanded(
                child: SingleChildScrollView(
                  controller: hDataController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalW,
                    child: ListView.builder(
                      controller: vDataController,
                      itemCount: items.length,
                      itemExtent: rowH,
                      itemBuilder: (_, i) => _DataRow(
                        item: items[i],
                        locations: locations,
                        rowIndex: i,
                        height: rowH,
                        colWidth: dataColW,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _abbrev(String name) {
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return name.length > 8 ? name.substring(0, 7).toUpperCase() : name.toUpperCase();
    }
    return words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
  }
}

class _ColumnShadow extends StatelessWidget {
  final bool right;
  const _ColumnShadow({required this.right});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: right ? Alignment.centerLeft : Alignment.centerRight,
          end: right ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.black.withOpacity(0.25),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final bool fixed;
  final bool isTotal;

  const _HeaderCell({
    required this.label,
    required this.width,
    this.fixed = false,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: fixed ? Alignment.centerLeft : Alignment.centerRight,
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: isTotal ? const Color(0xFF7444fd) : Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final IngredientStock item;
  final int rowIndex;
  final double height;

  const _NameCell(
      {required this.item, required this.rowIndex, required this.height});

  @override
  Widget build(BuildContext context) {
    final status = item.worstStatus;
    final dotColor = _dotColor(status);
    final isEven = rowIndex % 2 == 0;

    return Container(
      height: height,
      color: isEven ? const Color(0xFF0A1628) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (item.unit.isNotEmpty)
                  Text(
                    _abbrevUnit(item.unit),
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _dotColor(StockStatus s) {
    switch (s) {
      case StockStatus.critical: return const Color(0xFFEF4444);
      case StockStatus.low:      return const Color(0xFFF97316);
      case StockStatus.ok:       return const Color(0xFF22C55E);
      case StockStatus.noData:   return Colors.white24;
    }
  }

  String _abbrevUnit(String unit) {
    switch (unit.toLowerCase()) {
      case 'kilogramos': return 'kg';
      case 'gramos':     return 'g';
      case 'litros':     return 'L';
      case 'mililitros': return 'mL';
      case 'unidades':   return 'u';
      default:
        return unit.length > 5 ? unit.substring(0, 4) : unit;
    }
  }
}

class _DataRow extends StatelessWidget {
  final IngredientStock item;
  final List<LocationModel> locations;
  final int rowIndex;
  final double height;
  final double colWidth;

  const _DataRow({
    required this.item,
    required this.locations,
    required this.rowIndex,
    required this.height,
    required this.colWidth,
  });

  @override
  Widget build(BuildContext context) {
    final isEven = rowIndex % 2 == 0;

    return Container(
      height: height,
      color: isEven ? const Color(0xFF0A1628) : Colors.transparent,
      child: Row(
        children: [
          ...locations.map((l) => _StockCell(
                stock: item.stockByLocation[l.id],
                daysRemaining: item.daysRemainingByLocation[l.id],
                status: item.statusAt(l.id),
                width: colWidth,
                height: height,
              )),
          _TotalCell(
            total: item.totalStock,
            width: colWidth,
            height: height,
          ),
        ],
      ),
    );
  }
}

class _StockCell extends StatelessWidget {
  final double? stock;
  final double? daysRemaining;
  final StockStatus status;
  final double width;
  final double height;

  const _StockCell({
    required this.stock,
    required this.daysRemaining,
    required this.status,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (stock == null) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text('—',
              style: GoogleFonts.inter(color: Colors.white12, fontSize: 13)),
        ),
      );
    }

    final (bgColor, textColor) = _colors(status);

    return Container(
      width: width,
      height: height,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _fmt(stock!),
            style: GoogleFonts.inter(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (daysRemaining != null) ...[
            const SizedBox(height: 1),
            Text(
              _fmtDays(daysRemaining!),
              style: GoogleFonts.inter(
                color: textColor.withOpacity(0.75),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (Color, Color) _colors(StockStatus s) {
    switch (s) {
      case StockStatus.critical:
        return (const Color(0xFFEF4444).withOpacity(0.18), const Color(0xFFEF4444));
      case StockStatus.low:
        return (const Color(0xFFF97316).withOpacity(0.14), const Color(0xFFF97316));
      case StockStatus.ok:
        return (const Color(0xFF22C55E).withOpacity(0.10), const Color(0xFF22C55E));
      case StockStatus.noData:
        return (Colors.transparent, Colors.white38);
    }
  }

  String _fmtDays(double days) {
    if (days > 999) return '∞';
    if (days < 1) return '<1d';
    return '${days.round()}d';
  }

  String _fmt(double v) {
    if (v == 0) return '0';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'\.?0+$'), '');
  }
}

class _TotalCell extends StatelessWidget {
  final double total;
  final double width;
  final double height;

  const _TotalCell(
      {required this.total, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final fmt = total == total.truncateToDouble()
        ? total.toInt().toString()
        : total.toStringAsFixed(1);

    return Container(
      width: width,
      height: height,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        fmt,
        style: GoogleFonts.inter(
          color: const Color(0xFF7444fd),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── STATES ────────────────────────────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF7444fd)),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7444fd)),
            child:
                const Text('Reintentar', style: TextStyle(color: Colors.white)),
          ),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('Sin resultados',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
      );
}
