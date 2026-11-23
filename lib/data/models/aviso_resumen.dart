/// Cómo se lee un aviso de la bandeja: el título limpio, la línea de
/// descripción y las cifras que el diseño pone aparte (la pastilla, el monto),
/// sacados del texto que escribe el servidor.
///
/// El backend guarda de cada aviso solo `type`, `title`, `body` y un `data` con
/// ids: no guarda quién lo hizo, cuánto fue ni el nombre de la sucursal por
/// separado. Esos datos están DENTRO del `body`, que arman con plantillas las
/// Cloud Functions de `saborpro_app/functions/notifications/`. Aquí se leen con
/// expresiones regulares hechas contra esas plantillas.
///
/// Si el texto no calza con ninguna (otra versión de la función, un aviso
/// nuevo), la fila muestra el texto tal cual: nunca se esconde un aviso por no
/// entenderlo. Cambiar una plantilla allá sin tocar esto no rompe nada: solo
/// degrada a la fila simple.
library;

import 'manager_notification.dart';

/// El color de una pastilla o de un ícono del diseño.
enum TonoAviso { ok, warn, bad, blue, accent }

class PildoraAviso {
  final String texto;
  final TonoAviso tono;
  const PildoraAviso(this.texto, this.tono);
}

/// Lo que el texto de una entrada de inventario dice, para poder juntar las
/// que llegan seguidas (una carga de 8 productos son 8 avisos).
class DatosInventario {
  final String quien;

  /// 'entrada', 'salida' o 'ajuste'.
  final String movimiento;
  final String cantidad;
  final String producto;
  final String sucursal;

  const DatosInventario({
    required this.quien,
    required this.movimiento,
    required this.cantidad,
    required this.producto,
    required this.sucursal,
  });

  double? get cantidadNumero => double.tryParse(cantidad);

  /// "Entrada", "Salida" o "Ajuste".
  String get movimientoCapitalizado =>
      movimiento.isEmpty ? '' : movimiento[0].toUpperCase() + movimiento.substring(1);

  /// El signo con el que se escribe la cantidad: entra, sale o se corrige.
  String get signo => switch (movimiento) {
        'entrada' => '+',
        'salida' => '−',
        _ => '±',
      };
}

class AvisoResumen {
  /// Sin el emoji que mandan las funciones: el ícono ya dice lo mismo.
  final String titulo;
  final PildoraAviso? pildora;

  /// La línea chica bajo el título.
  final String descripcion;

  /// El monto que va a la derecha (o al inicio de la descripción en el
  /// teléfono): la venta de un cierre de caja, lo que salió en un retiro o un
  /// gasto. Ya con los miles separados.
  final String? monto;

  /// De qué color es el ícono.
  final TonoAviso tono;

  /// Solo en entradas de inventario que se pudieron leer.
  final DatosInventario? inventario;

  /// La descripción es el texto del servidor tal cual, porque no calzó con
  /// ninguna plantilla. Ese texto se muestra completo: cortarlo con puntos
  /// suspensivos sería esconder un aviso por no haberlo entendido.
  final bool crudo;

  const AvisoResumen({
    required this.titulo,
    this.pildora,
    required this.descripcion,
    this.monto,
    required this.tono,
    this.inventario,
    this.crudo = false,
  });

  // Un monto como lo escribe `conMoneda` en las funciones: "Q125.50", "$99.00",
  // "L1500.00", "C$100.00" y, con código de letras, "USD 99.00" (con espacio).
  static const _monto = r'(?:[A-Za-z]{2,} )?[^\s\d]{0,3}\d+(?:\.\d+)?';

  // Las plantillas, tal como las escriben las funciones.
  static final _reAbrio = RegExp(r'^(.+?) abrió caja en (.+)$');
  static final _reCerro = RegExp(
      r'^(.+?) cerró caja en (.+?)(?: con (faltante|sobrante) de (' +
          _monto +
          r'))?\. Venta total: (' +
          _monto +
          r')$');
  static final _reRetiro = RegExp(
      r'^(.+?) retiró (' + _monto + r') de la caja en (.+?)(?: — (.+))?$');
  static final _reRetiros = RegExp(
      r'^Se registraron (\d+) retiros por (' + _monto + r') en la caja de (.+?) en (.+)$');
  static final _reGasto = RegExp(
      r'^(.+?) registró un gasto de (' + _monto + r') \((.+)\) en (.+)$');
  static final _reInventario = RegExp(
      r'^(.+?) registró (entrada|salida|ajuste) de (\S+) en (.+) \(([^()]+)\)$');
  static final _reStock = RegExp(r'^(\d+) producto\(s\) con stock bajo: (.+)$');
  static final _reStockTitulo = RegExp(r'Stock bajo — (.+)$');

