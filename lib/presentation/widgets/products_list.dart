import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';
import '../../core/services/export_service.dart';

class ProductsList extends StatelessWidget {
  final List<ProductSummary> products;
  final String prevLabel;
  final double tips;
  final double discounts;
  final double totalSales;

  const ProductsList({
    super.key,
    required this.products,
    required this.prevLabel,
    this.tips = 0,
    this.discounts = 0,
    this.totalSales = 0,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');

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
                  Tooltip(
                    message: 'Descargar Excel',
                    child: InkWell(
                      onTap: () => ExportService.exportProducts(products, prevLabel),
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
                            Icon(Icons.download_rounded, color: Colors.white54, size: 16),
                            SizedBox(width: 4),
                            Text('Excel', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
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
          // Subtotal platillos
          _FooterRow(
            label: 'Total (${products.length} platillos)',
            qty: products.fold<int>(0, (s, p) => s + p.quantity),
            amount: products.fold<double>(0, (s, p) => s + p.total),
            fmt: fmt,
            labelColor: Colors.white54,
            amountColor: Colors.white70,
          ),
          if (tips > 0)
            _FooterRow(
              label: '+ Propinas',
              amount: tips,
              fmt: fmt,
              labelColor: const Color(0xFFF59E0B),
              amountColor: const Color(0xFFF59E0B),
            ),
          if (discounts > 0)
            _FooterRow(
              label: '− Descuentos',
              amount: -discounts,
              fmt: fmt,
              labelColor: const Color(0xFFEF4444),
              amountColor: const Color(0xFFEF4444),
            ),
          if (totalSales > 0)
            _FooterRow(
              label: 'Total cobrado',
              amount: totalSales,
              fmt: fmt,
              labelColor: Colors.white,
              amountColor: const Color(0xFF7444fd),
              bold: true,
              topBorder: true,
            ),
        ],
      ],
    );
  }
}

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
