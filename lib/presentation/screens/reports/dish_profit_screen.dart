import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../data/models/menu_margin_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/menu_margin_provider.dart';
import '../../providers/profitability_provider.dart';
import '../../widgets/dish_profit_card.dart';
import '../../widgets/dish_profit_widgets.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/period_selector.dart';

enum FiltroPlatillos {
  todos('Todos'),
  conUtilidad('Con utilidad'),
  // Separados a propósito: juntos invitaban a "quitar todo lo de este filtro",
  // y los que no cubren sus fijos sí aportan a la renta.
  pierden('Pierden'),
  noCubrenFijos('No cubren fijos'),
  conCosto('Con costo'),
  porRevisar('Por revisar'),
  incompletos('Falta costo'),
  sinReceta('Sin receta');

  final String etiqueta;
  const FiltroPlatillos(this.etiqueta);

  /// "Con utilidad", "Pierden" y "No cubren fijos" solo existen con gastos
  /// repartidos; sin reparto los reemplaza "Con costo".
  bool disponible(bool conReparto) => switch (this) {
        FiltroPlatillos.conUtilidad ||
        FiltroPlatillos.pierden ||
        FiltroPlatillos.noCubrenFijos =>
          conReparto,
        FiltroPlatillos.conCosto => !conReparto,
        _ => true,
      };

  bool acepta(FilaUtilidad f) => switch (this) {
        FiltroPlatillos.todos => true,
        FiltroPlatillos.conUtilidad =>
          f.confiable && f.desglose?.banda == Banda.cubreTodo,
        FiltroPlatillos.pierden =>
          f.confiable && f.desglose?.banda == Banda.pierde,
        FiltroPlatillos.noCubrenFijos =>
          f.confiable && f.desglose?.banda == Banda.noCubreFijos,
        FiltroPlatillos.conCosto => f.confiable,
        FiltroPlatillos.porRevisar => f.platillo.porRevisar,
        FiltroPlatillos.incompletos =>
          f.platillo.estado == EstadoCosto.incompleto,
        FiltroPlatillos.sinReceta => f.platillo.estado == EstadoCosto.sinReceta,
      };
}

enum OrdenPlatillos {
  menorPct('Menor utilidad (%) primero'),
  mayorPct('Mayor utilidad (%) primero'),
  mayorUtilidad('Mayor utilidad (Q) primero'),
  nombre('Nombre A–Z');

  final String etiqueta;
  const OrdenPlatillos(this.etiqueta);
}

/// Lo que el usuario eligió en la lista. Vive en la pantalla, FUERA de la
/// parte que se re-crea al cambiar de sucursal: comparar un platillo entre
/// sucursales no puede costar volver a buscarlo y volver a abrirlo.
class VistaUtilidadPlatillos extends ChangeNotifier {
  FiltroPlatillos _filtro = FiltroPlatillos.todos;
  OrdenPlatillos _orden = OrdenPlatillos.menorPct;
  final campo = TextEditingController();
  final abiertos = <String>{};

  FiltroPlatillos get filtro => _filtro;
  OrdenPlatillos get orden => _orden;
  String get busqueda => campo.text;

  set filtro(FiltroPlatillos f) {
    _filtro = f;
    notifyListeners();
  }

  set orden(OrdenPlatillos o) {
    _orden = o;
    notifyListeners();
  }

  void buscar(String _) => notifyListeners();

  void limpiarBusqueda() {
    campo.clear();
    notifyListeners();
  }

  void alternar(String clave) {
    if (!abiertos.remove(clave)) abiertos.add(clave);
    notifyListeners();
  }

  /// El filtro elegido, o "Todos" si con el período actual ya no existe.
  FiltroPlatillos filtroEfectivo(bool conReparto) =>
      _filtro.disponible(conReparto) ? _filtro : FiltroPlatillos.todos;

  @override
  void dispose() {
    campo.dispose();
    super.dispose();
  }
}

/// Las filas que se ven, en el orden en que se ven.
///
/// Primero las confiables, ordenadas; después las que tienen el costo mal
/// cargado; al final las incompletas y las sin receta, por nombre. Un costo
/// absurdo arriba de todo ("−620%") taparía lo que importa.
List<FilaUtilidad> filasVisibles(UtilidadMenu d, VistaUtilidadPlatillos v) {
  final filtro = v.filtroEfectivo(d.conReparto);
  final q = v.busqueda.trim().toLowerCase();
  final lista = d.filas
      .where(filtro.acepta)
      .where((f) => q.isEmpty || f.platillo.nombre.toLowerCase().contains(q))
      .toList();

  int grupo(FilaUtilidad f) {
    if (f.confiable) return 0;
    if (f.platillo.estado == EstadoCosto.completo) return 1;
    if (f.platillo.estado == EstadoCosto.incompleto) return 2;
    return 3;
  }

  int porNombre(FilaUtilidad a, FilaUtilidad b) =>
      a.platillo.nombre.toLowerCase().compareTo(b.platillo.nombre.toLowerCase());

  int porValor(num? a, num? b, {required bool asc}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return asc ? a.compareTo(b) : b.compareTo(a);
  }

  lista.sort((a, b) {
    if (v.orden == OrdenPlatillos.nombre) return porNombre(a, b);
    final g = grupo(a).compareTo(grupo(b));
    if (g != 0) return g;
    final c = switch (v.orden) {
      OrdenPlatillos.menorPct => porValor(a.pct, b.pct, asc: true),
      OrdenPlatillos.mayorPct => porValor(a.pct, b.pct, asc: false),
      OrdenPlatillos.mayorUtilidad =>
        porValor(a.utilidad, b.utilidad, asc: false),
      OrdenPlatillos.nombre => 0,
    };
    return c != 0 ? c : porNombre(a, b);
  });
  return lista;
}