  static final _reEmoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2B00}-\u{2BFF}]',
    unicode: true,
  );

  /// Los títulos vienen con un emoji al frente desde las Cloud Functions ("🔓
  /// Caja abierta"). En la push suma, pero en una lista de treinta se vuelve
  /// una columna de caritas que compite con el ícono de color que ya dice lo
  /// mismo.
  static String quitarEmoji(String titulo) {
    final limpio = titulo.replaceAll(_reEmoji, '').trim();
    return limpio.isEmpty ? titulo.trim() : limpio;
  }

  /// "Q2172.00" → "Q2,172.00": el servidor no separa los miles y el diseño sí.
  /// El signo (o el código de letras, "USD ") se respeta tal cual. Si no se
  /// entiende, vuelve igual que llegó.
  static String formatearMonto(String crudo) {
    final m = RegExp(r'^(\D*?)(\d+)(\.\d+)?$').firstMatch(crudo);
    if (m == null) return crudo;
    final enteros = m.group(2)!;
    final conComas = enteros.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${m.group(1)}$conComas${m.group(3) ?? ''}';
  }

  static AvisoResumen de(ManagerNotification n) {
    final titulo = quitarEmoji(n.title);
    final body = n.body.trim();

    AvisoResumen simple(TonoAviso tono) =>
        AvisoResumen(titulo: titulo, descripcion: body, tono: tono, crudo: true);

    switch (n.tipo) {
      case ManagerNotificationType.cajaAbierta:
        final m = _reAbrio.firstMatch(body);
        if (m == null) return simple(TonoAviso.ok);
        return AvisoResumen(
          titulo: 'Caja abierta',
          descripcion: '${m.group(1)} · ${m.group(2)}',
          tono: TonoAviso.ok,
        );

      case ManagerNotificationType.cajaCerrada:
        final m = _reCerro.firstMatch(body);
        if (m == null) {
          // Sin poder leer el texto, el título ("Cuadró" / "Descuadre") y la
          // marca del payload todavía dicen lo importante.
          final cuadro = n.data['cuadro'];
          if (cuadro == 'true') {
            return AvisoResumen(
              titulo: 'Caja cerrada',
              pildora: const PildoraAviso('Cuadró', TonoAviso.ok),
              descripcion: body,
              tono: TonoAviso.ok,
              crudo: true,
            );
          }
          if (cuadro == 'false') {
            return AvisoResumen(
              titulo: 'Caja cerrada',
              pildora: const PildoraAviso('Descuadre', TonoAviso.warn),
              descripcion: body,
              tono: TonoAviso.warn,
              crudo: true,
            );
          }
          return simple(TonoAviso.ok);
        }
        final tipo = m.group(3);
        final dif = m.group(4);
        final PildoraAviso pildora;
        if (tipo == null) {
          pildora = const PildoraAviso('Cuadró', TonoAviso.ok);
        } else if (tipo == 'faltante') {
          pildora = PildoraAviso('Faltó ${formatearMonto(dif!)}', TonoAviso.bad);
        } else {
          pildora = PildoraAviso('Sobró ${formatearMonto(dif!)}', TonoAviso.warn);
        }
        return AvisoResumen(
          titulo: 'Caja cerrada',
          pildora: pildora,
          descripcion: '${m.group(1)} · ${m.group(2)}',
          monto: formatearMonto(m.group(5)!),
          // Un cierre que no cuadró se marca distinto del que cuadró: es el
          // único aviso que puede exigir una acción esa misma noche.
          tono: tipo == null ? TonoAviso.ok : TonoAviso.warn,
        );

      case ManagerNotificationType.retiro:
        final m = _reRetiro.firstMatch(body);
        if (m == null) return simple(TonoAviso.warn);
        final detalle = m.group(4);
        return AvisoResumen(
          titulo: 'Retiro de efectivo',
          descripcion: '${m.group(1)} · ${m.group(3)}'
              '${detalle == null ? '' : ' · $detalle'}',
          monto: formatearMonto(m.group(2)!),
          tono: TonoAviso.warn,
        );

      case ManagerNotificationType.retirosEnLote:
        final m = _reRetiros.firstMatch(body);
        if (m == null) return simple(TonoAviso.warn);
        return AvisoResumen(
          titulo: 'Retiros de efectivo',
          pildora: PildoraAviso(m.group(1)!, TonoAviso.warn),
          descripcion: '${m.group(3)} · ${m.group(4)}',
          monto: formatearMonto(m.group(2)!),
          tono: TonoAviso.warn,
        );

      case ManagerNotificationType.gasto:
        final m = _reGasto.firstMatch(body);
        if (m == null) return simple(TonoAviso.warn);
        return AvisoResumen(
          titulo: titulo,
          descripcion: '${m.group(1)} · ${m.group(3)} · ${m.group(4)}',
          monto: formatearMonto(m.group(2)!),
          tono: TonoAviso.warn,
        );

      case ManagerNotificationType.inventario:
        final m = _reInventario.firstMatch(body);
        if (m == null) return simple(TonoAviso.blue);
        final datos = DatosInventario(
          quien: m.group(1)!,
          movimiento: m.group(2)!,
          cantidad: m.group(3)!,
          producto: m.group(4)!,
          sucursal: m.group(5)!,
        );
        return AvisoResumen(
          titulo: '${datos.movimientoCapitalizado} de inventario',
          descripcion: '${datos.quien} · ${datos.signo}${datos.cantidad} '
              '${datos.producto} · ${datos.sucursal}',
          tono: TonoAviso.blue,
          inventario: datos,
        );

      case ManagerNotificationType.stockBajo:
        final m = _reStock.firstMatch(body);
        if (m == null) return simple(TonoAviso.bad);
        final sucursal = _reStockTitulo.firstMatch(titulo)?.group(1);
        return AvisoResumen(
          titulo: 'Stock bajo',
          pildora: PildoraAviso(m.group(1)!, TonoAviso.bad),
          descripcion: '${sucursal == null ? '' : '$sucursal · '}${m.group(2)}',
          tono: TonoAviso.bad,
        );

      case ManagerNotificationType.otro:
        return simple(TonoAviso.accent);
    }
  }
}
