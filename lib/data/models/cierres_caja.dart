/// Lo que se ve en Cierres de caja (rediseño 2026-11-21, `cierres-caja.html` de
/// saborpro_app en su modo oscuro), sin widgets: el cuadre de cada corte y el
/// resumen del período.
///
/// La cuenta de cada corte es la MISMA que ya hacía `CajasScreen` (se portó tal
/// cual, y se prueba en `cierres_caja_test.dart`): ventas selladas al cerrar
/// (declarado − diferencia, también en los métodos propios) y, solo en cortes
/// antiguos sin diferencias selladas, recalculadas desde los pedidos del período.
/// Cambió lo que se dibuja, no lo que se cuenta.
///
/// Las cajas NO se convierten nunca: cada una se cuenta en la moneda de su
/// sucursal. Por eso el resumen se arma por moneda, sin mezclar quetzales con
/// dólares.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';

import 'atencion_inicio.dart' show AtencionInicio;
import 'cash_register_summary.dart';

final _dinero = NumberFormat('#,##0.00', 'en_US');

/// "Q1,234.50". El negativo lleva "−" (no "-") y lo que redondea a cero sale sin
/// signo: "−Q0.00" se lee como una pérdida que no existe.
String formatoMonto(String signo, double v) {
  // Los dígitos los pone intl sobre el valor, como siempre (redondear antes con
  // toStringAsFixed daba medio centavo distinto en unos pocos casos: 0.695).
  final digitos = _dinero.format(v.abs());
  final esCero = digitos == '0.00';
  return v < 0 && !esCero ? '−$signo$digitos' : '$signo$digitos';
}

/// "12 nov". En español (la app carga el idioma al arrancar); si no está cargado
/// (en una prueba, por ejemplo) sale en el idioma por defecto en vez de lanzar.
String fechaCorta(DateTime d) {
  try {
    return DateFormat('d MMM', 'es').format(d);
  } catch (_) {
    return DateFormat('d MMM').format(d);
  }
}

