import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/profitability_data.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/profitability_provider.dart';
import '../../widgets/location_selector.dart';
import '../../widgets/max_content_width.dart';

const _fondo = Color(0xFF0F172A);
const _appbar = Color(0xFF0A1020);
const _tarjeta = Color(0xFF1E293B);
const _acento = Color(0xFF7444fd);
const _verde = Color(0xFF22C55E);
const _rojo = Color(0xFFEF4444);
const _ambar = Color(0xFFFBBF24);

// El mismo patrón que el resto de la app (cajas, gastos, detalle de caja):
// coma para los miles, punto para los decimales y la Q adelante. El locale
// es_GT haría lo contrario —"64.733,00 Q"—, que no es como se escribe el
// quetzal ni como se ve en las demás pantallas.
final _q = NumberFormat('#,##0.00', 'en_US');

String _money(double v) => 'Q${_q.format(v)}';
String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

Color _colorDe(Salud s) => switch (s) {
      Salud.bien => _verde,
      Salud.atencion => _ambar,
      Salud.mal => _rojo,
      Salud.desconocido => Colors.white38,
    };

class ProfitabilityReportScreen extends StatefulWidget {
  const ProfitabilityReportScreen({super.key});

  @override
  State<ProfitabilityReportScreen> createState() =>
      _ProfitabilityReportScreenState();
}

