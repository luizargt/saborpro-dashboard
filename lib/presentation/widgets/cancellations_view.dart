/// La parte visual del reporte "Pedidos Cancelados", separada de la pantalla.
///
/// Vive aparte a propósito: la pantalla depende de providers con Firebase y no
/// se puede montar en un test, pero la regla del proyecto es verificar cada UI
/// nueva a 360dp con un widget test que falle si algo desborda. Esta mitad solo
/// necesita un [CancellationsReport] armado a mano, así que sí se puede probar
/// (ver test/presentation/widgets/cancellations_view_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../data/models/cancellation_data.dart';

// Paleta del dashboard (misma que Cierres de caja y Gastos).
const kCancelBg = Color(0xFF0F172A);
const _kCard = Color(0xFF1E293B);
const _kAccent = Color(0xFF7444fd);
const _kLoss = Color(0xFFEF4444);
const _kBack = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);

final _fmtMoney = NumberFormat('#,##0.00', 'en_US');
final _fmtInt = NumberFormat('#,##0', 'en_US');

/// Todo el contenido desplazable del reporte, de arriba hacia abajo:
/// el número grande, una fila por cancelación y el corte por persona.
class CancellationsReportBody extends StatelessWidget {
  final CancellationsReport report;

  const CancellationsReportBody({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroCard(report: r),
        if (r.truncated) ...[
          const SizedBox(height: 12),
          const _Notice(
            icon: Icons.warning_amber_rounded,
            color: _kWarn,
            text: 'Hay más movimientos de los que se pueden leer de una vez. '
                'Los totales de abajo se quedan cortos: acortá el periodo para '
                'verlo completo.',
          ),
        ],
        if (r.unpricedIngredients > 0) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.help_outline_rounded,
            color: _kWarn,
            text:
                '${r.unpricedIngredients} ${r.unpricedIngredients == 1 ? "ingrediente no tiene" : "ingredientes no tienen"} '
                'precio de compra. Lo que se perdió de ellos se cuenta en '
                'unidades, no en quetzales: no es que valgan cero.',
          ),
        ],
        const SizedBox(height: 20),
        _SectionTitle(
          'Cancelaciones',
          trailing: r.events.isEmpty ? null : '${r.events.length}',
        ),
        const SizedBox(height: 10),
        if (r.events.isEmpty)
          const _EmptyCard(text: 'Ninguna cancelación en este periodo.')
        else
          _EventsList(events: r.events),
        const SizedBox(height: 24),
        const _SectionTitle('Por persona'),
        const SizedBox(height: 4),
        Text(
          'Quién declara que el producto NO regresa. Declarar merma no pide '
          'permiso, así que esta es la única revisión que queda.',
          style:
              GoogleFonts.inter(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (r.people.isEmpty)
          const _EmptyCard(text: 'Nadie canceló nada en este periodo.')
        else
          _PeopleCut(report: r),
      ],
    );
  }
}

