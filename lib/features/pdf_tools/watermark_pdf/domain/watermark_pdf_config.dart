import '../../../../core/utils/pdf_font_asset_loader.dart';

/// Tipo de contenido para estampar como marca de agua.
enum WatermarkType {
  text('Texto Unicode'),
  image('Imagen PNG / JPG');

  final String label;
  const WatermarkType(this.label);
}

/// Posición de la marca de agua sobre cada página del PDF.
enum WatermarkPosition {
  center('Centro'),
  tiled('Mosaico diagonal'),
  topLeft('Superior izquierda'),
  topRight('Superior derecha'),
  bottomLeft('Inferior izquierda'),
  bottomRight('Inferior derecha');

  final String label;
  const WatermarkPosition(this.label);
}

/// Configuración para estampar marcas de agua locales sobre un PDF.
class WatermarkPdfConfig {
  final String sourcePdfPath;
  final String outputPdfPath;
  final WatermarkType type;
  final String text;
  final String? watermarkImagePath;
  final double fontSize;
  final double opacity;
  final double rotationDegrees;
  final double scale;
  final WatermarkPosition position;
  final int colorHex;
  final PdfFontBundle? fontBundle;

  const WatermarkPdfConfig({
    required this.sourcePdfPath,
    required this.outputPdfPath,
    this.type = WatermarkType.text,
    this.text = 'CONFIDENCIAL • LocalConvert',
    this.watermarkImagePath,
    this.fontSize = 40.0,
    this.opacity = 0.28,
    this.rotationDegrees = -45.0,
    this.scale = 0.45,
    this.position = WatermarkPosition.center,
    this.colorHex = 0xFFDC2626,
    this.fontBundle,
  });
}
