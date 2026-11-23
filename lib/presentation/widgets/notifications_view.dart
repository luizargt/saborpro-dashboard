/// La parte visual de la bandeja de avisos, separada de la pantalla.
///
/// Vive aparte por la misma razón que las otras vistas del Manager: la pantalla
/// depende de providers con Firebase, pero esta mitad solo necesita una lista
/// de [ManagerNotification] armada a mano y se puede probar a 360dp (ver
/// test/presentation/widgets/notifications_view_test.dart).
///
/// Diseño (2026-11-20): `assets/Desing/Sabor Manager/avisos.html` de
/// saborpro_app, en su modo oscuro (la misma paleta del detalle de cortesías).
/// Qué se muestra y qué hace cada toque NO cambia: sale todo de la misma lista
/// y tocar un aviso lo marca como leído. Lo nuevo del diseño: los filtros por
/// tipo, la pastilla y el monto de cada fila, juntar las entradas de inventario
/// seguidas y "Marcar leídas" siempre a la vista. Los datos de cada fila (quién,
/// cuánto, sucursal) los lee [AvisoResumen] del texto que guarda el servidor.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/aviso_resumen.dart';
import '../../data/models/manager_notification.dart';
import 'cortesias_view.dart' show CortesiasColores, cortesiasTexto, kCortesiasBg;
import '../navigation/contexto_shell.dart';

/// Fondo de la pantalla.
Color get kAvisosBg => kCortesiasBg;

typedef _C = CortesiasColores;
const _t = cortesiasTexto;

final _fmtCant = NumberFormat('#,##0.##', 'en_US');

Color _colorDe(TonoAviso t) => switch (t) {
      TonoAviso.ok => _C.gift,
      TonoAviso.warn => _C.warn,
      TonoAviso.bad => _C.bad,
      TonoAviso.blue => _C.don,
      TonoAviso.accent => _C.accent,
    };

Color _fondoDe(TonoAviso t) => switch (t) {
      TonoAviso.ok => _C.giftTint,
      TonoAviso.warn => _C.warnTint,
      TonoAviso.bad => _C.badTint,
      TonoAviso.blue => _C.donTint,
      TonoAviso.accent => _C.tint,
    };

/// La familia de un aviso en los filtros. Las tres primeras son las del
/// diseño y siempre se ofrecen; las otras solo si hay alguno.
enum _Familia { stock, caja, inventario, retiros, gastos, ventas, cortesias, anulaciones, otros }

_Familia _familiaDe(ManagerNotificationType t) => switch (t) {
      ManagerNotificationType.stockBajo => _Familia.stock,
      ManagerNotificationType.cajaAbierta ||
      ManagerNotificationType.cajaCerrada =>
        _Familia.caja,
      ManagerNotificationType.inventario => _Familia.inventario,
      ManagerNotificationType.retiro ||
      ManagerNotificationType.retirosEnLote =>
        _Familia.retiros,
      ManagerNotificationType.gasto => _Familia.gastos,
      ManagerNotificationType.ventasAyer => _Familia.ventas,
      ManagerNotificationType.cortesia => _Familia.cortesias,
      ManagerNotificationType.anulacion ||
      ManagerNotificationType.cuentaCancelada =>
        _Familia.anulaciones,
      ManagerNotificationType.otro => _Familia.otros,
    };

String _nombreDe(_Familia f) => switch (f) {
      _Familia.stock => 'Stock bajo',
      _Familia.caja => 'Caja',
      _Familia.inventario => 'Inventario',
      _Familia.retiros => 'Retiros',
      _Familia.gastos => 'Gastos',
      _Familia.ventas => 'Ventas',
      _Familia.cortesias => 'Cortesías',
      _Familia.anulaciones => 'Anulaciones',
      _Familia.otros => 'Avisos',
    };

/// El puntito de color del filtro.
Color _puntoDe(_Familia f) => switch (f) {
      _Familia.stock => _C.bad,
      _Familia.caja => _C.gift,
      _Familia.inventario => _C.don,
      _Familia.retiros || _Familia.gastos || _Familia.anulaciones => _C.warn,
      _Familia.ventas => _C.gift,
      _Familia.cortesias || _Familia.otros => _C.accent,
    };

String _hora(DateTime d) => DateFormat.Hm('es').format(d);

String _plural(num n, String uno, String varios) => n == 1 ? uno : varios;

/// Una fila de la lista: un aviso, o varias entradas de inventario seguidas
/// (una carga de ocho productos son ocho avisos) juntas en una.
class _Fila {
  final List<ManagerNotification> avisos;
  final AvisoResumen resumen;
  _Fila(this.avisos, this.resumen);

