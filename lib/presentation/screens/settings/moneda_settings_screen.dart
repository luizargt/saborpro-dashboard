import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/services/location_service.dart';
import '../../../core/utils/monedas.dart';
import '../../../data/models/config_moneda.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/max_content_width.dart';

const _fondo = Color(0xFF0F172A);
const _tarjeta = Color(0xFF1E293B);
const _acento = Color(0xFF7444fd);
const _ambar = Color(0xFFF59E0B);

final _fmtTasa = NumberFormat('#,##0.####', 'en_US');
final _fmtFecha = DateFormat("d 'de' MMMM 'de' y", 'es');

/// Moneda principal del negocio y tipos de cambio.
///
/// Sirve a los negocios con sucursales que venden en monedas distintas: para
/// ver todo junto, cada venta se pasa a la moneda principal con el tipo de
/// cambio que estaba vigente el día que se cobró. Cada ajuste vale desde su
/// fecha en adelante, así que cambiarlo no reescribe reportes ya vistos.
///
/// La moneda principal y los tipos de cambio son del negocio (los ven todos);
/// solo quien ve todas las sucursales los cambia. Ver cada sucursal en su
/// moneda es una preferencia de cada persona.
class MonedaSettingsScreen extends StatefulWidget {
  const MonedaSettingsScreen({super.key});

  @override
  State<MonedaSettingsScreen> createState() => _MonedaSettingsScreenState();
}

class _MonedaSettingsScreenState extends State<MonedaSettingsScreen> {
  bool _guardando = false;

