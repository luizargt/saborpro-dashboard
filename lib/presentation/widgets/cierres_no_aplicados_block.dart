import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show MonedaLocal;
import '../../data/models/cash_register_summary.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Los otros cierres de un corte, hechos cuando la caja ya estaba cerrada (en
/// otro aparato que no se enteró): no cambian su cuadre, pero el dueño los ve
/// con su hora, su aparato y lo que se contó.
///
/// Dice cuál vale por su hora y no "el primero": un aparato sin internet pudo
/// cerrar antes y mandarlo después. Mismas palabras que el historial del POS.
class CierresNoAplicadosBlock extends StatelessWidget {
  final CashRegisterSummary register;
  const CierresNoAplicadosBlock(this.register, {super.key});

  static final _fmt = NumberFormat('#,##0.00', 'en_US');

  /// El mismo formato de hora que la tarjeta del corte: el dueño compara las dos.
  static final _hora = DateFormat('hh:mm a');

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static DateTime? _fecha(dynamic v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  static String _cuando(DateTime f) => '${_dos(f.day)}/${_dos(f.month)} a las ${_hora.format(f)}';

  static String _monto(dynamic v, String signo) => '$signo${_fmt.format(v is num ? v.toDouble() : 0.0)}';

  static bool _usado(dynamic v) => v is num && v.abs() > 0.004;

  String _cierre(Map<String, dynamic> c, String signo) {
    final modelo = c['device_model'];
    final en = modelo is String && modelo.trim().isNotEmpty && modelo.trim().toLowerCase() != 'desconocido'
        ? ' en ${modelo.trim()}'
        : '';

    // Los métodos propios por su nombre; los que no tienen nombre, en un solo
    // "otros".
    final propios = <String, double>{};
    var sinNombre = 0.0;
    final otros = c['actualCustomMethods'];
    if (otros is Map) {
      for (final e in otros.entries) {
        if (!_usado(e.value)) continue;
        final valor = (e.value as num).toDouble();
        final nombre = register.customMethodNames[e.key.toString()]?.trim();
        if (nombre == null || nombre.isEmpty) {
          sinNombre += valor;
        } else {
          propios[nombre] = (propios[nombre] ?? 0) + valor;
        }
      }
    }

    final contado = [
      'efectivo ${_monto(c['actualCash'], signo)}',
      if (_usado(c['actualCard'])) 'tarjeta ${_monto(c['actualCard'], signo)}',
      if (_usado(c['actualTransfer'])) 'transferencia ${_monto(c['actualTransfer'], signo)}',
      if (_usado(c['actualPedidosya'])) 'PedidosYa ${_monto(c['actualPedidosya'], signo)}',
      if (_usado(c['actualUbereats'])) 'Uber Eats ${_monto(c['actualUbereats'], signo)}',
      for (final e in propios.entries) '${e.key} ${_monto(e.value, signo)}',
      if (_usado(sinNombre)) 'otros ${_monto(sinNombre, signo)}',
    ].join(', ');
    final fecha = _fecha(c['closed_at']);
    if (fecha == null) return 'Contó $contado.';
    // Uno hecho ANTES que el que vale: si no se dice que llegó después, parece
    // que el sistema se quedó con el equivocado.
    final vigente = register.closedAt?.toLocal();
    final tarde = vigente != null && fecha.isBefore(vigente) ? ', pero llegó después' : '';
    return 'Se hizo el ${_cuando(fecha)}$en$tarde. Contó $contado.';
  }

  @override
  Widget build(BuildContext context) {
    final cierres = register.cierresNoAplicados;
    final uno = cierres.length == 1;
    final vigente = register.closedAt?.toLocal();
    // El cierre forzado no contó nada: da por contado lo esperado. El conteo
    // real es el de abajo.
    final forzado = register.closingNotes?.contains('Cierre forzado') ?? false;
    final titulo = uno ? 'Esta caja se cerró dos veces' : 'Esta caja se cerró ${cierres.length + 1} veces';
    final explicacion = register.cerradaPorAdmin
        // "Esperado" no incluye el fondo de apertura y el cajón sí: el efectivo
        // se compara con "Total efectivo".
        ? 'La cerró un administrador sin contar el dinero. '
            '${uno ? 'Este es el conteo que se hizo' : 'Estos son los conteos que se hicieron'}: '
            'compara el efectivo con "Total efectivo" y lo demás con "Esperado".'
        : forzado
            ? 'Se cerró sin contar el dinero (cierre forzado), así que el cuadre de '
                'este corte no es real. ${uno ? 'Este es el conteo que se hizo' : 'Estos '
                    'son los conteos que se hicieron'}: compáralo con lo esperado.'
            : 'Vale el cierre ${vigente == null ? 'de este corte' : 'del ${_cuando(vigente)}'}. '
                '${uno ? 'Este otro llegó' : 'Estos otros llegaron'} cuando la caja ya '
                'estaba cerrada y no ${uno ? 'cambia' : 'cambian'} el cuadre:';
    final texto = _t(13, FontWeight.w400, _C.ink, height: 1.45);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: _C.warnTint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: _C.warn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: texto.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(explicacion, style: texto),
                const SizedBox(height: 4),
                for (final c in cierres)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(_cierre(c, MonedaLocal.de(context)), style: texto.copyWith(color: _C.muted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
