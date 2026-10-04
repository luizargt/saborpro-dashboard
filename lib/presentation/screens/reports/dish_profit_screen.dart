import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../data/models/menu_margin_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/menu_margin_provider.dart';
import '../../providers/profitability_provider.dart';
import '../../widgets/dish_profit_card.dart';
import '../../widgets/dish_profit_table.dart';
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

/// Lo que el usuario eligió en la tabla. Vive en la pantalla, FUERA de la
/// parte que se re-crea al cambiar de sucursal: comparar un platillo entre
/// sucursales no puede costar volver a buscarlo y volver a ordenar.
class VistaUtilidadPlatillos extends ChangeNotifier {
  FiltroPlatillos _filtro = FiltroPlatillos.todos;

  /// Por defecto, de la menor ganancia en % a la mayor: lo que hay que mirar
  /// primero queda arriba.
  ColumnaOrden _columna = ColumnaOrden.pct;
  bool _ascendente = true;
  final campo = TextEditingController();

  FiltroPlatillos get filtro => _filtro;
  ColumnaOrden get columna => _columna;
  bool get ascendente => _ascendente;
  String get busqueda => campo.text;

  set filtro(FiltroPlatillos f) {
    _filtro = f;
    notifyListeners();
  }

  /// Como en una hoja de cálculo: tocar otra columna ordena por ella de menor
  /// a mayor; tocar la misma invierte el orden.
  void ordenarPor(ColumnaOrden c) {
    if (c == _columna) {
      _ascendente = !_ascendente;
    } else {
      _columna = c;
      _ascendente = true;
    }
    notifyListeners();
  }

  void buscar(String _) => notifyListeners();

  void limpiarBusqueda() {
    campo.clear();
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

/// Las filas que se ven, en el orden en que se ven. Lo que no tiene cifra en
/// la columna elegida va siempre al final: primero los datos por revisar,
/// después los que les falta costo y al final los sin receta.
List<FilaUtilidad> filasVisibles(UtilidadMenu d, VistaUtilidadPlatillos v) {
  final filtro = v.filtroEfectivo(d.conReparto);
  final q = v.busqueda.trim().toLowerCase();
  final lista = d.filas
      .where(filtro.acepta)
      .where((f) => q.isEmpty || f.platillo.nombre.toLowerCase().contains(q))
      .toList();

  int porNombre(FilaUtilidad a, FilaUtilidad b) =>
      a.platillo.nombre.toLowerCase().compareTo(b.platillo.nombre.toLowerCase());

  int grupo(FilaUtilidad f) {
    if (f.confiable) return 0;
    if (f.platillo.estado == EstadoCosto.completo) return 1;
    if (f.platillo.estado == EstadoCosto.incompleto) return 2;
    return 3;
  }

  // El valor por el que se ordena es el que SE VE en la columna: un dato por
  // revisar dice "Revisar" y uno sin precio "—", así que no tienen cifra y van
  // al final. Ordenarlos por su número escondido dejaba un Q15.09 arriba de un
  // −Q13.98 sin explicación a la vista.
  num? valor(FilaUtilidad f) {
    final d = f.desglose;
    final sinCifraDeGanancia = f.platillo.porRevisar || f.pct == null;
    return switch (v.columna) {
      ColumnaOrden.producto => null,
      ColumnaOrden.costo => f.platillo.costo,
      ColumnaOrden.gasto =>
        d == null ? null : d.descuento + d.variables + d.fijos,
      ColumnaOrden.precio => f.platillo.precio,
      ColumnaOrden.ganancia => sinCifraDeGanancia ? null : f.utilidad,
      ColumnaOrden.pct => sinCifraDeGanancia ? null : f.pct,
    };
  }

  lista.sort((a, b) {
    if (v.columna == ColumnaOrden.producto) {
      final c = porNombre(a, b);
      return v.ascendente ? c : -c;
    }
    final va = valor(a), vb = valor(b);
    if (va == null && vb == null) {
      final g = grupo(a).compareTo(grupo(b));
      return g != 0 ? g : porNombre(a, b);
    }
    if (va == null) return 1;
    if (vb == null) return -1;
    final c = v.ascendente ? va.compareTo(vb) : vb.compareTo(va);
    return c != 0 ? c : porNombre(a, b);
  });
  return lista;
}

/// Hoja inferior con scroll propio, para la guía y los consejos.
Future<void> _abrirHoja(BuildContext context, Widget contenido) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kTarjeta,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          contenido,
        ],
      ),
    ),
  );
}

/// La tabla completa, conectada a los providers que le pasa Rentabilidad.
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
      // Sin LocationSwipeArea a propósito: la tabla se desliza de lado y se
      // quedaba con el gesto, salvo en la línea de resumen, donde deslizar
      // cambiaba de sucursal sin querer. Las pestañas siguen arriba.
      body: SafeArea(
        top: false,
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
    );
  }
}