  /// Aplica [cambio] sobre lo guardado en este momento (no sobre lo que la
  /// pantalla tenía en memoria): dos personas editando no se pisan.
  Future<void> _guardar(ConfigMoneda Function(ConfigMoneda actual) cambio) async {
    setState(() => _guardando = true);
    try {
      await context.read<DashboardProvider>().cambiarConfigMoneda(cambio);
    } catch (e) {
      if (mounted) {
        final texto = e is StateError ? e.message : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $texto')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarPrincipal(DashboardProvider dash, String codigo) async {
    final config = dash.configMoneda;
    final implicita = dash.codigoPrincipal;
    if (codigo == implicita && config.principal != null) return;
    final hayTasas = config.tasas.values.any((l) => l.isNotEmpty);
    if (hayTasas && codigo != implicita) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _tarjeta,
          title: Text('¿Cambiar la moneda principal?',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          content: Text(
            'Los tipos de cambio están escritos contra ${describirMoneda(implicita)}. '
            'Con otra moneda principal ya no sirven: se borran y tendrás que ponerlos de nuevo.',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambiar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final principalVista = config.principal;
    await _guardar((actual) {
      // Otra persona la cambió mientras esta pantalla estaba abierta: decidir
      // con lo de antes podría borrar sus tipos de cambio sin avisar.
      if (actual.principal != principalVista) {
        throw StateError('La moneda principal cambió mientras tanto. Vuelve a abrir esta pantalla.');
      }
      // Sin elegir antes, la principal era "la que más sucursales usan": se fija
      // en serio para que no cambie sola si mañana se abre otra sucursal. Si es
      // la misma que ya se usaba, los tipos de cambio siguen valiendo.
      if (actual.principal == null) {
        return ConfigMoneda(
          principal: codigo,
          tasas: codigo == implicita ? actual.tasas : const {},
        );
      }
      return actual.conPrincipal(codigo);
    });
  }

  Future<void> _ponerTasa(DashboardProvider dash, String codigo) async {
    final principal = dash.codigoPrincipal;
    final actual = dash.configMoneda.tasaEn(codigo, DateTime.now());
    final tasa = await showDialog<TasaCambio>(
      context: context,
      builder: (_) => _TasaDialog(
        simboloPrincipal: dash.simboloDe(principal),
        simboloMoneda: dash.simboloDe(codigo),
        nombreMoneda: describirMoneda(codigo),
        valorActual: actual?.valor,
        esLaPrimera: actual == null,
      ),
    );
    if (tasa == null) return;
    await _guardar((guardada) {
      // La tasa se escribió contra la principal que se veía. Si alguien la
      // cambió mientras tanto, guardarla diría otra cosa.
      if (guardada.principal != null && guardada.principal != principal) {
        throw StateError('La moneda principal cambió mientras tanto. Vuelve a abrir esta pantalla.');
      }
      // Fijar la principal también: los tipos de cambio solo valen contra ella.
      final base = guardada.principal == null
          ? ConfigMoneda(principal: principal, tasas: guardada.tasas)
          : guardada;
      return base.conTasa(codigo, tasa);
    });
  }

  Future<void> _borrarTasa(DashboardProvider dash, String codigo, TasaCambio t) async {
    final lista = dash.configMoneda.tasas[codigo] ?? const [];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _tarjeta,
        title: Text('¿Borrar este tipo de cambio?',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          lista.length == 1
              ? 'Es el único: sin él, las ventas en ${describirMoneda(codigo)} dejan de sumarse con las demás.'
              : 'Las ventas desde el ${_fmtFecha.format(t.desde)} se convertirán con el tipo de cambio anterior.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _guardar((guardada) {
      // Si alguien cambió el valor de ese día mientras tanto, no se borra el
      // suyo creyendo borrar este.
      final hoy = guardada.tasas[codigo] ?? const <TasaCambio>[];
      final sigue = hoy.any((x) =>
          TasaCambio.fechaTexto(x.desde) == TasaCambio.fechaTexto(t.desde) && x.valor == t.valor);
      if (!sigue) {
        throw StateError('Ese tipo de cambio cambió mientras tanto. Vuelve a abrir esta pantalla.');
      }
      return guardada.sinTasa(codigo, t.desde);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final principal = dash.codigoPrincipal;
    final puedeEditar = dash.puedeEditarMoneda && dash.configMonedaLeida && !_guardando;

    // Las monedas en que venden las sucursales, con quién vende en cada una.
    // También las inactivas: sus ventas viejas entran en los reportes.
    final porMoneda = <String, List<LocationModel>>{};
    for (final l in dash.sucursalesParaMoneda) {
      porMoneda.putIfAbsent(l.currencyCode, () => []).add(l);
    }
    final otras = porMoneda.keys.where((c) => c != principal).toList()..sort();
    final opciones = [
      ...porMoneda.keys,
      for (final c in codigosDeMoneda)
        if (!porMoneda.containsKey(c)) c,
    ];

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1020),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Moneda y tipo de cambio',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: _guardando
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2, color: _acento),
              )
            : null,
      ),
      body: MaxContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
          children: [
            Text(
              'Para ver juntas sucursales que venden en monedas distintas, cada venta se pasa '
              'a tu moneda principal con el tipo de cambio del día en que se cobró.',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 13.5, height: 1.45),
            ),
            if (!dash.configMonedaLeida) ...[
              const SizedBox(height: 10),
              Text(
                'No se pudo leer el tipo de cambio guardado. Revisa la conexión, desliza '
                'hacia abajo en el inicio para actualizar y vuelve a entrar aquí.',
                style: GoogleFonts.inter(color: _ambar, fontSize: 13, height: 1.4),
              ),
            ] else if (!dash.puedeEditarMoneda) ...[
              const SizedBox(height: 10),
              Text(
                'Solo quien ve todas las sucursales puede cambiar esto.',
                style: GoogleFonts.inter(color: _ambar, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            _Titulo('Moneda principal'),
            const SizedBox(height: 8),
            _Caja(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: principal,
                  isExpanded: true,
                  dropdownColor: _tarjeta,
                  iconEnabledColor: Colors.white54,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  items: [
                    for (final c in opciones)
                      DropdownMenuItem(
                        value: c,
                        child: Text('${describirMoneda(c)} · ${dash.simboloDe(c)}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: puedeEditar ? (c) => c == null ? null : _cambiarPrincipal(dash, c) : null,
                ),
              ),
            ),
            if (dash.configMoneda.principal == null && dash.hayOtraMoneda) ...[
              const SizedBox(height: 6),
              Text(
                'Sin elegir, es la que más sucursales usan.',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            if (otras.isEmpty)
              Text(
                'Todas tus sucursales venden en ${describirMoneda(principal)}: no hace falta tipo de cambio.',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 13.5, height: 1.4),
              )
            else ...[
              _Titulo('Tipos de cambio'),
              const SizedBox(height: 8),
              for (final c in otras) ...[
                _MonedaCard(
                  codigo: c,
                  sucursales: porMoneda[c] ?? const [],
                  simboloPrincipal: dash.simboloDe(principal),
                  simboloMoneda: dash.simboloDe(c),
                  tasas: dash.configMoneda.tasas[c] ?? const [],
                  puedeEditar: puedeEditar,
                  onPoner: () => _ponerTasa(dash, c),
                  onBorrar: (t) => _borrarTasa(dash, c, t),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (dash.hayOtraMoneda) ...[
              const SizedBox(height: 12),
              _Caja(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: dash.verEnLocal,
                  activeColor: _acento,
                  onChanged: (v) => dash.setVerEnLocal(v),
                  title: Text('Ver cada sucursal en su moneda',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Al elegir una sola sucursal. "Todas" siempre se ve en la principal: '
                    'no se pueden sumar monedas distintas.',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5, height: 1.35),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: GoogleFonts.inter(
            color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
      );
}

class _Caja extends StatelessWidget {
  const _Caja({required this.child});
  final Widget child;

  // Material y no Container: el interruptor de abajo es un ListTile, que
  // necesita un Material debajo para pintar su color y el toque.
  @override
  Widget build(BuildContext context) => Material(
        color: _tarjeta,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: child,
        ),
      );
}

/// Una moneda distinta de la principal: con quién vende en ella, el tipo de
/// cambio vigente y los anteriores.
class _MonedaCard extends StatelessWidget {
  const _MonedaCard({
    required this.codigo,
    required this.sucursales,
    required this.simboloPrincipal,
    required this.simboloMoneda,
    required this.tasas,
    required this.puedeEditar,
    required this.onPoner,
    required this.onBorrar,
  });

  final String codigo;
  final List<LocationModel> sucursales;
  final String simboloPrincipal;
  final String simboloMoneda;
  final List<TasaCambio> tasas;
  final bool puedeEditar;
  final VoidCallback onPoner;
  final ValueChanged<TasaCambio> onBorrar;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final vigentes = tasas.where((t) => !t.desde.isAfter(hoy)).toList();
    final vigente = vigentes.isNotEmpty ? vigentes.last : (tasas.isNotEmpty ? tasas.first : null);
    final historial = tasas.reversed.toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _tarjeta, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(describirMoneda(codigo),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            sucursales
                .map((l) => l.visible
                    ? l.name
                    : l.esBodega
                        ? '${l.name} (bodega)'
                        : '${l.name} (inactiva)')
                .join(', '),
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (vigente == null)
            Text(
              'Sin tipo de cambio: estas sucursales no entran en los totales de "Todas".',
              style: GoogleFonts.inter(color: _ambar, fontSize: 13, height: 1.4),
            )
          else ...[
            Text(
              '1 $simboloPrincipal = ${_fmtTasa.format(vigente.valor)} $simboloMoneda',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(
              'desde el ${_fmtFecha.format(vigente.desde)}',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5),
            ),
          ],
          if (puedeEditar) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onPoner,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(vigente == null ? 'Poner tipo de cambio' : 'Cambiar tipo de cambio'),
              ),
            ),
          ],
          if (historial.length > 1 || (historial.isNotEmpty && puedeEditar)) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.06), height: 1),
            const SizedBox(height: 6),
            for (final t in historial)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Desde el ${_fmtFecha.format(t.desde)}',
                        style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${_fmtTasa.format(t.valor)} $simboloMoneda',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    if (puedeEditar)
                      IconButton(
                        tooltip: 'Borrar',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white38),
                        onPressed: () => onBorrar(t),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Cuánto vale 1 de la principal en esta moneda, y desde qué día.
class _TasaDialog extends StatefulWidget {
  const _TasaDialog({
    required this.simboloPrincipal,
    required this.simboloMoneda,
    required this.nombreMoneda,
    required this.valorActual,
    required this.esLaPrimera,
  });

  final String simboloPrincipal;
  final String simboloMoneda;
  final String nombreMoneda;
  final double? valorActual;
  final bool esLaPrimera;

  @override
  State<_TasaDialog> createState() => _TasaDialogState();
}

class _TasaDialogState extends State<_TasaDialog> {
  late final TextEditingController _valor = TextEditingController(
      text: widget.valorActual == null ? '' : _fmtTasa.format(widget.valorActual).replaceAll(',', ''));
  late DateTime _desde = _hoy();
  String? _error;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _desde,
      firstDate: DateTime(2020),
      lastDate: DateTime(_hoy().year + 1, 12, 31),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _acento,
            onPrimary: Colors.white,
            surface: _tarjeta,
          ),
        ),
        child: child!,
      ),
    );
    if (elegida != null) setState(() => _desde = elegida);
  }

  void _listo() {
    final valor = leerNumeroTasa(_valor.text);
    if (valor == null || valor <= 0 || !valor.isFinite) {
      setState(() => _error = 'Escribe un número mayor que cero');
      return;
    }
    Navigator.pop(context, TasaCambio(desde: _desde, valor: valor));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _tarjeta,
      title: Text(
        widget.nombreMoneda,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Cuántos ${widget.simboloMoneda} son 1 ${widget.simboloPrincipal}?',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _valor,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: '1 ${widget.simboloPrincipal} = ',
                suffixText: widget.simboloMoneda,
                errorText: _error,
                filled: true,
                fillColor: _fondo,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (_) => _listo(),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _elegirFecha,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: _fondo, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 18, color: Colors.white54),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Desde el ${_fmtFecha.format(_desde)}',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    Text('Cambiar', style: GoogleFonts.inter(color: _acento, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.esLaPrimera
                  ? 'Como es el primero, también se usa para las ventas anteriores a esa fecha.'
                  : 'Las ventas desde ese día se convierten con este valor; las anteriores siguen con el que tenían.',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: _listo, child: const Text('Guardar')),
      ],
    );
  }
}

/// Lee lo que se escribió como tipo de cambio. La coma puede ser de miles
/// ("1,200" = mil doscientos, que es justo el rango del peso argentino contra
/// el dólar) o decimal ("7,75"): con grupos de tres cifras es de miles; si
/// no, decimal. Con coma y punto juntos, la coma es de miles ("1,234.5").
double? leerNumeroTasa(String texto) {
  var t = texto.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',') && t.contains('.')) {
    t = t.replaceAll(',', '');
  } else if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(',', '');
  } else {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}
