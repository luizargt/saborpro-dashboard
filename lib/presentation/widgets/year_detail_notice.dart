import 'package:flutter/material.dart';

import 'inicio_ui.dart';

typedef _C = InicioColores;
const _t = inicioTexto;

/// Lo que ocupa el lugar de los productos y las categorías mientras se preparan.
///
/// Los productos y las categorías salen de `items`, la lista que va dentro de
/// cada ticket. Las sumas de servidor de Firestore solo trabajan sobre campos
/// sueltos del documento y no saben agrupar, así que eso no se puede pedir ya
/// sumado como el resto del año: hay que abrir los tickets.
///
/// No hay botón. La vista de mes tampoco pide permiso para bajar sus pedidos, y
/// hacer que el año se comporte distinto obligaría al dueño a entender por qué
/// su reporte tiene un botón que los otros no. Esto se ve una sola vez por mes
/// en la vida del negocio: después queda guardado en Firestore y lo lee todo el
/// mundo, desde cualquier dispositivo.
class YearDetailNotice extends StatelessWidget {
  const YearDetailNotice({super.key, this.mes = 0});

  /// Mes que se está revisando, 1 a 12. Sin esto la barra se queda quieta medio
  /// minuto y parece colgada.
  final int mes;

  static const _meses = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo',
    'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  @override
  Widget build(BuildContext context) {
    final revisando = mes > 0 && mes < _meses.length
        ? 'Revisando ${_meses[mes]}…'
        : 'Revisando el año…';

    return InicioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _C.tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: _C.accent, size: 20),
              ),
              const SizedBox(width: 12),
              // Expanded y no un ancho fijo: en un teléfono de 360dp el texto
              // tiene que partirse en varias líneas en vez de desbordarse.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preparando lo más vendido del año',
                      style: _t(15, FontWeight.w700, _C.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Las ventas del año que ves arriba ya están completas. '
                      'Esto se hace una sola vez: la próxima vez aparece al toque.',
                      style: _t(13.5, FontWeight.w400, _C.muted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: mes > 0 ? mes / 12 : null,
              minHeight: 6,
              backgroundColor: _C.subtle,
              valueColor: AlwaysStoppedAnimation(_C.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            revisando,
            style: _t(12.5, FontWeight.w400, _C.muted),
          ),
        ],
      ),
    );
  }
}
