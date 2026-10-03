import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Montos y porcentajes: "Q1,250.00", "−3.0%".
final _cifra = RegExp(r'Q\d|\d%');

Iterable<RenderParagraph> _parrafosConCifras(WidgetTester tester) => tester
    .allRenderObjects
    .whereType<RenderParagraph>()
    .where((rp) => _cifra.hasMatch(rp.text.toPlainText()));

/// Falla si alguna cifra en pantalla sale cortada.
///
/// `find.text` compara el dato, no lo pintado: un "−Q558.00" que se dibuja
/// como "−Q55…" lo encuentra igual. Esto mira el render: que no se haya
/// pasado de sus líneas y que la palabra más larga quepa en su ancho.
void expectCifrasCompletas(WidgetTester tester) {
  var revisadas = 0;
  for (final rp in _parrafosConCifras(tester)) {
    revisadas++;
    final texto = rp.text.toPlainText();
    expect(rp.didExceedMaxLines, isFalse, reason: '"$texto" se corta');
    // Se compara contra el ancho que le dieron, no contra el que ocupa: un
    // texto que baja de renglón se encoge a su línea más larga y quedaría
    // "más angosto que su palabra más larga" sin que nada se corte.
    final necesita = rp.getMinIntrinsicWidth(double.infinity);
    final disponible = rp.constraints.maxWidth;
    expect(disponible + 0.5, greaterThanOrEqualTo(necesita),
        reason: '"$texto" no cabe: necesita $necesita y le dieron '
            '$disponible');
  }
  expect(revisadas, greaterThan(0), reason: 'no había ninguna cifra que revisar');
}

double _luminancia(Color c) => c.computeLuminance();

double contraste(Color a, Color b) {
  final la = _luminancia(a), lb = _luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Falla si alguna cifra no llega a 4.5:1 sobre [fondo] (WCAG AA).
///
/// Se usa una función propia y no `textContrastGuideline` porque esa pinta la
/// pantalla y en las pruebas GoogleFonts intenta bajar la tipografía.
void expectContrasteDeCifras(
  WidgetTester tester, {
  required Color fondo,
  Finder? excepto,
}) {
  final exentos = <RenderObject>{
    if (excepto != null)
      for (final e in find
          .descendant(of: excepto, matching: find.byType(RichText))
          .evaluate())
        e.renderObject!,
  };
  for (final rp in _parrafosConCifras(tester)) {
    if (exentos.contains(rp)) continue;
    final color = rp.text.style?.color;
    if (color == null) continue;
    final efectivo = Color.alphaBlend(color, fondo);
    expect(contraste(efectivo, fondo), greaterThanOrEqualTo(4.5),
        reason: '"${rp.text.toPlainText()}" tiene contraste '
            '${contraste(efectivo, fondo).toStringAsFixed(2)}');
  }
}
