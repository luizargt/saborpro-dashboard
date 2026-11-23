/// Lo que "Requiere tu atención" le dice al dueño al abrir el Inicio.
///
/// Todo sale de datos que el Inicio ya tiene en memoria: no hay consultas
/// nuevas. Tres cosas, las que un dueño quiere saber sin ir a buscarlas:
///
/// - un cierre de caja que terminó con FALTANTE de dinero (rojo);
/// - una caja que lleva días abierta, o sea que nadie la cerró (ámbar);
/// - cortesías de las que nadie dijo el motivo (ámbar).
///
/// Es una función pura para poder probar exactamente cuándo avisa y cuándo no:
/// un aviso de más enseña a ignorar la lista, y uno de menos esconde un
/// faltante.
library;

import 'package:intl/intl.dart';

import '../../core/utils/formato_dinero.dart' show signoParaMostrar;
import 'cash_register_summary.dart';
import 'cortesias_data.dart';

/// Qué tan grave es: rojo (dinero que faltó) o ámbar (algo olvidado o sin
/// explicar).
enum GravedadAtencion { alta, media }

/// A dónde lleva tocar el aviso.
enum DestinoAtencion { cierresDeCaja, cortesias }

class ParteTexto {
  final String texto;
  final bool negrita;
  const ParteTexto(this.texto, {this.negrita = false});

  @override
  bool operator ==(Object other) =>
      other is ParteTexto && other.texto == texto && other.negrita == negrita;

  @override
  int get hashCode => Object.hash(texto, negrita);
}

class ItemAtencion {
  final GravedadAtencion gravedad;

  /// La frase en pedazos: lo importante va en negritas.
  final List<ParteTexto> partes;

  /// De qué parte de la app es ("Cierres de caja", "Cortesías").
  final String seccion;
  final DestinoAtencion destino;

  /// Cuántas incidencias resume esta fila: 1, salvo la de "N cierres más con
  /// faltante", que resume N. La insignia de la tarjeta las suma: 7 faltantes
  /// no pueden decir "4".
  final int cuantos;

  const ItemAtencion({
    required this.gravedad,
    required this.partes,
    required this.seccion,
    required this.destino,
    this.cuantos = 1,
  });

  /// La frase sin formato.
  String get texto => partes.map((p) => p.texto).join();
}

class AtencionInicio {
  AtencionInicio._();

  /// El mismo umbral que el aviso de "Descuadre" que llega por push
  /// (functions/notifications/onCashRegisterWrite.js): menos de un centavo es
  /// cuadre.
  static const umbralFaltante = 0.01;

  /// Una caja que lleva abierta más que esto es de un turno que nadie cerró.
  static const cajaOlvidada = Duration(hours: 24);

