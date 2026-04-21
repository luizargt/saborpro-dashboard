import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';
import '../../core/services/export_service.dart';

class ProductsList extends StatelessWidget {
  final List<ProductSummary> products;
  final String prevLabel;

  const ProductsList({
    super.key,
    required this.products,
    required this.prevLabel,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Platillos vendidos',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  'vs $prevLabel',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(width: 8),
                if (products.isNotEmpty)
                  GestureDetector(
                    onTap: () => ExportService.exportProducts(products, prevLabel),
                    child: const Tooltip(
                      message: 'Descargar Excel',
                      child: Icon(Icons.download_rounded,
                          color: Colors.white38, size: 16),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Nombre', style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ),
              SizedBox(
                width: 50,
                child: Text('Cant.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ),
              SizedBox(
                width: 80,
                child: Text('Total', textAlign: TextAlign.right, style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ),
              SizedBox(
                width: 52,
                child: Text('Var.', textAlign: TextAlign.right, style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Sin ventas en este período',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
              ),
            ),
          )
        else ...[
          ...products.map((p) => _ProductRow(product: p, fmt: fmt)),
          // Fila de totales
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x33FFFFFF), width: 1)),
              color: Color(0x0AFFFFFF),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total (${products.length} platillos)',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${products.fold<int>(0, (s, p) => s + p.quantity)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Q${fmt.format(products.fold<double>(0, (s, p) => s + p.total))}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF7444fd),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
        ],
      ],
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
        ? Colors.white38
        : isPositive
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              product.name,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
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
