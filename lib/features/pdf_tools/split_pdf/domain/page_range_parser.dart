/// Representa un segmento continuo de páginas (1-indexed, inclusivo).
class PdfPageSegment {
  final int startPage;
  final int endPage;

  const PdfPageSegment({
    required this.startPage,
    required this.endPage,
  });

  String get label =>
      startPage == endPage ? 'pág_$startPage' : 'págs_$startPage-$endPage';

  List<int> get pages => [
        for (int p = startPage; p <= endPage; p++) p,
      ];
}

/// Resultado de validar y parsear una expresión de rangos como `"1-3, 5, 8-10"`.
class ParsedPageRangesResult {
  final List<PdfPageSegment> segments;
  final Set<int> uniqueSortedPages;
  final String? validationError;

  const ParsedPageRangesResult({
    this.segments = const [],
    this.uniqueSortedPages = const {},
    this.validationError,
  });

  bool get isValid => validationError == null && segments.isNotEmpty;
}

/// Analizador sintáctico para expresiones de rangos de páginas PDF (ej. `"1-3, 5, 8-10"`).
class PageRangeParser {
  static ParsedPageRangesResult parse(String input, {required int maxPages}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const ParsedPageRangesResult(
        validationError: 'Ingresa al menos una página o rango (ej. 1-3, 5).',
      );
    }

    final parts = trimmed
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return const ParsedPageRangesResult(
        validationError: 'Formato de rango vacío.',
      );
    }

    final segments = <PdfPageSegment>[];
    final allPages = <int>{};

    for (final token in parts) {
      if (token.contains('-')) {
        final bounds = token.split('-').map((s) => s.trim()).toList();
        if (bounds.length != 2) {
          return ParsedPageRangesResult(
            validationError: 'Rango inválido: "$token". Usa el formato A-B.',
          );
        }
        final start = int.tryParse(bounds[0]);
        final end = int.tryParse(bounds[1]);

        if (start == null || end == null) {
          return ParsedPageRangesResult(
            validationError: 'Números inválidos en el rango "$token".',
          );
        }
        if (start < 1 || end < 1) {
          return const ParsedPageRangesResult(
            validationError: 'Los números de página deben ser mayores o iguales a 1.',
          );
        }
        if (start > end) {
          return ParsedPageRangesResult(
            validationError:
                'En el rango "$token", la página inicial ($start) es mayor que la final ($end).',
          );
        }
        if (maxPages > 0 && end > maxPages) {
          return ParsedPageRangesResult(
            validationError:
                'El rango "$token" excede el total de páginas del documento ($maxPages).',
          );
        }

        final segment = PdfPageSegment(startPage: start, endPage: end);
        segments.add(segment);
        allPages.addAll(segment.pages);
      } else {
        final page = int.tryParse(token);
        if (page == null) {
          return ParsedPageRangesResult(
            validationError: 'Valor no numérico: "$token".',
          );
        }
        if (page < 1) {
          return const ParsedPageRangesResult(
            validationError: 'Las páginas comienzan en 1.',
          );
        }
        if (maxPages > 0 && page > maxPages) {
          return ParsedPageRangesResult(
            validationError:
                'La página $page excede el total del documento ($maxPages).',
          );
        }

        segments.add(PdfPageSegment(startPage: page, endPage: page));
        allPages.add(page);
      }
    }

    final sorted = allPages.toList()..sort();
    return ParsedPageRangesResult(
      segments: segments,
      uniqueSortedPages: sorted.toSet(),
    );
  }

  /// Convierte un conjunto de páginas seleccionadas (ej. `{1, 2, 3, 5, 8, 9}`)
  /// en su expresión compacta `"1-3, 5, 8-9"`.
  static String formatPagesToRangeString(Set<int> pages) {
    if (pages.isEmpty) return '';
    final sorted = pages.toList()..sort();

    final parts = <String>[];
    int rangeStart = sorted.first;
    int prev = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      if (current == prev + 1) {
        prev = current;
      } else {
        parts.add(rangeStart == prev ? '$rangeStart' : '$rangeStart-$prev');
        rangeStart = current;
        prev = current;
      }
    }
    parts.add(rangeStart == prev ? '$rangeStart' : '$rangeStart-$prev');
    return parts.join(', ');
  }
}



