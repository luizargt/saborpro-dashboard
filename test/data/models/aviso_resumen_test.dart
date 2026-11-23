import 'package:flutter_test/flutter_test.dart';
import 'package:saborpro_reports/data/models/aviso_resumen.dart';
import 'package:saborpro_reports/data/models/manager_notification.dart';

/// El lector de los textos de la bandeja, probado contra las plantillas EXACTAS
/// que escriben las Cloud Functions (saborpro_app/functions/notifications/).
/// Si allá cambia una plantilla, estas pruebas dicen qué hay que ajustar acá; y
/// si nadie lo ajusta, la fila degrada al texto tal cual (último grupo).
void main() {
  ManagerNotification aviso(
    ManagerNotificationType tipo,
    String title,
    String body, {
    Map<String, String> data = const {},
  }) =>
      ManagerNotification(
        id: 'n',
        tipo: tipo,
        title: title,
        body: body,
        data: data,
        locationId: 'L1',
        read: false,
        createdAt: DateTime(2026, 11, 20, 8),
      );

  group('caja', () {
    test('abierta: quién y dónde', () {
      final r = AvisoResumen.de(aviso(ManagerNotificationType.cajaAbierta,
          '🔓 Caja abierta', 'Rosario abrió caja en Santa Rosalía'));
      expect(r.titulo, 'Caja abierta');
      expect(r.descripcion, 'Rosario · Santa Rosalía');
      expect(r.pildora, isNull);
      expect(r.monto, isNull);
      expect(r.tono, TonoAviso.ok);
      expect(r.crudo, isFalse, reason: 'lo que se entendió ya no es el texto del servidor');
    });

    test('cerrada y cuadró: pastilla verde y la venta con los miles separados', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.cajaCerrada,
        '🔒 Caja cerrada — Cuadró',
        'Rosario cerró caja en Santa Rosalía. Venta total: Q2172.00',
        data: {'cuadro': 'true'},
      ));
      expect(r.titulo, 'Caja cerrada');
      expect(r.pildora!.texto, 'Cuadró');
      expect(r.pildora!.tono, TonoAviso.ok);
      expect(r.descripcion, 'Rosario · Santa Rosalía');
      expect(r.monto, 'Q2,172.00');
      expect(r.tono, TonoAviso.ok);
    });

    test('cerrada con faltante: pastilla roja con lo que faltó, ícono ámbar', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.cajaCerrada,
        '⚠️ Caja cerrada — Descuadre',
        'Rosario cerró caja en Santa Rosalía con faltante de Q25.00. Venta total: Q2860.00',
        data: {'cuadro': 'false'},
      ));
      expect(r.pildora!.texto, 'Faltó Q25.00');
      expect(r.pildora!.tono, TonoAviso.bad);
      expect(r.tono, TonoAviso.warn);
      expect(r.monto, 'Q2,860.00');
    });

    test('cerrada con sobrante: pastilla ámbar', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.cajaCerrada,
        '⚠️ Caja cerrada — Descuadre',
        'Rosario cerró caja en Santa Rosalía con sobrante de Q10.00. Venta total: Q2415.00',
        data: {'cuadro': 'false'},
      ));
      expect(r.pildora!.texto, 'Sobró Q10.00');
      expect(r.pildora!.tono, TonoAviso.warn);
    });

    test('con código de moneda ("USD 99.00") también se lee', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.cajaCerrada,
        '🔒 Caja cerrada — Cuadró',
        'Ana cerró caja en Zona 10. Venta total: USD 1250.50',
      ));
      expect(r.monto, 'USD 1,250.50');
      expect(r.pildora!.texto, 'Cuadró');
    });

    test('una sucursal con " con " en el nombre no confunde el faltante', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.cajaCerrada,
        '⚠️ Caja cerrada — Descuadre',
        'Ana cerró caja en Café con Leche con faltante de Q5.00. Venta total: Q100.00',
      ));
      expect(r.descripcion, 'Ana · Café con Leche');
      expect(r.pildora!.texto, 'Faltó Q5.00');
    });
  });

  group('dinero que sale', () {
    test('retiro: quién, dónde, el motivo y el monto', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.retiro,
        '💸 Retiro de efectivo',
        'Rosario retiró Q500.00 de la caja en Santa Rosalía — Compra de hielo (Insumos)',
      ));
      expect(r.titulo, 'Retiro de efectivo');
      expect(r.descripcion, 'Rosario · Santa Rosalía · Compra de hielo (Insumos)');
      expect(r.monto, 'Q500.00');
      expect(r.tono, TonoAviso.warn);
    });

    test('retiro sin motivo', () {
      final r = AvisoResumen.de(aviso(ManagerNotificationType.retiro,
          '💸 Retiro de efectivo', 'Rosario retiró Q1500.00 de la caja en Zona 10'));
      expect(r.descripcion, 'Rosario · Zona 10');
      expect(r.monto, 'Q1,500.00');
    });

    test('retiros en lote: cuántos y el total', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.retirosEnLote,
        '💸 Retiros de efectivo',
        'Se registraron 5 retiros por Q2500.00 en la caja de Rosario en Santa Rosalía',
      ));
      expect(r.pildora!.texto, '5');
      expect(r.monto, 'Q2,500.00');
      expect(r.descripcion, 'Rosario · Santa Rosalía');
    });

    test('gasto: quién, categoría, sucursal y monto', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.gasto,
        '💸 Nuevo gasto registrado',
        'Ana registró un gasto de Q50.00 (Servicios) en Santa Rosalía',
      ));
      expect(r.titulo, 'Nuevo gasto registrado');
      expect(r.descripcion, 'Ana · Servicios · Santa Rosalía');
      expect(r.monto, 'Q50.00');
    });
  });

  group('inventario', () {
    test('entrada: quién, cuánto, qué y dónde', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.inventario,
        '📦 Entrada de inventario',
        'Soporte registró entrada de 24 en Monte Carlo Bajo Cero (Santa Rosalía)',
      ));
      expect(r.titulo, 'Entrada de inventario');
      expect(r.descripcion, 'Soporte · +24 Monte Carlo Bajo Cero · Santa Rosalía');
      expect(r.tono, TonoAviso.blue);
      final d = r.inventario!;
      expect(d.quien, 'Soporte');
      expect(d.movimiento, 'entrada');
      expect(d.cantidadNumero, 24);
      expect(d.producto, 'Monte Carlo Bajo Cero');
      expect(d.sucursal, 'Santa Rosalía');
    });

    test('salida y ajuste llevan su signo y su nombre', () {
      final salida = AvisoResumen.de(aviso(ManagerNotificationType.inventario,
          '📦 Salida de inventario', 'Ana registró salida de 3 en Hielo (Zona 10)'));
      expect(salida.titulo, 'Salida de inventario');
      expect(salida.descripcion, startsWith('Ana · −3 Hielo'));

      final ajuste = AvisoResumen.de(aviso(ManagerNotificationType.inventario,
          '📦 Ajuste de inventario', 'Ana registró ajuste de 0.5 en Sal (Zona 10)'));
      expect(ajuste.titulo, 'Ajuste de inventario');
      expect(ajuste.inventario!.cantidadNumero, 0.5);
    });

    test('un producto con paréntesis y con " en " no rompe la sucursal', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.inventario,
        '📦 Entrada de inventario',
        'Ana registró entrada de 12 en Salsa en polvo (sobre 50 g) (Santa Rosalía)',
      ));
      expect(r.inventario!.producto, 'Salsa en polvo (sobre 50 g)');
      expect(r.inventario!.sucursal, 'Santa Rosalía');
    });
  });

  group('stock bajo', () {
    test('cuántos, la sucursal del título y los nombres', () {
      final r = AvisoResumen.de(aviso(
        ManagerNotificationType.stockBajo,
        '📉 Stock bajo — Santa Rosalía',
        '22 producto(s) con stock bajo: Adrenalina 296 ml, Dassani 1 Litro, Fanta Uva Desechable 600 ml y 19 más',
      ));
      expect(r.titulo, 'Stock bajo');
      expect(r.pildora!.texto, '22');
      expect(r.pildora!.tono, TonoAviso.bad);
      expect(r.descripcion,
          'Santa Rosalía · Adrenalina 296 ml, Dassani 1 Litro, Fanta Uva Desechable 600 ml y 19 más');
      expect(r.tono, TonoAviso.bad);
    });
  });

  group('lo que no se entiende se muestra tal cual', () {
    test('un texto de otra plantilla conserva título y texto', () {
      for (final tipo in ManagerNotificationType.values) {
        final r = AvisoResumen.de(aviso(tipo, '🆕 Algo nuevo', 'Un texto que ninguna plantilla conoce'));
        expect(r.titulo, anyOf('Algo nuevo', isNotEmpty), reason: '$tipo');
        expect(r.descripcion, 'Un texto que ninguna plantilla conoce', reason: '$tipo');
        expect(r.monto, isNull, reason: '$tipo');
        // Marcado como crudo para que la fila lo muestre completo, sin cortarlo.
        expect(r.crudo, isTrue, reason: '$tipo');
      }
    });

    test('un tipo desconocido cae al aspecto neutro', () {
      final r = AvisoResumen.de(
          aviso(ManagerNotificationType.otro, '🆕 Algo nuevo', 'Texto'));
      expect(r.tono, TonoAviso.accent);
      expect(r.titulo, 'Algo nuevo');
    });

    test('un cierre que no se pudo leer conserva Cuadró / Descuadre del payload', () {
      final cuadro = AvisoResumen.de(aviso(ManagerNotificationType.cajaCerrada,
          '🔒 Caja cerrada — Cuadró', 'texto distinto', data: {'cuadro': 'true'}));
      expect(cuadro.pildora!.texto, 'Cuadró');
      expect(cuadro.crudo, isTrue);
      final malo = AvisoResumen.de(aviso(ManagerNotificationType.cajaCerrada,
          '⚠️ Caja cerrada — Descuadre', 'texto distinto', data: {'cuadro': 'false'}));
      expect(malo.pildora!.texto, 'Descuadre');
      expect(malo.tono, TonoAviso.warn);
      expect(malo.crudo, isTrue);
    });
  });

  group('piezas', () {
    test('el emoji se quita del título, pero un título solo de emoji se conserva', () {
      expect(AvisoResumen.quitarEmoji('💸 Nuevo gasto registrado'), 'Nuevo gasto registrado');
      expect(AvisoResumen.quitarEmoji('⚠️ Caja cerrada — Descuadre'), 'Caja cerrada — Descuadre');
      expect(AvisoResumen.quitarEmoji('💸'), '💸');
    });

    test('los miles se separan y lo demás se respeta', () {
      expect(AvisoResumen.formatearMonto('Q2172.00'), 'Q2,172.00');
      expect(AvisoResumen.formatearMonto('Q12345678.50'), 'Q12,345,678.50');
      expect(AvisoResumen.formatearMonto('Q5.00'), 'Q5.00');
      expect(AvisoResumen.formatearMonto('USD 1000.00'), 'USD 1,000.00');
      expect(AvisoResumen.formatearMonto('C\$100.00'), 'C\$100.00');
      expect(AvisoResumen.formatearMonto('raro'), 'raro');
    });
  });
}