  String get clave => avisos.first.id;
  bool get agrupada => avisos.length > 1;
  bool get sinLeer => avisos.any((a) => !a.read);
  DateTime get cuando => avisos.first.createdAt;
}

/// Junta las entradas de inventario consecutivas de la misma persona, el mismo
/// movimiento, la misma sucursal y el mismo minuto.
List<_Fila> _armarFilas(List<ManagerNotification> avisos) {
  final filas = <_Fila>[];
  for (final a in avisos) {
    final r = AvisoResumen.de(a);
    final d = r.inventario;
    if (d != null && filas.isNotEmpty) {
      final ult = filas.last;
      final du = ult.resumen.inventario;
      if (du != null &&
          du.quien == d.quien &&
          du.movimiento == d.movimiento &&
          du.sucursal == d.sucursal &&
          _hora(ult.cuando) == _hora(a.createdAt)) {
        ult.avisos.add(a);
        continue;
      }
    }
    filas.add(_Fila([a], r));
  }
  return filas;
}

class _Dia {
  final String titulo;
  final List<ManagerNotification> avisos;
  _Dia(this.titulo, this.avisos);
}

/// Agrupa por día natural, no por "hace X horas": a las 00:30 un aviso de las
/// 23:50 es de ayer aunque hayan pasado cuarenta minutos, y mezclarlos bajo
/// "Hoy" confunde a quien está cuadrando el día.
List<_Dia> _agruparPorDia(List<ManagerNotification> avisos, DateTime ahora) {
  final hoy = DateUtils.dateOnly(ahora);
  final ayer = hoy.subtract(const Duration(days: 1));
  final dias = <_Dia>[];
  DateTime? diaActual;
  var actuales = <ManagerNotification>[];

  String titularDe(DateTime dia) {
    if (dia == hoy) return 'HOY';
    if (dia == ayer) return 'AYER';
    return DateFormat('EEEE d \'de\' MMMM', 'es').format(dia).toUpperCase();
  }

  for (final a in avisos) {
    final dia = DateUtils.dateOnly(a.createdAt);
    if (diaActual == null || dia != diaActual) {
      if (diaActual != null) dias.add(_Dia(titularDe(diaActual), actuales));
      diaActual = dia;
      actuales = [];
    }
    actuales.add(a);
  }
  if (diaActual != null) dias.add(_Dia(titularDe(diaActual), actuales));
  return dias;
}

/// El encabezado, los filtros y la lista de avisos por día. En pantalla ancha
/// el monto va a la derecha de cada fila; en el teléfono pasa al inicio de la
/// descripción.
class NotificationsView extends StatefulWidget {
  final List<ManagerNotification> avisos;
  final bool cargando;
  final String? error;

  /// Marca como leídos estos avisos (solo los que estaban sin leer).
  final ValueChanged<List<String>> onLeer;
  final VoidCallback onMarcarTodas;

  /// Para fijar "hoy" en las pruebas.
  final DateTime? ahora;

  const NotificationsView({
    super.key,
    required this.avisos,
    this.cargando = false,
    this.error,
    required this.onLeer,
    required this.onMarcarTodas,
    this.ahora,
  });

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  /// null = Todos.
  _Familia? _filtro;

  /// Las filas juntas que están desplegadas (por la clave de su primer aviso).
  final _abiertas = <String>{};

  void _tocar(_Fila f) {
    if (f.agrupada) {
      setState(() => _abiertas.contains(f.clave) ? _abiertas.remove(f.clave) : _abiertas.add(f.clave));
    }
    final ids = [for (final a in f.avisos) if (!a.read) a.id];
    if (ids.isNotEmpty) widget.onLeer(ids);
  }