class _ProfitabilityReportScreenState extends State<ProfitabilityReportScreen> {
  final _provider = ProfitabilityProvider();

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.loadIfNeeded(dash);
    });

    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: _fondo,
        appBar: AppBar(
          backgroundColor: _appbar,
          elevation: 0,
          title: const Text('Rentabilidad'),
        ),
        body: SafeArea(
          top: false,
          child: LocationSwipeArea(
            child: MaxContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LocationHeaderBar(),
                  Expanded(
                    child: Consumer<ProfitabilityProvider>(
                      builder: (context, p, _) => RefreshIndicator(
                        color: _acento,
                        backgroundColor: _tarjeta,
                        onRefresh: () async {
                          await dash.load();
                          await p.load(dash);
                        },
                        // dash.loading cuenta como cargando: las ventas salen
                        // de ahí, y mientras no lleguen no hay reporte que
                        // mostrar. Sin esto quedaban en pantalla los números
                        // del mes anterior, sin ninguna señal de que ya no
                        // correspondían.
                        child: _Cuerpo(provider: p, cargandoVentas: dash.loading),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  final ProfitabilityProvider provider;
  final bool cargandoVentas;
  const _Cuerpo({required this.provider, this.cargandoVentas = false});

  @override
  Widget build(BuildContext context) {
    if (provider.loading || cargandoVentas) {
      return ListView(children: const [
        SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator(color: _acento)),
        ),
      ]);
    }

    if (provider.error != null) {
      return _Aviso(
        icono: Icons.cloud_off_rounded,
        titulo: provider.error!,
        detalle: 'Deslizá hacia abajo para reintentar.',
      );
    }

    final d = provider.data;
    if (d.sinDatos) {
      return const _Aviso(
        icono: Icons.query_stats_rounded,
        titulo: 'Sin movimientos en este período',
        detalle: 'Elegí otro rango de fechas para ver tu rentabilidad.',
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: 28 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _Indicadores(d: d),
        const SizedBox(height: 18),
        _Cascada(d: d),
        const SizedBox(height: 14),
        _PuntoDeEquilibrio(d: d),
        const SizedBox(height: 14),
        _FueraDeLaCuenta(d: d),
        if (!d.costoConfiable && d.itemsTotales > 0) ...[
          const SizedBox(height: 14),
          _AvisoCobertura(d: d),
        ],
      ],
    );
  }
}

/// Los tres números que un gerente mira primero. En porcentaje, porque en
/// quetzales no se pueden comparar dos meses de distinto volumen.
class _Indicadores extends StatelessWidget {
  final ProfitabilityData d;
  const _Indicadores({required this.d});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _IndicadorTile(
        label: 'Costo de comida',
        valor: _pct(d.foodCostPct),
        meta: 'Meta: menos de 35%',
        salud: evaluarFoodCost(d.foodCostPct),
      ),
      _IndicadorTile(
        label: 'Costo primo',
        valor: _pct(d.primeCostPct),
        meta: 'Comida + sueldos. Meta: menos de 65%',
        salud: evaluarPrimeCost(d.primeCostPct),
      ),
      _IndicadorTile(
        label: 'Margen',
        valor: _pct(d.marginPct),
        meta: 'Lo que queda de cada venta',
        salud: evaluarMargen(d.marginPct),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        // A 360dp tres tarjetas lado a lado dejan el número ilegible.
        if (c.maxWidth < 520) {
          return Column(
            children: [
              for (final t in tiles) ...[t, const SizedBox(height: 8)],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i < tiles.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _IndicadorTile extends StatelessWidget {
  final String label;
  final String valor;
  final String meta;
  final Salud salud;

  const _IndicadorTile({
    required this.label,
    required this.valor,
    required this.meta,
    required this.salud,
  });

  @override
  Widget build(BuildContext context) {
    final c = _colorDe(salud);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: _tarjeta,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 38, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(valor,
                    style: GoogleFonts.inter(
                        color: c,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 2),
                Text(meta,
                    style: GoogleFonts.inter(
                        color: Colors.white24, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El estado de resultados en cascada.
class _Cascada extends StatelessWidget {
  final ProfitabilityData d;
  const _Cascada({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: _tarjeta,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Fila(
            label: 'Ventas netas',
            monto: d.netSales,
            pct: d.netSales > 0 ? 100 : null,
            fuerte: true,
          ),
          const SizedBox(height: 2),
          Text('sin propinas ni envíos',
              style:
                  GoogleFonts.inter(color: Colors.white24, fontSize: 10.5)),
          const SizedBox(height: 10),
          _Fila(
            label: 'Costo de lo vendido',
            monto: -d.cogs,
            pct: d.foodCostPct,
          ),
          _Separador(),
          _Fila(
            label: 'Utilidad bruta',
            monto: d.grossProfit,
            pct: d.pct(d.grossProfit),
            fuerte: true,
            resaltar: true,
          ),
          const SizedBox(height: 12),
          for (final e in d.expenses)
            _Fila(label: e.label, monto: -e.amount, pct: d.pct(e.amount)),
          if (d.expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Sin gastos registrados en el período',
                  style: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 12)),
            ),
          _Separador(),
          _Fila(
            label: 'Utilidad operativa',
            monto: d.operatingProfit,
            pct: d.marginPct,
            fuerte: true,
            resaltar: true,
            colorear: true,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(
            color: Colors.white.withValues(alpha: 0.1), height: 1),
      );
}

class _Fila extends StatelessWidget {
  final String label;
  final double monto;
  final double? pct;
  final bool fuerte;
  final bool resaltar;
  final bool colorear;

  const _Fila({
    required this.label,
    required this.monto,
    this.pct,
    this.fuerte = false,
    this.resaltar = false,
    this.colorear = false,
  });

  @override
  Widget build(BuildContext context) {
    final negativo = monto < 0;
    final color = colorear
        ? (monto >= 0 ? _verde : _rojo)
        : (resaltar ? Colors.white : (negativo ? Colors.white70 : Colors.white));

    return Padding(
      padding: EdgeInsets.symmetric(vertical: fuerte ? 4 : 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: fuerte ? Colors.white : Colors.white60,
                fontSize: fuerte ? 14 : 13,
                fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            // El signo lo lleva la resta, no el número: "− Q 32,000" se lee
            // como una resta de la cascada, no como un saldo negativo.
            negativo ? '−${_money(monto.abs())}' : _money(monto),
            style: GoogleFonts.inter(
              color: color,
              fontSize: fuerte ? 15 : 13,
              fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              _pct(pct),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: fuerte ? Colors.white54 : Colors.white30,
                fontSize: 11.5,
                fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuánto hay que vender para no perder.
///
/// Es la conclusión de la cascada, no un dato suelto: por eso va después y no
/// arriba. Traduce todos los porcentajes anteriores a una sola frase
/// accionable — "te faltan Q14,000" — que es lo que de verdad se puede usar
/// para decidir algo un martes a media tarde.
class _PuntoDeEquilibrio extends StatelessWidget {
  final ProfitabilityData d;
  const _PuntoDeEquilibrio({required this.d});

  @override
  Widget build(BuildContext context) {
    // Cada venta cuesta más de lo que deja: no existe volumen que salve esto.
    if (d.pierdeConCadaVenta) {
      return _Caja(
        color: _rojo,
        titulo: 'Cada venta te cuesta dinero',
        cuerpo: 'Lo que gastás en comida y costos variables supera lo que '
            'cobrás. Vender más aumenta la pérdida en lugar de reducirla: lo '
            'que hay que revisar son los precios del menú o el costo de los '
            'insumos, no el volumen.',
      );
    }

    if (d.sinCostosFijos) {
      return _Caja(
        color: _ambar,
        titulo: 'Falta registrar tus gastos fijos',
        cuerpo: 'En este período no hay gastos marcados como fijos (renta, '
            'sueldos, seguros). Sin ellos no se puede calcular cuánto '
            'necesitás vender para no perder. Si estás viendo un solo día, es '
            'normal: esos gastos se registran una vez al mes — probá con el '
            'rango mensual.',
      );
    }

    final be = d.breakEven;
    if (be == null) {
      return _Caja(
        color: _ambar,
        titulo: 'Sin ventas en el período',
        cuerpo: 'Con ventas en cero no se puede medir qué parte de cada '
            'quetzal queda libre para pagar los costos fijos.',
      );
    }

    final avance = (d.avanceBreakEven ?? 0).clamp(0.0, 1.0);
    final falta = d.faltaParaBreakEven ?? 0;
    final superado = falta <= 0;
    final color = superado ? _verde : _acento;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: _tarjeta,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(superado ? Icons.flag_rounded : Icons.golf_course_rounded,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Text('PUNTO DE EQUILIBRIO',
                  style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            superado
                ? 'Ya cubriste tus costos'
                : 'Te faltan ${_money(falta)}',
            style: GoogleFonts.inter(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.15),
          ),
          const SizedBox(height: 4),
          Text(
            superado
                // Con el margen de contribución en 60%, de cada Q100 vendidos
                // quedan Q60 — ya sin costos fijos que cubrir, esos son
                // ganancia limpia.
                ? 'Pasaste la meta de ${_money(be)}. Desde aquí, de cada Q100 '
                    'que vendas te quedan '
                    'Q${(d.contributionMarginPct ?? 0).toStringAsFixed(0)} '
                    'de ganancia.'
                : 'Necesitás vender ${_money(be)} en este período para no '
                    'perder ni ganar.',
            style: GoogleFonts.inter(
                color: Colors.white60, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: avance,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Vendiste ${_money(d.netSales)}',
                    style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
              Text('Meta ${_money(be)}',
                  style: GoogleFonts.inter(
                      color: Colors.white30, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 10),
          _MiniDato(
            label: 'Costos fijos del período',
            valor: _money(d.fixedCosts),
            nota: 'Se pagan aunque no vendas',
          ),
          const SizedBox(height: 6),
          _MiniDato(
            label: 'De cada venta queda libre',
            valor: _pct(d.contributionMarginPct),
            nota: 'Después de comida y costos variables',
          ),
        ],
      ),
    );
  }
}

class _MiniDato extends StatelessWidget {
  final String label;
  final String valor;
  final String nota;
  const _MiniDato(
      {required this.label, required this.valor, required this.nota});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.inter(
                      color: Colors.white60, fontSize: 12.5)),
              Text(nota,
                  style: GoogleFonts.inter(
                      color: Colors.white24, fontSize: 10.5)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(valor,
            style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13.5,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Caja de explicación para cuando el punto de equilibrio no se puede calcular.
class _Caja extends StatelessWidget {
  final Color color;
  final String titulo;
  final String cuerpo;

  const _Caja({
    required this.color,
    required this.titulo,
    required this.cuerpo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.inter(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(cuerpo,
              style: GoogleFonts.inter(
                  color: Colors.white60, fontSize: 11.5, height: 1.45)),
        ],
      ),
    );
  }
}

/// Lo que NO entra en la cascada, y por qué.
class _FueraDeLaCuenta extends StatelessWidget {
  final ProfitabilityData d;
  const _FueraDeLaCuenta({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _tarjeta.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('FUERA DE LA CUENTA',
              style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          // Ya está sumado arriba, en los gastos. Se muestra solo para saber
          // cuánto de la operación se está pagando con el efectivo de la caja
          // en vez de por otra vía.
          if (d.paidFromCash > 0)
            _Dato(
              label: 'Pagado en efectivo desde caja',
              monto: d.paidFromCash,
              nota: 'Ya contado arriba en los gastos',
            ),
          _Dato(
            label: 'Invertido en compras',
            monto: d.purchases,
            nota: d.entradasSinCosto > 0
                ? 'Mercadería que entró a la despensa · '
                    '${d.entradasSinCosto} entrada(s) sin costo quedan fuera'
                : 'Mercadería que entró a la despensa; el gasto se cuenta al vender',
          ),
          _Dato(
            label: 'Valor de tu despensa hoy',
            monto: d.inventoryValue,
            nota: d.rotacion != null
                ? 'Se renovó ${d.rotacion!.toStringAsFixed(1)} veces en el período'
                : 'A precio de compra',
            destacar: true,
          ),
          if (d.ingredientesSinPrecio > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${d.ingredientesSinPrecio} ingrediente(s) con stock pero sin '
                'precio de compra: no suman al valor.',
                style: GoogleFonts.inter(
                    color: _ambar.withValues(alpha: 0.85), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String label;
  final double monto;
  final String nota;
  final bool destacar;

  const _Dato({
    required this.label,
    required this.monto,
    required this.nota,
    this.destacar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Text(nota,
                    style: GoogleFonts.inter(
                        color: Colors.white24, fontSize: 10.5, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _money(monto),
            style: GoogleFonts.inter(
              color: destacar ? _acento : Colors.white70,
              fontSize: destacar ? 15 : 13.5,
              fontWeight: destacar ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Se muestra cuando parte de lo vendido no tiene costo cargado. Callarlo sería
/// peor que no mostrar el margen: un costo bajo por falta de datos se ve
/// idéntico a un costo bajo por buena gestión.
class _AvisoCobertura extends StatelessWidget {
  final ProfitabilityData d;
  const _AvisoCobertura({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _ambar.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ambar.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _ambar, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.costoMayormenteEstimado
                      ? 'El costo es una estimación'
                      : 'Tu ganancia real puede ser menor',
                  style: GoogleFonts.inter(
                      color: _ambar,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  d.costoMayormenteEstimado
                      // Caso típico al mirar meses anteriores: el POS no
                      // guardó el costo de esas ventas, así que se valorizan
                      // con el precio de compra de hoy.
                      ? '${_pct(d.porcentajeEstimado)} del costo se calculó con '
                          'los precios de compra de hoy, porque esas ventas no '
                          'guardaron el costo del momento. Sirve para orientarte, '
                          'pero si los precios cambiaron desde entonces, el '
                          'margen real es distinto.'
                      : 'Solo ${_pct(d.coberturaCosto)} de lo que vendiste tiene '
                          'costo. Los ingredientes sin precio de compra cuentan '
                          'como costo cero, así que el margen de arriba sale '
                          'optimista.',
                  style: GoogleFonts.inter(
                      color: Colors.white60, fontSize: 11.5, height: 1.45),
                ),
                if (d.itemsSinCosto > 0 && d.costoMayormenteEstimado) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Otro ${_pct(100 - (d.coberturaCosto ?? 0))} no tiene ni '
                    'precio actual: esos cuentan como cero.',
                    style: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 11, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    // ListView y no Center: el pull-to-refresh necesita algo desplazable.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 120),
        Icon(icono, color: Colors.white24, size: 34),
        const SizedBox(height: 14),
        Text(titulo,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 14.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(detalle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: Colors.white30, fontSize: 12.5, height: 1.5)),
      ],
    );
  }
}
