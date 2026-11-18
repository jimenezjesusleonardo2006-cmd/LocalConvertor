import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_convert/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:local_convert/main.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets(
      'Dashboard desktop muestra las 21 herramientas, diálogo Acerca de, filtra Multimedia y alterna tema',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: LocalConvertApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verifica branding y herramientas iniciales
    expect(find.text('LocalConvert'), findsOneWidget);
    expect(find.textContaining('Zero-Network'), findsOneWidget);
    expect(find.text('Imágenes a PDF'), findsOneWidget);
    expect(find.text('PDF a Imágenes'), findsOneWidget);

    // Diálogo Acerca de LocalConvert
    await tester.tap(find.text('Acerca de'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LocalConvert Studio'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();

    // Filtro por categoría "Documentos" (incluye Excel/ODS y Word/DOCX)
    await tester.tap(find.widgetWithText(ChoiceChip, 'Documentos'));
    await tester.pumpAndSettle();
    expect(find.text('Texto / Markdown a PDF'), findsOneWidget);
    expect(find.text('Datos CSV / JSON / XML'), findsOneWidget);
    expect(find.text('HTML / EPUB a PDF y TXT'), findsOneWidget);
    expect(find.text('Excel / Hojas de Cálculo'), findsOneWidget);
    expect(find.text('Word / DOCX a PDF y Markdown'), findsOneWidget);

    // Filtro por categoría "Imágenes" incluye Estudio de Códigos QR
    await tester.tap(find.widgetWithText(ChoiceChip, 'Imágenes'));
    await tester.pumpAndSettle();
    expect(find.text('Estudio de Códigos QR'), findsOneWidget);

    // Filtro por categoría "Multimedia" muestra las 4 herramientas + badge directo YouTube
    await tester.tap(find.widgetWithText(ChoiceChip, 'Multimedia'));
    await tester.pumpAndSettle();
    expect(find.text('Conversor de Audio'), findsOneWidget);
    expect(find.text('Conversor y Compresor Video'), findsOneWidget);
    expect(find.text('Extraer Audio de Video'), findsOneWidget);
    expect(find.text('Descargar de YouTube'), findsOneWidget);
    expect(find.text('Requiere conexión directa a YouTube'), findsOneWidget);

    // Volver a "Todas" y buscar por texto "Marca de Agua"
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Marca de Agua');
    await tester.pumpAndSettle();
    expect(find.text('Marca de Agua en PDF'), findsOneWidget);
    expect(find.text('Unir PDFs'), findsNothing);

    // Alternar modo oscuro -> modo claro
    await tester.tap(find.text('Modo Oscuro'));
    await tester.pumpAndSettle();
    expect(find.text('Modo Claro'), findsOneWidget);
  });

  testWidgets('Navega a Multimedia y YouTube Downloader con ajustes en móvil sin errores',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: LocalConvertApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);

    // Navegar a la pestaña Multimedia en móvil
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Multimedia'),
      ),
    );
    await tester.pumpAndSettle();

    final ytCard = find.descendant(
      of: find.byType(DashboardScreen),
      matching: find.text('Descargar de YouTube'),
    );
    await tester.scrollUntilVisible(
      ytCard,
      200.0,
      scrollable: find
          .descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(ytCard);
    await tester.pumpAndSettle();
    await tester.tap(ytCard);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Requiere conexión directa a YouTube'),
      findsOneWidget,
    );
    expect(find.text('Obtener Video'), findsOneWidget);

    // Abrir modal bottom sheet de ajustes de YouTube en móvil
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Modo de Descarga'), findsOneWidget);
    expect(find.text('Resolución MP4'), findsOneWidget);
  });

  testWidgets('Todas las 21 herramientas se abren y cierran sin errores de layout en desktop',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: LocalConvertApp(),
      ),
    );
    await tester.pumpAndSettle();

    const toolTitles = [
      'Imágenes a PDF',
      'PDF a Imágenes',
      'Unir PDFs',
      'Dividir PDF',
      'Organizar y Rotar PDF',
      'Proteger y Desbloquear PDF',
      'Marca de Agua en PDF',
      'Comprimir PDF',
      'Conversión de Formatos',
      'Comprimir y Redimensionar',
      'Limpiador de Metadatos EXIF',
      'Estudio de Códigos QR',
      'Texto / Markdown a PDF',
      'Datos CSV / JSON / XML',
      'HTML / EPUB a PDF y TXT',
      'Excel / Hojas de Cálculo',
      'Word / DOCX a PDF y Markdown',
      'Conversor de Audio',
      'Conversor y Compresor Video',
      'Extraer Audio de Video',
      'Descargar de YouTube',
    ];

    for (final title in toolTitles) {
      final cardFinder = find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.text(title),
      );
      await tester.scrollUntilVisible(
        cardFinder,
        240.0,
        scrollable: find
            .descendant(
              of: find.byType(DashboardScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(cardFinder);
      await tester.pumpAndSettle();
      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.text('Parámetros de Conversión'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver al Dashboard'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Argumentos CLI abren automáticamente el workspace y precargan archivo .md',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmpDir = Directory.systemTemp.createTempSync('lc_cli_widget_');
    final mdPath = p.join(tmpDir.path, 'nota.md');
    File(mdPath).writeAsStringSync('# Nota CLI\n\nCargada desde Explorer.');

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialCliArgsProvider.overrideWithValue([mdPath]),
          ],
          child: const LocalConvertApp(),
        ),
      );
      for (int i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.textContaining('nota.md').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();

      expect(find.text('Texto / Markdown a PDF'), findsOneWidget);
      expect(find.text('Parámetros de Conversión'), findsOneWidget);
      expect(find.textContaining('nota.md'), findsWidgets);
    } finally {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      try {
        if (tmpDir.existsSync()) {
          tmpDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  });
}
