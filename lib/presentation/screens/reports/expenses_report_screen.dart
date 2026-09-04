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
      // top: false — el AppBar ya reservó el borde de arriba. Abajo no lo
      // reserva nadie: esta pantalla se abre con push, sin la barra de
      // navegación de la app debajo, así que el Scaffold la dibuja hasta el
      // último píxel y el último gasto queda tras los botones del sistema.
      body: const SafeArea(top: false, child: ExpensesScreen()),
    );
  }
}
