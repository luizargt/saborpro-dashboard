import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/models/dashboard_data.dart';
import '../../core/utils/date_range.dart';

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

  static const _dayColors = [
    Color(0xFF7444fd), // Lun
    Color(0xFF3B82F6), // Mar
    Color(0xFF06B6D4), // Mié
    Color(0xFF22C55E), // Jue
    Color(0xFFF59E0B), // Vie
    Color(0xFFF97316), // Sáb
    Color(0xFFEF4444), // Dom
  ];

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.compact(locale: 'en_US');

    // Semana → una barra por semana del mes, para ubicar la semana elegida
    // dentro del mes. No se compara contra el período anterior porque ahí el
    // "anterior" es una sola semana, no un mes de semanas.
    if (mode == PeriodMode.week && monthlyDailyPoints.isNotEmpty) {
      return _buildComparisonBarChart(
        _weeksFromDailyPoints(monthlyDailyPoints),
        fmt,
        compare: const [],
      );
    }

    // Día → líneas por hora de la semana actual
    if (mode == PeriodMode.day && weeklyHourly.isNotEmpty) {
      return _buildWeeklyHourlyChart(weeklyHourly, fmt);
    }

    // Mes → barras por semana, comparadas contra el período anterior.
    // Año → barras por mes, mismo esquema.
    if (mode == PeriodMode.month || mode == PeriodMode.year) {
      return _buildComparisonBarChart(points, fmt, compare: prevPoints);
    }

    // Custom → área suavizada con punto destacado al final
    return _buildAreaChart(points, fmt);
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

  /// Barras agrupadas: por cada corte (semana o mes) una barra del período
  /// actual y, al lado, una gris del anterior. Las barras dejan comparar
  /// altura contra altura, que es más fácil de leer que dos líneas cruzándose.
  Widget _buildComparisonBarChart(
    List<PeriodPoint> points,
    NumberFormat fmt, {
    required List<PeriodPoint> compare,
  }) {
    // Paleta validada contra la superficie de la tarjeta (#1E293B) en modo
    // oscuro: banda de luminosidad, croma, separación para daltonismo y
    // contraste ≥3:1. El morado de marca (#7444fd) queda en 2.78:1 sobre esta
    // tarjeta —demasiado oscuro para leerse como barra—, por eso aquí se usa
    // un paso más claro de la misma familia.
    const accent = Color(0xFF8B5CF6);
    const accentTop = Color(0xFFA78BFA);
    const prevColor = Color(0xFF0D9488); // teal: se separa del navy sin competir
    final fmtFull = NumberFormat('#,##0.00', 'en_US');

    if (points.isEmpty) return const SizedBox(height: 180);

    final comparePoints = compare.take(points.length).toList();
    final showCompare =
        comparePoints.isNotEmpty && comparePoints.any((p) => p.amount > 0);

    final allAmounts = [
      ...points.map((p) => p.amount),
      if (showCompare) ...comparePoints.map((p) => p.amount),
    ].where((a) => a > 0);
    final maxY = allAmounts.isEmpty
        ? 100.0
        : allAmounts.reduce((a, b) => a > b ? a : b) * 1.2;

    final n = points.length;

    return LayoutBuilder(builder: (context, constraints) {
    // El ancho de barra se deriva del espacio real, no de umbrales fijos: con
    // pocas semanas en un monitor ancho quedaban barras diminutas rodeadas de
    // aire. Se reparte el espacio del grupo entre sus barras y se acota para
    // que no se vuelvan bloques en pantallas enormes.
    const leftAxisWidth = 44.0;
    final slot = ((constraints.maxWidth - leftAxisWidth) / n).clamp(1.0, 400.0);
    final barWidth = showCompare
        ? (slot * 0.26).clamp(4.0, 30.0)
        : (slot * 0.45).clamp(6.0, 48.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final isPrev = showCompare && rodIndex == 1;
                    final series = isPrev ? comparePoints : points;
                    if (group.x < 0 || group.x >= series.length) return null;
                    final pt = series[group.x];
                    return BarTooltipItem(
                      isPrev
                          ? '${_compareLabel()} · ${pt.label}\nQ${fmtFull.format(pt.amount)}'
                          : '${pt.label}\nQ${fmtFull.format(pt.amount)}\n${pt.orders} tickets',
                      GoogleFonts.inter(
                        color: isPrev ? const Color(0xFFCBD5E1) : Colors.white,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Text(
                        'Q${fmt.format(value)}',
                        style: GoogleFonts.inter(
                            color: Colors.white38, fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= points.length) {
                        return const SizedBox.shrink();
                      }
                      // Con muchos cortes (año) se muestran algunos para que
                      // las etiquetas no se encimen.
                      final step = n > 12 ? 3 : n > 8 ? 2 : 1;
                      if (idx % step != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          points[idx].label,
                          style: GoogleFonts.inter(
                              color: Colors.white38, fontSize: 9),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0x1AFFFFFF),
                  strokeWidth: 1,
                ),
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
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                      gradient: const LinearGradient(
                        colors: [accent, accentTop],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    if (showCompare)
                      BarChartRodData(
                        toY: i < comparePoints.length
                            ? comparePoints[i].amount
                            : 0,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        color: prevColor,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        if (showCompare) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _legendSwatch(color: accent, label: _currentLabel()),
              const SizedBox(width: 16),
              _legendSwatch(color: prevColor, label: _compareLabel()),
            ],
          ),
        ],
      ],
    );
    });
  }

  Widget _legendSwatch({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildWeeklyHourlyChart(List<DayHourlyPoints> days, NumberFormat fmt) {
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
    if (firstHour > lastHour) { firstHour = 0; lastHour = 23; }
    // Padding de 1 hora a cada lado
    final minX = (firstHour - 1).clamp(0, 23).toDouble();
    final maxX = (lastHour + 1).clamp(0, 23).toDouble();
    maxY *= 1.2;

    final lines = days.asMap().entries.map((entry) {
      final i = entry.key;
      final day = entry.value;
      final color = _dayColors[i % _dayColors.length];
      return LineChartBarData(
        spots: List.generate(24, (h) => FlSpot(h.toDouble(), day.hourlyAmounts[h])),
        isCurved: true,
        curveSmoothness: 0.3,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withOpacity(0.05),
        ),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
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
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  getTooltipItems: (spots) => spots.asMap().entries.map((e) {
                    final day = days[e.key];
                    final color = _dayColors[e.key % _dayColors.length];
                    final h = e.value.x.toInt();
                    final hourStr = '${h.toString().padLeft(2, '0')}:00';
                    return LineTooltipItem(
                      '${day.dayLabel} $hourStr\nQ${fmtFull.format(e.value.y)}',
                      GoogleFonts.inter(color: color, fontSize: 10),
                    );
                  }).toList(),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0x1AFFFFFF),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Text(
                        'Q${fmt.format(value)}',
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 4,
                    getTitlesWidget: (value, meta) {
                      final h = value.toInt();
                      if (h % 4 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${h.toString().padLeft(2, '0')}:00',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Leyenda de días
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: days.asMap().entries.map((e) {
            final color = _dayColors[e.key % _dayColors.length];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  e.value.dayLabel,
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                ),
              ],
            );
          }).toList(),
        ),
        _buildWeeklyInsight(days),
      ],
    );
  }

  /// Resumen en lenguaje simple: qué día vendió más y en qué hora se concentra
  /// la venta. Solo aparece con más de 3 días con ventas, para no sacar
  /// conclusiones de una muestra demasiado pequeña.
  Widget _buildWeeklyInsight(List<DayHourlyPoints> days) {
    final daysWithSales =
        days.where((d) => d.hourlyAmounts.any((a) => a > 0)).toList();
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
    const fullDayNames = [
      'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'
    ];
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

    const insightColor = Color(0xFFF59E0B); // ámbar: destaca sobre el morado de marca

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: insightColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: insightColor.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _insightBullet(
              color: insightColor,
              label: 'Tu mejor día de esta semana fue ',
              value: dayText,
              tail: ', vendiste Q${money.format(bestDayTotal)}.',
            ),
            const SizedBox(height: 6),
            _insightBullet(
              color: insightColor,
              label: '',
              value: '${hourText[0].toUpperCase()}${hourText.substring(1)}',
              tail:
                  ', es cuando vendes más, en ese horario vendes en promedio Q${money.format(hourTotals[bestHour] / daysWithSales.length)}.',
            ),
          ],
        ),
      ),
    );
  }

  /// Viñeta compacta del recuadro de datos clave. Cada una es un dato
  /// independiente, no una conclusión sobre la otra.
  Widget _insightBullet({
    required Color color,
    required String label,
    required String value,
    required String tail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
                height: 1.35,
              ),
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: value,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: tail),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildAreaChart(List<PeriodPoint> points, NumberFormat fmt) {
    // Misma paleta validada que las barras, para que las dos gráficas del
    // dashboard se lean como un solo sistema.
    const accent = Color(0xFF8B5CF6);
    const prevColor = Color(0xFF0D9488);
    final fmtFull = NumberFormat('#,##0.00', 'en_US');

    if (points.isEmpty) {
      return const SizedBox(height: 180);
    }

    final lastIndex = points.length - 1;
    // Comparativa contra el período anterior. Solo se dibuja si hay ventas que
    // comparar, para no ensuciar la gráfica con una línea plana en cero.
    final comparePoints = prevPoints.take(points.length).toList();
    final showCompare =
        comparePoints.isNotEmpty && comparePoints.any((p) => p.amount > 0);

    // La escala considera ambas series para que ninguna se salga del área.
    final allAmounts = [
      ...points.map((p) => p.amount),
      if (showCompare) ...comparePoints.map((p) => p.amount),
    ].where((a) => a > 0);
    final maxY = allAmounts.isEmpty
        ? 100.0
        : allAmounts.reduce((a, b) => a > b ? a : b) * 1.2;

    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.amount)).toList();

    final prevBarData = LineChartBarData(
      spots: comparePoints
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.amount))
          .toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      preventCurveOverShooting: true,
      color: prevColor.withOpacity(0.75),
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
      color: accent,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => index == lastIndex
            ? _GlowDotPainter(color: accent)
            : FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeColor: Colors.transparent),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [accent.withOpacity(0.35), accent.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
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
                ShowingTooltipIndicators(
                    [LineBarSpot(barData, showCompare ? 1 : 0, spots[lastIndex])]),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
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
                          ? '${_compareLabel()} · ${pt.label}\nQ${fmtFull.format(pt.amount)}'
                          : '${pt.label}\nQ${fmtFull.format(pt.amount)}\n${pt.orders} tickets',
                      GoogleFonts.inter(
                        color: isPrev ? prevColor : Colors.white,
                        fontSize: 11,
                      ),
                    );
                  }).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Text(
                        'Q${fmt.format(value)}',
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
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
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          points[idx].label,
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 9),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0x1AFFFFFF),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        if (showCompare) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDash(color: accent, label: _currentLabel(), dashed: false),
              const SizedBox(width: 16),
              _legendDash(color: prevColor, label: _compareLabel(), dashed: true),
            ],
          ),
        ],
      ],
    );
  }

  /// Etiquetas de la leyenda según el período que se está viendo.
  String _currentLabel() {
    switch (mode) {
      case PeriodMode.month: return 'Este mes';
      case PeriodMode.year: return 'Este año';
      default: return 'Período actual';
    }
  }

  String _compareLabel() {
    switch (mode) {
      case PeriodMode.month: return 'Mes pasado';
      case PeriodMode.year: return 'Año pasado';
      default: return 'Período anterior';
    }
  }

  Widget _legendDash({
    required Color color,
    required String label,
    required bool dashed,
  }) {
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
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
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
      ..color = color.withOpacity(0.35)
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
