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

  const SalesChart({
    super.key,
    required this.points,
    required this.mode,
    this.weeklyHourly = const [],
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

    // Gráfico de horas siempre muestra la semana actual con líneas por día
    if (weeklyHourly.isNotEmpty) {
      return _buildWeeklyHourlyChart(weeklyHourly, fmt);
    }

    // Fallback: gráfico de barras estándar
    return _buildBarChart(points, fmt);
  }

  Widget _buildWeeklyHourlyChart(List<DayHourlyPoints> days, NumberFormat fmt) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');
    double maxY = 100;
    for (final d in days) {
      for (final v in d.hourlyAmounts) {
        if (v > maxY) maxY = v;
      }
    }
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

  Widget _buildBarChart(List<PeriodPoint> points, NumberFormat fmt) {
    final fmtFull = NumberFormat('#,##0.00', 'en_US');
    final nonEmpty = points.where((p) => p.amount > 0).toList();
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
                    final pt = points[group.x];
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
                      if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                      if (mode == PeriodMode.day && idx % 4 != 0) {
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
              barGroups: points.asMap().entries.map((e) {
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
