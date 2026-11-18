import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

/// Utilidades compartidas para manipulación vectorial de páginas PDF sin rasterizar.
class PdfVectorHelpers {
  const PdfVectorHelpers._();

  /// Lee rápidamente el número total de páginas de un PDF sin rasterizarlo.
  static int readPageCount(Uint8List pdfBytes) {
    final doc = sfpdf.PdfDocument(inputBytes: pdfBytes);
    try {
      return doc.pages.count;
    } finally {
      doc.dispose();
    }
  }

  /// Convierte [sfpdf.PdfPageRotateAngle] a grados enteros (0, 90, 180, 270).
  static int rotateAngleToDegrees(sfpdf.PdfPageRotateAngle angle) {
    switch (angle) {
      case sfpdf.PdfPageRotateAngle.rotateAngle0:
        return 0;
      case sfpdf.PdfPageRotateAngle.rotateAngle90:
        return 90;
      case sfpdf.PdfPageRotateAngle.rotateAngle180:
        return 180;
      case sfpdf.PdfPageRotateAngle.rotateAngle270:
        return 270;
    }
  }

  /// Convierte grados enteros a [sfpdf.PdfPageRotateAngle].
  static sfpdf.PdfPageRotateAngle degreesToRotateAngle(int degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    switch (normalized) {
      case 90:
        return sfpdf.PdfPageRotateAngle.rotateAngle90;
      case 180:
        return sfpdf.PdfPageRotateAngle.rotateAngle180;
      case 270:
        return sfpdf.PdfPageRotateAngle.rotateAngle270;
      default:
        return sfpdf.PdfPageRotateAngle.rotateAngle0;
    }
  }

  /// Copia una página vectorial desde un documento abierto hacia [targetDoc]
  /// conservando texto seleccionable, fuentes y gráficos vectoriales.
  ///
  /// IMPORTANTE: El documento dueño de [sourcePage] NO debe ser liberado con
  /// `dispose()` hasta después de ejecutar `await targetDoc.save()`.
  static void appendVectorPage(
    sfpdf.PdfDocument targetDoc,
    sfpdf.PdfPage sourcePage, {
    int additionalRotationDegrees = 0,
  }) {
    final template = sourcePage.createTemplate();
    final section = targetDoc.sections!.add();
    section.pageSettings.size = sourcePage.size;
    section.pageSettings.margins.all = 0;

    final baseDeg = rotateAngleToDegrees(sourcePage.rotation);
    final totalDeg = (((baseDeg + additionalRotationDegrees) % 360) + 360) % 360;
    section.pageSettings.rotate = degreesToRotateAngle(totalDeg);

    section.pageSettings.orientation =
        sourcePage.size.width > sourcePage.size.height
            ? sfpdf.PdfPageOrientation.landscape
            : sfpdf.PdfPageOrientation.portrait;

    final destPage = section.pages.add();
    destPage.graphics.drawPdfTemplate(template, Offset.zero, sourcePage.size);
  }
}
