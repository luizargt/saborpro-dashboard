/// La navegación del teléfono (diseño `sidebar-manager.html`, móvil): la barra
/// inferior flotante con cinco pestañas y la hoja "Reportes" que lista los reportes con
/// su dato de hoy. (La línea de arriba, con el logo y el nombre de la vista, es
/// `EncabezadoMovil`; la cuenta y la búsqueda están en "Más".)
///
/// Sin providers ni Firebase: se prueba en test/presentation/widgets/
/// barra_inferior_test.dart.
library;

import 'package:flutter/material.dart';

import '../navigation/destinos.dart';
import 'barra_lateral.dart' show kRojoContador;
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Las cinco pestañas, en el orden en que se ven: lo de todos los días primero
/// (Inicio y Despensa), después los reportes y los avisos, y al final la cuenta.
enum PestanaMovil { inicio, despensa, reportes, avisos, mas }

/// Qué pestaña se enciende según dónde se está: los reportes encienden "Reportes", y las
/// notificaciones y las descargas (cosas de la cuenta), "Más".
PestanaMovil pestanaDe(Destino d) {
  if (Destinos.esReporte(d)) return PestanaMovil.reportes;
  return switch (d) {
    Destino.inicio => PestanaMovil.inicio,
    Destino.despensa => PestanaMovil.despensa,
    Destino.avisos => PestanaMovil.avisos,
    _ => PestanaMovil.mas,
  };
}

/// La barra inferior flotante.
class BarraInferiorMovil extends StatelessWidget {
  final PestanaMovil actual;
  final int avisosSinLeer;
  final ValueChanged<PestanaMovil> onElegir;

  const BarraInferiorMovil({super.key, required this.actual, required this.avisosSinLeer, required this.onElegir});

  /// Lo que mide la barra con su margen de abajo (sin el borde del sistema): el
  /// contenido deja ese hueco para no quedar tapado.
  static const alto = 86.0;

  static const _pestanas = [
    (PestanaMovil.inicio, 'Inicio', Icons.home_outlined),
    (PestanaMovil.despensa, 'Despensa', Icons.inventory_2_outlined),
    (PestanaMovil.reportes, 'Reportes', Icons.bar_chart_rounded),
    (PestanaMovil.avisos, 'Avisos', Icons.notifications_none_rounded),
    (PestanaMovil.mas, 'Más', Icons.more_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _C.barra,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _C.barraLinea),
        boxShadow: [BoxShadow(color: _C.sombra, blurRadius: 60, offset: const Offset(0, 24))],
      ),
      child: Row(
        children: [
          for (final (p, nombre, icono) in _pestanas)
            Expanded(
              child: Semantics(
                button: true,
                selected: p == actual,
                label: nombre,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onElegir(p),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 7),
                    decoration: BoxDecoration(color: p == actual ? _C.barraActivo : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(icono, size: 20, color: p == actual ? _C.barraActivoIcono : _C.barraApagado),
                            if (p == PestanaMovil.avisos && avisosSinLeer > 0)
                              Positioned(
                                left: 11,
                                top: -8,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: kRojoContador, borderRadius: BorderRadius.circular(999)),
                                  child: Text(avisosSinLeer > 99 ? '99+' : '$avisosSinLeer', maxLines: 1, style: _t(10, FontWeight.w700, const Color(0xFFFFFFFF), height: 1.1)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11, FontWeight.w600, p == actual ? _C.barraActivoTexto : _C.barraApagado, height: 1.3)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La hoja que se abre desde abajo (con su manija), como las del diseño.
Future<T?> mostrarHojaManager<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _C.card,
    barrierColor: const Color(0x730A0C1C),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: _C.line, borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 12),
          builder(context),
        ],
      ),
    ),
  );
}

/// El contenido de la hoja "Reportes": cada reporte con su dato de hoy.
class HojaReportes extends StatelessWidget {
  final Destino actual;

  /// El dato de hoy de cada reporte, si se sabe ("Q842 hoy"). Sin dato, la fila dice
  /// de qué trata el reporte.
  final Map<Destino, String> datos;

  /// Los que llevan el dato en rojo (hay algo que revisar).
  final Set<Destino> alertas;

  final ValueChanged<Destino> onElegir;

  const HojaReportes({super.key, required this.actual, required this.datos, required this.alertas, required this.onElegir});

  @override
  Widget build(BuildContext context) {
    Widget grupo(String titulo, List<Destino> lista) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(titulo.toUpperCase(), style: _t(11, FontWeight.w700, _C.soft).copyWith(letterSpacing: 0.77)),
            ),
            for (final d in lista)
              Material(
                color: d == actual ? _C.tint : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onElegir(d),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 62),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: d == actual ? 10 : 4, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: d == actual ? _C.card : _C.subtle, borderRadius: BorderRadius.circular(12)),
                            child: Icon(Destinos.icono(d), size: 19, color: d == actual ? _C.accent : _C.muted),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(Destinos.nombre(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(15, FontWeight.w600, _C.ink, height: 1.3)),
                                Text(
                                  datos[d] ?? Destinos.descripcion(d),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(12.5, alertas.contains(d) ? FontWeight.w600 : FontWeight.w400, alertas.contains(d) ? _C.bad : _C.muted, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 18, color: _C.soft),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 0), child: Text('Reportes', style: _t(19, FontWeight.w700, _C.ink, height: 1.3))),
        grupo('Dinero', Destinos.deSeccion(SeccionNav.dinero)),
        grupo('Control y pérdidas', Destinos.deSeccion(SeccionNav.control)),
      ],
    );
  }
}