/// "7h 24m"; menos de una hora, "50m".
String formatoDuracion(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// "AC" para "Ana Cosme"; "?" si no hay nombre.
String inicialesDe(String nombre) {
  final palabras = nombre.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final i = palabras.map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  return i.isEmpty ? '?' : i;
}

/// El nombre de un método propio. 'otros' es donde el POS junta los pagos con
/// un método que no reconoce, y 'custom' la clave de ventas viejas sin el id del
/// método: los dos salían con el id crudo.
String nombreDelMetodo(CashRegisterSummary r, String id) =>
    r.customMethodNames[id] ??
    switch (id) {
      'otros' => 'Otros (revisar)',
      'custom' => 'Personalizado',
      _ => id,
    };

/// Cómo terminó un corte.
enum EstadoCierre {
  /// No se contó nada (el corte no trae lo contado).
  sinContar,
  cuadro,
  sobrante,
  faltante,

  /// La cerró un administrador sin contar el dinero: no hay con qué cuadrarla.
  descuadrada,
}

/// Una fila de "¿Cuadró la caja?": lo esperado y lo contado de un método. Los
/// dos SIN el fondo de apertura (el efectivo, con retiros y depósitos).
class FilaCuadre {
  final String metodo;
  final double esperado;
  final double? contado;

  const FilaCuadre(this.metodo, this.esperado, this.contado);

  double? get diferencia => contado == null ? null : contado! - esperado;
}

/// Las ventas de un corte recalculadas desde los pedidos del período. Solo para
/// cortes antiguos que no traen diferencias selladas: los acumulados del corte
/// pudieron ser sobrescritos por la sincronización de otro aparato.
class VentasRecalculadas {
  final double cash, card, transfer, pedidosya, ubereats;
  final Map<String, double> custom;
  final bool hayPedidos;

  const VentasRecalculadas({
    this.cash = 0,
    this.card = 0,
    this.transfer = 0,
    this.pedidosya = 0,
    this.ubereats = 0,
    this.custom = const {},
    this.hayPedidos = false,
  });

  double get total => cash + card + transfer + pedidosya + ubereats + custom.values.fold(0.0, (a, b) => a + b);

  /// Port de `_calcSalesFromOrders` de `CajasScreen`.
  static VentasRecalculadas desde(CashRegisterSummary reg, List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) return const VentasRecalculadas();

    final rangeEnd = reg.closedAt ?? DateTime.now();
    final openBuf = reg.openedAt.subtract(const Duration(seconds: 1));
    final closeBuf = rangeEnd.add(const Duration(seconds: 1));
    final locId = reg.locationId ?? '';

    double cash = 0, card = 0, transfer = 0, py = 0, ue = 0;
    final customMap = <String, double>{};
    var found = false;

    void suma(String method, double amount) {
      switch (method) {
        case 'cash':
          cash += amount;
        case 'card':
          card += amount;
        case 'transfer':
          transfer += amount;
        case 'pedidosya':
          py += amount;
        case 'ubereats':
          ue += amount;
        default:
          if (method.startsWith('custom_') || method == 'custom') {
            customMap[method] = (customMap[method] ?? 0) + amount;
          } else {
            cash += amount;
          }
      }
    }

    for (final o in orders) {
      if ((o['status'] as String? ?? '') == 'CANCELLED') continue;
      if (locId.isNotEmpty && o['location_id'] != locId) continue;

      final paidAt = _aFecha(o['paid_at']);
      if (paidAt == null) continue;
      if (!paidAt.isAfter(openBuf) || !paidAt.isBefore(closeBuf)) continue;

      found = true;
      final amount = _montoDelPedido(o);
      final method = o['payment_method'] as String? ?? 'cash';

      if (method == 'split') {
        final splits = (o['split_payments'] as List<dynamic>?)?.whereType<Map>().toList() ?? [];
        if (splits.isEmpty) {
          cash += amount;
        } else {
          for (final sp in splits) {
            suma(sp['payment_method'] as String? ?? 'cash', (sp['amount'] as num? ?? 0).toDouble());
          }
        }
      } else if (method == 'mixed') {
        final mps = (o['mixed_payments'] as List<dynamic>?)?.whereType<Map>().toList() ?? [];
        if (mps.isEmpty) {
          cash += amount;
        } else {
          for (final mp in mps) {
            suma(mp['method'] as String? ?? 'cash', (mp['amount'] as num? ?? 0).toDouble());
          }
        }
      } else {
        suma(method, amount);
      }
    }

    if (!found) return const VentasRecalculadas();
    return VentasRecalculadas(
      cash: cash,
      card: card,
      transfer: transfer,
      pedidosya: py,
      ubereats: ue,
      custom: customMap,
      hayPedidos: true,
    );
  }

  static double _montoDelPedido(Map<String, dynamic> o) {
    final pm = o['payment_amount'];
    if (pm is num && pm > 0) return pm.toDouble();
    if (pm is String) {
      final v = double.tryParse(pm);
      if (v != null && v > 0) return v;
    }
    final ta = o['total_amount'];
    if (ta is num) return ta.toDouble();
    if (ta is String) return double.tryParse(ta) ?? 0.0;
    return 0.0;
  }

  static DateTime? _aFecha(dynamic ts) {
    if (ts is DateTime) return ts.toLocal();
    if (ts is String) return DateTime.tryParse(ts)?.toLocal();
    if (ts is Timestamp) return ts.toDate().toLocal();
    try {
      return (ts as dynamic).toDate().toLocal() as DateTime;
    } catch (_) {}
    return null;
  }
}

/// Un corte cerrado, listo para dibujar.
class CierreCaja {
  final CashRegisterSummary caja;

  /// El signo de la moneda de su sucursal (las cajas no se convierten).
  final String signo;

  /// La moneda de su sucursal (su código, "GTQ"; si no se conoce, el signo). Es lo
  /// que se usa para agrupar: dos monedas pueden compartir signo ("$" de MXN y de
  /// USD) y una misma puede escribirse distinto ("Q" y "Q.").
  final String moneda;

  /// Sus ventas se recalcularon desde los pedidos del período (un corte antiguo
  /// sin diferencias selladas). Ese recálculo no distingue de qué cajero es cada
  /// pedido: con dos cajas abiertas a la vez en una sucursal, el mismo pedido sale
  /// en las dos. Por eso un total que las suma lo avisa.
  final bool recalculado;

  final double ventasEfectivo;
  final double ventasTarjeta;
  final double ventasTransferencia;
  final double ventasPedidosya;
  final double ventasUbereats;

  /// Las ventas de cada método propio (id → monto).
  final Map<String, double> ventasPropias;

  /// Lo contado menos lo esperado, de todos los métodos. Nulo si no se contó nada.
  final double? diferencia;

  /// La tabla "¿Cuadró la caja?".
  final List<FilaCuadre> cuadre;