/// La lista completa, conectada a los providers que le pasa Rentabilidad.
class UtilidadPlatillosScreen extends StatefulWidget {
  const UtilidadPlatillosScreen({super.key});

  @override
  State<UtilidadPlatillosScreen> createState() =>
      _UtilidadPlatillosScreenState();
}

class _UtilidadPlatillosScreenState extends State<UtilidadPlatillosScreen> {
  final _vista = VistaUtilidadPlatillos();

  @override
  void dispose() {
    _vista.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final rentabilidad = context.watch<ProfitabilityProvider>();
    final menu = context.watch<MenuMarginProvider>();

    // Si el usuario cambia el período o la sucursal desde aquí, los gastos se
    // recalculan aunque Rentabilidad quede debajo, tapada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      rentabilidad.loadIfNeeded(dash);
      final tenant = dash.tenantId;
      if (tenant != null) menu.cargarSiHaceFalta(tenant);
    });

    return Scaffold(
      backgroundColor: kFondo,
      appBar: AppBar(
        backgroundColor: kBarra,
        elevation: 0,
        title: const Text('Utilidad por platillo'),
      ),
      body: SafeArea(
        top: false,
        child: LocationSwipeArea(
          child: MaxContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SelectorFechaEnTelefono(),
                const LocationHeaderBar(),
                Expanded(
                  child: UtilidadPlatillosView(
                    datos: construirUtilidad(dash, rentabilidad, menu),
                    cargando: menu.cargando && !menu.listo,
                    error: menu.error,
                    vista: _vista,
                    periodo: dash.range.label,
                    calculandoGastos: calculandoGastos(dash, rentabilidad),
                    errorGastos: rentabilidad.error != null,
                    vistaTodas: esVistaTodas(dash),
                    onRefresh: () => Future.wait([
                      dash.load().then((_) => rentabilidad.load(dash)),
                      menu.recargar(),
                    ]),
                    envolverLista: (l) => LocationContentSwitcher(child: l),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La lista tal como se ve, sin providers: se prueba a 360dp.
class UtilidadPlatillosView extends StatelessWidget {
  final UtilidadMenu? datos;
  final bool cargando;
  final String? error;
  final VistaUtilidadPlatillos vista;
  final String periodo;
  final bool calculandoGastos;
  final bool errorGastos;
  final bool vistaTodas;
  final Future<void> Function()? onRefresh;

  /// Envuelve SOLO la lista (no los filtros ni el buscador). La pantalla le
  /// pone la animación de cambio de sucursal, que re-crea lo que envuelve.
  final Widget Function(Widget lista)? envolverLista;

  const UtilidadPlatillosView({
    super.key,
    required this.datos,
    this.cargando = false,
    this.error,
    required this.vista,
    required this.periodo,
    this.calculandoGastos = false,
    this.errorGastos = false,
    this.vistaTodas = false,
    this.onRefresh,
    this.envolverLista,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vista,
      builder: (context, _) {
        final d = datos;
        final conReparto = d?.conReparto ?? false;
        final filtros =
            FiltroPlatillos.values.where((f) => f.disponible(conReparto));
        final actual = vista.filtroEfectivo(conReparto);

        Widget lista = _Lista(
          datos: d,
          cargando: cargando,
          error: error,
          vista: vista,
          periodo: periodo,
          calculandoGastos: calculandoGastos,
          errorGastos: errorGastos,
          vistaTodas: vistaTodas,
        );
        if (onRefresh != null) {
          lista = RefreshIndicator(
            color: kAcento,
            backgroundColor: kTarjeta,
            onRefresh: onRefresh!,
            child: lista,
          );
        }
        if (envolverLista != null) lista = envolverLista!(lista);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final f in filtros) ...[
                    ChipFiltro(
                      etiqueta: d == null
                          ? f.etiqueta
                          : '${f.etiqueta} ${d.filas.where(f.acepta).length}',
                      activo: f == actual,
                      // Un filtro vacío no se esconde (cambiaría el orden de
                      // los chips bajo el dedo): se apaga.
                      deshabilitado: d == null ||
                          (f != FiltroPlatillos.todos &&
                              !d.filas.any(f.acepta)),
                      onTap: () => vista.filtro = f,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: vista.campo,
                      onChanged: vista.buscar,
                      textInputAction: TextInputAction.search,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style:
                          GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: kTarjeta,
                        hintText: 'Buscar platillo',
                        hintStyle: GoogleFonts.inter(
                            color: Colors.white54, fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white54, size: 20),
                        suffixIcon: vista.busqueda.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white54, size: 18),
                                onPressed: vista.limpiarBusqueda,
                              ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<OrdenPlatillos>(
                    tooltip: 'Ordenar',
                    color: kTarjeta,
                    icon: const Icon(Icons.sort_rounded, color: Colors.white70),
                    initialValue: vista.orden,
                    onSelected: (o) => vista.orden = o,
                    itemBuilder: (_) => [
                      for (final o in OrdenPlatillos.values)
                        PopupMenuItem(
                          value: o,
                          child: Text(
                            o.etiqueta,
                            style: GoogleFonts.inter(
                              color: o == vista.orden
                                  ? kAcentoTexto
                                  : Colors.white70,
                              fontSize: 13.5,
                              fontWeight: o == vista.orden
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: lista),
          ],
        );
      },
    );
  }
}

class _Lista extends StatelessWidget {
  final UtilidadMenu? datos;
  final bool cargando;
  final String? error;
  final VistaUtilidadPlatillos vista;
  final String periodo;
  final bool calculandoGastos;
  final bool errorGastos;
  final bool vistaTodas;

  const _Lista({
    required this.datos,
    required this.cargando,
    required this.error,
    required this.vista,
    required this.periodo,
    required this.calculandoGastos,
    required this.errorGastos,
    required this.vistaTodas,
  });

  @override
  Widget build(BuildContext context) {
    final d = datos;
    final fondo = MediaQuery.paddingOf(context).bottom;

    if (d == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 100),
          if (error != null && !cargando) ...[
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white54, size: 34),
            const SizedBox(height: 14),
            Text(error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 14, height: 1.45)),
            const SizedBox(height: 6),
            Text('Deslizá hacia abajo para reintentar.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5)),
          ] else
            const Center(child: CircularProgressIndicator(color: kAcento)),
        ],
      );
    }

    final visibles = filasVisibles(d, vista);
    final vacio = visibles.isEmpty;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + fondo),
      itemCount: 1 + (vacio ? 1 : visibles.length),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _Encabezado(
            datos: d,
            periodo: periodo,
            calculandoGastos: calculandoGastos,
            errorGastos: errorGastos,
            vistaTodas: vistaTodas,
            error: error,
          );
        }
        if (vacio) return _SinResultados(vista: vista);
        final f = visibles[i - 1];
        return FilaPlatillo(
          key: ValueKey(f.platillo.clave),
          fila: f,
          reparto: d.reparto,
          abierta: vista.abiertos.contains(f.platillo.clave),
          onToggle: () => vista.alternar(f.platillo.clave),
        );
      },
    );
  }
}