// ── EL NÚMERO GRANDE ─────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final CancellationsReport report;
  const _HeroCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final noInventory =
        report.cancelledBeforeKitchen + report.cancelledWithoutRecipe;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLoss.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delete_outline_rounded, color: _kLoss, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Producto perdido en cancelaciones',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ValueText(value: report.totalWasted, color: _kLoss, size: 30),
          const SizedBox(height: 10),
          Text(
            report.itemsCancelled == 0
                ? 'Nadie declaró producto perdido.'
                : '${_fmtInt.format(report.itemsLost)} de ${_fmtInt.format(report.itemsCancelled)} '
                    'artículos anulados se declararon perdidos '
                    '(${(report.houseLostRate * 100).round()}%).',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5, height: 1.4),
          ),
          const Divider(color: Colors.white12, height: 26),
          // Wrap y no Row: a 360dp dos columnas de números no caben sin
          // recortar el monto.
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _MiniStat(
                label: 'Regresó a despensa',
                child: _ValueText(
                    value: report.totalReturned, color: _kBack, size: 17),
              ),
              _MiniStat(
                label: 'Sin tocar inventario',
                child: Text(
                  noInventory == 0 ? '—' : '${_fmtInt.format(noInventory)} pedidos',
                  style: GoogleFonts.inter(
                    color: noInventory == 0 ? Colors.white38 : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (noInventory > 0) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (report.cancelledBeforeKitchen > 0)
                  '${report.cancelledBeforeKitchen} se deshicieron antes de cocina',
                if (report.cancelledWithoutRecipe > 0)
                  '${report.cancelledWithoutRecipe} sin receta que devolver',
              ].join(' · '),
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final Widget child;
  const _MiniStat({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Dibuja un [PartialValue] sin mentir.
///
/// Lo que tiene precio se muestra en quetzales; lo que no, en unidades. Nunca
/// aparece "Q0.00" para algo que sí se perdió: eso es exactamente lo que hace
/// que un faltante pase desapercibido.
class _ValueText extends StatelessWidget {
  final PartialValue value;
  final Color color;
  final double size;

  const _ValueText({
    required this.value,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return Text('—',
          style: GoogleFonts.inter(
              color: Colors.white38, fontSize: size, fontWeight: FontWeight.w700));
    }

    final money = value.hasMoney;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            money ? 'Q${_fmtMoney.format(value.amount)}' : value.unpricedLabel,
            style: GoogleFonts.inter(
              color: color,
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (value.hasUnpriced)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              money
                  ? '+ ${value.unpricedLabel} sin costo'
                  : 'sin precio de compra',
              style: GoogleFonts.inter(
                color: _kWarn,
                fontSize: size <= 18 ? 11 : 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ── UNA FILA POR CANCELACIÓN ─────────────────────────────────────────────────

class _EventsList extends StatefulWidget {
  final List<CancellationEvent> events;
  const _EventsList({required this.events});

  @override
  State<_EventsList> createState() => _EventsListState();
}

class _EventsListState extends State<_EventsList> {
  // Con la lista entera desplegada, el corte por persona —que es lo que hay
  // que revisar— queda a un scroll interminable en un teléfono.
  static const _kPreview = 15;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown =
        _all ? widget.events : widget.events.take(_kPreview).toList();
    final rest = widget.events.length - shown.length;

    return Column(
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EventTile(event: e),
          ),
        if (rest > 0)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text(
              'Ver las otras $rest cancelaciones',
              style: GoogleFonts.inter(color: _kAccent, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _EventTile extends StatefulWidget {
  final CancellationEvent event;
  const _EventTile({required this.event});

  @override
  State<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends State<_EventTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final when = DateFormat('d MMM · HH:mm', 'es').format(e.at);
    final summary = e.items.isEmpty
        ? 'Sin detalle de artículos'
        : e.items
            .map((i) => i.qty > 1 ? '${i.name} x${i.qty}' : i.name)
            .join(' · ');

    return Material(
      color: _kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: e.items.isEmpty ? null : () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '$when  ·  ${e.tableLabel}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ImpactBadge(impact: e.impact),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                summary,
                maxLines: _open ? 6 : 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 8),
              // A 360dp los dos montos no caben junto al nombre en una fila.
              Wrap(
                spacing: 16,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _InlineValue(
                      label: 'Regresó', value: e.returned, color: _kBack),
                  _InlineValue(label: 'Merma', value: e.wasted, color: _kLoss),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                e.reason == null || e.reason!.isEmpty
                    ? '${e.userName}  ·  sin motivo anotado'
                    : '${e.userName}  ·  ${e.reason}',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5),
              ),
              if (_open && e.items.isNotEmpty) ...[
                const Divider(color: Colors.white12, height: 20),
                for (final i in e.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            i.qty > 1 ? '${i.name} x${i.qty}' : i.name,
                            style: GoogleFonts.inter(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (i.declaredLost)
                          _ValueText(value: i.wasted, color: _kLoss, size: 12)
                        else
                          Text(
                            'Regresó completo',
                            style: GoogleFonts.inter(
                                color: _kBack,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineValue extends StatelessWidget {
  final String label;
  final PartialValue value;
  final Color color;

  const _InlineValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5)),
        _ValueText(value: value, color: color, size: 13),
      ],
    );
  }
}

class _ImpactBadge extends StatelessWidget {
  final InventoryImpact impact;
  const _ImpactBadge({required this.impact});

  @override
  Widget build(BuildContext context) {
    // Las cancelaciones que no mueven producto van marcadas distinto en vez de
    // esconderse: cuántos pedidos se toman y se deshacen es otro síntoma.
    final Color color;
    switch (impact) {
      case InventoryImpact.conMovimiento:
        color = _kAccent;
      case InventoryImpact.sinCocina:
        color = const Color(0xFF3B82F6);
      case InventoryImpact.sinReceta:
        color = Colors.white38;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        impact.label,
        style: GoogleFonts.inter(
          color: color == Colors.white38 ? Colors.white60 : color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── EL CORTE POR PERSONA ─────────────────────────────────────────────────────

class _PeopleCut extends StatelessWidget {
  final CancellationsReport report;
  const _PeopleCut({required this.report});

  /// Alguien "salta a la vista" cuando marca perdido bastante más seguido que
  /// la casa. Se exige un mínimo de casos para no señalar a quien anuló dos
  /// cosas y tuvo mala suerte.
  bool _standsOut(PersonCut p) {
    if (p.itemsLost < 3) return false;
    final bar = (report.houseLostRate * 1.5).clamp(0.2, 1.0);
    return p.lostRate > bar;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final p in report.people)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PersonTile(
              person: p,
              houseRate: report.houseLostRate,
              flagged: _standsOut(p),
            ),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Promedio de la casa: ${(report.houseLostRate * 100).round()}% de lo '
            'anulado se declaró perdido.',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  final PersonCut person;
  final double houseRate;
  final bool flagged;

  const _PersonTile({
    required this.person,
    required this.houseRate,
    required this.flagged,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (person.lostRate * 100).round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: flagged
            ? Border.all(color: _kLoss.withValues(alpha: 0.55))
            : Border.all(color: Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  person.userName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (flagged) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kLoss.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Revisar',
                    style: GoogleFonts.inter(
                      color: _kLoss,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // La barra compara contra el promedio de la casa: el número solo no
          // dice nada, lo que delata es la distancia con el resto.
          _RateBar(rate: person.lostRate, houseRate: houseRate, flagged: flagged),
          const SizedBox(height: 8),
          Text(
            person.itemsCancelled == 0
                ? '${person.events} ${person.events == 1 ? "cancelación" : "cancelaciones"} sin efecto en inventario'
                : '$pct% declarado perdido · ${person.itemsLost} de ${person.itemsCancelled} artículos · '
                    '${person.events} ${person.events == 1 ? "cancelación" : "cancelaciones"}',
            style: GoogleFonts.inter(
                color: Colors.white54, fontSize: 11.5, height: 1.35),
          ),
          if (!person.wasted.isEmpty) ...[
            const SizedBox(height: 8),
            _InlineValue(
                label: 'Merma', value: person.wasted, color: _kLoss),
          ],
        ],
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  final double rate;
  final double houseRate;
  final bool flagged;

  const _RateBar({
    required this.rate,
    required this.houseRate,
    required this.flagged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final fill = (w * rate.clamp(0.0, 1.0)).clamp(0.0, w);
      final marker = (w * houseRate.clamp(0.0, 1.0)).clamp(0.0, w - 2);

      return SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              width: fill,
              decoration: BoxDecoration(
                color: flagged ? _kLoss : _kAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Marca del promedio de la casa.
            Positioned(
              left: marker,
              child: Container(width: 2, height: 8, color: Colors.white54),
            ),
          ],
        ),
      );
    });
  }
}

// ── PIEZAS CHICAS ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const _SectionTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}
