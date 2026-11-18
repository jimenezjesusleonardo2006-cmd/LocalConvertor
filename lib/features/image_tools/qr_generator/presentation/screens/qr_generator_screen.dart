import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/qr_generator_config.dart';
import '../providers/qr_generator_notifier.dart';

Future<void> pickQrBatchFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Importar lista desde TXT o CSV',
    type: FileType.custom,
    allowedExtensions: ['txt', 'csv'],
  );
  if (file?.path != null) {
    await ref
        .read(qrGeneratorNotifierProvider.notifier)
        .loadListFile(file!.path!);
  }
}

class QrGeneratorWorkspaceBody extends ConsumerStatefulWidget {
  const QrGeneratorWorkspaceBody({super.key});

  @override
  ConsumerState<QrGeneratorWorkspaceBody> createState() =>
      _QrGeneratorWorkspaceBodyState();
}

class _QrGeneratorWorkspaceBodyState
    extends ConsumerState<QrGeneratorWorkspaceBody> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(qrGeneratorNotifierProvider).rawLinesText,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(qrGeneratorNotifierProvider);
    final notifier = ref.read(qrGeneratorNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (_controller.text != state.rawLinesText) {
      _controller.value = TextEditingValue(
        text: state.rawLinesText,
        selection: TextSelection.collapsed(offset: state.rawLinesText.length),
      );
    }

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Generando códigos QR en Rust...',
            accentColor: AppTheme.imageAccent,
            onCancel: () {},
          ),
        ),
      );
    }

    final itemsCount = state.parsedItems.length;

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
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final editorCard = Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.qrCode,
                              color: AppTheme.imageAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Contenido ($itemsCount código${itemsCount == 1 ? "" : "s"} • 1 línea = 1 QR)',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => pickQrBatchFile(ref),
                              icon: const Icon(LucideIcons.fileUp, size: 15),
                              label: const Text('Importar TXT/CSV'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: TextField(
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText:
                                  'Escribe una URL, texto, Wi-Fi o pega varias líneas para generar un lote en paralelo...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onChanged: notifier.updateText,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                final previewCard = Card(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Vista Previa (1er QR)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: 180,
                            height: 180,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: state.previewPngBytes != null
                                ? Image.memory(
                                    state.previewPngBytes!,
                                    fit: BoxFit.contain,
                                  )
                                : const Center(
                                    child: Text(
                                      'Sin contenido',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          if (state.previewModules != null)
                            Text(
                              'Matriz ${state.previewModules}×${state.previewModules} • Corrección ${state.errorCorrection.code}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                );

                if (constraints.maxWidth >= 560) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: editorCard),
                      const SizedBox(width: 16),
                      SizedBox(width: 240, child: previewCard),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: editorCard),
                    const SizedBox(height: 12),
                    SizedBox(height: 250, child: previewCard),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QrGeneratorSettingsPanel extends ConsumerWidget {
  const QrGeneratorSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qrGeneratorNotifierProvider);
    final notifier = ref.read(qrGeneratorNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Formato de Exportación',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<QrOutputFormat>(
          segments: QrOutputFormat.values
              .map(
                (fmt) => ButtonSegment<QrOutputFormat>(
                  value: fmt,
                  label: Text(fmt.label),
                ),
              )
              .toList(),
          selected: {state.outputFormat},
          onSelectionChanged: (sel) =>
              notifier.updateSettings(outputFormat: sel.first),
        ),
        const SizedBox(height: 20),
        Text(
          'Corrección de Errores',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<QrErrorCorrection>(
          isExpanded: true,
          initialValue: state.errorCorrection,
          decoration: const InputDecoration(isDense: true),
          items: QrErrorCorrection.values
              .map(
                (ec) => DropdownMenuItem(
                  value: ec,
                  child: Text(ec.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (val) => notifier.updateSettings(errorCorrection: val),
        ),
        const SizedBox(height: 20),
        Text(
          'Resolución',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 256, label: Text('256 px')),
            ButtonSegment(value: 512, label: Text('512 px')),
            ButtonSegment(value: 1024, label: Text('1024 px')),
          ],
          selected: {state.sizePx},
          onSelectionChanged: (sel) =>
              notifier.updateSettings(sizePx: sel.first),
        ),
        if (state.outputFormat != QrOutputFormat.pdf) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Empaquetar en .ZIP'),
            subtitle: const Text('Recomendado para lotes'),
            value: state.packageAsZip || state.parsedItems.length > 1,
            onChanged: state.parsedItems.length > 1
                ? null
                : (v) => notifier.updateSettings(packageAsZip: v),
          ),
        ],
      ],
    );
  }
}

class QrGeneratorPrimaryActionButton extends ConsumerWidget {
  const QrGeneratorPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qrGeneratorNotifierProvider);
    final itemsCount = state.parsedItems.length;
    final enabled = itemsCount > 0 && !state.isProcessing;

    return FilledButton.icon(
      onPressed: enabled
          ? () => ref
              .read(qrGeneratorNotifierProvider.notifier)
              .generateAndExport()
          : null,
      style: FilledButton.styleFrom(backgroundColor: AppTheme.imageAccent),
      icon: const Icon(LucideIcons.qrCode),
      label: Text(
        'Generar $itemsCount QR (${state.outputFormat.label})',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