  @override
  Widget build(BuildContext context) {
    final avisos = widget.avisos;
    final sinLeer = avisos.where((a) => !a.read).length;

    return LayoutBuilder(builder: (context, c) {
      // 760: el punto donde el diseño pasa a su versión de teléfono.
      final ancho = c.maxWidth > 760;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Encabezado(
            ancho: ancho,
            // Mientras carga no se dice "Todo leído": todavía no se sabe.
            sinLeer: widget.cargando ? null : sinLeer,
            onMarcarTodas: sinLeer == 0 ? null : widget.onMarcarTodas,
          ),
          Expanded(child: _cuerpo(context, ancho)),
        ],
      );
    });
  }

  Widget _cuerpo(BuildContext context, bool ancho) {
    if (widget.cargando) {
      return Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: _C.accent),
        ),
      );
    }
    if (widget.error != null) {
      return _SoloTarjeta(
        ancho: ancho,
        child: _TarjetaVacia(
          icono: Icons.cloud_off_rounded,
          titulo: 'No se pudieron cargar',
          detalle: widget.error!,
        ),
      );
    }
    if (widget.avisos.isEmpty) {
      return _SoloTarjeta(
        ancho: ancho,
        child: const _TarjetaVacia(
          icono: Icons.notifications_none_rounded,
          titulo: 'Sin avisos por ahora',
          detalle: 'Acá van a aparecer las aperturas y cierres de caja, los '
              'gastos, los retiros y los movimientos de inventario de tus '
              'sucursales.',
        ),
      );
    }

    final avisos = widget.avisos;
    final pad = ancho ? 20.0 : 16.0;
    final cuenta = <_Familia, int>{};
    for (final a in avisos) {
      cuenta.update(_familiaDe(a.tipo), (n) => n + 1, ifAbsent: () => 1);
    }

    final visibles = _filtro == null
        ? avisos
        : avisos.where((a) => _familiaDe(a.tipo) == _filtro).toList();
    final dias = _agruparPorDia(visibles, widget.ahora ?? DateTime.now());

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            pad,
            4,
            pad,
            40 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _Filtros(
              total: avisos.length,
              cuenta: cuenta,
              elegido: _filtro,
              onElegir: (f) => setState(() => _filtro = f),
            ),
            SizedBox(height: ancho ? 14 : 10),
            if (dias.isEmpty)
              const _TarjetaVacia(
                icono: Icons.check_rounded,
                titulo: 'Todo en orden',
                detalle: 'No hay avisos aquí.',
                tono: TonoAviso.ok,
              )
            else
              for (final d in dias) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                  child: Text(
                    d.titulo,
                    style: _t(12, FontWeight.w700, _C.muted).copyWith(letterSpacing: 0.84),
                  ),
                ),
                _Lista(
                  filas: _armarFilas(d.avisos),
                  ancho: ancho,
                  abiertas: _abiertas,
                  onTocar: _tocar,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// Una sola tarjeta (sin avisos, o no se pudieron cargar), arriba y con el mismo
/// ancho y relleno que la lista: sin centrarla en la pantalla, que dejaría un
/// hueco entre el encabezado y ella.
class _SoloTarjeta extends StatelessWidget {
  final bool ancho;
  final Widget child;
  const _SoloTarjeta({required this.ancho, required this.child});

  @override
  Widget build(BuildContext context) {
    final pad = ancho ? 20.0 : 16.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
          children: [child],
        ),
      ),
    );
  }
}

// ── ENCABEZADO ───────────────────────────────────────────────────────────────

class _Encabezado extends StatelessWidget {
  final bool ancho;

  /// null = cargando (no se dice nada).
  final int? sinLeer;
  final VoidCallback? onMarcarTodas;

  const _Encabezado({required this.ancho, required this.sinLeer, required this.onMarcarTodas});

  @override
  Widget build(BuildContext context) {
    final pad = ancho ? 20.0 : 16.0;
    final n = sinLeer;
    // Dentro del shell el título "Avisos" ya lo pone el encabezado del shell.
    final enShell = ContextoShell.enShell(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, ancho ? 16 : 12, pad, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!enShell) Text('Avisos', style: _t(ancho ? 26 : 22, FontWeight.w700, _C.ink, height: 1.15)),
                if (n != null)
                  Text(
                    n == 0 ? 'Todo leído' : '$n sin leer',
                    style: _t(
                      ancho ? 14 : 13,
                      FontWeight.w600,
                      n == 0 ? _C.muted : _C.accent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _BotonMarcar(ancho: ancho, onTap: onMarcarTodas),
        ],
      ),
    );
  }
}