  const CierreCaja._({
    required this.caja,
    required this.signo,
    required this.moneda,
    required this.recalculado,
    required this.ventasEfectivo,
    required this.ventasTarjeta,
    required this.ventasTransferencia,
    required this.ventasPedidosya,
    required this.ventasUbereats,
    required this.ventasPropias,
    required this.diferencia,
    required this.cuadre,
  });

  /// [pedidos]: los del período, sin convertir; solo se usan para recalcular un
  /// corte que no trae diferencias selladas.
  factory CierreCaja.desde(
    CashRegisterSummary r,
    List<Map<String, dynamic>> pedidos, {
    required String signo,
    String? moneda,
  }) {
    // Cuando el cierre tiene diferencias almacenadas (differenceCash != null), se
    // usan tal cual: son las calculadas desde los pedidos reales al cerrar. Si no
    // (cortes antiguos), se recalcula desde los pedidos. Una caja cerrada por
    // administrador tampoco se recalcula: al cerrarla se le guardó lo vendido,
    // sacado de sus propios pedidos.
    final selladas = r.differenceCash != null || r.cerradaPorAdmin;
    final calc = selladas ? const VentasRecalculadas() : VentasRecalculadas.desde(r, pedidos);
    final efectivo = calc.hayPedidos ? calc.cash : r.salesCash;
    final tarjeta = calc.hayPedidos ? calc.card : r.salesCard;
    final transferencia = calc.hayPedidos ? calc.transfer : r.salesTransfer;
    final pedidosya = calc.hayPedidos ? calc.pedidosya : r.salesPedidosya;
    final ubereats = calc.hayPedidos ? calc.ubereats : r.salesUbereats;
    // Las ventas de métodos propios: de los pedidos si se recalculó, si no las del
    // corte (ver CashRegisterSummary.ventasPropias).
    final propias = calc.hayPedidos ? calc.custom : r.ventasPropias;
    final totalVentas = calc.hayPedidos ? calc.total : r.totalSales;

    // La diferencia: la almacenada cuando hay diferencias selladas; si no, se
    // recalcula.
    double? dif = r.totalDifference;
    if (!selladas && calc.hayPedidos) {
      final hayContado = r.actualCash != null ||
          r.actualCard != null ||
          r.actualTransfer != null ||
          r.actualPedidosya != null ||
          r.actualUbereats != null ||
          r.actualCustomMethods.isNotEmpty;
      if (hayContado) {
        final contado = (r.actualCash ?? 0) -
            r.initialCash +
            (r.actualCard ?? 0) -
            r.initialCard +
            (r.actualTransfer ?? 0) -
            r.initialTransfer +
            (r.actualPedidosya ?? 0) -
            r.initialPedidosya +
            (r.actualUbereats ?? 0) -
            r.initialUbereats +
            r.actualCustomMethods.values.fold(0.0, (a, b) => a + b);
        dif = contado - totalVentas + r.totalWithdrawals - r.totalDeposits;
      }
    }

    return CierreCaja._(
      caja: r,
      signo: signo,
      moneda: moneda ?? signo,
      recalculado: calc.hayPedidos,
      ventasEfectivo: efectivo,
      ventasTarjeta: tarjeta,
      ventasTransferencia: transferencia,
      ventasPedidosya: pedidosya,
      ventasUbereats: ubereats,
      ventasPropias: propias,
      diferencia: dif,
      cuadre: _filasDeCuadre(r, efectivo, tarjeta, transferencia, pedidosya, ubereats, propias),
    );
  }

