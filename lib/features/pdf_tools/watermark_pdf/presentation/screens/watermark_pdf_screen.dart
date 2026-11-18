import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/watermark_pdf_config.dart';
import '../providers/watermark_pdf_notifier.dart';

Future<void> pickPdfForWatermark(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar PDF para estampar marca de agua',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file?.path != null) {
    ref.read(watermarkPdfNotifierProvider.notifier).loadPdfFile(file!.path!);
  }
}

Future<void> pickWatermarkImageFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar imagen PNG/JPG para marca de agua',
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg'],
  );
  if (file?.path != null) {
    ref.read(watermarkPdfNotifierProvider.notifier).setWatermarkImage(
          file!.path!,
        );
  }
}

class WatermarkPdfWorkspaceBody extends ConsumerStatefulWidget {
  const WatermarkPdfWorkspaceBody({super.key});

  @override
  ConsumerState<WatermarkPdfWorkspaceBody> createState() =>
      _WatermarkPdfWorkspaceBodyState();
}

class _WatermarkPdfWorkspaceBodyState
    extends ConsumerState<WatermarkPdfWorkspaceBody> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: ref.read(watermarkPdfNotifierProvider).text,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watermarkPdfNotifierProvider);
    final notifier = ref.read(watermarkPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Aplicando marca de agua...',
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
                      title: 'Arrastra aquí el PDF a marcar',
                      subtitle:
                          'Estampa texto Unicode (tildes, ñ, €, ©) o un logotipo PNG/JPG con opacidad, ángulo y posición configurables.',
                      allowedExtensionsBadges: const ['PDF + Texto Unicode', 'PDF + Imagen'],
                      accentColor: AppTheme.pdfAccent,
                      onPickFilesPressed: () => pickPdfForWatermark(ref),
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
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.stamp,
                              color: AppTheme.pdfAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                p.basename(state.sourcePdfPath!),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
                    if (state.type == WatermarkType.text)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _textController,
                            onChanged: (v) => notifier.updateConfig(text: v),
                            decoration: const InputDecoration(
                              labelText: 'Texto de marca de agua (Unicode)',
                              hintText: 'Ej. CONFIDENCIAL • Año 2026 ©',
                              prefixIcon: Icon(LucideIcons.type),
                            ),
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.image,
                                color: AppTheme.pdfAccent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.watermarkImagePath != null
                                      ? p.basename(state.watermarkImagePath!)
                                      : 'Ninguna imagen seleccionada (.png / .jpg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => pickWatermarkImageFile(ref),
                                icon: const Icon(LucideIcons.upload, size: 16),
                                label: const Text('Elegir imagen'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Previsualización Esquemática de Posición',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Container(
                                width: 220,
                                height: 280,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                  ),
                                ),
                                alignment: _alignmentFor(state.position),
                                padding: const EdgeInsets.all(16),
                                child: Opacity(
                                  opacity: state.opacity.clamp(0.1, 1.0),
                                  child: Transform.rotate(
                                    angle:
                                        state.rotationDegrees * math.pi / 180.0,
                                    child: Text(
                                      state.type == WatermarkType.text
                                          ? (state.text.isEmpty
                                              ? 'MARCA DE AGUA'
                                              : state.text)
                                          : '[IMAGEN]',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(state.colorHex),
                                        fontWeight: FontWeight.w800,
                                        fontSize: (state.fontSize * 0.4)
                                            .clamp(11.0, 22.0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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

  Alignment _alignmentFor(WatermarkPosition pos) {
    switch (pos) {
      case WatermarkPosition.center:
      case WatermarkPosition.tiled:
        return Alignment.center;
      case WatermarkPosition.topLeft:
        return Alignment.topLeft;
      case WatermarkPosition.topRight:
        return Alignment.topRight;
      case WatermarkPosition.bottomLeft:
        return Alignment.bottomLeft;
      case WatermarkPosition.bottomRight:
        return Alignment.bottomRight;
    }
  }
}

class WatermarkPdfSettingsPanel extends ConsumerWidget {
  const WatermarkPdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watermarkPdfNotifierProvider);
    final notifier = ref.read(watermarkPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Marca',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<WatermarkType>(
          segments: const [
            ButtonSegment(value: WatermarkType.text, label: Text('Texto')),
            ButtonSegment(value: WatermarkType.image, label: Text('Imagen')),
          ],
          selected: {state.type},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(type: sel.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('Opacidad:')),
            Text(
              '${(state.opacity * 100).round()}%',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.pdfAccent,
              ),
            ),
          ],
        ),
        Slider(
          value: state.opacity,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          activeColor: AppTheme.pdfAccent,
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateConfig(opacity: v),
        ),
        Row(
          children: [
            const Expanded(child: Text('Rotación:')),
            Text(
              '${state.rotationDegrees.round()}°',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Slider(
          value: state.rotationDegrees,
          min: -90,
          max: 90,
          divisions: 36,
          activeColor: AppTheme.pdfAccent,
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateConfig(rotationDegrees: v),
        ),
        Row(
          children: [
            const Expanded(child: Text('Escala:')),
            Text(
              '${(state.scale * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        Slider(
          value: state.scale,
          min: 0.2,
          max: 1.5,
          divisions: 26,
          activeColor: AppTheme.pdfAccent,
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateConfig(scale: v),
        ),
        if (state.type == WatermarkType.text) ...[
          const SizedBox(height: 8),
          Text(
            'Color de Texto',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              0xFFDC2626,
              0xFF334155,
              0xFF2563EB,
              0xFF059669,
            ].map((hex) {
              final selected = state.colorHex == hex;
              return InkWell(
                onTap: () => notifier.updateConfig(colorHex: hex),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.black : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Posición',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        RadioGroup<WatermarkPosition>(
          groupValue: state.position,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateConfig(position: v);
            }
          },
          child: Column(
            children: WatermarkPosition.values.map((pos) {
              return RadioListTile<WatermarkPosition>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(pos.label, style: const TextStyle(fontSize: 13)),
                value: pos,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class WatermarkPdfPrimaryActionButton extends ConsumerWidget {
  const WatermarkPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watermarkPdfNotifierProvider);
    final validTarget = state.type == WatermarkType.text
        ? state.text.trim().isNotEmpty
        : state.watermarkImagePath != null;
    final canRun =
        state.sourcePdfPath != null && validTarget && !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canRun
            ? () => ref
                .read(watermarkPdfNotifierProvider.notifier)
                .applyAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.pdfAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.stamp, size: 18),
        label: const Text(
          'Estampar y Guardar PDF',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
