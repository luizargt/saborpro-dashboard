import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/date_range.dart';
import '../../presentation/providers/dashboard_provider.dart';
import 'package:provider/provider.dart';

Widget _darkTheme(BuildContext ctx, Widget? child) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7444fd),
          onPrimary: Colors.white,
          surface: Color(0xFF1E293B),
        ),
      ),
      child: child!,
    );

// ── DATE NAVIGATOR ─────────────────────────────────────────────────────────────
// Muestra < [etiqueta ▼] > y al tocar la etiqueta abre el picker unificado.
class DateNavigator extends StatelessWidget {
  const DateNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final range = provider.range;
    final isCustom = range.mode == PeriodMode.custom;
    final canGoNext = !range.next().isFuture;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: provider.goPrevious,
        ),
        GestureDetector(
          onTap: () => _openPicker(context, provider),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  range.label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: isCustom || !canGoNext ? Colors.white24 : Colors.white,
          ),
          onPressed: isCustom || !canGoNext ? null : provider.goNext,
        ),
      ],
    );
  }

  void _openPicker(BuildContext context, DashboardProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _UnifiedPickerSheet(
        current: provider.range,
        onSelected: provider.setRange,
        onOpenCustomPicker: () => _showCustomPicker(context, provider),
      ),
    );
  }

  Future<void> _showCustomPicker(
      BuildContext context, DashboardProvider provider) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
      initialDateRange:
          DateTimeRange(start: provider.range.start, end: provider.range.end),
      builder: _darkTheme,
    );
    if (picked != null) {
      provider.setRange(DateRange(
        start: picked.start,
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
        mode: PeriodMode.custom,
      ));
    }
  }
}

// ── UNIFIED PICKER SHEET ──────────────────────────────────────────────────────
class _UnifiedPickerSheet extends StatefulWidget {
  final DateRange current;
  final void Function(DateRange) onSelected;
  final VoidCallback onOpenCustomPicker;

  const _UnifiedPickerSheet({
    required this.current,
    required this.onSelected,
    required this.onOpenCustomPicker,
  });

  @override
  State<_UnifiedPickerSheet> createState() => _UnifiedPickerSheetState();
}

class _UnifiedPickerSheetState extends State<_UnifiedPickerSheet> {
  late PeriodMode _mode;
  late DateTime _focusedMonth;
  late int _monthYear;

