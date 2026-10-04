import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../data/models/menu_margin_data.dart';
import '../providers/dashboard_provider.dart';
import '../providers/menu_margin_provider.dart';
import '../providers/profitability_provider.dart';
import '../screens/reports/dish_profit_screen.dart';
import 'dish_profit_widgets.dart';

/// La sucursal con que se costea el menú. "Todas" (null) solo cuando de verdad
/// hay varias a la vista: con una sola —un usuario con una sucursal asignada,
/// o el selector escondido— el dashboard ya muestra sus ventas y sus gastos,
/// y el menú tiene que ir con sus precios y sus ingredientes.
String? sucursalEfectiva(String? seleccionada, List<String> visibles) =>
    seleccionada ?? (visibles.length == 1 ? visibles.first : null);

/// Une el menú (costo de receta) con los gastos del período de Rentabilidad.
/// Null mientras el menú no llegó.
UtilidadMenu? construirUtilidad(
  DashboardProvider dash,
  ProfitabilityProvider rentabilidad,
  MenuMarginProvider menu,
) {
  final platillos = menu.platillosPara(sucursalEfectiva(
      dash.selectedLocationId, [for (final l in dash.locations) l.id]));
  if (platillos == null) return null;

  RepartoGastos? reparto;
  // Solo con los números de Rentabilidad de ESTE período y ESTA sucursal:
  // repartir con los de antes (o con ceros mientras cargan) daría una
  // utilidad inventada, aunque sea por un cuadro.
  if (!dash.loading && rentabilidad.alDiaCon(dash)) {
    final m = dash.metrics;
    reparto = RepartoGastos.desde(
      datos: rentabilidad.data,
      rango: dash.range,
      // El dashboard se traga los fallos de gastos y de cajas y devuelve
      // listas vacías; estas dos señales son la única huella.
      gastosLeidos: dash.expenseRawCount >= 0 && dash.cajasLeidas,
      // En Año la venta sale de agregados, no de órdenes: su señal de corte
      // es la del agregado.
      ventasCompletas: dash.sinOrdenesEnMemoria
          ? !(m?.truncated ?? false)
          : !dash.ordenesCortadas,
      // En la vista de año el desglose llega después: mientras tanto no se
      // sabe el descuento, y se dice en vez de inventarlo.
      descuentos: m != null && m.detailAvailable ? m.discounts : null,
    );
  }
  return UtilidadMenu.armar(platillos,
      reparto: reparto, descartados: menu.descartados);
}

/// Los gastos todavía no se pueden repartir porque Rentabilidad está
/// cargando (o recalculando tras un cambio de período o sucursal).
bool calculandoGastos(DashboardProvider dash, ProfitabilityProvider r) =>
    r.error == null && (dash.loading || !r.alDiaCon(dash));

bool esVistaTodas(DashboardProvider dash) =>
    dash.selectedLocationId == null && dash.locations.length > 1;

/// Abre la lista completa con los MISMOS providers: sin volver a descargar el
/// menú, y sin liberarlos al volver.
void abrirUtilidadPlatillos(BuildContext context) {
  final rentabilidad = context.read<ProfitabilityProvider>();
  final menu = context.read<MenuMarginProvider>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: rentabilidad),
        ChangeNotifierProvider.value(value: menu),
      ],
      child: const UtilidadPlatillosScreen(),
    ),
  ));
}

/// La tarjeta dentro de Rentabilidad, conectada a los providers. Escucha por
/// su cuenta: cuando llega el menú se redibuja ella, no todo el reporte.
class UtilidadPlatillosSeccion extends StatelessWidget {
  const UtilidadPlatillosSeccion({super.key});

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final rentabilidad = context.watch<ProfitabilityProvider>();
    final menu = context.watch<MenuMarginProvider>();

    return UtilidadPlatillosCard(
      datos: construirUtilidad(dash, rentabilidad, menu),
      cargando: menu.cargando && !menu.listo,
      error: menu.error,
      periodo: dash.range.label,
      calculandoGastos: calculandoGastos(dash, rentabilidad),
      errorGastos: rentabilidad.error != null,
      vistaTodas: esVistaTodas(dash),
      onReintentar: menu.recargar,
      onVerTodos: () => abrirUtilidadPlatillos(context),
    );
  }
}

/// La tarjeta tal como se ve, sin saber de providers: se prueba a 360dp.
class UtilidadPlatillosCard extends StatelessWidget {
  final UtilidadMenu? datos;
  final bool cargando;
  final String? error;
  final String periodo;
  final bool calculandoGastos;
  final bool errorGastos;
  final bool vistaTodas;
  final VoidCallback onReintentar;
  final VoidCallback onVerTodos;

