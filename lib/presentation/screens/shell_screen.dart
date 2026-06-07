import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/export_service.dart';
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
  int? _patchNumber;

  @override
  void initState() {
    super.initState();
    _loadPatchNumber();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = AuthService().tenantId;
      if (id != null) {
        context.read<DashboardProvider>().init(id);
        context.read<InventoryProvider>().init(id);
      }
    });
  }

  Future<void> _loadPatchNumber() async {
    try {
      final updater = ShorebirdUpdater();
      if (!updater.isAvailable) return;

      final current = await updater.readCurrentPatch();
      final next = await updater.readNextPatch();

      // Mostrar el mayor número disponible (next si hay parche pendiente)
      final display = [current?.number, next?.number]
          .whereType<int>()
          .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

      if (mounted) setState(() => _patchNumber = display);

      // Descargar nuevos parches en background sin bloquear la UI
      updater.checkForUpdate().then((status) {
        if (status == UpdateStatus.outdated) updater.update();
      });
    } catch (_) {}
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
        final versionLabel = _patchNumber != null ? 'v1.0.1 ($_patchNumber)' : 'v1.0.1';
        return wide
            ? _WideShell(index: _index, onSelect: _setIndex, onLogout: _logout, versionLabel: versionLabel)
            : _NarrowShell(index: _index, onSelect: _setIndex, onLogout: _logout, versionLabel: versionLabel);
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
  final String versionLabel;

  const _WideShell(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          _Rail(index: index, onSelect: onSelect, onLogout: onLogout, versionLabel: versionLabel),
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
  final String versionLabel;

  const _NarrowShell(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sabor Manager',
              style: GoogleFonts.inter(
                color: const Color(0xFF7444fd),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              versionLabel,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
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
  final String versionLabel;

  const _Rail(
      {required this.index, required this.onSelect, required this.onLogout, required this.versionLabel});

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
            'Sabor Manager',
            style: GoogleFonts.inter(
              color: const Color(0xFF7444fd),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            versionLabel,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w400,
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
          // Menu
          GestureDetector(
            onTap: () => _showMenuModal(context, onLogout),
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_rounded,
                  color: Colors.white38, size: 20),
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
    return SafeArea(
      top: false,
      child: Container(
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
            // Menú
            GestureDetector(
              onTap: () => _showMenuModal(context, onLogout),
              child: SizedBox(
                width: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_rounded, color: Colors.white38, size: 24),
                    const SizedBox(height: 4),
                    Text('Más',
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

// ── MENU MODAL ────────────────────────────────────────────────────────────────
void _showMenuModal(BuildContext context, VoidCallback onLogout) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MenuModal(onLogout: onLogout),
  );
}

enum _ReportType {
  caja('Reporte de Caja'),
  platillos('Platillos vendidos'),
  inventario('Inventario');

  final String label;
  const _ReportType(this.label);
}

class _MenuModal extends StatefulWidget {
  final VoidCallback onLogout;
  const _MenuModal({required this.onLogout});

  @override
  State<_MenuModal> createState() => _MenuModalState();
}

class _MenuModalState extends State<_MenuModal> {
  _ReportType _selected = _ReportType.caja;
  bool _downloading = false;

  // Biometría — null mientras carga
  bool?  _biometricAvailable;
  bool   _biometricEnabled = false;
  String? _biometricError;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final available = await BiometricService().isHardwarePresent();
    final enabled   = await BiometricService().isEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled   = enabled;
      });
    }
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final email    = AuthService().sessionEmail;
      final password = AuthService().sessionPassword;
      if (email != null && password != null) {
        // Credenciales completas en sesión → activar directo sin diálogo
        await _activateBiometricWithCredentials(email, password);
      } else {
        // Solo tenemos email (sesión restaurada) → pedir solo contraseña
        await _showBiometricSetupDialog();
      }
    } else {
      await BiometricService().clearCredentials();
      if (mounted) setState(() {
        _biometricEnabled = false;
        _biometricError   = null;
      });
    }
  }

  Future<void> _activateBiometricWithCredentials(
      String email, String password) async {
    final hasEnrolled = await BiometricService().isAvailable();
    if (!hasEnrolled) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.fingerprint,
                  color: Color(0xFF7444fd), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sin huella registrada',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            content: Text(
              'Este dispositivo no tiene huellas registradas.\n\n'
              'Ve a Configuración → Seguridad → Huella digital '
              'para registrar una y luego vuelve aquí.',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7444fd),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('Entendido', style: GoogleFonts.inter()),
              ),
            ],
          ),
        );
      }
      return;
    }
    await BiometricService().saveCredentials(email, password);
    final auth = await BiometricService().authenticate();
    if (auth != null) {
      if (mounted) setState(() => _biometricEnabled = true);
    } else {
      await BiometricService().clearCredentials();
    }
  }

  Future<void> _showBiometricSetupDialog() async {
    // Email: sesión en memoria > Firebase Auth > storage biométrico anterior
    final sessionEmail  = AuthService().sessionEmail ?? '';
    final firebaseEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final storedEmail   = await BiometricService().getStoredEmail() ?? '';
    final email = sessionEmail.isNotEmpty ? sessionEmail
        : firebaseEmail.isNotEmpty ? firebaseEmail
        : storedEmail;

    final emailCtrl = TextEditingController(text: email);
    final pwCtrl    = TextEditingController();
    bool obscure    = true;
    String? errorMsg;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFF7444fd), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Activar acceso con huella',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mostrar email como texto si ya lo tenemos, campo editable si no
              if (email.isNotEmpty) ...[
                Text(email,
                    style: GoogleFonts.inter(
                        color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 12),
              ] else ...[
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    labelStyle: GoogleFonts.inter(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: pwCtrl,
                obscureText: obscure,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: GoogleFonts.inter(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                        size: 18),
                    onPressed: () => setStateDialog(() => obscure = !obscure),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(errorMsg!,
                    style: GoogleFonts.inter(
                        color: const Color(0xFFEF4444), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: GoogleFonts.inter(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7444fd),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final resolvedEmail =
                    email.isNotEmpty ? email : emailCtrl.text.trim();
                if (resolvedEmail.isEmpty || pwCtrl.text.isEmpty) {
                  setStateDialog(
                      () => errorMsg = 'Ingresa tu correo y contraseña');
                  return;
                }
                final hasEnrolled = await BiometricService().isAvailable();
                if (!hasEnrolled) {
                  setStateDialog(() => errorMsg =
                      'No hay huellas registradas. Ve a Configuración → '
                      'Seguridad del dispositivo para registrar una.');
                  return;
                }
                await BiometricService()
                    .saveCredentials(resolvedEmail, pwCtrl.text);
                final auth = await BiometricService().authenticate();
                if (auth != null) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  await BiometricService().clearCredentials();
                  setStateDialog(
                      () => errorMsg = 'No se pudo verificar la huella.');
                }
              },
              child: Text('Activar', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _biometricEnabled = true;
        _biometricError   = null;
      });
    }
  }

  Future<void> _download() async {
    final dp = context.read<DashboardProvider>();
    final ip = context.read<InventoryProvider>();
    if (dp.loading || ip.loading || _downloading) return;

    setState(() => _downloading = true);
    try {
      switch (_selected) {
        case _ReportType.caja:
          final orders = dp.currentOrders;
          final orderDocIds = orders
              .map((o) => o['_docId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          final userIdsToResolve = orders
              .where((o) => (o['paid_by_user_name'] as String? ?? '').isEmpty)
              .map((o) => o['paid_by_user_id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          final results = await Future.wait([
            dp.fetchCertifiedInvoiceOrderIds(orderDocIds),
            dp.fetchUserNamesById(userIdsToResolve),
            dp.fetchCancelledOrders(),
          ]);
          final certifiedIds    = results[0] as Set<String>;
          final userNamesById   = results[1] as Map<String, String>;
          final cancelledOrders = results[2] as List<Map<String, dynamic>>;
          ExportService.exportCajaReport(
            orders,
            certifiedIds,
            userNamesById,
            dp.range.label,
            cancelledOrders: cancelledOrders,
          );
        case _ReportType.platillos:
          ExportService.exportProducts(
            dp.metrics?.topProducts ?? [],
            dp.range.prevLabel,
          );
        case _ReportType.inventario:
          ExportService.exportInventory(ip.items, ip.locations);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DashboardProvider>();
    final ip = context.watch<InventoryProvider>();
    final isLoading = dp.loading || ip.loading || _downloading;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sección Reportes
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Reportes',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${dp.range.label})',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButton<_ReportType>(
                    value: _selected,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF1E293B),
                    iconEnabledColor: Colors.white38,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    items: _ReportType.values
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selected = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isLoading ? null : _download,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7444fd).withOpacity(isLoading ? 0.06 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF7444fd).withOpacity(isLoading ? 0.1 : 0.3)),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF7444fd),
                          ),
                        )
                      : const Icon(Icons.download_rounded,
                          color: Color(0xFF7444fd), size: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 8),

          // Biometría (solo Android/iOS con soporte)
          if (_biometricAvailable == true) ...[
            GestureDetector(
              onTap: () => _toggleBiometric(!_biometricEnabled),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      color: _biometricEnabled
                          ? const Color(0xFF7444fd)
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Inicio con huella / Face ID',
                        style: GoogleFonts.inter(
                          color: _biometricEnabled
                              ? Colors.white70
                              : Colors.white38,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _biometricEnabled,
                      onChanged: _toggleBiometric,
                      activeColor: const Color(0xFF7444fd),
                      activeTrackColor:
                          const Color(0xFF7444fd).withOpacity(0.3),
                      inactiveThumbColor: Colors.white38,
                      inactiveTrackColor: Colors.white12,
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 8),
          ],

          // Botón Salir
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Cerrar sesión',
                    style: GoogleFonts.inter(
                      color: Color(0xFFEF4444),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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
