import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formato_dinero.dart' show moneda;
import '../../../data/models/propinas_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/cortesias_view.dart' show CortesiasColores, cortesiasTexto, kCortesiasBg;
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';
import '../../widgets/moneda_vista_aviso.dart';
import '../../widgets/period_selector.dart';
import '../../widgets/propinas_view.dart';
import '../../navigation/contexto_shell.dart';

Color get _kCard => CortesiasColores.card;
Color get _kAccent => CortesiasColores.accent;

/// Abre el detalle desde la tarjeta "Propinas" del Inicio o desde Reportes.
void abrirPropinas(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PropinasScreen()),
  );
}

/// Quién recibe la propina, a qué hora se deja más, y cuánto según el tipo de
/// servicio, el tamaño de la cuenta, la zona y el método de pago.
///
/// No consulta los pedidos: usa los MISMOS con que el Inicio sumó la tarjeta
/// (y los del período anterior, para decir si subió o bajó), así que el total
/// cuadra con ella y obedece a la misma barra de sucursal y fecha. Lo único que
/// lee aparte son los nombres de quien no lo trae el pedido y la zona de cada
/// mesa (dos lecturas chicas, solo al abrir esta pantalla).
///
/// En la vista de año el Inicio no tiene los pedidos en memoria (los totales
/// los suma Firestore), así que ahí solo se muestra el total.
///
/// Solo arma el andamio (barras, carga, error); lo que se ve lo dibuja
/// [PropinasReportBody], que es la parte que se prueba a 360dp.
class PropinasScreen extends StatefulWidget {
  const PropinasScreen({super.key});

  @override
  State<PropinasScreen> createState() => _PropinasScreenState();
}

class _PropinasScreenState extends State<PropinasScreen> {
  // El reporte se rehace solo cuando cambia algo de lo que depende, no en cada
  // redibujo.
  List<Map<String, dynamic>>? _ordenes;
  List<Map<String, dynamic>>? _anteriores;
  String? _signo;
  int _version = 0;
  int _versionArmada = -1;
  PropinasReporte _reporte = PropinasReporte.vacio;

  // Nombre de quien cobró cada pedido que no lo trae (users/{id}.name).
  final Map<String, String> _nombres = {};
  final Set<String> _nombresPedidos = {};

  // Zona de cada mesa. Nula mientras no se lee (o si no se pudo leer): el
  // reporte no muestra la tarjeta de zonas en vez de inventarlas.
  Map<String, String>? _zonas;
  bool _zonasPedidas = false;

  Future<void> _refrescar(DashboardProvider dash) async {
    // Jalar hacia abajo también vuelve a leer las zonas (si no se habían podido
    // leer, es la forma de reintentar).
    _zonasPedidas = false;
    await dash.refresh();
  }

  void _pedirNombres(DashboardProvider dash, List<Map<String, dynamic>> ordenes) {
    final faltan = PropinasReporte.idsSinNombre(ordenes).where((id) => !_nombresPedidos.contains(id)).toList();
    if (faltan.isEmpty) return;
    _nombresPedidos.addAll(faltan);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final nombres = await dash.fetchUserNamesById(faltan);
      if (mounted && nombres.isNotEmpty) {
        setState(() {
          _nombres.addAll(nombres);
          _version++;
        });
      }
    });
  }

  void _pedirZonas(DashboardProvider dash) {
    if (_zonasPedidas) return;
    _zonasPedidas = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final zonas = await dash.fetchZonasDeMesas();
      if (mounted && zonas != null) {
        setState(() {
          _zonas = zonas;
          _version++;
        });
      }
    });
  }

  PropinasReporte _armar(DashboardProvider dash) {
    final ordenes = dash.currentOrders;
    final anteriores = dash.prevOrders;
    final signo = moneda;
    if (!identical(ordenes, _ordenes) ||
        !identical(anteriores, _anteriores) ||
        signo != _signo ||
        _version != _versionArmada) {
      _ordenes = ordenes;
      _anteriores = anteriores;
      _signo = signo;
      _versionArmada = _version;
      _reporte = PropinasReporte.desde(
        ordenes,
        anteriores: anteriores,
        nombresUsuario: _nombres,
        zonaDeMesa: _zonas,
        signo: signo,
      );
    }
    return _reporte;
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final enAnio = dash.sinOrdenesEnMemoria;
    final metricas = dash.metrics;

    final Widget contenido;
    if (dash.error != null) {
      contenido = _Relleno(child: _TextoAviso(dash.error!));
    } else if (dash.loading || metricas == null) {
      contenido = _Relleno(child: CircularProgressIndicator(color: _kAccent));
    } else if (enAnio) {
      // Sin pedidos en memoria: solo se sabe el total del año.
      contenido = PropinasReportBody(
        reporte: PropinasReporte.vacio,
        totalPeriodo: metricas.allTips,
        enCaja: metricas.tipsOutsideSales,
        conDetalle: false,
      );
    } else {
      _pedirNombres(dash, dash.currentOrders);
      _pedirZonas(dash);
      contenido = PropinasReportBody(
        reporte: _armar(dash),
        totalPeriodo: metricas.allTips,
        enCaja: metricas.tipsOutsideSales,
        vsEtiqueta: dash.range.prevLabel,
        incompleto: dash.ordenesCortadas,
      );
    }

    return Scaffold(
      backgroundColor: kCortesiasBg,
      body: SafeArea(
        child: LocationSwipeArea(
          child: MaxContentWidth(
            maxWidth: 1280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Encabezado(),
                // Las pestañas de sucursal (si hay varias) y la moneda de la
                // vista; la fecha ya va en el encabezado.
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [LocationTabsBar(), MonedaVistaAviso()],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LocationContentSwitcher(
                    child: RefreshIndicator(
                      color: _kAccent,
                      backgroundColor: _kCard,
                      onRefresh: () => _refrescar(dash),
                      child: contenido,
                    ),
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

/// Regresar, el título y la fecha del período (como el diseño). En el
/// teléfono la fecha baja a su propia línea: al lado se comía el título.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    // Dentro del shell el encabezado (migas, título y fecha) lo pone el shell.
    if (ContextoShell.enShell(context)) return const SizedBox.shrink();

    final telefono = MediaQuery.sizeOf(context).width < 640;
    final regresar = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: CortesiasColores.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => Navigator.of(context).maybePop(),
          child: Tooltip(
            message: 'Regresar',
            child: Icon(Icons.arrow_back_rounded, color: CortesiasColores.ink, size: 22),
          ),
        ),
      ),
    );
    final titulo = Text(
      'Propinas',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: cortesiasTexto(telefono ? 20 : 24, FontWeight.w700, CortesiasColores.ink),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: telefono
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [regresar, const SizedBox(width: 14), Expanded(child: titulo)]),
                const SizedBox(height: 10),
                const DateSelectorChip(),
              ],
            )
          : Row(
              children: [
                regresar,
                const SizedBox(width: 14),
                Expanded(child: titulo),
                const SizedBox(width: 14),
                const DateSelectorChip(),
              ],
            ),
    );
  }
}

class _TextoAviso extends StatelessWidget {
  final String texto;
  const _TextoAviso(this.texto);

  @override
  Widget build(BuildContext context) => Text(
        texto,
        textAlign: TextAlign.center,
        style: cortesiasTexto(13.5, FontWeight.w400, CortesiasColores.muted),
      );
}

class _Relleno extends StatelessWidget {
  final Widget child;
  const _Relleno({required this.child});

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el RefreshIndicator necesita algo desplazable para
    // que se pueda reintentar jalando hacia abajo.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 140),
        Center(child: child),
      ],
    );
  }
}