  static List<FilaCuadre> _filasDeCuadre(
    CashRegisterSummary r,
    double efectivo,
    double tarjeta,
    double transferencia,
    double pedidosya,
    double ubereats,
    Map<String, double> propias,
  ) {
    final filas = <FilaCuadre>[];
    // Cerrada por administrador: nadie contó, aunque haya algo guardado.
    final sinConteo = r.cerradaPorAdmin;

    void agrega(String metodo, double ventas, double? contado, double apertura,
        {double retiros = 0, double depositos = 0}) {
      final esperado = ventas - retiros + depositos;
      final contadoSinApertura = contado != null && !sinConteo ? contado - apertura : null;
      if (esperado == 0 && (contadoSinApertura == null || contadoSinApertura == 0)) return;
      filas.add(FilaCuadre(metodo, esperado, contadoSinApertura));
    }

    agrega('Efectivo', efectivo, r.actualCash, r.initialCash, retiros: r.totalWithdrawals, depositos: r.totalDeposits);
    agrega('Tarjeta', tarjeta, r.actualCard, r.initialCard);
    agrega('Transferencia', transferencia, r.actualTransfer, r.initialTransfer);
    agrega('PedidosYa', pedidosya, r.actualPedidosya, r.initialPedidosya);
    agrega('Uber Eats', ubereats, r.actualUbereats, r.initialUbereats);

    // En un corte sellado, lo contado de un método propio es esperado + su
    // diferencia sellada, como en el ticket del POS: uno que no se declaró sale con
    // su faltante, uno declarado sin ventas con su sobrante, y el de un cierre
    // forzado sin diferencia. Así la tabla suma lo mismo que la insignia.
    final sellado = r.differenceCash != null;
    propias.forEach((id, esperado) {
      final contado = sinConteo
          ? null
          : (sellado ? esperado + (r.differenceCustomMethods[id] ?? 0) : r.actualCustomMethods[id]);
      if (esperado.abs() < 0.005 && (contado ?? 0).abs() < 0.005) return;
      filas.add(FilaCuadre(nombreDelMetodo(r, id), esperado, contado));
    });
    return filas;
  }

  double get ventasPropiasTotal => ventasPropias.values.fold(0.0, (a, b) => a + b);

  /// Todo lo vendido en el corte, sin el fondo de apertura.
  double get ventas =>
      ventasEfectivo + ventasTarjeta + ventasTransferencia + ventasPedidosya + ventasUbereats + ventasPropiasTotal;

  /// Lo que no es efectivo ni tarjeta.
  double get ventasOtros => ventasTransferencia + ventasPedidosya + ventasUbereats + ventasPropiasTotal;

  double get apertura => caja.initialCash;
  double get depositos => caja.totalDeposits;
  double get retiros => caja.totalWithdrawals;

  /// El efectivo que debe haber en la gaveta: apertura + ventas + depósitos − retiros.
  double get totalEfectivo => apertura + ventasEfectivo + depositos - retiros;

  /// Lo mismo con todo lo vendido por los demás métodos. En el mismo orden de
  /// suma que la tarjeta de antes (a centavos no cambia, pero no se reordena).
  double get totalConApertura =>
      apertura +
      ventasEfectivo +
      depositos -
      retiros +
      ventasTarjeta +
      ventasTransferencia +
      ventasPedidosya +
      ventasUbereats +
      ventasPropiasTotal;

  /// Los demás métodos con ventas, en el orden en que se muestran (solo los que
  /// vendieron algo).
  List<(String, double)> get otrosMetodos => [
        if (ventasTarjeta > 0) ('Venta con tarjeta', ventasTarjeta),
        if (ventasTransferencia > 0) ('Venta con transferencia', ventasTransferencia),
        if (ventasPedidosya > 0) ('PedidosYa', ventasPedidosya),
        if (ventasUbereats > 0) ('Uber Eats', ventasUbereats),
        for (final e in ventasPropias.entries)
          if (e.value > 0) (nombreDelMetodo(caja, e.key), e.value),
      ];

  EstadoCierre get estado {
    if (caja.cerradaPorAdmin) return EstadoCierre.descuadrada;
    final d = diferencia;
    if (d == null) return EstadoCierre.sinContar;
    if (d.abs() < AtencionInicio.umbralFaltante) return EstadoCierre.cuadro;
    return d > 0 ? EstadoCierre.sobrante : EstadoCierre.faltante;
  }

  /// Cuánto faltó (positivo), o 0.
  double get faltante => estado == EstadoCierre.faltante ? -diferencia! : 0;

  /// Cuánto sobró (positivo), o 0.
  double get sobrante => estado == EstadoCierre.sobrante ? diferencia! : 0;

  /// Lo que escribió quien cerró para explicar la diferencia. Solo se muestra
  /// cuando la hay.
  String? get aclaracion {
    final notas = caja.closingNotes?.trim();
    if (notas == null || notas.isEmpty) return null;
    final d = diferencia;
    if (d == null || d.abs() < AtencionInicio.umbralFaltante) return null;
    return notas;
  }
}

/// Los totales de las cajas de UNA moneda.
class ResumenMoneda {
  final String signo;

  /// La moneda del grupo (ver [CierreCaja.moneda]); `signo` es solo para mostrar.
  final String moneda;
  final int cierres;
  final double ventas;
  final double efectivo;
  final double tarjeta;