  const UtilidadPlatillosCard({
    super.key,
    required this.datos,
    this.cargando = false,
    this.error,
    required this.periodo,
    this.calculandoGastos = false,
    this.errorGastos = false,
    this.vistaTodas = false,
    required this.onReintentar,
    required this.onVerTodos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      decoration: BoxDecoration(
        color: kTarjeta,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu_rounded,
                  color: kAcentoTexto, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('UTILIDAD POR PLATILLO',
                    style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._cuerpo(),
        ],
      ),
    );
  }

  List<Widget> _cuerpo() {
    final d = datos;

    if (d == null) {
      if (error != null && !cargando) {
        return [
          _texto(error!, Colors.white70),
          const SizedBox(height: 10),
          _BotonAncho(etiqueta: 'Reintentar', onTap: onReintentar),
        ];
      }
      return const [
        SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(color: kAcento)),
        ),
      ];
    }

    if (d.sinPlatillos) {
      return [
        _texto('Tu menú todavía no tiene platillos. Cuando los cargués con su '
            'receta en Sabor Suite, vas a ver aquí cuánto te deja cada uno.',
            Colors.white70),
      ];
    }

    final confiables = d.confiables;
    final faltantes = d.faltantes(3);

    return [
      ResumenReparto(
        reparto: d.reparto,
        periodo: periodo,
        calculando: calculandoGastos,
        errorGastos: errorGastos,
        vistaTodas: vistaTodas,
        compacto: true,
      ),
      const SizedBox(height: 12),
      if (confiables.length >= 6) ...[
        _Seccion(titulo: 'MENOR GANANCIA (% DEL PRECIO)', filas: d.menosDejan(3)),
        const SizedBox(height: 8),
        _Seccion(titulo: 'MAYOR GANANCIA (% DEL PRECIO)', filas: d.masDejan(3)),
      ] else if (confiables.isNotEmpty)
        // Con pocos platillos con costo, separar "menor" y "mayor" repetiría
        // los mismos: va una sola lista, de menor a mayor.
        _Seccion(
            titulo: 'TUS PLATILLOS CON COSTO (% DEL PRECIO)',
            filas: d.menosDejan(confiables.length))
      else
        _texto(
            'Todavía ningún platillo tiene su costo completo y confiable. '
            'Abrí "Ver todos" para ver qué le falta a cada uno.',
            Colors.white70),
      if (confiables.isNotEmpty)
        // El ranking es por venta: un platillo que deja poco pero se vende
        // mucho puede aportar más que uno que deja mucho y casi no sale.
        _texto('Por cada venta: no cuenta cuántos vendés.', Colors.white60),
      const SizedBox(height: 10),
      _texto(
          'Con costo completo: ${d.completos} de ${d.total} platillos'
          '${d.porRevisar > 0 ? ' · ${d.porRevisar} por revisar' : ''}',
          Colors.white70),
      if (faltantes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          // En el POS el precio de compra de un ingrediente ya creado solo
          // cambia con una entrada con costo: "cargá el precio" no se puede.
          child: _texto(
              'Para completar, registrá en Despensa una entrada con costo de: '
              '${faltantes.map((f) => '${f.ingrediente} (en ${f.platillos} '
                  '${f.platillos == 1 ? 'platillo' : 'platillos'})').join(', ')}.',
              Colors.white60),
        ),
      if (d.descartados > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _texto(textoDescartadosMenu(d.descartados), Colors.white60),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _texto(
              'No se pudo actualizar el menú: se muestran los datos '
              'anteriores. Deslizá hacia abajo para reintentar.',
              kAmbar),
        ),
      const SizedBox(height: 10),
      _BotonAncho(
          etiqueta: 'Ver todos los platillos (${d.total})', onTap: onVerTodos),
    ];
  }

  Widget _texto(String t, Color c) => Text(t,
      style: GoogleFonts.inter(color: c, fontSize: 12, height: 1.45));
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final List<FilaUtilidad> filas;
  const _Seccion({required this.titulo, required this.filas});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo,
            style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        for (final f in filas) FilaPlatilloCompacta(fila: f),
      ],
    );
  }
}

class _BotonAncho extends StatelessWidget {
  final String etiqueta;
  final VoidCallback onTap;
  const _BotonAncho({required this.etiqueta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAcento,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Center(
              child: Text(etiqueta,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}
