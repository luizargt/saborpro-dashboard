import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'cash_closures_report_screen.dart';
import 'expenses_report_screen.dart';

class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _ReportTile(
          icon: Icons.point_of_sale_rounded,
          title: 'Cierres de Caja',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CashClosuresReportScreen()),
          ),
        ),
        const SizedBox(height: 10),
        _ReportTile(
          icon: Icons.payments_rounded,
          title: 'Gastos',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExpensesReportScreen()),
          ),
        ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ReportTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF7444fd).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF7444fd), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
