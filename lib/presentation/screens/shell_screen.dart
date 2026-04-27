import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../../presentation/providers/dashboard_provider.dart';
import '../../presentation/providers/inventory_provider.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/expenses/expenses_screen.dart';
import '../../presentation/screens/inventory/inventory_screen.dart';
import '../../presentation/widgets/location_selector.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = AuthService().tenantId;
      if (id != null) {
        context.read<DashboardProvider>().init(id);
        context.read<InventoryProvider>().init(id);
      }
    });
  }

  Future<void> _logout() async {
    await AuthService().logout();
    await BiometricService().clearCredentials();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        return wide ? _WideShell(index: _index, onSelect: _setIndex, onLogout: _logout)
                    : _NarrowShell(index: _index, onSelect: _setIndex, onLogout: _logout);
      },
    );
  }

  void _setIndex(int i) => setState(() => _index = i);
}

// ── WIDE (sidebar rail) ───────────────────────────────────────────────────────
class _WideShell extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _WideShell(
      {required this.index, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          _Rail(index: index, onSelect: onSelect, onLogout: onLogout),
          Container(width: 1, color: Colors.white.withOpacity(0.05)),
          Expanded(
            child: _PageContent(index: index),
          ),
        ],
      ),
    );
  }
}

// ── NARROW (bottom nav) ───────────────────────────────────────────────────────
class _NarrowShell extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _NarrowShell(
      {required this.index, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SaborPro ',
              style: GoogleFonts.inter(
                color: const Color(0xFF7444fd),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Gerencia',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: const LocationSelector(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _PageContent(index: index),
      bottomNavigationBar: _BottomNav(index: index, onSelect: onSelect, onLogout: onLogout),
    );
  }
}

// ── RAIL ──────────────────────────────────────────────────────────────────────
class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _Rail(
      {required this.index, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      color: const Color(0xFF070E1A),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo
          Image.asset(
            'assets/images/logo.png',
            width: 44,
            height: 44,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 6),
          Text(
            'SaborPro',
            style: GoogleFonts.inter(
              color: const Color(0xFF7444fd),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            'Dashboard',
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          // Divider
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 20),
          // Nav items
          _RailItem(
            icon: Icons.bar_chart_rounded,
            label: 'Ventas',
            active: index == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.payments_outlined,
            label: 'Gastos',
            active: index == 1,
            onTap: () => onSelect(1),
          ),
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.inventory_2_rounded,
            label: 'Inventario',
            active: index == 2,
            onTap: () => onSelect(2),
          ),
          const Spacer(),
          // Logout
          GestureDetector(
            onTap: onLogout,
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: Colors.white24, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RailItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF7444fd).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(
                  color: const Color(0xFF7444fd).withOpacity(0.3), width: 1)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color:
                    active ? const Color(0xFF7444fd) : Colors.white38,
                size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: active ? const Color(0xFF7444fd) : Colors.white38,
                fontSize: 10,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── BOTTOM NAV ────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _BottomNav({required this.index, required this.onSelect, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF070E1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              indicatorColor: const Color(0xFF7444fd).withOpacity(0.2),
              selectedIndex: index,
              onDestinationSelected: onSelect,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.bar_chart_outlined, color: Colors.white38),
                  selectedIcon: const Icon(Icons.bar_chart_rounded, color: Color(0xFF7444fd)),
                  label: 'Ventas',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.payments_outlined, color: Colors.white38),
                  selectedIcon: const Icon(Icons.payments_rounded, color: Color(0xFF7444fd)),
                  label: 'Gastos',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.inventory_2_outlined, color: Colors.white38),
                  selectedIcon: const Icon(Icons.inventory_2_rounded, color: Color(0xFF7444fd)),
                  label: 'Inventario',
                ),
              ],
            ),
          ),
          // Salir — mismo estilo que NavigationDestination
          GestureDetector(
            onTap: onLogout,
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, color: Colors.white38, size: 24),
                  const SizedBox(height: 4),
                  Text('Salir',
                      style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PAGE CONTENT ──────────────────────────────────────────────────────────────
class _PageContent extends StatelessWidget {
  final int index;
  const _PageContent({required this.index});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: IndexedStack(
        key: ValueKey(index),
        index: index,
        children: const [
          DashboardScreen(),
          ExpensesScreen(),
          InventoryScreen(),
        ],
      ),
    );
  }
}