  /// Transferencia, PedidosYa, Uber Eats y métodos propios.
  final double otros;
  final int conFaltante;
  final double faltante;
  final int conSobrante;
  final double sobrante;
  final int sinContar;

  /// Cerrados por un administrador sin contar el dinero.
  final int descuadradas;

  /// Cuántos de sus cierres se recalcularon desde los pedidos (cortes antiguos):
  /// sus ventas pueden repetir las de otro corte hecho a la vez.
  final int recalculados;
  final int abiertas;

  /// Las abiertas que llevan 24 h o más, la más vieja primero.
  final List<CashRegisterSummary> olvidadas;

  const ResumenMoneda({
    required this.signo,
    required this.moneda,
    required this.cierres,
    required this.ventas,
    required this.efectivo,
    required this.tarjeta,
    required this.otros,
    required this.conFaltante,
    required this.faltante,
    required this.conSobrante,
    required this.sobrante,
    required this.sinContar,
    required this.descuadradas,
    required this.recalculados,
    required this.abiertas,
    required this.olvidadas,
  });
}

/// El resumen del período, por moneda.
class ResumenCierres {
  final List<ResumenMoneda> porMoneda;

  /// Todas las cajas que nadie cerró (de cualquier moneda), la más vieja primero.
  final List<CashRegisterSummary> olvidadas;

  const ResumenCierres({required this.porMoneda, required this.olvidadas});

  /// [signoDeCaja]: el signo de la sucursal de cada caja. [ahora]: contra qué se
  /// mide cuánto lleva abierta una caja.
  static ResumenCierres desde({
    required List<CierreCaja> cierres,
    required List<CashRegisterSummary> abiertas,
    required String Function(String? locationId) signoDeCaja,
    required DateTime ahora,

    /// La moneda de cada sucursal (su código). Sin ella se agrupa por signo.
    String Function(String? locationId)? monedaDeCaja,
  }) {
    final monedaDe = monedaDeCaja ?? signoDeCaja;

    // Las monedas en el orden en que aparecen (primero las de los cierres), cada
    // una con el signo con que se muestra.
    final monedas = <String>[];
    final signos = <String, String>{};
    void ve(String moneda, String signo) {
      if (!signos.containsKey(moneda)) {
        monedas.add(moneda);
        signos[moneda] = signo;
      }
    }

    for (final c in cierres) {
      ve(c.moneda, c.signo);
    }
    for (final a in abiertas) {
      ve(monedaDe(a.locationId), signoDeCaja(a.locationId));
    }

    bool olvidada(CashRegisterSummary r) => ahora.difference(r.openedAt) >= AtencionInicio.cajaOlvidada;
    int masVieja(CashRegisterSummary a, CashRegisterSummary b) => a.openedAt.compareTo(b.openedAt);

    final grupos = <ResumenMoneda>[];
    for (final m in monedas) {
      final propios = cierres.where((c) => c.moneda == m).toList();
      final abiertasDeLaMoneda = abiertas.where((a) => monedaDe(a.locationId) == m).toList();
      final viejas = abiertasDeLaMoneda.where(olvidada).toList()..sort(masVieja);
      grupos.add(ResumenMoneda(
        signo: signos[m]!,
        moneda: m,
        cierres: propios.length,
        ventas: propios.fold(0.0, (a, c) => a + c.ventas),
        efectivo: propios.fold(0.0, (a, c) => a + c.ventasEfectivo),
        tarjeta: propios.fold(0.0, (a, c) => a + c.ventasTarjeta),
        otros: propios.fold(0.0, (a, c) => a + c.ventasOtros),
        conFaltante: propios.where((c) => c.estado == EstadoCierre.faltante).length,
        faltante: propios.fold(0.0, (a, c) => a + c.faltante),
        conSobrante: propios.where((c) => c.estado == EstadoCierre.sobrante).length,
        sobrante: propios.fold(0.0, (a, c) => a + c.sobrante),
        sinContar: propios.where((c) => c.estado == EstadoCierre.sinContar).length,
        descuadradas: propios.where((c) => c.estado == EstadoCierre.descuadrada).length,
        recalculados: propios.where((c) => c.recalculado).length,
        abiertas: abiertasDeLaMoneda.length,
        olvidadas: viejas,
      ));
    }
    return ResumenCierres(
      porMoneda: grupos,
      olvidadas: abiertas.where(olvidada).toList()..sort(masVieja),
    );
  }
}