/// La tabla tal como se ve, sin providers: se prueba a 360dp.
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

  /// Envuelve SOLO la tabla (no los filtros ni el buscador). La pantalla le
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

  void _abrirGuia(BuildContext context) => _abrirHoja(
        context,
        GuiaUtilidad(
          reparto: datos?.reparto,
          periodo: periodo,
          calculando: calculandoGastos,
          errorGastos: errorGastos,
          vistaTodas: vistaTodas,
          descartados: datos?.descartados ?? 0,
          errorMenu: datos == null ? null : error,
        ),
      );

  void _abrirPlatillo(BuildContext context, FilaUtilidad f) =>
      _abrirHoja(context, ConsejosPlatillo(fila: f, reparto: datos?.reparto));

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
        final resumen = resumenCorto(d?.reparto,
            calculando: calculandoGastos, errorGastos: errorGastos);
        final avisos = hayAvisos(d?.reparto,
                errorGastos: errorGastos, vistaTodas: vistaTodas) ||
            (d != null && error != null);

        Widget cuerpo;
        if (d == null) {
          cuerpo = _SinMenu(cargando: cargando, error: error);
          if (onRefresh != null) {
            cuerpo = RefreshIndicator(
              color: kAcento,
              backgroundColor: kTarjeta,
              onRefresh: onRefresh!,
              child: cuerpo,
            );
          }
        } else {
          final visibles = filasVisibles(d, vista);
          if (visibles.isEmpty) {
            cuerpo = _SinResultados(vista: vista);
            if (onRefresh != null) {
              cuerpo = RefreshIndicator(
                color: kAcento,
                backgroundColor: kTarjeta,
                onRefresh: onRefresh!,
                child: cuerpo,
              );
            }
          } else {
            cuerpo = TablaUtilidad(
                  filas: visibles,
                  todas: d.filas,
                  columna: vista.columna,
                  ascendente: vista.ascendente,
                  onOrdenar: vista.ordenarPor,
                  onAbrir: (f) => _abrirPlatillo(context, f),
                  onRefresh: onRefresh,
                );
          }
        }
        if (envolverLista != null) cuerpo = envolverLista!(cuerpo);

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
              padding: const EdgeInsets.only(left: 16, right: 8),
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
                  _BotonGuia(
                      encendido: avisos, onTap: () => _abrirGuia(context)),
                ],
              ),
            ),
            if (resumen != null)
              _LineaResumen(
                texto: resumen.texto,
                color: resumen.color,
                onTap: () => _abrirGuia(context),
              ),
            const SizedBox(height: 4),
            Expanded(child: cuerpo),
          ],
        );
      },
    );
  }
}

/// El ícono de idea que abre la guía. Con un punto ámbar cuando hay avisos
/// que conviene leer.
class _BotonGuia extends StatelessWidget {
  final bool encendido;
  final VoidCallback onTap;
  const _BotonGuia({required this.encendido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      tooltip: 'Cómo leer la tabla y consejos',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: encendido ? kAmbar : Colors.white70, size: 24),
          if (encendido)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    color: kAmbar, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

/// La única línea de texto que queda sobre la tabla: de qué gastos sale la
/// columna Gasto, o por qué está vacía. Tocarla abre la guía.
class _LineaResumen extends StatelessWidget {
  final String texto;
  final Color color;
  final VoidCallback onTap;

  const _LineaResumen({
    required this.texto,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // Wrap y no Row: con la letra agrandada, "Ver más" baja de renglón
          // en vez de apretar el texto hasta partirle las palabras.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(texto,
                  style: GoogleFonts.inter(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35)),
              Text('Ver más',
                  style: GoogleFonts.inter(
                      color: kAcentoTexto,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinMenu extends StatelessWidget {
  final bool cargando;
  final String? error;
  const _SinMenu({required this.cargando, required this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 100),
        if (error != null && !cargando) ...[
          const Icon(Icons.cloud_off_rounded, color: Colors.white54, size: 34),
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
}

class _SinResultados extends StatelessWidget {
  final VistaUtilidadPlatillos vista;
  const _SinResultados({required this.vista});

  @override
  Widget build(BuildContext context) {
    final buscando = vista.busqueda.trim().isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      children: [
        Text(
          buscando
              ? 'Ningún platillo coincide con "${vista.busqueda.trim()}"'
              : 'Ningún platillo en este filtro',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5),
        ),
        if (buscando)
          Center(
            child: TextButton(
              onPressed: vista.limpiarBusqueda,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text('Limpiar búsqueda',
                  style: GoogleFonts.inter(
                      color: kAcentoTexto, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}
