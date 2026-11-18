import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/models/tool_item.dart';

/// Pantalla Principal (Dashboard estilo iLovePDF) con filtro rápido por categoría
/// y cuadrícula responsiva de herramientas 100% locales.
class DashboardScreen extends StatefulWidget {
  final ToolCategory selectedCategory;
  final ValueChanged<ToolCategory> onCategoryChanged;
  final ValueChanged<ToolItem> onToolSelected;

  const DashboardScreen({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onToolSelected,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _searchQuery = '';

  List<ToolItem> get _filteredTools {
    return ToolItem.catalog.where((tool) {
      final matchesCategory = widget.selectedCategory == ToolCategory.all ||
          tool.category == widget.selectedCategory;
      final q = _searchQuery.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          tool.title.toLowerCase().contains(q) ||
          tool.subtitle.toLowerCase().contains(q) ||
          tool.supportedFormats.any((f) => f.toLowerCase().contains(q));
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = _filteredTools;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todas las herramientas para tus archivos, 100% en tu dispositivo',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Convierte, une, divide y comprime PDFs, imágenes y documentos sin subir jamás tus datos a ningún servidor.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 20),
                // Barra de búsqueda + Filtros rápidos por categoría
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Buscar herramienta (ej. PDF, WEBP, Unir)...',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: theme.cardTheme.color,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    ...ToolCategory.values.map((category) {
                      final isSelected = widget.selectedCategory == category;
                      return ChoiceChip(
                        selected: isSelected,
                        onSelected: (_) => widget.onCategoryChanged(category),
                        avatar: Icon(
                          category.icon,
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                        label: Text(category.label),
                        selectedColor: theme.colorScheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 36),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisExtent: 272,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final tool = tools[index];
                return _ToolDashboardCard(
                  tool: tool,
                  onTap: () => widget.onToolSelected(tool),
                );
              },
              childCount: tools.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolDashboardCard extends StatefulWidget {
  final ToolItem tool;
  final VoidCallback onTap;

  const _ToolDashboardCard({
    required this.tool,
    required this.onTap,
  });

  @override
  State<_ToolDashboardCard> createState() => _ToolDashboardCardState();
}

class _ToolDashboardCardState extends State<_ToolDashboardCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = widget.tool;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0.0, _isHovered ? -3.0 : 0.0, 0.0),
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _isHovered
                  ? tool.accentColor
                  : theme.dividerColor.withValues(alpha: 0.15),
              width: _isHovered ? 1.8 : 1.0,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tool.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          tool.icon,
                          color: tool.accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: tool.supportedFormats.take(3).map((fmt) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: tool.accentColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  fmt,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: tool.accentColor,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tool.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      tool.subtitle,
                      maxLines: tool.requiresDirectNetwork ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (tool.requiresDirectNetwork) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.wifi,
                          size: 13,
                          color: tool.accentColor,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Requiere conexión directa a YouTube',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tool.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}



