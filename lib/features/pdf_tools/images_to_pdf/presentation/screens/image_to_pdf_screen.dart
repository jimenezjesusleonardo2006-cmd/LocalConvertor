import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/image_to_pdf_config.dart';
import '../providers/image_to_pdf_notifier.dart';

/// Utilidad compartida para abrir el selector nativo de imágenes (usada por el botón y por Ctrl/Cmd+O).
Future<void> pickImagesForPdf(WidgetRef ref) async {
  final state = ref.read(imageToPdfNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle: 'Seleccionar imágenes (JPG, PNG, WEBP)',
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );

  if (result.isNotEmpty) { final paths = result.map((f) => f.path).whereType<String>().toList();
    ref.read(imageToPdfNotifierProvider.notifier).addImages(paths);
  }
}

/// Área central de trabajo de la herramienta "Imágenes a PDF".
class ImageToPdfWorkspaceBody extends ConsumerWidget {
  const ImageToPdfWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageToPdfNotifierProvider);
    final notifier = ref.read(imageToPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner de estado o error si existe
          if (state.errorMessage != null) ...[
            StatusBanner(
              message: state.errorMessage!,
              icon: LucideIcons.alertTriangle,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
          ] else if (!state.isProcessing && state.statusMessage != null) ...[
            StatusBanner(
              message: state.statusMessage!,
              icon: LucideIcons.checkCircle2,
              color: AppTheme.privacyBadge,
            ),
            const SizedBox(height: 16),
          ],

          // Barra de progreso determinista cuando el Isolate está procesando
          if (state.isProcessing) ...[
            DeterministicProgressBar(
              progress: state.progress,
              statusText: state.statusMessage ?? 'Procesando imágenes...',
              accentColor: AppTheme.pdfAccent,
              onCancel: notifier.cancelConversion,
            ),
            const SizedBox(height: 20),
          ],

          // Si no hay imágenes cargadas, mostrar DropZone a pantalla completa
          if (state.selectedImages.isEmpty)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra y suelta tus imágenes aquí',
                    subtitle:
                        'O selecciónalas desde tu dispositivo. Todo el procesamiento se realiza en memoria local.',
                    allowedExtensionsBadges: const ['JPG', 'JPEG', 'PNG', 'WEBP'],
                    accentColor: AppTheme.pdfAccent,
                    onPickFilesPressed: () => pickImagesForPdf(ref),
                    onFilesDropped: notifier.addImages,
                  ),
                ),
              ),
            )
          else ...[
            // Cabecera compacta de DropZone + Contador y guía de Drag & Drop
            DesktopDropZone(
              title:
                  '${state.selectedImages.length} páginas listas • Arrastra miniaturas para reordenar',
              subtitle:
                  'También puedes soltar más imágenes aquí para añadirlas al final del documento.',
              allowedExtensionsBadges: const ['JPG', 'PNG', 'WEBP'],
              accentColor: AppTheme.pdfAccent,
              compact: true,
              onPickFilesPressed: () => pickImagesForPdf(ref),
              onFilesDropped: notifier.addImages,
            ),
            const SizedBox(height: 18),

            // Cuadrícula de miniaturas con Reordenamiento Drag & Drop
            Expanded(
              child: ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisExtent: 245,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: state.selectedImages.length,
                onReorder: notifier.reorderImages,
                itemBuilder: (context, index) {
                  final path = state.selectedImages[index];
                  return _ImagePageThumbnailCard(
                    key: ValueKey('$path#$index'),
                    filePath: path,
                    pageNumber: index + 1,
                    onRemove: state.isProcessing
                        ? null
                        : () => notifier.removeImageAt(index),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panel lateral (Escritorio) o ModalBottomSheet (Móvil) con los parámetros de configuración.
class ImageToPdfSettingsPanel extends ConsumerWidget {
  const ImageToPdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageToPdfNotifierProvider);
    final notifier = ref.read(imageToPdfNotifierProvider.notifier);
    final theme = Theme.of(context);
    final isFitToImage = state.pageSize == PdfPageSizeOption.fitToImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Tamaño de página
        Text(
          'Tamaño de Página',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfPageSizeOption>(
          segments: const [
            ButtonSegment(
              value: PdfPageSizeOption.a4,
              label: Text('A4'),
            ),
            ButtonSegment(
              value: PdfPageSizeOption.letter,
              label: Text('Carta'),
            ),
            ButtonSegment(
              value: PdfPageSizeOption.fitToImage,
              label: Text('Ajustar'),
            ),
          ],
          selected: {state.pageSize},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(pageSize: sel.first),
        ),
        const SizedBox(height: 20),

        // 2. Orientación de página
        Text(
          'Orientación',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfPageOrientationOption>(
          segments: const [
            ButtonSegment(
              value: PdfPageOrientationOption.portrait,
              icon: Icon(LucideIcons.file, size: 16),
              label: Text('Vertical'),
            ),
            ButtonSegment(
              value: PdfPageOrientationOption.landscape,
              icon: Icon(LucideIcons.fileSpreadsheet, size: 16),
              label: Text('Horizontal'),
            ),
          ],
          selected: {state.orientation},
          onSelectionChanged: (state.isProcessing || isFitToImage)
              ? null
              : (sel) => notifier.updateConfig(orientation: sel.first),
        ),
        if (isFitToImage) ...[
          const SizedBox(height: 6),
          Text(
            'En modo "Ajustar", cada página adopta las dimensiones exactas de su imagen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
        const SizedBox(height: 20),

        // 3. Márgenes
        Text(
          'Márgenes',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfMarginOption>(
          segments: const [
            ButtonSegment(
              value: PdfMarginOption.none,
              label: Text('Sin margen'),
            ),
            ButtonSegment(
              value: PdfMarginOption.small,
              label: Text('Delgado'),
            ),
            ButtonSegment(
              value: PdfMarginOption.large,
              label: Text('Grande'),
            ),
          ],
          selected: {state.margin},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(margin: sel.first),
        ),
        const SizedBox(height: 24),

        // 4. Calidad JPEG en el PDF
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Calidad de Imagen',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.pdfAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${state.jpegQuality}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.pdfAccent,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: state.jpegQuality.toDouble(),
          min: 20,
          max: 100,
          divisions: 16,
          activeColor: AppTheme.pdfAccent,
          label: '${state.jpegQuality}%',
          onChanged: state.isProcessing
              ? null
              : (val) => notifier.updateConfig(jpegQuality: val.round()),
        ),
        Text(
          '85–90% ofrece excelente nitidez visual reduciendo drásticamente el peso del PDF final.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// Botón de acción principal para disparar la conversión y guardado (también invocable vía Ctrl/Cmd+S).
class ImageToPdfPrimaryActionButton extends ConsumerWidget {
  const ImageToPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageToPdfNotifierProvider);
    final notifier = ref.read(imageToPdfNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.selectedImages.isEmpty || state.isProcessing)
          ? null
          : notifier.convertAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.pdfAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.fileOutput, size: 18),
      label: Text(
        state.isProcessing
            ? 'Procesando en Isolate...'
            : 'Convertir a PDF (${state.selectedImages.length})',
      ),
    );
  }
}

class _ImagePageThumbnailCard extends StatelessWidget {
  final String filePath;
  final int pageNumber;
  final VoidCallback? onRemove;

  const _ImagePageThumbnailCard({
    super.key,
    required this.filePath,
    required this.pageNumber,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = p.basename(filePath);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera con número de página y botón de eliminar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            child: Row(
              children: [
                const Icon(LucideIcons.gripVertical, size: 14),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.pdfAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Pág. $pageNumber',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Miniatura decodificada con cacheWidth acotado para proteger la RAM de la UI
          Expanded(
            child: Container(
              color: Colors.black12,
              padding: const EdgeInsets.all(8),
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
                cacheWidth: MemoryGuardConfig.thumbnailDecodeWidthPx,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(LucideIcons.imageOff, size: 28),
                ),
              ),
            ),
          ),

          // Pie con nombre del archivo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



