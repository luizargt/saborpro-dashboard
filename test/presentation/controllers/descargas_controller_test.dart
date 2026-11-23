import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/presentation/controllers/descargas_controller.dart';

void main() {
  const a = ItemDescarga('a', Icons.abc, 'Reporte A', 'Uno');
  const b = ItemDescarga('b', Icons.abc, 'Reporte B', 'Dos');

  test('descargar marca el reporte como hecho y avisa al empezar y al terminar', () async {
    final salieron = <String>[];
    final c = DescargasController(items: const [a, b], ejecutar: (i) async => salieron.add(i.id));
    var avisos = 0;
    c.addListener(() => avisos++);
    await c.descargar(a);
    expect(salieron, ['a']);
    expect(c.hechas, {'a'});
    expect(c.descargando, isNull);
    expect(c.error, isNull);
    expect(avisos, 2);
    c.dispose();
  });

  test('mientras uno se genera, otro toque no hace nada', () async {
    final puerta = Completer<void>();
    var corridas = 0;
    final c = DescargasController(items: const [a, b], ejecutar: (i) async {
      corridas++;
      await puerta.future;
    });
    final primera = c.descargar(a);
    expect(c.descargando, 'a');
    expect(c.ocupado, isTrue);
    await c.descargar(b); // ignorado
    await c.descargar(a); // ignorado
    expect(corridas, 1);
    puerta.complete();
    await primera;
    expect(c.hechas, {'a'});
    expect(c.ocupado, isFalse);
    c.dispose();
  });

  test('si falla, lo dice con el nombre del reporte y no lo marca como hecho', () async {
    final c = DescargasController(items: const [a], ejecutar: (_) async => throw StateError('sin red'));
    await c.descargar(a);
    expect(c.hechas, isEmpty);
    expect(c.error, 'No se pudo generar "Reporte A". Intenta de nuevo.');
    expect(c.descargando, isNull);
    c.dispose();
  });

  test('un intento nuevo limpia el error anterior', () async {
    var falla = true;
    final c = DescargasController(items: const [a], ejecutar: (_) async {
      if (falla) throw StateError('x');
    });
    await c.descargar(a);
    expect(c.error, isNotNull);
    falla = false;
    await c.descargar(a);
    expect(c.error, isNull);
    expect(c.hechas, {'a'});
    c.dispose();
  });

  test('reiniciar (cambió el mes o la sucursal) quita los "Listo" y el error', () async {
    final c = DescargasController(items: const [a, b], ejecutar: (_) async {});
    await c.descargar(a);
    var avisos = 0;
    c.addListener(() => avisos++);
    c.reiniciar();
    expect(c.hechas, isEmpty);
    expect(avisos, 1);
    c.reiniciar(); // ya no hay nada que quitar: no avisa de balde
    expect(avisos, 1);
    c.dispose();
  });

  test('si se cierra el diálogo con una descarga en curso, terminar no revienta', () async {
    final puerta = Completer<void>();
    final c = DescargasController(items: const [a], ejecutar: (_) => puerta.future);
    final f = c.descargar(a);
    c.dispose();
    puerta.complete();
    await f; // no debe lanzar "usado después de dispose"
  });

  test('la lista de hechas no se puede alterar por fuera', () async {
    final c = DescargasController(items: const [a], ejecutar: (_) async {});
    await c.descargar(a);
    expect(() => c.hechas.add('z'), throwsUnsupportedError);
    c.dispose();
  });
}
