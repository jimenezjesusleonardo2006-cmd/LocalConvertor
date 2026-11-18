import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/protect_pdf_config.dart';
import '../providers/protect_pdf_notifier.dart';

Future<void> pickPdfForProtect(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar PDF para proteger o desbloquear (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file?.path != null) {
    ref.read(protectPdfNotifierProvider.notifier).loadPdfFile(file!.path!);
  }
}

class ProtectPdfWorkspaceBody extends ConsumerStatefulWidget {
  const ProtectPdfWorkspaceBody({super.key});

  @override
  ConsumerState<ProtectPdfWorkspaceBody> createState() =>
      _ProtectPdfWorkspaceBodyState();
}

class _ProtectPdfWorkspaceBodyState
    extends ConsumerState<ProtectPdfWorkspaceBody> {
  final _userPwController = TextEditingController();
  final _ownerPwController = TextEditingController();
  final _currentPwController = TextEditingController();
  bool _obscurePasswords = true;

  @override
  void dispose() {
    _userPwController.dispose();
    _ownerPwController.dispose();
    _currentPwController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(protectPdfNotifierProvider);
    final notifier = ref.read(protectPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Procesando cifrado...',
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
                      title: 'Arrastra aquí un documento PDF',
                      subtitle:
                          'Cifra archivos confidenciales con contraseña AES/RC4 sin subir nada a la nube, o elimina contraseñas que conozcas.',
                      allowedExtensionsBadges: const [
                        'AES-256',
                        'AES-128',
                        'Desbloqueo Local',
                      ],
                      accentColor: AppTheme.pdfAccent,
                      onPickFilesPressed: () => pickPdfForProtect(ref),
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.pdfAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                state.mode == ProtectPdfMode.encrypt
                                    ? LucideIcons.lock
                                    : LucideIcons.unlock,
                                color: AppTheme.pdfAccent,
                              ),
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    state.mode == ProtectPdfMode.encrypt
                                        ? 'Credenciales de Protección'
                                        : 'Contraseña Actual del PDF',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(
                                    () => _obscurePasswords = !_obscurePasswords,
                                  ),
                                  icon: Icon(
                                    _obscurePasswords
                                        ? LucideIcons.eye
                                        : LucideIcons.eyeOff,
                                    size: 18,
                                  ),
                                  tooltip: 'Mostrar/Ocultar contraseñas',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (state.mode == ProtectPdfMode.encrypt) ...[
                              TextField(
                                controller: _userPwController,
                                obscureText: _obscurePasswords,
                                onChanged: (val) =>
                                    notifier.updateConfig(userPassword: val),
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña de apertura (Usuario)',
                                  hintText:
                                      'Requerida para abrir el documento PDF',
                                  prefixIcon: Icon(LucideIcons.keyRound),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _ownerPwController,
                                obscureText: _obscurePasswords,
                                onChanged: (val) =>
                                    notifier.updateConfig(ownerPassword: val),
                                decoration: const InputDecoration(
                                  labelText:
                                      'Contraseña de permisos (Propietario, opcional)',
                                  hintText:
                                      'Por defecto usa la misma contraseña de apertura',
                                  prefixIcon: Icon(LucideIcons.shield),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _currentPwController,
                                obscureText: _obscurePasswords,
                                onChanged: (val) =>
                                    notifier.updateConfig(currentPassword: val),
                                decoration: const InputDecoration(
                                  labelText:
                                      'Contraseña previa (solo si el PDF ya tiene clave)',
                                  prefixIcon: Icon(LucideIcons.lockOpen),
                                ),
                              ),
                            ] else
                              TextField(
                                controller: _currentPwController,
                                obscureText: _obscurePasswords,
                                onChanged: (val) =>
                                    notifier.updateConfig(currentPassword: val),
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña actual del PDF',
                                  hintText:
                                      'Ingresa la contraseña para generar una copia sin bloqueo',
                                  prefixIcon: Icon(LucideIcons.keyRound),
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
}

class ProtectPdfSettingsPanel extends ConsumerWidget {
  const ProtectPdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(protectPdfNotifierProvider);
    final notifier = ref.read(protectPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Operación',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ProtectPdfMode>(
          segments: const [
            ButtonSegment(
              value: ProtectPdfMode.encrypt,
              label: Text('Proteger'),
            ),
            ButtonSegment(
              value: ProtectPdfMode.unlock,
              label: Text('Desbloquear'),
            ),
          ],
          selected: {state.mode},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(mode: sel.first),
        ),
        const SizedBox(height: 20),
        if (state.mode == ProtectPdfMode.encrypt) ...[
          Text(
            'Algoritmo de Cifrado',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          RadioGroup<PdfCipherLevel>(
            groupValue: state.cipherLevel,
            onChanged: (val) {
              if (!state.isProcessing && val != null) {
                notifier.updateConfig(cipherLevel: val);
              }
            },
            child: Column(
              children: PdfCipherLevel.values.map((level) {
                return RadioListTile<PdfCipherLevel>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(level.label, style: const TextStyle(fontSize: 13)),
                  value: level,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Permisos del Documento',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Permitir impresión'),
            value: state.allowPrint,
            activeThumbColor: AppTheme.pdfAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateConfig(allowPrint: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Permitir copiar texto'),
            value: state.allowCopy,
            activeThumbColor: AppTheme.pdfAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateConfig(allowCopy: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Permitir edición y anotaciones'),
            value: state.allowEdit,
            activeThumbColor: AppTheme.pdfAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateConfig(allowEdit: v),
          ),
        ] else
          const StatusBanner(
            message:
                'Requiere conocer la contraseña actual autorizada para retirar el cifrado.',
            icon: LucideIcons.info,
            color: AppTheme.pdfAccent,
          ),
      ],
    );
  }
}

class ProtectPdfPrimaryActionButton extends ConsumerWidget {
  const ProtectPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(protectPdfNotifierProvider);
    final hasPassword = state.mode == ProtectPdfMode.encrypt
        ? (state.userPassword.isNotEmpty || state.ownerPassword.isNotEmpty)
        : state.currentPassword.isNotEmpty;
    final canRun = state.sourcePdfPath != null && hasPassword && !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canRun
            ? () => ref
                .read(protectPdfNotifierProvider.notifier)
                .processAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.pdfAccent,
          foregroundColor: Colors.white,
        ),
        icon: Icon(
          state.mode == ProtectPdfMode.encrypt
              ? LucideIcons.lock
              : LucideIcons.unlock,
          size: 18,
        ),
        label: Text(
          state.mode == ProtectPdfMode.encrypt
              ? 'Cifrar y Guardar PDF'
              : 'Desbloquear y Guardar PDF',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
