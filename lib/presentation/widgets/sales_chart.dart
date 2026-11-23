import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/utils/formato_dinero.dart';
import '../../data/models/dashboard_data.dart';
import '../../core/utils/date_range.dart';
import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// La gráfica de ventas del Inicio. Rediseño 2026-11-20 (inicio-manager.html,
/// modo oscuro): los modos, las comparaciones y los datos son los de siempre
/// (por hora de la semana, barras contra el período anterior, área); cambian la
/// paleta, la letra, el alto y el recuadro de lo que más se vende.
class SalesChart extends StatelessWidget {
  final List<PeriodPoint> points;
  final PeriodMode mode;
  final List<DayHourlyPoints> weeklyHourly;
  final List<PeriodPoint> monthlyDailyPoints;
  final List<PeriodPoint> prevPoints;

  const SalesChart({
    super.key,
    required this.points,
    required this.mode,
    this.weeklyHourly = const [],
    this.monthlyDailyPoints = const [],
    this.prevPoints = const [],
  });

  // Los colores de los días del diseño (lunes a viernes); sábado y domingo
  // siguen la misma familia.
  static const _dayColors = [
    Color(0xFF7C5CFF), // Lun
    Color(0xFF3E7BEA), // Mar
    Color(0xFF22B5D6), // Mié
    Color(0xFF2FA866), // Jue
    Color(0xFFF0A030), // Vie
    Color(0xFFF0624D), // Sáb
    Color(0xFFE879A8), // Dom
  ];

  // Las barras y el área: el acento del diseño y, para el período anterior, un
  // verde azulado que se separa de él también para quien no distingue colores.
  static Color get _accent => _C.accent;
  static const _accentTop = Color(0xFFB9A4FF);
  static Color get _prevColor => _C.gift;

  /// Las líneas de la cuadrícula y los ejes, como en el diseño.
  static FlLine get _gridLine => FlLine(color: _C.line, strokeWidth: 1);
  static TextStyle get _ejeStyle => _t(11.5, FontWeight.w400, _C.muted);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.compact(locale: 'en_US');
    final alto = MediaQuery.sizeOf(context).width <= kInicioQuiebreTelefono ? 200.0 : 260.0;

    // Semana → una barra por semana del mes, para ubicar la semana elegida
    // dentro del mes. No se compara contra el período anterior porque ahí el
    // "anterior" es una sola semana, no un mes de semanas.
    if (mode == PeriodMode.week && monthlyDailyPoints.isNotEmpty) {
      return _buildComparisonBarChart(
        _weeksFromDailyPoints(monthlyDailyPoints),
        fmt,
        alto,
        compare: const [],
      );
    }

    // Día → líneas por hora de la semana actual
    if (mode == PeriodMode.day && weeklyHourly.isNotEmpty) {
      return _buildWeeklyHourlyChart(weeklyHourly, fmt, alto);
    }

    // Mes → barras por semana, comparadas contra el período anterior.
    // Año → barras por mes, mismo esquema.
    if (mode == PeriodMode.month || mode == PeriodMode.year) {
      return _buildComparisonBarChart(points, fmt, alto, compare: prevPoints);
    }

