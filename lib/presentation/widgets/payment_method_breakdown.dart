import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// "Ventas por método de pago": una fila por método con su monto, su parte del
/// total y una barra, y el total abajo. Rediseño 2026-11-20 (inicio-manager.html,
/// modo oscuro); los métodos, el orden y las cuentas son los de siempre.
class PaymentMethodBreakdown extends StatelessWidget {
  final Map<String, double> salesByMethod;
  final Map<String, String> customMethodNames;

  const PaymentMethodBreakdown({
    super.key,
    required this.salesByMethod,
    this.customMethodNames = const {},
  });

  static const _knownNames = {
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'transfer': 'Transferencia',
    'pedidosya': 'PedidosYa',
    'ubereats': 'Uber Eats',
    '_tips': 'Propinas',
  };

  static Map<String, Color> get _knownColors => {
    'cash': _C.gift,
    'card': _C.don,
    'transfer': _C.accent,
    'pedidosya': _C.warn,
    'ubereats': _C.bad,
    '_tips': _C.warn,
  };

  // Para los métodos que el negocio inventó: colores que no se confunden con
  // los de arriba.
  static const _fallback = [
    Color(0xFF22B5D6),
    Color(0xFFF28BC8),
    Color(0xFFB4D86A),
    Color(0xFFE9967A),
    Color(0xFF8E9AAF),
  ];

  String _name(String key) {
    if (_knownNames.containsKey(key)) return _knownNames[key]!;
    if (customMethodNames.containsKey(key)) return customMethodNames[key]!;
    final cleaned = key.replaceAll('custom_', '');
    return cleaned.length > 12 ? cleaned.substring(0, 12) : cleaned;
  }

  Color _color(String key, int index) {
    if (_knownColors.containsKey(key)) return _knownColors[key]!;
    return _fallback[index % _fallback.length];
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    // Propinas al final, el resto ordenado por monto
    final entries = salesByMethod.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        if (a.key == '_tips') return 1;
        if (b.key == '_tips') return -1;
        return b.value.compareTo(a.value);
      });

    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold(0.0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InicioTituloTarjeta(titulo: 'Ventas por método de pago'),
        for (var idx = 0; idx < entries.length; idx++)
          _FilaMetodo(
            nombre: _name(entries[idx].key),
            color: _color(entries[idx].key, idx),
            monto: '$moneda${fmt.format(entries[idx].value)}',
            porcentaje: total > 0 ? entries[idx].value / total : 0.0,
          ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: _C.line))),
          child: Row(
            children: [
              Text('Total', style: _t(15, FontWeight.w500, _C.ink)),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('$moneda${fmt.format(total)}', maxLines: 1, style: _t(18, FontWeight.w700, _C.accent)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaMetodo extends StatelessWidget {
  final String nombre;
  final Color color;
  final String monto;
  final double porcentaje;

  const _FilaMetodo({
    required this.nombre,
    required this.color,
    required this.monto,
    required this.porcentaje,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El monto manda sobre el nombre (el nombre se acorta primero), pero
          // nunca pasa de la mitad de la pantalla: con una cifra enorme se
          // achica. El tope sale del ancho de la pantalla y NO de un
          // LayoutBuilder: esta tarjeta va dentro de un IntrinsicHeight (junto a
          // "Ventas por sucursal"), que no admite LayoutBuilders.
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(15, FontWeight.w500, _C.ink),
                ),
              ),
              const SizedBox(width: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(monto, maxLines: 1, style: _t(16, FontWeight.w700, _C.ink)),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 48,
                child: Text(
                  '${(porcentaje * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: _t(13.5, FontWeight.w400, _C.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: _C.subtle)),
                  FractionallySizedBox(
                    widthFactor: porcentaje.clamp(0.0, 1.0),
                    child: ColoredBox(color: color, child: const SizedBox.expand()),
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
