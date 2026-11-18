import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';

/// Categorías principales de herramientas para filtrado rápido en el Dashboard.
enum ToolCategory {
  all('Todas', LucideIcons.layoutGrid),
  pdf('PDF', LucideIcons.fileText),
  images('Imágenes', LucideIcons.image),
  documents('Documentos', LucideIcons.fileCode),
  multimedia('Multimedia', LucideIcons.film);

  final String label;
  final IconData icon;
  const ToolCategory(this.label, this.icon);
}

/// Identificadores únicos para las herramientas de LocalConvert.
enum ToolId {
  imagesToPdf,
  pdfToImages,
  mergePdf,
  splitPdf,
  organizePdf,
  protectPdf,
  watermarkPdf,
  compressPdf,
  imageFormatConverter,
  imageCompressorResizer,
  stripExif,
  qrGenerator,
  markdownToPdf,
  structuredDataConverter,
  ebookToPdf,
  spreadsheetConverter,
  docxConverter,
  audioConverter,
  videoConverter,
  videoToAudio,
  youtubeDownloader,
}

/// Modelo descriptivo de cada tarjeta de herramienta en el Dashboard.
class ToolItem {
  final ToolId id;
  final String title;
  final String subtitle;
  final ToolCategory category;
  final IconData icon;
  final Color accentColor;
  final List<String> supportedFormats;
  final bool requiresDirectNetwork;

