import 'package:flutter/material.dart';
import '../expenses/expenses_screen.dart';

class ExpensesReportScreen extends StatelessWidget {
  const ExpensesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        title: const Text('Gastos'),
      ),
      body: const ExpensesScreen(),
    );
  }
}
