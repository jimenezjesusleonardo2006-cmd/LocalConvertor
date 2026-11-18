import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/file_size_formatter.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/compress_pdf_config.dart';
import '../providers/compress_pdf_notifier.dart';

Future<void> pickPdfForCompression(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar PDF para comprimir (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file?.path != null) {
    await ref
        .read(compressPdfNotifierProvider.notifier)
        .loadPdfFile(file!.path!);
  }
}

class CompressPdfWorkspaceBody extends ConsumerWidget {
  const CompressPdfWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressPdfNotifierProvider);
    final notifier = ref.read(compressPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Comprimiendo PDF...',
            accentColor: AppTheme.pdfAccent,
            onCancel: () {},
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.errorMessage != null) ...[
            StatusBanner(
              message: state.errorMessage!,
              icon: LucideIcons.alertTriangle,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
          ] else if (state.statusMessage != null) ...[
            StatusBanner(
              message: state.statusMessage!,
              icon: LucideIcons.checkCircle2,
              color: AppTheme.privacyBadge,
            ),
            const SizedBox(height: 16),
          ],

          if (state.sourcePdfPath == null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: DesktopDropZone(
                      title: 'Arrastra aquí el archivo PDF a optimizar',
                      subtitle:
                          'Reduce el peso mediante compresión de objetos vectoriales sin pérdida o remuestreo inteligente de imágenes con protección de RAM.',
                      allowedExtensionsBadges: const [
                        'PDF Vectorial',
                        'Remuestreo 110–150 DPI',
                      ],
                      accentColor: AppTheme.pdfAccent,
                      onPickFilesPressed: () => pickPdfForCompression(ref),
                      onFilesDropped: (paths) {
                        if (paths.isNotEmpty) {
                          notifier.loadPdfFile(paths.first);
                        }
                      },
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.pdfAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                LucideIcons.fileDown,
                                color: AppTheme.pdfAccent,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.basename(state.sourcePdfPath!),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${state.pageCount} páginas • Peso original: ${formatFileSize(state.originalSizeBytes)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: notifier.clear,
                              icon: const Icon(LucideIcons.trash2, size: 16),
                              label: const Text('Quitar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Perfil Activo: ${state.level.label}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              state.level.description,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (state.lastCompressedBytes != null) ...[
                              const Divider(height: 28),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text('Último peso optimizado:'),
                                  ),
                                  Text(
                                    formatFileSize(state.lastCompressedBytes!),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.privacyBadge,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CompressPdfSettingsPanel extends ConsumerWidget {
  const CompressPdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressPdfNotifierProvider);
    final notifier = ref.read(compressPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nivel de Compresión',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        RadioGroup<CompressPdfLevel>(
          groupValue: state.level,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateLevel(v);
            }
          },
          child: Column(
            children: CompressPdfLevel.values.map((level) {
              return RadioListTile<CompressPdfLevel>(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  level.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  level.description,
                  style: const TextStyle(fontSize: 12),
                ),
                value: level,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        const StatusBanner(
          message:
              'Respeta MemoryGuardConfig para evitar picos de RAM en PDFs extensos.',
          icon: LucideIcons.cpu,
          color: AppTheme.privacyBadge,
        ),
      ],
    );
  }
}

class CompressPdfPrimaryActionButton extends ConsumerWidget {
  const CompressPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressPdfNotifierProvider);
    final canRun = state.sourcePdfPath != null && !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canRun
            ? () => ref
                .read(compressPdfNotifierProvider.notifier)
                .compressAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.pdfAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.minimize2, size: 18),
        label: const Text(
          'Comprimir y Guardar PDF',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
