import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/biometric_service.dart';
import '../shell_screen.dart';
import 'biometric_login_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool _biometricAvailable = false;
  BiometricKind _biometricKind = BiometricKind.fingerprint;

  /// Cuentas con acceso rápido vinculado en este teléfono, en minúsculas.
  Set<String> _linkedAccounts = {};

  /// La cuenta a la que va a entrar el botón biométrico: la que está escrita
  /// arriba. No hay ninguna cuenta escondida en otro lado.
  String get _typedEmail => BiometricService.normalizeEmail(_emailCtrl.text);
  bool get _typedEmailLinked => _linkedAccounts.contains(_typedEmail);

  @override
  void initState() {
    super.initState();
    // El botón sigue al correo escrito: pasa de "Ingresar con Face ID" a
    // "Activar" en cuanto se teclea una cuenta que no está vinculada.
    _emailCtrl.addListener(_onEmailChanged);
    _checkBiometric();
  }

  void _onEmailChanged() {
    if (!mounted) return;
    // Tocar el correo es reaccionar al mensaje de error: dejarlo pegado en
    // rojo mientras se escribe la cuenta nueva solo estorba.
    setState(() => _error = null);
  }

  Future<void> _checkBiometric() async {
    // isHardwarePresent y no isAvailable: el botón se muestra también en un
    // teléfono con sensor pero sin huellas registradas todavía, para que quien
    // nunca lo configuró vea que la opción existe en vez de un login pelado.
    final available = await BiometricService().isHardwarePresent();
    final kind = await BiometricService().detectKind();
    final linked = await BiometricService().linkedEmails();
    final last = await BiometricService().lastEmail();
    if (!mounted) return;

    // El correo recordado va al campo editable de arriba, no a un letrero fijo
    // debajo del botón: así se ve cuál es, y se puede borrar y escribir otro.
    // Nunca pisa lo que el usuario ya haya empezado a escribir.
    if (last != null && last.isNotEmpty && _emailCtrl.text.trim().isEmpty) {
      _emailCtrl.text = last;
    }

    setState(() {
      _biometricAvailable = available;
      _biometricKind = kind;
      _linkedAccounts = linked.toSet();
    });
  }

  /// Toque en el botón biométrico. Nunca se dispara solo: el usuario decide
  /// cuándo, y sobre qué cuenta, porque la cuenta es la del campo de arriba.
  Future<void> _onBiometricTap() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error =
          'Escribe arriba el correo de la cuenta a la que quieres entrar.');
      return;
    }
    if (_typedEmailLinked) {
      await _loginWithBiometric(email);
      return;
    }
    await _showActivationHelp(email);
  }

  Future<void> _loginWithBiometric(String email) async {
    setState(() { _loading = true; _error = null; });

    final result = await BiometricService().authenticate(
      reason: 'Verifica tu identidad para entrar a Sabor Manager',
      email: email,
    );
    if (!mounted) return;

    if (!result.success) {
      if (result.needsSetup) await BiometricService().unlink(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Cancelar a propósito no es un error: el usuario solo quiere teclear
        // su contraseña, y no merece un letrero rojo por eso.
        _error = result.cancelled ? null : result.error;
        if (result.needsSetup) {
          _linkedAccounts.remove(BiometricService.normalizeEmail(email));
        }
      });
      return;
    }

    final login = await AuthService().login(result.email!, result.password!);
    if (!mounted) return;

    // Un correo con cuenta en dos restaurantes también entra con la cara: sin
    // esto se tomaba por contraseña equivocada y se desvinculaba solo.
    if (login.needsTenantSelection) {
      setState(() => _loading = false);
      await _showTenantSelectionDialog(
          login.candidates, result.email!, result.password!);
      return;
    }

    if (!login.success) {
      // Credenciales guardadas ya no son válidas — se desvincula solo esta
      // cuenta, las otras del teléfono siguen sirviendo.
      await BiometricService().unlink(result.email!);
      if (!mounted) return;
      setState(() {
        _error = 'Tu contraseña cambió. Ingresa con tu correo y contraseña '
            'para volver a activar el acceso rápido.';
        _linkedAccounts.remove(result.email!);
        _loading = false;
      });
      return;
    }

    await BiometricService().rememberEmail(result.email!);
    if (!mounted) return;
    _goToDashboard();
  }

  /// Por qué el botón todavía no puede entrar a la cuenta escrita arriba.
  Future<void> _showActivationHelp(String email) async {
    final hasEnrolled = await BiometricService().isAvailable();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(_biometricIcon, color: const Color(0xFF7444fd), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasEnrolled
                    ? 'Activa el acceso rápido'
                    : 'Sin ${_biometricKind.label} registrada',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          hasEnrolled
              ? 'Esta cuenta ($email) todavía no tiene acceso con '
                  '${_biometricKind.label}. Ingresa esta vez con su '
                  'contraseña y al terminar te preguntamos si quieres '
                  'activarlo; la próxima vez entras con un toque.'
              : 'Tu dispositivo todavía no tiene ${_biometricKind.label} '
                  'registrada.\n\n${_biometricKind.enrollHint}',
          style: GoogleFonts.inter(
              color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7444fd),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Entendido', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  IconData get _biometricIcon => BiometricLoginButton.iconFor(_biometricKind);

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final result = await AuthService().login(email, password);
    if (!mounted) return;

    if (result.needsTenantSelection) {
      setState(() => _loading = false);
      await _showTenantSelectionDialog(result.candidates, email, password);
      return;
    }

    if (!result.success) {
      setState(() { _error = result.error; _loading = false; });
      return;
    }

    await _afterPasswordLogin(email, password);
  }

  Future<void> _showTenantSelectionDialog(
    List<TenantLoginCandidate> candidates,
    String email,
    String password,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '¿A qué restaurante querés entrar?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: SizedBox(
          width: double.maxFinite,
          // AlertDialog no desplaza su contenido por su cuenta: mete el content
          // en un Flexible y lo recorta. Con una Column pelada, un admin con
          // muchos restaurantes veía la lista cortada y sin forma de llegar a
          // los de abajo — o sea sin poder entrar a esos negocios.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(candidates.length, (i) {
              final c = candidates[i];
              final data = c.data;
              final tenantId = (data['current_tenant_id'] ?? data['tenant_id'] ?? '') as String;
              final name = (data['name'] ?? tenantId) as String;
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, i),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7444fd).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF7444fd).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.store_rounded, size: 20, color: Color(0xFF7444fd)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              );
            }),
          ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancelar', style: GoogleFonts.inter(color: Colors.white38)),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    setState(() => _loading = true);
    final c = candidates[selected];
    final result = await AuthService().completeTenantLogin(
      data: c.data,
      docId: c.docId,
      email: email,
      password: password,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() { _error = result.error; _loading = false; });
      return;
    }

    await _afterPasswordLogin(email, password);
  }

  /// Entró con contraseña: se recuerda el correo para la próxima y, si esa
  /// cuenta todavía no tiene acceso rápido, se le ofrece.
  Future<void> _afterPasswordLogin(String email, String password) async {
    await BiometricService().rememberEmail(email);
    if (!mounted) return;

    final normalized = BiometricService.normalizeEmail(email);
    if (_biometricAvailable && !_linkedAccounts.contains(normalized)) {
      await _offerBiometric(email, password);
    } else {
      _goToDashboard();
    }
  }

  Future<void> _offerBiometric(String email, String password) async {
    // _biometricAvailable solo dice que hay sensor. Ofrecer activar la huella
    // a quien no tiene ninguna registrada es prometer algo que va a fallar.
    final hasEnrolled = await BiometricService().isAvailable();
    if (!mounted) return;
    if (!hasEnrolled) {
      _goToDashboard();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '¿Activar acceso rápido?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'La próxima vez entras a $email con tu ${_biometricKind.label}, sin '
          'escribir tu contraseña.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _goToDashboard();
            },
            child: Text('No, gracias', style: GoogleFonts.inter(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              // Se guarda y se pide la biometría en el acto: si el sensor no
              // responde, el usuario se entera ahora y no la próxima vez que
              // llegue al login confiando en algo que nunca funcionó.
              await BiometricService().saveCredentials(email, password);
              final check = await BiometricService().authenticate(
                reason: 'Confirma tu ${_biometricKind.label} para activar el '
                    'acceso rápido',
                email: email,
              );
              if (!check.success) await BiometricService().unlink(email);
              if (!mounted) return;
              Navigator.pop(context);
              _goToDashboard();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7444fd),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Activar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onEmailChanged);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      // Sin AppBar ni bottomNavigationBar, el Scaffold dibuja el body hasta el
      // último píxel de la pantalla: el logo se metía bajo el reloj y el botón
      // "Ingresar" quedaba contra la barra de navegación. Y es la primera
      // pantalla que ve un cliente nuevo.
      body: SafeArea(
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/SaborManagerLogo.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sabor Suite',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'Manager',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Email'),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Contraseña').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white38,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFEF4444)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7444fd),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Ingresar',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  // Acceso biométrico. Se muestra siempre que el dispositivo
                  // tenga sensor, y entra a la cuenta escrita arriba: encendido
                  // si ese correo está vinculado, apagado si no. Nunca se
                  // dispara solo al abrir la app — el usuario decide cuándo,
                  // porque si no, nunca alcanzaba a cambiar de cuenta.
                  if (_biometricAvailable)
                    BiometricLoginButton(
                      kind: _biometricKind,
                      enabled: _typedEmailLinked,
                      onTap: _loading ? null : _onBiometricTap,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF7444fd)),
      ),
      errorStyle: const TextStyle(color: Color(0xFFEF4444)),
    );
  }
}