  /// Los cierres que terminaron con FALTANTE, de mayor a menor, con cuánto
  /// faltó (positivo). La regla es una sola para todo el Manager: solo con las
  /// diferencias selladas al cerrar (`differenceCash != null`, la misma
  /// condición con que `CajasScreen` decide qué pintar como "Faltante") y desde
  /// el umbral del aviso push de "Descuadre". Sin ellas la diferencia se
  /// recalcularía de acumulados que otro aparato pudo sobrescribir, y un
  /// faltante inventado es peor que no avisar.
  static List<(CashRegisterSummary, double)> faltantesDe(List<CashRegisterSummary> cerradas) {
    return <(CashRegisterSummary, double)>[
      for (final r in cerradas)
        if (r.differenceCash != null && r.totalDifference != null && r.totalDifference! <= -umbralFaltante)
          (r, -r.totalDifference!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  static final _entero = NumberFormat('#,##0', 'en_US');
  static final _centavos = NumberFormat('#,##0.00', 'en_US');

  /// "Q385" si es redondo; "Q385.50" si lleva centavos.
  static String monto(String signo, double v) {
    final s = signoParaMostrar(signo);
    final redondo = (v - v.roundToDouble()).abs() < 0.005;
    return '$s${redondo ? _entero.format(v.roundToDouble()) : _centavos.format(v)}';
  }

  /// [cerradas]: las cajas cerradas dentro del período que se mira. [abiertas]:
  /// todas las que siguen abiertas, de cualquier antigüedad.
  ///
  /// [signoDeCaja]: el signo de la sucursal de cada caja (las cajas no se
  /// convierten nunca). [signoVista]: el de la moneda de la vista, que es en la
  /// que vienen las cortesías.
  ///
  /// [mostrarSucursal]: agrega el nombre de la sucursal a la sección, para
  /// quien tiene varias.
  static List<ItemAtencion> armar({
    required List<CashRegisterSummary> cerradas,
    required List<CashRegisterSummary> abiertas,
    required int cortesiasSinMotivo,
    required double montoSinMotivo,
    required String Function(String? locationId) signoDeCaja,
    required String signoVista,
    required DateTime ahora,
    bool mostrarSucursal = false,
    int maxPorTipo = 3,
  }) {
    String seccion(String base, CashRegisterSummary r) {
      final loc = r.locationName;
      return mostrarSucursal && loc != null && loc.isNotEmpty ? '$base · $loc' : base;
    }

    final items = <ItemAtencion>[];

    // 1) Faltantes. Solo cierres con las diferencias selladas al cerrar: sin
    // ellas la diferencia se recalcula de acumulados que otro aparato puede
    // haber sobrescrito, y un faltante inventado es peor que no avisar.
    final faltantes = faltantesDe(cerradas);

    for (final f in faltantes.take(maxPorTipo)) {
      items.add(ItemAtencion(
        gravedad: GravedadAtencion.alta,
        partes: [
          const ParteTexto('Faltante de '),
          ParteTexto(monto(signoDeCaja(f.$1.locationId), f.$2), negrita: true),
          ParteTexto(' en el cierre de ${f.$1.userName}'),
        ],
        seccion: seccion('Cierres de caja', f.$1),
        destino: DestinoAtencion.cierresDeCaja,
      ));
    }
    if (faltantes.length > maxPorTipo) {
      final mas = faltantes.length - maxPorTipo;
      items.add(ItemAtencion(
        gravedad: GravedadAtencion.alta,
        partes: [
          ParteTexto('$mas ${mas == 1 ? 'cierre más' : 'cierres más'}', negrita: true),
          const ParteTexto(' con faltante'),
        ],
        seccion: 'Cierres de caja',
        destino: DestinoAtencion.cierresDeCaja,
        cuantos: mas,
      ));
    }

    // 2) Cajas que nadie cerró.
    final olvidadas = [
      for (final r in abiertas)
        if (ahora.difference(r.openedAt) >= cajaOlvidada) r,
    ]..sort((a, b) => a.openedAt.compareTo(b.openedAt));

    for (final r in olvidadas.take(maxPorTipo)) {
      final dias = ahora.difference(r.openedAt).inDays;
      items.add(ItemAtencion(
        gravedad: GravedadAtencion.media,
        partes: [
          const ParteTexto('La caja de '),
          ParteTexto(r.userName, negrita: true),
          const ParteTexto(' lleva '),
          ParteTexto('$dias ${dias == 1 ? 'día' : 'días'} abierta', negrita: true),
        ],
        seccion: seccion('Cierres de caja', r),
        destino: DestinoAtencion.cierresDeCaja,
      ));
    }
    if (olvidadas.length > maxPorTipo) {
      final mas = olvidadas.length - maxPorTipo;
      items.add(ItemAtencion(
        gravedad: GravedadAtencion.media,
        partes: [
          ParteTexto('$mas ${mas == 1 ? 'caja más' : 'cajas más'}', negrita: true),
          const ParteTexto(' llevan días abiertas'),
        ],
        seccion: 'Cierres de caja',
        destino: DestinoAtencion.cierresDeCaja,
        cuantos: mas,
      ));
    }

    // 3) Cortesías sin motivo (las mismas cifras que el aviso del detalle).
    if (cortesiasSinMotivo > 0) {
      items.add(ItemAtencion(
        gravedad: GravedadAtencion.media,
        partes: [
          ParteTexto(
            '$cortesiasSinMotivo ${cortesiasSinMotivo == 1 ? 'cortesía' : 'cortesías'} sin motivo',
            negrita: true,
          ),
          ParteTexto(' por ${monto(signoVista, montoSinMotivo)}'),
        ],
        seccion: 'Cortesías',
        destino: DestinoAtencion.cortesias,
      ));
    }

    return items;
  }
}

/// Lo que se cuenta recorriendo los pedidos del período, para el Inicio: cuántos
/// cobros llevaron descuento y las cortesías sin motivo. Las cifras de las
/// cortesías son las mismas del detalle (`CortesiasReport`), para que el aviso y
/// la pantalla a la que lleva digan lo mismo.
class ResumenPedidosInicio {
  /// Cobros con descuento.
  final int descuentos;

  /// Pedidos con alguna cortesía o donación sin motivo, y lo que suman.
  final int cortesiasSinMotivo;
  final double montoSinMotivo;

  const ResumenPedidosInicio({
    this.descuentos = 0,
    this.cortesiasSinMotivo = 0,
    this.montoSinMotivo = 0,
  });

  static const vacio = ResumenPedidosInicio();

  /// [pedidos]: los que el Inicio ya tiene en memoria (cobrados, de la
  /// sucursal que se mira y en la moneda de la vista).
  static ResumenPedidosInicio desde(List<Map<String, dynamic>> pedidos) {
    var descuentos = 0;
    for (final o in pedidos) {
      if (((o['discount_amount'] as num?) ?? 0) > 0) descuentos++;
    }

    final reporte = CortesiasReport.desde(pedidos);
    var sinMotivo = 0;
    var monto = 0.0;
    for (final p in reporte.pedidos) {
      var alguna = false;
      for (final r in p.renglones) {
        if (r.motivo == null) {
          alguna = true;
          monto += r.monto;
        }
      }
      if (alguna) sinMotivo++;
    }

    return ResumenPedidosInicio(
      descuentos: descuentos,
      cortesiasSinMotivo: sinMotivo,
      montoSinMotivo: monto,
    );
  }
}