class _Encabezado extends StatelessWidget {
  final UtilidadMenu datos;
  final String periodo;
  final bool calculandoGastos;
  final bool errorGastos;
  final bool vistaTodas;
  final String? error;

  const _Encabezado({
    required this.datos,
    required this.periodo,
    required this.calculandoGastos,
    required this.errorGastos,
    required this.vistaTodas,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle estilo(Color c) =>
        GoogleFonts.inter(color: c, fontSize: 11.5, height: 1.45);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResumenReparto(
            reparto: datos.reparto,
            periodo: periodo,
            calculando: calculandoGastos,
            errorGastos: errorGastos,
            vistaTodas: vistaTodas,
          ),
          const SizedBox(height: 8),
          Text(
            'Costo: lo que pide la receta al último precio de compra, como lo '
            'descuenta el POS (sin merma, extras ni desechables). Precio con '
            'IVA: lo que te queda es antes de impuestos. Todo es por venta.',
            style: estilo(Colors.white60),
          ),
          if (datos.descartados > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(textoDescartados(datos.descartados),
                  style: estilo(Colors.white60)),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'No se pudo actualizar el menú: se muestran los datos '
                  'anteriores. Deslizá hacia abajo para reintentar.',
                  style: estilo(kAmbar)),
            ),
        ],
      ),
    );
  }
}

class _SinResultados extends StatelessWidget {
  final VistaUtilidadPlatillos vista;
  const _SinResultados({required this.vista});

  @override
  Widget build(BuildContext context) {
    final buscando = vista.busqueda.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            buscando
                ? 'Ningún platillo coincide con "${vista.busqueda.trim()}"'
                : 'Ningún platillo en este filtro',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5),
          ),
          if (buscando)
            TextButton(
              onPressed: vista.limpiarBusqueda,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text('Limpiar búsqueda',
                  style: GoogleFonts.inter(
                      color: kAcentoTexto, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
