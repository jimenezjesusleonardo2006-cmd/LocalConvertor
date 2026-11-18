import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../models/tool_item.dart';

/// Intent para atajo de teclado Ctrl/Cmd + O (Abrir archivos).
class OpenFilesIntent extends Intent {
  const OpenFilesIntent();
}

/// Intent para atajo de teclado Ctrl/Cmd + S (Procesar y Guardar).
class SaveOutputIntent extends Intent {
  const SaveOutputIntent();
}

/// Contenedor Adaptativo (Responsive) para Escritorio y Móvil.
///
/// - **Escritorio (>= 840px):** Barra lateral persistente + Área central de trabajo
///   + Panel lateral derecho de parámetros + Atajos `Ctrl/Cmd+O` y `Ctrl/Cmd+S`.
/// - **Móvil (< 840px):** Barra superior compacta + Área de trabajo táctil
///   + Botón de ajustes que despliega un `ModalBottomSheet` + Barra inferior.
class AdaptiveWorkspaceShell extends ConsumerWidget {
  final ToolCategory selectedCategory;
  final ValueChanged<ToolCategory> onCategorySelected;
  final ToolItem? activeTool;
  final VoidCallback? onCloseTool;
  final Widget body;
  final Widget? settingsPanel;
  final VoidCallback? onShortcutOpenFiles;
  final VoidCallback? onShortcutSaveOutput;
  final Widget? primaryActionFooter;

  const AdaptiveWorkspaceShell({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.body,
    this.activeTool,
    this.onCloseTool,
    this.settingsPanel,
    this.onShortcutOpenFiles,
    this.onShortcutSaveOutput,
    this.primaryActionFooter,
  });

  static const double desktopBreakpoint = 840.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= desktopBreakpoint;
    final themeMode = ref.watch(themeModeProvider);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            const OpenFilesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            const OpenFilesIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const SaveOutputIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            const SaveOutputIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenFilesIntent: CallbackAction<OpenFilesIntent>(
            onInvoke: (_) {
              onShortcutOpenFiles?.call();
              return null;
            },
          ),
          SaveOutputIntent: CallbackAction<SaveOutputIntent>(
            onInvoke: (_) {
              onShortcutSaveOutput?.call();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: isDesktop
              ? _buildDesktopLayout(context, ref, themeMode)
              : _buildMobileLayout(context, ref, themeMode),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // 1. Barra Lateral Persistente de Escritorio
          Material(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            child: Container(
              width: 250,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding LocalConvert
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 38,
                            height: 38,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.pdfAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              LucideIcons.layers,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LocalConvert',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '100% Offline Suite',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.privacyBadge,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'MÓDULOS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...ToolCategory.values.map((category) {
                  final isSelected =
                      activeTool == null && selectedCategory == category ||
                          activeTool?.category == category;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      selected: isSelected,
                      selectedTileColor:
                          theme.colorScheme.primary.withValues(alpha: 0.1),
                      leading: Icon(
                        category.icon,
                        size: 20,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      title: Text(
                        category.label,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        if (activeTool != null) {
                          onCloseTool?.call();
                        }
                        onCategorySelected(category);
                      },
                    ),
                  );
                }),
                const Spacer(),
                // Insignia de Auditoría de Privacidad Zero-Network
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.privacyBadge.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.privacyBadge.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.shieldCheck,
                        color: AppTheme.privacyBadge,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Zero-Network\nSandbox Local Activo',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.privacyBadge,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Acerca de + Selector Light / Dark Mode
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(LucideIcons.info, size: 18),
                    title: const Text('Acerca de'),
                    onTap: () => _showAboutDialog(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      isDark ? LucideIcons.sun : LucideIcons.moon,
                      size: 18,
                    ),
                    title: Text(isDark ? 'Modo Claro' : 'Modo Oscuro'),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).toggle(isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
          ),

          // 2. Área Central de Trabajo
          Expanded(
            child: Column(
              children: [
                if (activeTool != null) _buildToolHeaderBar(context),
                Expanded(child: body),
              ],
            ),
          ),

          // 3. Panel Lateral Derecho de Configuración (solo si hay herramienta activa)
          if (activeTool != null && settingsPanel != null)
            Material(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              child: Container(
                width: 340,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.sliders,
                            size: 18,
                            color: activeTool!.accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Parámetros de Conversión',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: settingsPanel!,
                      ),
                    ),
                    if (primaryActionFooter != null)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: primaryActionFooter!,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: activeTool != null
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: onCloseTool,
              )
            : null,
        title: Text(
          activeTool != null ? activeTool!.title : 'LocalConvert',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (activeTool != null && settingsPanel != null)
            IconButton(
              tooltip: 'Ajustes de conversión',
              icon: const Icon(LucideIcons.sliders),
              onPressed: () => _showMobileSettingsSheet(context),
            ),
          IconButton(
            tooltip: 'Cambiar tema',
            icon: Icon(isDark ? LucideIcons.sun : LucideIcons.moon),
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle(isDark);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (activeTool != null && primaryActionFooter != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    if (settingsPanel != null) ...[
                      OutlinedButton.icon(
                        onPressed: () => _showMobileSettingsSheet(context),
                        icon: const Icon(LucideIcons.sliders, size: 18),
                        label: const Text('Ajustes'),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: primaryActionFooter!),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: activeTool == null
          ? NavigationBar(
              selectedIndex: ToolCategory.values.indexOf(selectedCategory),
              onDestinationSelected: (idx) =>
                  onCategorySelected(ToolCategory.values[idx]),
              destinations: ToolCategory.values.map((cat) {
                return NavigationDestination(
                  icon: Icon(cat.icon),
                  label: cat.label,
                );
              }).toList(),
            )
          : null,
    );
  }

  Widget _buildToolHeaderBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color:
                isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver al Dashboard',
            onPressed: onCloseTool,
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: activeTool!.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              activeTool!.icon,
              size: 18,
              color: activeTool!.accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeTool!.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  activeTool!.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileSettingsSheet(BuildContext context) {
    if (settingsPanel == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: settingsPanel!,
            ),
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icons/app_icon.png',
                width: 40,
                height: 40,
                errorBuilder: (_, __, ___) => const Icon(
                  LucideIcons.layers,
                  color: AppTheme.pdfAccent,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LocalConvert',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Versión 1.0.0 • LocalConvert Studio',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suite local de conversión y manipulación de archivos PDF, imágenes, ofimática y multimedia sin subir archivos a la nube.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              '• Motor nativo FFI en Rust (local_convert_core.dll)\n'
              '• PDFium + Syncfusion PDF + FFmpeg local empaquetado\n'
              '• 100% Offline (excepto conexión directa opcional a YouTube)',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}




