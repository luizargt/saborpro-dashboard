import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/max_content_width.dart';
import 'cancelled_orders_report_screen.dart';
import 'cash_closures_report_screen.dart';
import 'expenses_report_screen.dart';

/// Grupos en los que se organizan los reportes. El orden de esta lista es el
/// orden en que aparecen; un grupo sin reportes disponibles no se dibuja.
enum _Group {
  ventas('Ventas', Color(0xFF8B5CF6)),
  menu('Menú', Color(0xFFF97316)),
  dinero('Dinero', Color(0xFF22C55E)),
  bodega('Bodega', Color(0xFF3B82F6)),
  personal('Personal', Color(0xFF06B6D4));

  final String label;
  final Color color;
  const _Group(this.label, this.color);
}

class _Report {
  final _Group group;
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  const _Report({
    required this.group,
    required this.icon,
    required this.label,
    required this.builder,
  });
}

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  // Solo reportes que ya funcionan. Al construir uno nuevo basta agregarlo aquí
  // con su grupo: la pantalla se arma sola.
  static final _reports = <_Report>[
    _Report(
      group: _Group.dinero,
      icon: Icons.point_of_sale_rounded,
      label: 'Cierres de caja',
      builder: (_) => const CashClosuresReportScreen(),
    ),
    _Report(
      group: _Group.dinero,
      icon: Icons.receipt_long_rounded,
      label: 'Gastos',
      builder: (_) => const ExpensesReportScreen(),
    ),
    // Va en Bodega y no en Ventas: lo que se revisa aquí es producto perdido,
    // no dinero no vendido.
    _Report(
      group: _Group.bodega,
      icon: Icons.remove_shopping_cart_rounded,
      label: 'Pedidos cancelados',
      builder: (_) => const CancelledOrdersReportScreen(),
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? _reports
        : _reports
            .where((r) =>
                r.label.toLowerCase().contains(q) ||
                r.group.label.toLowerCase().contains(q))
            .toList();

    return MaxContentWidth(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text(
                'Reportes',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 20),
              // El buscador no necesita 1600px: se acota para que no quede una
              // barra de un extremo al otro con dos palabras adentro.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    'Ningún reporte coincide con "$_query"',
                    style:
                        GoogleFonts.inter(color: Colors.white60, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final group in _Group.values)
                      ..._buildGroup(group, matches),
                  ],
                ),
        ),
      ],
      ),
    );
  }

  List<Widget> _buildGroup(_Group group, List<_Report> matches) {
    final items = matches.where((r) => r.group == group).toList();
    if (items.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Text(
          group.label,
          style: GoogleFonts.inter(
            color: Colors.white60,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // Rejilla que se adapta al ancho: en móvil una tarjeta por fila, en
      // escritorio varias, para no dejar la pantalla medio vacía.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, constraints) {
          const gap = 12.0;
          final columns = (constraints.maxWidth / 340).floor().clamp(1, 4);
          final cardWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final report in items)
                SizedBox(
                  width: cardWidth,
                  child: _ReportTile(report: report),
                ),
            ],
          );
        }),
      ),
    ];
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar reporte',
          hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final _Report report;

  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: report.builder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: report.group.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(report.icon, color: report.group.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  report.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
