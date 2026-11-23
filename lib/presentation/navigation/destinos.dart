/// A dónde se puede ir en Sabor Manager y cómo se llama cada lugar: la barra lateral,
/// la barra inferior, las hojas del teléfono y la paleta de comandos salen de AQUÍ
/// (diseño `sidebar-manager.html`), para que se llamen y se ordenen igual en todos.
///
/// Dart puro (solo los íconos son de Flutter): se prueba sin pantalla.
library;

import 'package:flutter/material.dart';

/// Cada lugar al que se puede ir.
enum Destino {
  inicio,
  avisos,
  despensa,
  rentabilidad,
  comprasVentas,
  gastos,
  cierres,
  propinas,
  cortesias,
  cancelados,

  /// Qué avisos llegan al teléfono (ajustes de notificaciones).
  notificaciones,

  /// No es una pantalla: abre el diálogo de descargas.
  descargas,
}

/// Cómo se agrupan en la barra lateral.
enum SeccionNav { general, dinero, control }

class InfoDestino {
  final String nombre;
  final IconData icono;
  final SeccionNav? seccion;

  /// Una línea de lo que muestra (para las hojas del teléfono cuando no hay un dato
  /// de hoy que ponerle).
  final String descripcion;

  const InfoDestino(this.nombre, this.icono, this.seccion, this.descripcion);
}

abstract final class Destinos {
  static const info = <Destino, InfoDestino>{
    Destino.inicio: InfoDestino('Inicio', Icons.home_outlined, SeccionNav.general, 'Cómo va el día'),
    Destino.avisos: InfoDestino('Avisos', Icons.notifications_none_rounded, SeccionNav.general, 'Lo que pasó mientras no mirabas'),
    Destino.despensa: InfoDestino('Despensa', Icons.inventory_2_outlined, SeccionNav.general, 'Lo que hay en bodega y lo que falta'),
    Destino.rentabilidad: InfoDestino('Rentabilidad', Icons.trending_up_rounded, SeccionNav.dinero, 'Cuánto ganas después de costos y gastos'),
    Destino.comprasVentas: InfoDestino('Compras vs Ventas', Icons.compare_arrows_rounded, SeccionNav.dinero, 'Cuánto ganas con la mercadería que compras'),
    Destino.gastos: InfoDestino('Gastos', Icons.receipt_long_rounded, SeccionNav.dinero, 'En qué se fue el dinero del negocio'),
    Destino.cierres: InfoDestino('Cierres de caja', Icons.point_of_sale_rounded, SeccionNav.dinero, 'Lo que cuadró, faltó o sobró en cada caja'),
    Destino.propinas: InfoDestino('Propinas', Icons.paid_outlined, SeccionNav.dinero, 'Quién recibe más y a qué hora se deja más'),
    Destino.cortesias: InfoDestino('Cortesías y donaciones', Icons.card_giftcard_rounded, SeccionNav.control, 'Lo que se regaló, quién y por qué'),
    Destino.cancelados: InfoDestino('Pedidos cancelados', Icons.cancel_outlined, SeccionNav.control, 'Lo anulado y el producto que se perdió'),
    Destino.notificaciones: InfoDestino('Notificaciones', Icons.notifications_active_outlined, null, 'Qué avisos te llegan al teléfono'),
    Destino.descargas: InfoDestino('Descargar reportes', Icons.file_download_outlined, null, 'Reportes en Excel'),
  };

  static String nombre(Destino d) => info[d]!.nombre;
  static IconData icono(Destino d) => info[d]!.icono;
  static String descripcion(Destino d) => info[d]!.descripcion;

  /// Los de una sección, en el orden de la barra.
  static List<Destino> deSeccion(SeccionNav s) => [
        for (final d in Destino.values)
          if (info[d]!.seccion == s) d,
      ];

  /// El título de una sección en la barra lateral.
  static String tituloDeSeccion(SeccionNav s) => switch (s) {
        SeccionNav.general => 'General',
        SeccionNav.dinero => 'Reportes · Dinero',
        SeccionNav.control => 'Control y pérdidas',
      };

  /// Los reportes: lo que cuelga de "Reportes" en el teléfono.
  static bool esReporte(Destino d) {
    final s = info[d]!.seccion;
    return s == SeccionNav.dinero || s == SeccionNav.control;
  }

  /// Si es una pantalla (y no una acción como las descargas).
  static bool esPantalla(Destino d) => d != Destino.descargas;

  /// El grupo con que sale en la paleta de comandos.
  static String grupoDeBusqueda(Destino d) => switch (info[d]!.seccion) {
        SeccionNav.general => 'Ir a',
        SeccionNav.dinero => 'Reportes · Dinero',
        SeccionNav.control => 'Reportes · Control',
        null => 'Cuenta',
      };

  /// La pestaña que pide una notificación tocada (`pestanaSolicitada`): 0 Inicio,
  /// 1 Reportes, 2 Despensa, 3 Avisos. "Reportes" ya no es una página: abre el primero.
  static Destino? dePestana(int pestana) => switch (pestana) {
        0 => Destino.inicio,
        1 => Destino.rentabilidad,
        2 => Destino.despensa,
        3 => Destino.avisos,
        _ => null,
      };

  /// "Buenos días", "Buenas tardes", "Buenas noches".
  static String saludo(int hora) => hora < 12 ? 'Buenos días' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

  /// El nombre de pila ("Luis Arreago" → "Luis"); null si no hay nombre.
  static String? primerNombre(String? nombre) {
    final n = nombre?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  /// La línea chica sobre el título: el saludo en Inicio, y en los demás el grupo.
  static String miga(Destino d, {required int hora, String? nombre}) {
    switch (d) {
      case Destino.inicio:
        final n = primerNombre(nombre);
        return n == null ? saludo(hora) : '${saludo(hora)}, $n';
      case Destino.notificaciones:
        return 'Avisos';
      case Destino.avisos:
      case Destino.despensa:
        return 'General';
      case Destino.descargas:
        return 'Cuenta';
      default:
        return grupoDeBusqueda(d);
    }
  }

  /// Si en el encabezado va el selector de fecha. Avisos y los ajustes de
  /// notificaciones no dependen del período, y Despensa muestra las existencias de
  /// HOY (ahí el selector no tendría efecto y solo confundiría).
  static bool muestraFecha(Destino d) => d != Destino.avisos && d != Destino.notificaciones && d != Destino.despensa && d != Destino.descargas;

  /// "Configurar avisos" solo en Avisos.
  static bool muestraConfigurarAvisos(Destino d) => d == Destino.avisos;

  /// Sin tildes ni mayúsculas, para buscar.
  static String sinTildes(String s) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';
    final b = StringBuffer();
    for (final c in s.toLowerCase().split('')) {
      final i = con.indexOf(c);
      b.write(i >= 0 ? sin[i] : c);
    }
    return b.toString();
  }

  /// A dónde se puede ir: lo de la barra en su orden, y lo de la cuenta.
  static List<Destino> get todos => [
        ...deSeccion(SeccionNav.general),
        ...deSeccion(SeccionNav.dinero),
        ...deSeccion(SeccionNav.control),
        Destino.descargas,
        Destino.notificaciones,
      ];

  /// Lo que coincide con lo que se escribió (sin importar tildes ni mayúsculas).
  /// Sin nada escrito, todo.
  static List<Destino> buscar(String consulta) {
    final q = sinTildes(consulta.trim());
    return [
      for (final d in todos)
        if (q.isEmpty || sinTildes(nombre(d)).contains(q)) d,
    ];
  }
}