    // Custom → área suavizada con punto destacado al final
    return _buildAreaChart(points, fmt, alto);
  }

  /// Agrupa los puntos diarios del mes en semanas. La lista viene ordenada
  /// desde el día 1, así que el índice basta para saber la semana y no hace
  /// falta parsear la etiqueta.
  List<PeriodPoint> _weeksFromDailyPoints(List<PeriodPoint> daily) {
    final amounts = <int, double>{};
    final orders = <int, int>{};
    for (var i = 0; i < daily.length; i++) {
      final week = (i ~/ 7) + 1;
      amounts[week] = (amounts[week] ?? 0) + daily[i].amount;
      orders[week] = (orders[week] ?? 0) + daily[i].orders;
    }
    final weeks = amounts.keys.toList()..sort();
    return weeks
        .map((w) => PeriodPoint(
              label: 'Sem $w',
              amount: amounts[w] ?? 0,
              orders: orders[w] ?? 0,
            ))
        .toList();
  }

  /// Los ejes de siempre: dinero compacto a la izquierda, etiquetas abajo.
  FlTitlesData _titulos({
    required NumberFormat fmt,
    required double alturaAbajo,
    required Widget Function(double value, TitleMeta meta) abajo,
    double? intervaloAbajo,
  }) {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 46,
          getTitlesWidget: (value, meta) {
            // Sin el cero ni el tope: el tope es el máximo de los datos más un
            // margen (un número cualquiera como "Q6.82K") y el diseño solo
            // marca los valores redondos.
            if (value == 0 || value == meta.max) return const SizedBox.shrink();
            return Text('$moneda${fmt.format(value)}', style: _ejeStyle);
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: alturaAbajo,
          interval: intervaloAbajo,
          getTitlesWidget: abajo,
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  /// Barras agrupadas: por cada corte (semana o mes) una barra del período
  /// actual y, al lado, una gris del anterior. Las barras dejan comparar
  /// altura contra altura, que es más fácil de leer que dos líneas cruzándose.
  Widget _buildComparisonBarChart(
    List<PeriodPoint> points,
    NumberFormat fmt,
    double alto, {
    required List<PeriodPoint> compare,
  }) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');

    if (points.isEmpty) return SizedBox(height: alto);

    final comparePoints = compare.take(points.length).toList();
    final showCompare = comparePoints.isNotEmpty && comparePoints.any((p) => p.amount > 0);

    final allAmounts = [
      ...points.map((p) => p.amount),
      if (showCompare) ...comparePoints.map((p) => p.amount),
    ].where((a) => a > 0);
    final maxY = allAmounts.isEmpty ? 100.0 : allAmounts.reduce((a, b) => a > b ? a : b) * 1.2;

    final n = points.length;

    return LayoutBuilder(builder: (context, constraints) {
      // El ancho de barra se deriva del espacio real, no de umbrales fijos: con
      // pocas semanas en un monitor ancho quedaban barras diminutas rodeadas de
      // aire. Se reparte el espacio del grupo entre sus barras y se acota para
      // que no se vuelvan bloques en pantallas enormes.
      const leftAxisWidth = 46.0;
      final slot = ((constraints.maxWidth - leftAxisWidth) / n).clamp(1.0, 400.0);
      final barWidth = showCompare ? (slot * 0.26).clamp(4.0, 30.0) : (slot * 0.45).clamp(6.0, 48.0);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: alto,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _C.subtle,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final isPrev = showCompare && rodIndex == 1;
                      final series = isPrev ? comparePoints : points;
                      if (group.x < 0 || group.x >= series.length) return null;
                      final pt = series[group.x];
                      return BarTooltipItem(
                        isPrev
                            ? '${_compareLabel()} · ${pt.label}\n$moneda${fmtFull.format(pt.amount)}'
                            : '${pt.label}\n$moneda${fmtFull.format(pt.amount)}\n${pt.orders} tickets',
                        _t(12, FontWeight.w500, isPrev ? _C.muted : _C.ink),
                      );
                    },
                  ),
                ),
                titlesData: _titulos(
                  fmt: fmt,
                  alturaAbajo: 26,
                  abajo: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= points.length) {
                      return const SizedBox.shrink();
                    }
                    // Con muchos cortes (año) se muestran algunos para que
                    // las etiquetas no se encimen.
                    final step = n > 12 ? 3 : n > 8 ? 2 : 1;
                    if (idx % step != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(points[idx].label, style: _ejeStyle, overflow: TextOverflow.ellipsis),
                    );
                  },
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => _gridLine,
                ),
                borderData: FlBorderData(show: false),
                barGroups: points.asMap().entries.map((e) {
                  final i = e.key;
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 2, // separador de 2px entre barras adyacentes
                    barRods: [
                      BarChartRodData(
                        toY: e.value.amount,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        gradient: LinearGradient(
                          colors: [_accent, _accentTop],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                      if (showCompare)
                        BarChartRodData(
                          toY: i < comparePoints.length ? comparePoints[i].amount : 0,
                          width: barWidth,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          color: _prevColor,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (showCompare) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _legendSwatch(color: _accent, label: _currentLabel()),
                _legendSwatch(color: _prevColor, label: _compareLabel()),
              ],
            ),
          ],
        ],
      );
    });
  }

  /// Una entrada de la leyenda: la rayita del color y su nombre.
  Widget _legendSwatch({required Color color, required String label, bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 3,
          child: dashed
              ? Row(
                  children: List.generate(
                    3,
                    (i) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 2 ? 0 : 2),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                )
              : Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(width: 7),
        Text(label, style: _t(13, FontWeight.w400, _C.muted)),
      ],
    );
  }

  Widget _buildWeeklyHourlyChart(List<DayHourlyPoints> days, NumberFormat fmt, double alto) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');
    double maxY = 100;
    int firstHour = 23;
    int lastHour = 0;
    for (final d in days) {
      for (var h = 0; h < 24; h++) {
        if (d.hourlyAmounts[h] > 0) {
          if (h < firstHour) firstHour = h;
          if (h > lastHour) lastHour = h;
        }
        if (d.hourlyAmounts[h] > maxY) maxY = d.hourlyAmounts[h];
      }
    }
    // Si no hay ventas, mostrar rango completo
    if (firstHour > lastHour) {
      firstHour = 0;
      lastHour = 23;
    }
    // Padding de 1 hora a cada lado
    final minX = (firstHour - 1).clamp(0, 23).toDouble();
    final maxX = (lastHour + 1).clamp(0, 23).toDouble();
    maxY *= 1.2;

    // Hoy: su línea va más gruesa y llega hasta la hora en que estamos. Las
    // horas que aún no pasan no son ventas en cero, y dibujarlas así hacía caer
    // la línea de golpe.
    final ahora = DateTime.now();
    bool esHoy(DayHourlyPoints d) => d.fecha != null && DateUtils.isSameDay(d.fecha, ahora);

    final lines = days.asMap().entries.map((entry) {
      final i = entry.key;
      final day = entry.value;
      final color = _dayColors[i % _dayColors.length];
      final hoy = esHoy(day);
      var hasta = hoy ? ahora.hour : 23;
      // Nunca deja fuera una venta ya registrada: con el reloj del teléfono
      // atrasado frente al del punto de venta, hay ventas "del futuro".
      if (hoy) {
        for (var h = 23; h > hasta; h--) {
          if (day.hourlyAmounts[h] > 0) {
            hasta = h;
            break;
          }
        }
      }
      return LineChartBarData(
        spots: [for (var h = 0; h <= hasta; h++) FlSpot(h.toDouble(), day.hourlyAmounts[h])],
        isCurved: true,
        curveSmoothness: 0.3,
        color: hoy ? color : color.withValues(alpha: 0.75),
        barWidth: hoy ? 3 : 2,
        dotData: const FlDotData(show: false),
        // Sin relleno: el diseño son solo líneas, y siete rellenos tenues
        // apilados ensuciaban las horas donde se cruzan.
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: alto,
          child: LineChart(
            LineChartData(
              maxY: maxY,
              minY: 0,
              minX: minX,
              maxX: maxX,
              clipData: const FlClipData.all(),
              lineBarsData: lines,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => _C.subtle,
                  // Cada punto toca SU línea (barIndex): hoy termina antes que
                  // las demás y ya no se puede asumir que hay uno por día.
                  getTooltipItems: (spots) => spots.map((s) {
                    final day = days[s.barIndex];
                    final color = _dayColors[s.barIndex % _dayColors.length];
                    final h = s.x.toInt();
                    final hourStr = '${h.toString().padLeft(2, '0')}:00';
                    return LineTooltipItem(
                      '${day.dayLabel} $hourStr\n$moneda${fmtFull.format(s.y)}',
                      _t(12, FontWeight.w600, color),
                    );
                  }).toList(),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => _gridLine,
              ),
              borderData: FlBorderData(show: false),
              titlesData: _titulos(
                fmt: fmt,
                alturaAbajo: 26,
                intervaloAbajo: 4,
                abajo: (value, meta) {
                  final h = value.toInt();
                  if (h % 4 != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${h.toString().padLeft(2, '0')}:00', style: _ejeStyle),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Leyenda de días
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: days
              .asMap()
              .entries
              .map((e) => _legendSwatch(color: _dayColors[e.key % _dayColors.length], label: e.value.dayLabel))
              .toList(),
        ),
        _buildWeeklyInsight(days),
      ],
    );
  }

  /// Resumen en lenguaje simple: qué día vendió más y en qué hora se concentra
  /// la venta. Solo aparece con más de 3 días con ventas, para no sacar
  /// conclusiones de una muestra demasiado pequeña.
  Widget _buildWeeklyInsight(List<DayHourlyPoints> days) {
    final daysWithSales = days.where((d) => d.hourlyAmounts.any((a) => a > 0)).toList();
    if (daysWithSales.length <= 3) return const SizedBox.shrink();

    // Día más fuerte
    DayHourlyPoints? bestDay;
    var bestDayTotal = 0.0;
    for (final d in daysWithSales) {
      final total = d.hourlyAmounts.fold<double>(0, (s, a) => s + a);
      if (total > bestDayTotal) {
        bestDayTotal = total;
        bestDay = d;
      }
    }

    // Mejor hora sumando todos los días del período
    final hourTotals = List<double>.filled(24, 0);
    for (final d in daysWithSales) {
      for (var h = 0; h < 24; h++) {
        hourTotals[h] += d.hourlyAmounts[h];
      }
    }
    var bestHour = 0;
    for (var h = 1; h < 24; h++) {
      if (hourTotals[h] > hourTotals[bestHour]) bestHour = h;
    }

    if (bestDay == null || bestDayTotal <= 0 || hourTotals[bestHour] <= 0) {
      return const SizedBox.shrink();
    }

    final money = NumberFormat('#,##0', 'en_US');

    // days[i] corresponde a lunes + i, así que hoy está en weekday - 1.
    final bestDayIndex = days.indexOf(bestDay);
    final isToday = bestDayIndex == DateTime.now().weekday - 1;

    // Nombre del día completo, no abreviado: "el sábado" en vez de "Sáb 15".
    const fullDayNames = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final dayText = isToday
        ? 'hoy'
        : (bestDayIndex >= 0 && bestDayIndex < fullDayNames.length)
            ? 'el ${fullDayNames[bestDayIndex]}'
            : bestDay.dayLabel;

    // Horas habladas: "9 de la noche" en vez de "21:00".
    String h12(int h) => '${h % 12 == 0 ? 12 : h % 12}';
    String period(int h) {
      if (h == 0) return 'de la noche';
      if (h < 5) return 'de la madrugada';
      if (h < 12) return 'de la mañana';
      if (h == 12) return 'del mediodía';
      if (h < 19) return 'de la tarde';
      return 'de la noche';
    }

    final endHour = (bestHour + 1) % 24;
    final hourText = period(bestHour) == period(endHour)
        ? 'de ${h12(bestHour)} a ${h12(endHour)} ${period(endHour)}'
        : 'de ${h12(bestHour)} ${period(bestHour)} a ${h12(endHour)} ${period(endHour)}';

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: _C.subtle, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _insightLinea(
              label: 'Tu mejor día de esta semana fue ',
              value: dayText,
              tail: ', vendiste $moneda${money.format(bestDayTotal)}.',
            ),
            const SizedBox(height: 4),
            _insightLinea(
              label: '',
              value: '${hourText[0].toUpperCase()}${hourText.substring(1)}',
              tail:
                  ', es cuando vendes más, en ese horario vendes en promedio $moneda${money.format(hourTotals[bestHour] / daysWithSales.length)}.',
            ),
          ],
        ),
      ),
    );
  }

  /// Una línea del recuadro de datos clave: lo importante en el color de
  /// acento y negritas. Cada una es un dato independiente, no una conclusión
  /// sobre la otra.
  Widget _insightLinea({required String label, required String value, required String tail}) {
    return RichText(
      text: TextSpan(
        style: _t(14, FontWeight.w400, _C.ink, height: 1.4),
        children: [
          TextSpan(text: label),
          TextSpan(text: value, style: _t(14, FontWeight.w700, _C.accent, height: 1.4)),
          TextSpan(text: tail),
        ],
      ),
    );
  }

  Widget _buildAreaChart(List<PeriodPoint> points, NumberFormat fmt, double alto) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');

    if (points.isEmpty) {
      return SizedBox(height: alto);
    }

    final lastIndex = points.length - 1;
    // Comparativa contra el período anterior. Solo se dibuja si hay ventas que
    // comparar, para no ensuciar la gráfica con una línea plana en cero.
    final comparePoints = prevPoints.take(points.length).toList();
    final showCompare = comparePoints.isNotEmpty && comparePoints.any((p) => p.amount > 0);

    // La escala considera ambas series para que ninguna se salga del área.
    final allAmounts = [
      ...points.map((p) => p.amount),
      if (showCompare) ...comparePoints.map((p) => p.amount),
    ].where((a) => a > 0);
    final maxY = allAmounts.isEmpty ? 100.0 : allAmounts.reduce((a, b) => a > b ? a : b) * 1.2;

    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.amount)).toList();

    final prevBarData = LineChartBarData(
      spots: comparePoints.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.amount)).toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      preventCurveOverShooting: true,
      color: _prevColor.withValues(alpha: 0.75),
      barWidth: 2,
      dashArray: const [5, 4],
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );

    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      preventCurveOverShooting: true,
      color: _accent,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => index == lastIndex
            ? _GlowDotPainter(color: _accent)
            : FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [_accent.withValues(alpha: 0.35), _accent.withValues(alpha: 0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: alto,
          child: LineChart(
            LineChartData(
              maxY: maxY,
              minY: 0,
              minX: 0,
              maxX: lastIndex.toDouble(),
              clipData: const FlClipData.all(),
              // La comparativa va primero para que quede detrás de la línea actual.
              lineBarsData: [if (showCompare) prevBarData, barData],
              showingTooltipIndicators: [
                ShowingTooltipIndicators([LineBarSpot(barData, showCompare ? 1 : 0, spots[lastIndex])]),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => _C.subtle,
                  getTooltipItems: (touched) => touched.map((s) {
                    final idx = s.x.toInt();
                    final isPrev = showCompare && s.barIndex == 0;
                    final series = isPrev ? comparePoints : points;
                    if (idx < 0 || idx >= series.length) {
                      return null;
                    }
                    final pt = series[idx];
                    return LineTooltipItem(
                      isPrev
                          ? '${_compareLabel()} · ${pt.label}\n$moneda${fmtFull.format(pt.amount)}'
                          : '${pt.label}\n$moneda${fmtFull.format(pt.amount)}\n${pt.orders} tickets',
                      _t(12, FontWeight.w500, isPrev ? _prevColor : _C.ink),
                    );
                  }).toList(),
                ),
              ),
              titlesData: _titulos(
                fmt: fmt,
                alturaAbajo: 26,
                intervaloAbajo: 1,
                abajo: (value, meta) {
                  final idx = value.round();
                  if ((value - idx).abs() > 0.01) return const SizedBox.shrink();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  final n = points.length;
                  // Mostrar solo algunos labels cuando hay muchos puntos.
                  // Aplica a todos los modos: con un mes en días son 31
                  // etiquetas que si no se encimarían unas con otras.
                  final step = n > 20 ? 5 : n > 10 ? 3 : n > 7 ? 2 : 1;
                  if (mode == PeriodMode.day) {
                    if (idx % 4 != 0) return const SizedBox.shrink();
                  } else if (idx % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(points[idx].label, style: _ejeStyle, overflow: TextOverflow.ellipsis),
                  );
                },
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => _gridLine,
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (showCompare) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _legendSwatch(color: _accent, label: _currentLabel()),
              _legendSwatch(color: _prevColor, label: _compareLabel(), dashed: true),
            ],
          ),
        ],
      ],
    );
  }

  /// Etiquetas de la leyenda según el período que se está viendo.
  String _currentLabel() {
    switch (mode) {
      case PeriodMode.month:
        return 'Este mes';
      case PeriodMode.year:
        return 'Este año';
      default:
        return 'Período actual';
    }
  }

  String _compareLabel() {
    switch (mode) {
      case PeriodMode.month:
        return 'Mes pasado';
      case PeriodMode.year:
        return 'Año pasado';
      default:
        return 'Período anterior';
    }
  }
}

// Punto destacado con halo (glow) para resaltar el valor más reciente,
// imitando el estilo de tarjetas de tendencia tipo "sentiment score".
class _GlowDotPainter extends FlDotPainter {
  final Color color;
  final double radius;

  _GlowDotPainter({required this.color, this.radius = 5});

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(offsetInCanvas, radius * 2.4, glowPaint);

    canvas.drawCircle(offsetInCanvas, radius + 2, Paint()..color = color);
    canvas.drawCircle(offsetInCanvas, radius, Paint()..color = Colors.white);
  }

  @override
  Size getSize(FlSpot spot) => Size.fromRadius(radius * 2.4);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    if (a is! _GlowDotPainter || b is! _GlowDotPainter) return b;
    return _GlowDotPainter(
      color: Color.lerp(a.color, b.color, t)!,
      radius: a.radius + (b.radius - a.radius) * t,
    );
  }

  @override
  List<Object?> get props => [color, radius];
}
