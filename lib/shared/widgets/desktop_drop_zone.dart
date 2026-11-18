import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Zona interactiva de Arrastrar y Soltar (Drag & Drop) en Escritorio
/// y selector táctil prominente en Móvil.
class DesktopDropZone extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> allowedExtensionsBadges;
  final Color accentColor;
  final VoidCallback onPickFilesPressed;
  final ValueChanged<List<String>> onFilesDropped;
  final bool compact;

  const DesktopDropZone({
    super.key,
    required this.title,
    required this.subtitle,
    required this.allowedExtensionsBadges,
    required this.accentColor,
    required this.onPickFilesPressed,
    required this.onFilesDropped,
    this.compact = false,
  });

  @override
  State<DesktopDropZone> createState() => _DesktopDropZoneState();
}

class _DesktopDropZoneState extends State<DesktopDropZone> {
  static bool? _cachedNativeDropSupported;
  bool _isDragging = false;

  static bool get _isNativeDropSupported {
    final cached = _cachedNativeDropSupported;
    if (cached != null) return cached;

    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return _cachedNativeDropSupported = false;
    }
    if (WidgetsBinding.instance is! WidgetsFlutterBinding) {
      return false;
    }
    return _cachedNativeDropSupported = true;
  }

  void _handleDrop(DropDoneDetails details) {
    if (mounted) {
      setState(() => _isDragging = false);
    }

    final paths = <String>[];
    for (final item in details.files) {
      if (item is DropItemDirectory) {
        for (final child in item.children) {
          if (child is! DropItemDirectory && child.path.isNotEmpty) {
            paths.add(child.path);
          }
        }
        if (item.children.isEmpty && item.path.isNotEmpty) {
          final dir = Directory(item.path);
          if (dir.existsSync()) {
            for (final entity in dir.listSync(followLinks: false)) {
              if (entity is File) {
                paths.add(entity.path);
              }
            }
          }
        }
      } else if (item.path.isNotEmpty) {
        paths.add(item.path);
      }
    }

    if (paths.isNotEmpty) {
      widget.onFilesDropped(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dropContent = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: widget.compact ? 18 : 36,
        ),
        decoration: BoxDecoration(
          color: _isDragging
              ? widget.accentColor.withValues(alpha: 0.10)
              : (isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                  : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isDragging
                ? widget.accentColor
                : widget.accentColor.withValues(alpha: 0.35),
            width: _isDragging ? 2.5 : 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.compact) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isDragging ? LucideIcons.downloadCloud : LucideIcons.upload,
                  size: 36,
                  color: widget.accentColor,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              _isDragging ? '¡Suelta los archivos aquí!' : widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: widget.allowedExtensionsBadges.map((ext) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ext,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onPickFilesPressed,
              style: FilledButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.folderOpen, size: 18),
              label: Text(
                widget.compact
                    ? 'Añadir más archivos (Ctrl+O)'
                    : 'Seleccionar archivos (Ctrl+O)',
              ),
            ),
          ],
        ),
      );

    if (!_isNativeDropSupported) {
      return dropContent;
    }

    return DropTarget(
      onDragEntered: (_) {
        if (mounted) setState(() => _isDragging = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _isDragging = false);
      },
      onDragDone: _handleDrop,
      child: dropContent,
    );
  }
}
