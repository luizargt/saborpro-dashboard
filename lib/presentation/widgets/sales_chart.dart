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

  const SalesChart({
    super.key,
    required this.points,
    required this.mode,
    this.weeklyHourly = const [],
    this.monthlyDailyPoints = const [],
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

    // Semana → barras diarias del mes actual con etiquetas L M M J V S D
    if (mode == PeriodMode.week && monthlyDailyPoints.isNotEmpty) {
      return _buildMonthlyDailyChart(monthlyDailyPoints, fmt);
    }

    // Día → líneas por hora de la semana actual
    if (mode == PeriodMode.day && weeklyHourly.isNotEmpty) {
      return _buildWeeklyHourlyChart(weeklyHourly, fmt);
    }

    // Mes / Año / Custom → barras estándar
    return _buildBarChart(points, fmt);
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
      ],
    );
  }

  Widget _buildMonthlyDailyChart(List<PeriodPoint> points, NumberFormat fmt) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final startWeekday = monthStart.weekday; // 1=Mon ... 7=Sun

    const dayAbbr = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    const monthNames = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    final nonEmpty = points.where((p) => p.amount > 0).toList();
    final maxY = nonEmpty.isEmpty
        ? 100.0
        : nonEmpty.map((p) => p.amount).reduce((a, b) => a > b ? a : b) * 1.2;

    final barGroups = points.asMap().entries.map((e) {
      final idx = e.key;
      final wdayIdx = (startWeekday - 1 + idx) % 7;
      final isWeekend = wdayIdx >= 5;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: e.value.amount,
            width: _barWidth(points.length),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            gradient: LinearGradient(
              colors: isWeekend
                  ? [const Color(0xFF3B82F6), const Color(0xFF60A5FA)]
                  : [const Color(0xFF7444fd), const Color(0xFF9066ff)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ],
      );
    }).toList();

    final weekRanges = _computeWeekRanges(points, monthStart, monthNames);
    const leftAxisWidth = 44.0;

    final barChart = BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final pt = points[group.x];
              final wdayIdx = (startWeekday - 1 + group.x) % 7;
              const fullNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
              return BarTooltipItem(
                '${fullNames[wdayIdx]} ${pt.label} ${monthNames[now.month]}\nQ${fmtFull.format(rod.toY)}\n${pt.orders} tickets',
                GoogleFonts.inter(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftAxisWidth,
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
              reservedSize: 20,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                final wdayIdx = (startWeekday - 1 + idx) % 7;
                final isWeekend = wdayIdx >= 5;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    dayAbbr[wdayIdx],
                    style: GoogleFonts.inter(
                      color: isWeekend ? const Color(0xFF60A5FA) : Colors.white38,
                      fontSize: 9,
                      fontWeight: isWeekend ? FontWeight.w600 : FontWeight.w400,
                    ),
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
        barGroups: barGroups,
      ),
    );

    if (weekRanges.isEmpty || points.isEmpty) {
      return SizedBox(height: 180, child: barChart);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final barAreaWidth = constraints.maxWidth - leftAxisWidth;
        final dayWidth = barAreaWidth / points.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 180, child: barChart),
            const SizedBox(height: 4),
            // Etiquetas de semana alineadas con las barras
            Row(
              children: [
                SizedBox(width: leftAxisWidth),
                ...weekRanges.map((week) => SizedBox(
                  width: week.dayCount * dayWidth,
                  child: Text(
                    week.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                )),
              ],
            ),
          ],
        );
      },
    );
  }

  List<_WeekRange> _computeWeekRanges(
      List<PeriodPoint> points, DateTime monthStart, List<String> monthNames) {
    if (points.isEmpty) return [];
    final startWeekday = monthStart.weekday;
    final ranges = <_WeekRange>[];
    int weekStart = 0;
    final mon = monthNames[monthStart.month];

    for (int i = 1; i <= points.length; i++) {
      final isLast = i == points.length;
      final nextIsMonday = (startWeekday - 1 + i) % 7 == 0;
      if (nextIsMonday || isLast) {
        ranges.add(_WeekRange(
          startIdx: weekStart,
          dayCount: i - weekStart,
          label: '${points[weekStart].label}–${points[i - 1].label}\n$mon',
        ));
        weekStart = i;
        if (isLast) break;
      }
    }
    return ranges;
  }

  Widget _buildBarChart(List<PeriodPoint> points, NumberFormat fmt, {bool skipEmpty = true}) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');
    final displayPoints = skipEmpty ? points : points;
    final nonEmpty = displayPoints.where((p) => p.amount > 0).toList();
    final maxY = nonEmpty.isEmpty
        ? 100.0
        : nonEmpty.map((p) => p.amount).reduce((a, b) => a > b ? a : b) * 1.2;

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
                    final pt = displayPoints[group.x];
                    return BarTooltipItem(
                      '${pt.label}\nQ${fmtFull.format(rod.toY)}\n${pt.orders} tickets',
                      GoogleFonts.inter(color: Colors.white, fontSize: 11),
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
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
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
                      if (idx < 0 || idx >= displayPoints.length) return const SizedBox.shrink();
                      final n = displayPoints.length;
                      // Mostrar solo algunos labels cuando hay muchos puntos
                      final step = n > 20 ? 5 : n > 10 ? 3 : n > 7 ? 2 : 1;
                      if (mode == PeriodMode.day && idx % 4 != 0) return const SizedBox.shrink();
                      if (mode == PeriodMode.week && idx % step != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          displayPoints[idx].label,
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
              barGroups: displayPoints.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.amount,
                      width: _barWidth(points.length),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7444fd), Color(0xFF9066ff)],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  double _barWidth(int count) {
    if (count <= 7) return 18;
    if (count <= 12) return 14;
    if (count <= 24) return 8;
    return 6;
  }
}

class _WeekRange {
  final int startIdx;
  final int dayCount;
  final String label;
  const _WeekRange({required this.startIdx, required this.dayCount, required this.label});
}
