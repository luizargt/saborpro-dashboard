import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/utils/monedas.dart';
import '../providers/dashboard_provider.dart';
import '../screens/settings/moneda_settings_screen.dart';

/// Una línea bajo las pestañas de sucursal que dice en qué moneda se está
/// viendo, cuando el negocio tiene sucursales en monedas distintas.
///
/// - Convertido: "En quetzales, con tu tipo de cambio" y el botón para ver la
///   sucursal en la suya.
/// - Falta un tipo de cambio: qué sucursales quedaron fuera y el botón para
///   ponerlo. Sumarlas sin convertir daría un total que no es de nada.
///
/// Con una sola moneda no ocupa ni un píxel.
class MonedaVistaAviso extends StatelessWidget {
  const MonedaVistaAviso({super.key});

  static const _ambar = Color(0xFFF59E0B);

  void _abrirAjustes(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MonedaSettingsScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    if (!dash.hayOtraMoneda) return const SizedBox.shrink();

    final principal = dash.codigoPrincipal;
    final nombrePrincipal = nombreDeMoneda[principal] ?? principal;
    final sinTasa = dash.sucursalesSinTasa;

    String texto;
    Color color = Colors.white38;
    String? accion;
    VoidCallback? alTocar;

    if (sinTasa.isNotEmpty) {
      final monedas = {for (final l in sinTasa) nombreDeMoneda[l.currencyCode] ?? l.currencyCode};
      texto = 'No incluye ${sinTasa.map((l) => l.name).join(', ')}: falta el tipo de cambio '
          '(${monedas.join(', ')}).';
      color = _ambar;
      if (dash.puedeEditarMoneda) {
        accion = 'Ponerlo';
        alTocar = () => _abrirAjustes(context);
      }
    } else if (dash.faltaTasaEnVista) {
      final local = nombreDeMoneda[dash.codigoVista] ?? dash.codigoVista;
      texto = 'En $local: falta el tipo de cambio para verla en $nombrePrincipal.';
      color = _ambar;
      if (dash.puedeEditarMoneda) {
        accion = 'Ponerlo';
        alTocar = () => _abrirAjustes(context);
      }
    } else if (dash.convierte) {
      texto = 'Convertido a ${dash.simboloDe(principal)} con tu tipo de cambio';
      if (dash.puedeVerEnLocal) {
        final local = dash.locations
            .firstWhere((l) => l.id == dash.selectedLocationId, orElse: () => dash.locations.first);
        accion = 'Ver en ${local.currencySymbol}';
        alTocar = () => dash.setVerEnLocal(true);
      }
    } else if (dash.puedeVerEnLocal) {
      final local = nombreDeMoneda[dash.codigoVista] ?? dash.codigoVista;
      texto = 'En ${dash.simboloDe(dash.codigoVista)} ($local), sin convertir';
      accion = 'Ver en ${dash.simboloDe(principal)}';
      alTocar = () => dash.setVerEnLocal(false);
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.currency_exchange_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: color, fontSize: 12, height: 1.3),
            ),
          ),
          if (accion != null)
            TextButton(
              onPressed: alTocar,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7444fd),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(accion, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