/// "Marcar leídas": con algo pendiente va en el color de acento; sin nada, se
/// apaga pero no desaparece. En el teléfono es solo el ícono.
class _BotonMarcar extends StatelessWidget {
  final bool ancho;
  final VoidCallback? onTap;
  const _BotonMarcar({required this.ancho, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? _C.soft : _C.accent;
    return Tooltip(
      message: 'Marcar leídas',
      child: Material(
        color: _C.card,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: ancho ? 46 : 40, minWidth: ancho ? 0 : 40),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ancho ? 18 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all_rounded, size: 22, color: color),
                  if (ancho) ...[
                    const SizedBox(width: 8),
                    Text('Marcar leídas', style: _t(14.5, FontWeight.w600, color)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── FILTROS ──────────────────────────────────────────────────────────────────

class _Filtros extends StatelessWidget {
  final int total;
  final Map<_Familia, int> cuenta;
  final _Familia? elegido;
  final ValueChanged<_Familia?> onElegir;

  const _Filtros({
    required this.total,
    required this.cuenta,
    required this.elegido,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    // Las tres del diseño siempre; las demás, solo si hay (o si es la elegida).
    final familias = [
      for (final f in _Familia.values)
        if (f.index <= _Familia.inventario.index || (cuenta[f] ?? 0) > 0 || elegido == f) f,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ChipFiltro(
            texto: 'Todos',
            cuenta: total,
            elegido: elegido == null,
            onTap: () => onElegir(null),
          ),
          for (final f in familias) ...[
            const SizedBox(width: 8),
            _ChipFiltro(
              texto: _nombreDe(f),
              cuenta: cuenta[f] ?? 0,
              punto: _puntoDe(f),
              elegido: elegido == f,
              onTap: () => onElegir(f),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String texto;
  final int cuenta;
  final Color? punto;
  final bool elegido;
  final VoidCallback onTap;

  const _ChipFiltro({
    required this.texto,
    required this.cuenta,
    this.punto,
    required this.elegido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = elegido ? _C.card : _C.ink;
    return Material(
      color: elegido ? _C.ink : _C.card,
      shape: StadiumBorder(side: BorderSide(color: elegido ? _C.ink : _C.line, width: 1.5)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (punto != null) ...[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: punto, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(texto, style: _t(13.5, FontWeight.w600, color)),
                const SizedBox(width: 8),
                Text(
                  '$cuenta',
                  style: _t(12.5, FontWeight.w600, elegido ? color.withValues(alpha: 0.7) : _C.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── LISTA ────────────────────────────────────────────────────────────────────

class _Lista extends StatelessWidget {
  final List<_Fila> filas;
  final bool ancho;
  final Set<String> abiertas;
  final ValueChanged<_Fila> onTocar;

  const _Lista({
    required this.filas,
    required this.ancho,
    required this.abiertas,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < filas.length; i++)
            _FilaAviso(
              fila: filas[i],
              ancho: ancho,
              primera: i == 0,
              abierta: abiertas.contains(filas[i].clave),
              onTap: () => onTocar(filas[i]),
            ),
        ],
      ),
    );
  }
}

class _FilaAviso extends StatelessWidget {
  final _Fila fila;
  final bool ancho;
  final bool primera;
  final bool abierta;
  final VoidCallback onTap;

  const _FilaAviso({
    required this.fila,
    required this.ancho,
    required this.primera,
    required this.abierta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = fila.resumen;
    final sinLeer = fila.sinLeer;
    final agrupada = fila.agrupada;

    // La fila de varias entradas de inventario dice cuántas y cuántas unidades.
    var titulo = r.titulo;
    var pildora = r.pildora;
    var descripcion = r.descripcion;
    if (agrupada) {
      final d = r.inventario!;
      final numeros = [for (final a in fila.avisos) AvisoResumen.de(a).inventario?.cantidadNumero];
      final total = numeros.every((n) => n != null) ? numeros.fold<double>(0, (s, n) => s + n!) : null;
      titulo = '${d.movimientoCapitalizado} de inventario';
      pildora = PildoraAviso('${fila.avisos.length}', TonoAviso.blue);
      descripcion = '${d.quien}'
          '${total == null ? '' : ' · ${_fmtCant.format(total)} ${_plural(total, 'unidad', 'unidades')}'}'
          ' · ${d.sucursal}';
    }

    final tono = r.tono;
    final monto = r.monto;
    final icono = fila.avisos.first.tipo.icono;

    // El diseño la recorta a una línea. Aquí, en el teléfono, caben dos: la
    // sucursal y los nombres de un stock bajo, o el motivo de un retiro, son
    // justo lo que se abre el aviso a mirar. Un texto que no se entendió
    // (`crudo`) se muestra completo: nunca se esconde un aviso por no leerlo.
    final descWidget = Text.rich(
      TextSpan(children: [
        if (!ancho && monto != null) ...[
          TextSpan(text: monto, style: _t(13, FontWeight.w600, _C.ink)),
          const WidgetSpan(child: SizedBox(width: 6)),
        ],
        TextSpan(text: descripcion, style: _t(13, FontWeight.w400, _C.muted)),
      ]),
      maxLines: r.crudo ? null : (ancho ? 1 : 2),
      overflow: r.crudo ? TextOverflow.clip : TextOverflow.ellipsis,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            // Un aviso suelto que ya se leyó no hace nada al tocarlo (como
            // antes): sin onTap tampoco hay salpicado que prometa algo. Una fila
            // de varias entradas siempre se puede abrir y cerrar.
            onTap: agrupada || sinLeer ? onTap : null,
            hoverColor: _C.subtle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: EdgeInsets.symmetric(horizontal: ancho ? 14 : 12, vertical: 10),
              decoration: BoxDecoration(
                border: primera ? null : Border(top: BorderSide(color: _C.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: _fondoDe(tono), borderRadius: BorderRadius.circular(11)),
                    child: Icon(icono, size: 18, color: _colorDe(tono)),
                  ),
                  SizedBox(width: ancho ? 12 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Titulo(texto: titulo, sinLeer: sinLeer, pildora: pildora),
                        const SizedBox(height: 1),
                        descWidget,
                      ],
                    ),
                  ),
                  if (ancho && monto != null) ...[
                    const SizedBox(width: 12),
                    Text(monto, style: _t(14.5, FontWeight.w700, _C.ink)),
                  ],
                  SizedBox(width: ancho ? 12 : 10),
                  // La hora, el puntito de "sin leer" (su lugar se reserva
                  // aunque ya esté leído, para que las horas queden alineadas)
                  // y, en las juntas, la flecha que las despliega.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 38),
                    child: Text(
                      _hora(fila.cuando),
                      textAlign: TextAlign.right,
                      style: _t(12.5, FontWeight.w400, _C.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: sinLeer ? _C.accent : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (agrupada) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: abierta ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _C.soft),
                    ),
                  ] else if (ancho)
                    const SizedBox(width: 24),
                ],
              ),
            ),
          ),
        ),
        if (agrupada && abierta) _Detalle(fila: fila, ancho: ancho),
      ],
    );
  }
}

/// El título y, si lleva, su pastilla. Cuando no caben juntos se acorta el
/// título (con puntos suspensivos); la pastilla, que trae la cifra que importa
/// ("Faltó Q25.00"), solo se recorta si ella sola ya no cabe en la fila.
class _Titulo extends StatelessWidget {
  final String texto;
  final bool sinLeer;
  final PildoraAviso? pildora;

  const _Titulo({required this.texto, required this.sinLeer, required this.pildora});

  @override
  Widget build(BuildContext context) {
    final titulo = Text(
      texto,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _t(14.5, sinLeer ? FontWeight.w700 : FontWeight.w600, _C.ink),
    );
    final p = pildora;
    if (p == null) return titulo;

    return LayoutBuilder(builder: (context, c) {
      // Tope de la pastilla: todo el ancho menos el espacio que la separa del
      // título. Sin él, una cifra larga con letra grande la sacaba de la fila.
      final tope = !c.hasBoundedWidth
          ? double.infinity
          : c.maxWidth > 6
              ? c.maxWidth - 6
              : 0.0;
      return Row(
        children: [
          Flexible(child: titulo),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tope),
            child: _Pildora(p),
          ),
        ],
      );
    });
  }
}

class _Pildora extends StatelessWidget {
  final PildoraAviso pildora;
  const _Pildora(this.pildora);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: _fondoDe(pildora.tono), borderRadius: BorderRadius.circular(999)),
      // `Center` con widthFactor y no `alignment` en el Container: ese alineado
      // ocuparía todo el ancho que le den, y la pastilla se ensancharía.
      child: Center(
        widthFactor: 1,
        child: Text(
          pildora.texto,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: _t(11.5, FontWeight.w700, _colorDe(pildora.tono), height: 1.0),
        ),
      ),
    );
  }
}

/// Lo que trae una fila de entradas juntas: "+24 Monte Carlo Bajo Cero".
class _Detalle extends StatelessWidget {
  final _Fila fila;
  final bool ancho;
  const _Detalle({required this.fila, required this.ancho});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(ancho ? 60 : 56, 0, 14, 8),
      child: Column(
        children: [
          for (final a in fila.avisos)
            Builder(builder: (_) {
              final d = AvisoResumen.de(a).inventario!;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 36),
                      child: Text('${d.signo}${d.cantidad}', style: _t(13, FontWeight.w700, _C.don)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.producto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(13, FontWeight.w400, _C.muted),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── VACÍOS ───────────────────────────────────────────────────────────────────

class _TarjetaVacia extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final TonoAviso tono;

  const _TarjetaVacia({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.tono = TonoAviso.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tono == TonoAviso.accent ? _C.subtle : _fondoDe(tono),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icono, size: 24, color: tono == TonoAviso.accent ? _C.muted : _colorDe(tono)),
          ),
          const SizedBox(height: 10),
          Text(titulo, textAlign: TextAlign.center, style: _t(16, FontWeight.w700, _C.ink)),
          const SizedBox(height: 6),
          Text(detalle, textAlign: TextAlign.center, style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45)),
        ],
      ),
    );
  }
}