  const ToolItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.accentColor,
    required this.supportedFormats,
    this.requiresDirectNetwork = false,
  });

  /// Catálogo completo de las herramientas offline de LocalConvert.
  static const List<ToolItem> catalog = [
    // --- MÓDULO PDF ---
    ToolItem(
      id: ToolId.imagesToPdf,
      title: 'Imágenes a PDF',
      subtitle:
          'Convierte y reordena fotos JPG, PNG o WEBP en un documento PDF con márgenes y tamaño a medida.',
      category: ToolCategory.pdf,
      icon: LucideIcons.filePlus2,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['JPG', 'PNG', 'WEBP'],
    ),
    ToolItem(
      id: ToolId.pdfToImages,
      title: 'PDF a Imágenes',
      subtitle:
          'Extrae cada página de un archivo PDF como imágenes PNG o JPG de alta resolución o en un archivo ZIP.',
      category: ToolCategory.pdf,
      icon: LucideIcons.image,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF → PNG/JPG/ZIP'],
    ),
    ToolItem(
      id: ToolId.mergePdf,
      title: 'Unir PDFs',
      subtitle:
          'Combina múltiples documentos PDF en un solo archivo reordenando su secuencia visualmente.',
      category: ToolCategory.pdf,
      icon: LucideIcons.files,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF'],
    ),
    ToolItem(
      id: ToolId.splitPdf,
      title: 'Dividir PDF',
      subtitle:
          'Extrae páginas específicas o rangos personalizados (ej. 1-3, 5, 8-10) hacia nuevos documentos.',
      category: ToolCategory.pdf,
      icon: LucideIcons.scissors,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF'],
    ),
    ToolItem(
      id: ToolId.organizePdf,
      title: 'Organizar y Rotar PDF',
      subtitle:
          'Rota páginas individuales 90°/180°/270°, reordena o elimina páginas conservando el contenido vectorial.',
      category: ToolCategory.pdf,
      icon: LucideIcons.layoutGrid,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF'],
    ),
    ToolItem(
      id: ToolId.protectPdf,
      title: 'Proteger y Desbloquear PDF',
      subtitle:
          'Cifra documentos con contraseña AES/RC4 y permisos locales o desbloquea PDFs protegidos.',
      category: ToolCategory.pdf,
      icon: LucideIcons.lock,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF • AES/RC4'],
    ),
    ToolItem(
      id: ToolId.watermarkPdf,
      title: 'Marca de Agua en PDF',
      subtitle:
          'Estampa texto Unicode personalizado o imágenes PNG/JPG con opacidad, ángulo, escala y posición.',
      category: ToolCategory.pdf,
      icon: LucideIcons.stamp,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF + Texto/PNG'],
    ),
    ToolItem(
      id: ToolId.compressPdf,
      title: 'Comprimir PDF',
      subtitle:
          'Reduce el peso de documentos PDF mediante optimización vectorial o remuestreo DPI controlado.',
      category: ToolCategory.pdf,
      icon: LucideIcons.fileDown,
      accentColor: AppTheme.pdfAccent,
      supportedFormats: ['PDF'],
    ),

    // --- MÓDULO DE IMÁGENES ---
    ToolItem(
      id: ToolId.imageFormatConverter,
      title: 'Conversión de Formatos',
      subtitle:
          'Conversión por lotes en memoria entre PNG, JPG, WEBP, BMP, TIFF, ICO, GIF, TGA y rasterización de SVG.',
      category: ToolCategory.images,
      icon: LucideIcons.refreshCw,
      accentColor: AppTheme.imageAccent,
      supportedFormats: ['PNG', 'JPG', 'WEBP', 'TIFF', 'ICO', 'GIF', 'SVG'],
    ),
    ToolItem(
      id: ToolId.imageCompressorResizer,
      title: 'Comprimir y Redimensionar',
      subtitle:
          'Ajusta la calidad de 1 a 100 con estimación de peso final y reduce la resolución por porcentaje o píxeles.',
      category: ToolCategory.images,
      icon: LucideIcons.minimize2,
      accentColor: AppTheme.imageAccent,
      supportedFormats: ['JPG', 'PNG', 'WEBP'],
    ),
    ToolItem(
      id: ToolId.stripExif,
      title: 'Limpiador de Metadatos EXIF',
      subtitle:
          'Elimina ubicación GPS, cámara, fechas y perfiles ICC por lotes en Isolate con resumen de etiquetas.',
      category: ToolCategory.images,
      icon: LucideIcons.shieldCheck,
      accentColor: AppTheme.imageAccent,
      supportedFormats: ['JPG', 'PNG', 'WEBP', 'TIFF'],
    ),
    ToolItem(
      id: ToolId.qrGenerator,
      title: 'Estudio de Códigos QR',
      subtitle:
          'Genera códigos QR individuales o por lotes desde texto/CSV en PNG, SVG vectorial o lámina PDF imprimible.',
      category: ToolCategory.images,
      icon: LucideIcons.qrCode,
      accentColor: AppTheme.imageAccent,
      supportedFormats: ['PNG', 'SVG', 'Lámina PDF'],
    ),

    // --- MÓDULO DE DOCUMENTOS Y TEXTO ---
    ToolItem(
      id: ToolId.markdownToPdf,
      title: 'Texto / Markdown a PDF',
      subtitle:
          'Transforma notas .txt y documentos .md con encabezados, listas y bloques de código en PDFs listos para imprimir.',
      category: ToolCategory.documents,
      icon: LucideIcons.fileCheck2,
      accentColor: AppTheme.docAccent,
      supportedFormats: ['MD', 'TXT → PDF'],
    ),
    ToolItem(
      id: ToolId.structuredDataConverter,
      title: 'Datos CSV / JSON / XML',
      subtitle:
          'Convierte bidireccionalmente entre CSV, JSON y XML con validación de sintaxis o exporta CSV a tabla PDF.',
      category: ToolCategory.documents,
      icon: LucideIcons.table,
      accentColor: AppTheme.docAccent,
      supportedFormats: ['CSV ↔ JSON ↔ XML', 'CSV → PDF'],
    ),
    ToolItem(
      id: ToolId.ebookToPdf,
      title: 'HTML / EPUB a PDF y TXT',
      subtitle:
          'Extrae capítulos locales de archivos .epub y .html para generar texto .txt limpio o un .pdf paginado.',
      category: ToolCategory.documents,
      icon: LucideIcons.bookOpen,
      accentColor: AppTheme.docAccent,
      supportedFormats: ['EPUB', 'HTML → PDF/TXT'],
    ),
    ToolItem(
      id: ToolId.spreadsheetConverter,
      title: 'Excel / Hojas de Cálculo',
      subtitle:
          'Convierte archivos .xlsx, .xls y .ods offline (sin Microsoft Office) hacia CSV, JSON o PDF tabular.',
      category: ToolCategory.documents,
      icon: LucideIcons.sheet,
      accentColor: AppTheme.docAccent,
      supportedFormats: ['XLSX', 'XLS', 'ODS → CSV/JSON/PDF'],
    ),
    ToolItem(
      id: ToolId.docxConverter,
      title: 'Word / DOCX a PDF y Markdown',
      subtitle:
          'Extrae estilos, listas y tablas de documentos .docx localmente hacia Markdown, texto plano o PDF.',
      category: ToolCategory.documents,
      icon: LucideIcons.fileText,
      accentColor: AppTheme.docAccent,
      supportedFormats: ['DOCX → PDF/MD/TXT'],
    ),

    // --- MÓDULO MULTIMEDIA ---
    ToolItem(
      id: ToolId.audioConverter,
      title: 'Conversor de Audio',
      subtitle:
          'Convierte pistas por lotes entre MP3, WAV, M4A, OGG, FLAC y OPUS con bitrate y muestreo local.',
      category: ToolCategory.multimedia,
      icon: LucideIcons.music,
      accentColor: AppTheme.mediaAccent,
      supportedFormats: ['MP3', 'WAV', 'FLAC', 'OPUS'],
    ),
    ToolItem(
      id: ToolId.videoConverter,
      title: 'Conversor y Compresor Video',
      subtitle:
          'Transcodifica y comprime MP4, MKV, WEBM, MOV, AVI o GIF animado con escala, CRF, mute y recorte Trim.',
      category: ToolCategory.multimedia,
      icon: LucideIcons.video,
      accentColor: AppTheme.mediaAccent,
      supportedFormats: ['MP4', 'MKV', 'WEBM', 'GIF'],
    ),
    ToolItem(
      id: ToolId.videoToAudio,
      title: 'Extraer Audio de Video',
      subtitle:
          'Extrae pistas de sonido hacia MP3, M4A o WAV con opción rápida sin pérdida (Stream Copy).',
      category: ToolCategory.multimedia,
      icon: LucideIcons.fileAudio,
      accentColor: AppTheme.mediaAccent,
      supportedFormats: ['MP4 → MP3/M4A/WAV'],
    ),
    ToolItem(
      id: ToolId.youtubeDownloader,
      title: 'Descargar de YouTube',
      subtitle:
          'Conexión directa cliente a YouTube sin intermediarios para descargar MP4 (hasta 1080p) o solo audio.',
      category: ToolCategory.multimedia,
      icon: LucideIcons.download,
      accentColor: AppTheme.youtubeAccent,
      supportedFormats: ['MP4 1080p', 'MP3 / M4A'],
      requiresDirectNetwork: true,
    ),
  ];
}



