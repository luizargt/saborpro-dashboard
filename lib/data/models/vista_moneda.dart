import '../../core/services/location_service.dart';
import '../../core/utils/monedas.dart';
import 'config_moneda.dart';

/// En qué moneda se ve lo que está en pantalla y cómo se pasa cada monto a
/// ella. Puro, sin Firestore: el DashboardProvider lo arma con las sucursales,
/// la que está elegida, la configuración del negocio y la preferencia.
///
/// Las reglas:
/// - Una sola moneda en vista (una sucursal, o "Todas" si venden en la misma)
///   se suma tal cual: en la suya si el dueño lo prefiere o si todavía no hay
///   tipo de cambio; si no, convertida a la principal.
/// - Varias monedas en vista se convierten SIEMPRE a la principal: sumarlas
///   tal cual no da nada. Las que no tienen tipo de cambio quedan fuera.
class VistaMoneda {
  VistaMoneda({
    required this.sucursales,
    required this.seleccionada,
    required this.config,
    required this.verEnLocal,
    this.ocultas = const [],
    this.bodegas = const [],
  });

  final List<LocationModel> sucursales;

  /// Sucursales que no salen en las pestañas (inactivas, bodegas) pero cuyas
  /// ventas viejas sí entran en "Todas". Sin esto se sumaban como si fueran de
  /// la moneda principal.
  final List<LocationModel> ocultas;

  /// Bodegas: no deciden si un negocio es "mixto" (una bodega creada con "Q"
  /// en un negocio de Honduras lo partía en dos monedas). Pero cuando la vista
  /// ya convierte por las sucursales que venden, entran como cualquier otra:
  /// se convierten (o, sin tipo de cambio, quedan fuera con aviso), igual en
  /// la vista de mes que en la de año.
  final List<LocationModel> bodegas;

  /// Nula = "Todas".
  final String? seleccionada;
  final ConfigMoneda config;
  final bool verEnLocal;

  /// La que eligió el dueño o, si no eligió, la que más sucursales usan.
  late final String principal = config.principal ?? _masUsada();

  String _masUsada() {
    if (sucursales.isEmpty) return 'GTQ';
    final cuantas = <String, int>{};
    for (final l in sucursales) {
      cuantas[l.currencyCode] = (cuantas[l.currencyCode] ?? 0) + 1;
    }
    // En empate, la primera que aparece (sucursales vienen ordenadas).
    var ganadora = sucursales.first.currencyCode;
    for (final e in cuantas.entries) {
      if (e.value > cuantas[ganadora]!) ganadora = e.key;
    }
    return ganadora;
  }

  late final bool hayOtraMoneda =
      [...sucursales, ...ocultas].any((l) => l.currencyCode != principal);

  /// Las que deciden si la vista convierte: las que venden.
  late final List<LocationModel> _vendenEnVista = seleccionada == null
      ? [...sucursales, ...ocultas]
      // Una sucursal sola puede ser una oculta o una bodega: un usuario
      // puede tenerla asignada.
      : [...sucursales, ...ocultas, ...bodegas].where((l) => l.id == seleccionada).take(1).toList();

  /// Todo lo que entra en la vista. En "Todas" convertida, también las
  /// bodegas (ver [bodegas]).
  late final List<LocationModel> enVista = seleccionada == null && convierte
      ? [..._vendenEnVista, ...bodegas.where((b) => !_vendenEnVista.any((l) => l.id == b.id))]
      : _vendenEnVista;

  late final Set<String> codigosEnVista = {for (final l in enVista) l.currencyCode};

  late final bool convierte = _convierte();

  bool _convierte() {
    final codigos = {for (final l in _vendenEnVista) l.currencyCode};
    if (codigos.isEmpty || codigos.every((c) => c == principal)) return false;
    if (codigos.length == 1 && (verEnLocal || !config.tieneTasa(codigos.single))) return false;
    return true;
  }

  /// La moneda en que se ven los montos.
  late final String codigoVista = convierte
      ? principal
      : (codigosEnVista.length == 1 ? codigosEnVista.single : principal);

  /// Se puede alternar entre la principal y la de la sucursal.
  late final bool puedeVerEnLocal = codigosEnVista.length == 1 &&
      codigosEnVista.single != principal &&
      config.tieneTasa(codigosEnVista.single);

  /// Fuera de los totales porque su moneda no tiene tipo de cambio.
  late final List<LocationModel> sinTasa = convierte
      ? enVista
          .where((l) => l.currencyCode != principal && !config.tieneTasa(l.currencyCode))
          .toList()
      : const [];

  /// Una sola moneda en vista, distinta de la principal y sin tipo de cambio.
  late final bool faltaTasaEnVista = codigosEnVista.length == 1 &&
      codigosEnVista.single != principal &&
      !config.tieneTasa(codigosEnVista.single);

  late final Map<String, String> _codigoPorSucursal = {
    for (final l in [...bodegas, ...ocultas, ...sucursales]) l.id: l.currencyCode,
  };

  /// La moneda de una sucursal. Una que ya no está activa no se sabe en qué
  /// vende: se toma como de la principal, igual que antes de que hubiera
  /// conversión.
  String codigoDe(String? locationId) => _codigoPorSucursal[locationId] ?? principal;

  /// Por cuánto se multiplica un monto de [locationId] cobrado en [fecha].
  /// Nulo = no hay tipo de cambio y ese monto no se suma.
  double? factorDe(String? locationId, DateTime? fecha) {
    if (!convierte) return 1;
    return config.factor(codigoDe(locationId), principal, fecha ?? DateTime.now());
  }

  /// Todo lo que decide la conversión. Si cambia, lo ya calculado no sirve.
  /// Sin conversión los números son los crudos, sea cual sea la moneda: solo
  /// cambia el signo, y eso no obliga a volver a pedir nada.
  late final String firma = convierte
      ? '$principal|${config.firma(principal, codigosEnVista, DateTime(1970), DateTime(2200))}'
          '|$_mapaEnVista'
      : 'local';

  /// Ordenado por id: renombrar o desactivar una sucursal no debe cambiar la
  /// firma (obligaría a rehacer todos los meses convertidos sin necesidad).
  String get _mapaEnVista =>
      (enVista.map((l) => '${l.id}:${l.currencyCode}').toList()..sort()).join(',');

  /// Huella de un mes guardado convertido: las tasas que lo tocan Y qué
  /// sucursal está en qué moneda (corregir la moneda de una sucursal cambia
  /// el mes aunque el conjunto de monedas siga igual). Vacía sin conversión,
  /// igual que los resúmenes de siempre.
  String firmaMes(int year, int month) => convierte
      ? '${config.firma(principal, codigosEnVista, DateTime(year, month, 1), DateTime(year, month + 1, 1))}'
          '|$_mapaEnVista'
      : '';

  /// Moneda con que se guardan los resúmenes convertidos (nula si no).
  String? get enMoneda => convierte ? principal : null;

  /// El signo de una moneda: el de las sucursales que la usan o, si ninguna,
  /// el de siempre ("US\$" para el dólar).
  String simboloDe(String codigo) {
    final usan = [for (final l in sucursales) if (l.currencyCode == codigo) l.currencySymbol];
    if (usan.isEmpty) return simboloDeCodigo(codigo);
    final cuantas = <String, int>{};
    for (final s in usan) {
      cuantas[s] = (cuantas[s] ?? 0) + 1;
    }
    var ganador = usan.first;
    for (final e in cuantas.entries) {
      if (e.value > cuantas[ganador]!) ganador = e.key;
    }
    return ganador;
  }
}