  static const _weekDayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _monthNames = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];
  static const _monthShort = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.current.mode == PeriodMode.custom
        ? PeriodMode.day
        : widget.current.mode;
    _focusedMonth = DateTime(
        widget.current.start.year, widget.current.start.month);
    _monthYear = widget.current.start.year;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildModeTabs(),
          ),
          const SizedBox(height: 8),
          _buildContent(),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    const modes = [
      (PeriodMode.day, 'Día'),
      (PeriodMode.week, 'Semana'),
      (PeriodMode.month, 'Mes'),
      (PeriodMode.year, 'Año'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          ...modes.map((m) {
            final sel = _mode == m.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _mode = m.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF7444fd) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    m.$2,
                    style: GoogleFonts.inter(
                      color: sel ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: () => setState(() => _mode = PeriodMode.custom),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _mode == PeriodMode.custom
                    ? const Color(0xFF7444fd)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.date_range,
                size: 16,
                color: _mode == PeriodMode.custom
                    ? Colors.white
                    : Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case PeriodMode.day:
      case PeriodMode.week:
        return _buildCalendar();
      case PeriodMode.month:
        return _buildMonthGrid();
      case PeriodMode.year:
        return _buildYearGrid();
      case PeriodMode.custom:
        return _buildCustomButton();
    }
  }

  // ── CALENDARIO (Día / Semana) ───────────────────────────────────────────────
  Widget _buildCalendar() {
    final now = DateTime.now();
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDay =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = firstDay.weekday - 1; // 0=Lun
    final totalRows = (startOffset + daysInMonth + 6) ~/ 7;

    // Límites de la semana seleccionada (para modo semana)
    DateTime? wStart;
    DateTime? wEnd;
    if (_mode == PeriodMode.week) {
      final ws = widget.current.start;
      final mon = ws.subtract(Duration(days: ws.weekday - 1));
      wStart = DateTime(mon.year, mon.month, mon.day);
      wEnd = wStart.add(const Duration(days: 6));
    }

    final canGoNext = !(_focusedMonth.year == now.year &&
        _focusedMonth.month >= now.month);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Navegador de mes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => setState(() {
                  _focusedMonth = DateTime(
                      _focusedMonth.year, _focusedMonth.month - 1);
                }),
              ),
              Text(
                '${_monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: canGoNext ? Colors.white : Colors.white24),
                onPressed: canGoNext
                    ? () => setState(() {
                          _focusedMonth = DateTime(
                              _focusedMonth.year, _focusedMonth.month + 1);
                        })
                    : null,
              ),
            ],
          ),
          // Encabezados días
          Row(
            children: _weekDayLabels
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // Filas de días
          ...List.generate(totalRows, (row) {
            return Row(
              children: List.generate(7, (col) {
                final dayIndex = row * 7 + col - startOffset;
                if (dayIndex < 0 || dayIndex >= daysInMonth) {
                  return const Expanded(child: SizedBox(height: 38));
                }
                final day = dayIndex + 1;
                final date =
                    DateTime(_focusedMonth.year, _focusedMonth.month, day);
                final isFuture = date
                    .isAfter(DateTime(now.year, now.month, now.day));
                final isToday = date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;

                bool isSelected = false;
                BorderRadius radius = BorderRadius.circular(8);

                if (_mode == PeriodMode.day) {
                  final sel = widget.current.start;
                  isSelected = date.year == sel.year &&
                      date.month == sel.month &&
                      date.day == sel.day;
                  radius = BorderRadius.circular(20);
                } else if (wStart != null && wEnd != null) {
                  isSelected =
                      !date.isBefore(wStart!) && !date.isAfter(wEnd!);
                  if (isSelected) {
                    final leftEdge =
                        date == wStart || date.day == 1 || col == 0;
                    final rightEdge = date == wEnd ||
                        date.day == daysInMonth ||
                        col == 6;
                    radius = BorderRadius.horizontal(
                      left: leftEdge
                          ? const Radius.circular(8)
                          : Radius.zero,
                      right: rightEdge
                          ? const Radius.circular(8)
                          : Radius.zero,
                    );
                  }
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: isFuture
                        ? null
                        : () {
                            if (_mode == PeriodMode.day) {
                              Navigator.pop(context);
                              widget.onSelected(DateRange(
                                start: DateTime(
                                    date.year, date.month, date.day),
                                end: DateTime(date.year, date.month,
                                    date.day, 23, 59, 59),
                                mode: PeriodMode.day,
                              ));
                            } else {
                              final mon = date.subtract(
                                  Duration(days: date.weekday - 1));
                              final start = DateTime(
                                  mon.year, mon.month, mon.day);
                              final end = DateTime(mon.year, mon.month,
                                  mon.day + 6, 23, 59, 59);
                              Navigator.pop(context);
                              widget.onSelected(DateRange(
                                  start: start,
                                  end: end,
                                  mode: PeriodMode.week));
                            }
                          },
                    child: Container(
                      height: 38,
                      decoration: isSelected
                          ? BoxDecoration(
                              color: const Color(0xFF7444fd)
                                  .withOpacity(0.85),
                              borderRadius: radius,
                            )
                          : null,
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: GoogleFonts.inter(
                          color: isFuture
                              ? Colors.white24
                              : isSelected
                                  ? Colors.white
                                  : isToday
                                      ? const Color(0xFF7444fd)
                                      : Colors.white70,
                          fontSize: 14,
                          fontWeight: (isSelected || isToday)
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── GRILLA DE MESES ────────────────────────────────────────────────────────
  Widget _buildMonthGrid() {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => setState(() => _monthYear--),
              ),
              Text('$_monthYear',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: _monthYear >= now.year
                        ? Colors.white24
                        : Colors.white),
                onPressed: _monthYear >= now.year
                    ? null
                    : () => setState(() => _monthYear++),
              ),
            ],
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.8,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(12, (i) {
              final month = i + 1;
              final isFuture =
                  _monthYear == now.year && month > now.month;
              final isSelected = _monthYear ==
                      widget.current.start.year &&
                  month == widget.current.start.month;
              return GestureDetector(
                onTap: isFuture
                    ? null
                    : () {
                        final lastDay = DateUtils.getDaysInMonth(
                            _monthYear, month);
                        Navigator.pop(context);
                        widget.onSelected(DateRange(
                          start: DateTime(_monthYear, month, 1),
                          end: DateTime(
                              _monthYear, month, lastDay, 23, 59, 59),
                          mode: PeriodMode.month,
                        ));
                      },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF7444fd)
                        : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _monthShort[i],
                    style: GoogleFonts.inter(
                      color: isFuture
                          ? Colors.white24
                          : isSelected
                              ? Colors.white
                              : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── GRILLA DE AÑOS ─────────────────────────────────────────────────────────
  Widget _buildYearGrid() {
    final now = DateTime.now();
    final years = List.generate(now.year - 2019, (i) => 2020 + i);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.8,
            physics: const NeverScrollableScrollPhysics(),
            children: years.map((year) {
              final isSelected = year == widget.current.start.year;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onSelected(DateRange(
                    start: DateTime(year, 1, 1),
                    end: DateTime(year, 12, 31, 23, 59, 59),
                    mode: PeriodMode.year,
                  ));
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF7444fd)
                        : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$year',
                    style: GoogleFonts.inter(
                      color:
                          isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── PERSONALIZADO ──────────────────────────────────────────────────────────
  Widget _buildCustomButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          widget.onOpenCustomPicker();
        },
        icon: const Icon(Icons.date_range),
        label: const Text('Seleccionar rango personalizado'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7444fd),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

// ── PERIOD MODE BAR (kept for compatibility) ──────────────────────────────────
class PeriodModeBar extends StatelessWidget {
  const PeriodModeBar({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ── PERIOD SELECTOR (legacy) ──────────────────────────────────────────────────
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return const DateNavigator();
  }
}
