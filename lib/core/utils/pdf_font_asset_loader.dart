import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Paquete inmutable de fuentes TTF embebidas localmente (Roboto + RobotoMono)
/// con soporte completo de caracteres Unicode (tildes, ñ, €, —, •, etc.).
/// Seguro para enviarse a través de fronteras de [Isolate].
class PdfFontBundle {
  final Uint8List regular;
  final Uint8List bold;
  final Uint8List italic;
  final Uint8List boldItalic;
  final Uint8List monoRegular;
  final Uint8List monoBold;

  const PdfFontBundle({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.monoRegular,
    required this.monoBold,
  });
}

/// Cargador offline de fuentes TTF empaquetadas en `assets/fonts/`.
class PdfFontAssetLoader {
  const PdfFontAssetLoader._();

  static const String _regularPath = 'assets/fonts/Roboto-Regular.ttf';
  static const String _boldPath = 'assets/fonts/Roboto-Bold.ttf';
  static const String _italicPath = 'assets/fonts/Roboto-Italic.ttf';
  static const String _boldItalicPath = 'assets/fonts/Roboto-BoldItalic.ttf';
  static const String _monoRegularPath = 'assets/fonts/RobotoMono-Regular.ttf';
  static const String _monoBoldPath = 'assets/fonts/RobotoMono-Bold.ttf';

  static PdfFontBundle? _cachedBundle;

  /// Carga las fuentes desde `rootBundle` (en ejecución de la app) o desde disco
  /// (en pruebas unitarias sin widget binding), devolviendo `null` si no existen.
  static Future<PdfFontBundle?> loadBundledFonts() async {
    if (_cachedBundle != null) return _cachedBundle;

    try {
      final results = await Future.wait([
        _loadAssetBytes(_regularPath),
        _loadAssetBytes(_boldPath),
        _loadAssetBytes(_italicPath),
        _loadAssetBytes(_boldItalicPath),
        _loadAssetBytes(_monoRegularPath),
        _loadAssetBytes(_monoBoldPath),
      ]);

      _cachedBundle = PdfFontBundle(
        regular: results[0],
        bold: results[1],
        italic: results[2],
        boldItalic: results[3],
        monoRegular: results[4],
        monoBold: results[5],
      );
      return _cachedBundle;
    } catch (_) {
      return loadFromDiskSync();
    }
  }

  /// Carga síncrona desde el directorio local `assets/fonts/` para entornos
  /// de Isolate o tests de VM donde `rootBundle` no esté disponible.
  static PdfFontBundle? loadFromDiskSync() {
    if (_cachedBundle != null) return _cachedBundle;
    try {
      final reg = File(_regularPath);
      final bold = File(_boldPath);
      final italic = File(_italicPath);
      final boldItalic = File(_boldItalicPath);
      final monoReg = File(_monoRegularPath);
      final monoBold = File(_monoBoldPath);

      if (!reg.existsSync() ||
          !bold.existsSync() ||
          !italic.existsSync() ||
          !boldItalic.existsSync() ||
          !monoReg.existsSync() ||
          !monoBold.existsSync()) {
        return null;
      }

      _cachedBundle = PdfFontBundle(
        regular: reg.readAsBytesSync(),
        bold: bold.readAsBytesSync(),
        italic: italic.readAsBytesSync(),
        boldItalic: boldItalic.readAsBytesSync(),
        monoRegular: monoReg.readAsBytesSync(),
        monoBold: monoBold.readAsBytesSync(),
      );
      return _cachedBundle;
    } catch (_) {
      return null;
    }
  }

  /// Construye un [pw.ThemeData] Unicode con las fuentes Roboto embebidas y una fuente monoespaciada.
  static ({pw.ThemeData? theme, pw.Font? monoFont}) buildPdfTheme([
    PdfFontBundle? providedBundle,
  ]) {
    final fontBundle = providedBundle ?? loadFromDiskSync();
    if (fontBundle == null) return (theme: null, monoFont: null);

    final base = pw.Font.ttf(ByteData.sublistView(fontBundle.regular));
    final bold = pw.Font.ttf(ByteData.sublistView(fontBundle.bold));
    final italic = pw.Font.ttf(ByteData.sublistView(fontBundle.italic));
    final boldItalic = pw.Font.ttf(ByteData.sublistView(fontBundle.boldItalic));
    final monoFont = pw.Font.ttf(ByteData.sublistView(fontBundle.monoRegular));

    return (
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
        fontFallback: [base, monoFont],
      ),
      monoFont: monoFont,
    );
  }

  static Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
