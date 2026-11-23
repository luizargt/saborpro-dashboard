/// El dato de "ahora" que cada tarjeta de Reportes muestra bajo su descripción
/// ("Hoy Q225.00", "2 cajas abiertas · Faltante Q385"). Rediseño 2026-11-20
/// (reportes.html).
///
/// Todo sale de lo que el Inicio ya tiene en memoria, y siguiendo la regla de
/// siempre: lo que no se sabe NO se muestra. Una tarjeta sin dato no dibuja la
/// fila, en vez de afirmar un cero que no se midió.
///
/// Dos tarjetas no llevan dato a propósito:
/// - Rentabilidad: su margen sale de las recetas y los costos (otro provider,
///   pesado). Calcular aquí uno "parecido" daría un número distinto al del
///   reporte al tocarlo.
/// - Pedidos cancelados: sus cifras salen de leer hasta 2000 pedidos y todos los
///   costos de los ingredientes; no se paga en cada visita a la lista.
library;

import 'package:intl/intl.dart';

import 'atencion_inicio.dart';
import 'cash_register_summary.dart';
import 'dashboard_data.dart';

/// De qué color va la banderita de una tarjeta.
enum TonoBandera { rojo, ambar, verde }

class BanderaReporte {
  final String texto;
  final TonoBandera tono;
  const BanderaReporte(this.texto, this.tono);

  @override
  bool operator ==(Object other) => other is BanderaReporte && other.texto == texto && other.tono == tono;

  @override
  int get hashCode => Object.hash(texto, tono);
}

/// La fila de dato de una tarjeta: texto con lo importante en negritas y, si hay
/// algo que mirar, una banderita a la derecha.
class DatoReporte {
  final List<ParteTexto> partes;
  final BanderaReporte? bandera;

  const DatoReporte({required this.partes, this.bandera});

  /// El texto sin formato.
  String get texto => partes.map((p) => p.texto).join();
}

/// Las claves de las tarjetas que llevan dato.
class IdReporte {
  IdReporte._();
  static const cierres = 'cierres';
  static const gastos = 'gastos';
  static const propinas = 'propinas';
  static const cortesias = 'cortesias';
}

class DatosReportes {
  DatosReportes._();

  static final _dinero = NumberFormat('#,##0.00', 'en_US');

  /// [periodo]: cómo se llama lo que se está mirando ("Hoy", "noviembre 2026").
  /// [metrics]: nulo mientras carga o si falló. [signoVista]: el de la moneda de
  /// la vista (gastos y cortesías vienen convertidos); cada caja usa el de su
  /// sucursal ([signoDeCaja]), porque las cajas no se convierten nunca.
  ///
  /// Solo trae las claves que SE SABEN.
  static Map<String, DatoReporte> armar({
    required String periodo,
    required PeriodMetrics? metrics,
    required bool cajasOk,
    required List<CashRegisterSummary> abiertas,
    required List<CashRegisterSummary> cerradas,
    required String Function(String? locationId) signoDeCaja,
    required String signoVista,
    required ResumenPedidosInicio pedidos,
  }) {
    final datos = <String, DatoReporte>{};
    String q(double v) => '${signoVista.isEmpty ? '' : signoVista}${_dinero.format(v)}';

    // Cierres de caja: cuántas siguen abiertas y si hubo faltantes en el período.
    if (cajasOk) {
      final n = abiertas.length;
      datos[IdReporte.cierres] = DatoReporte(
        partes: n == 0
            ? const [ParteTexto('Ninguna caja abierta')]
            : [ParteTexto('$n', negrita: true), ParteTexto(n == 1 ? ' caja abierta' : ' cajas abiertas')],
        bandera: _banderaFaltantes(cerradas, signoDeCaja),
      );
    }

    if (metrics != null) {
      // Gastos: lo mismo que dice la cabecera del reporte ("Total gastos del
      // período": gastos, retiros de caja y compras).
      datos[IdReporte.gastos] = DatoReporte(
        partes: [ParteTexto('$periodo '), ParteTexto(q(metrics.totalCosts), negrita: true)],
      );

      // Propinas: lo mismo que la tarjeta del Inicio y la cabecera del reporte
      // (las cobradas en los tickets y las metidas a la caja). También en la
      // vista de año: es un total que suma Firestore, no detalle de tickets.
      datos[IdReporte.propinas] = DatoReporte(
        partes: [ParteTexto('$periodo '), ParteTexto(q(metrics.allTips), negrita: true)],
      );

      // Cortesías: viven dentro de los tickets; la vista de año no las tiene.
      if (metrics.detailAvailable) {
        final sin = pedidos.cortesiasSinMotivo;
        datos[IdReporte.cortesias] = DatoReporte(
          partes: [ParteTexto('$periodo '), ParteTexto(q(metrics.courtesyTotal), negrita: true)],
          bandera: sin > 0 ? BanderaReporte('$sin sin motivo', TonoBandera.ambar) : null,
        );
      }
    }
    return datos;
  }

  /// "Faltante Q385" si todos los faltantes son de una misma moneda; con varias
  /// (sumarlas daría un total que no es de nada), solo cuántos cierres.
  static BanderaReporte? _banderaFaltantes(
    List<CashRegisterSummary> cerradas,
    String Function(String? locationId) signoDeCaja,
  ) {
    final faltantes = AtencionInicio.faltantesDe(cerradas);
    if (faltantes.isEmpty) return null;
    final porSigno = <String, double>{};
    for (final f in faltantes) {
      porSigno.update(signoDeCaja(f.$1.locationId), (t) => t + f.$2, ifAbsent: () => f.$2);
    }
    if (porSigno.length == 1) {
      final e = porSigno.entries.single;
      return BanderaReporte('Faltante ${AtencionInicio.monto(e.key, e.value)}', TonoBandera.rojo);
    }
    return BanderaReporte('${faltantes.length} cierres con faltante', TonoBandera.rojo);
  }
}
