import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

/// Rasterizador SVG offline en puro Dart para ejecutarse dentro de un [Isolate]
/// sin dependencias de red ni de contexto de UI.
class SvgRasterizer {
  const SvgRasterizer._();

  /// Decodifica un documento SVG a un buffer raster RGBA aplicando [scaleMultiplier]
  /// (`1x`, `2x`, `4x`) y respetando el límite máximo [maxDimensionPx].
  static img.Image decodeSvgToImage(
    String svgSource, {
    int scaleMultiplier = 2,
    int maxDimensionPx = 4096,
  }) {
    final document = XmlDocument.parse(svgSource);
    final root = document.rootElement;
    if (root.name.local.toLowerCase() != 'svg') {
      throw const FormatException('El archivo no contiene un nodo raíz <svg>.');
    }

    double vbMinX = 0;
    double vbMinY = 0;
    double? vbWidth;
    double? vbHeight;

    final viewBoxAttr = root.getAttribute('viewBox');
    if (viewBoxAttr != null) {
      final nums = _parseNumberList(viewBoxAttr);
      if (nums.length >= 4) {
        vbMinX = nums[0];
        vbMinY = nums[1];
        vbWidth = nums[2] > 0 ? nums[2] : null;
        vbHeight = nums[3] > 0 ? nums[3] : null;
      }
    }

    final attrW = _parseLength(root.getAttribute('width'));
    final attrH = _parseLength(root.getAttribute('height'));
    final baseW = attrW ?? vbWidth ?? 512.0;
    final baseH = attrH ?? vbHeight ?? 512.0;
    final srcW = vbWidth ?? baseW;
    final srcH = vbHeight ?? baseH;

    final mult = scaleMultiplier.clamp(1, 8);
    double outW = math.max(1.0, baseW * mult);
    double outH = math.max(1.0, baseH * mult);

    final maxSide = math.max(outW, outH);
    if (maxSide > maxDimensionPx) {
      final ratio = maxDimensionPx / maxSide;
      outW *= ratio;
      outH *= ratio;
    }

    final canvasW = math.max(1, outW.round());
    final canvasH = math.max(1, outH.round());
    final sx = canvasW / math.max(0.001, srcW);
    final sy = canvasH / math.max(0.001, srcH);

    final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    _renderElement(
      canvas: canvas,
      element: root,
      offsetX: -vbMinX,
      offsetY: -vbMinY,
      sx: sx,
      sy: sy,
      inheritedStyle: const _SvgStyle(),
    );

    return canvas;
  }

  static void _renderElement({
    required img.Image canvas,
    required XmlElement element,
    required double offsetX,
    required double offsetY,
    required double sx,
    required double sy,
    required _SvgStyle inheritedStyle,
  }) {
    final style = inheritedStyle.mergeFrom(element);
    final tag = element.name.local.toLowerCase();

    if (tag == 'defs' || tag == 'clippath' || tag == 'mask') {
      return;
    }

    if (tag == 'svg' || tag == 'g') {
      final dx = _parseTranslateX(element.getAttribute('transform'));
      final dy = _parseTranslateY(element.getAttribute('transform'));
      for (final child in element.childElements) {
        _renderElement(
          canvas: canvas,
          element: child,
          offsetX: offsetX + dx,
          offsetY: offsetY + dy,
          sx: sx,
          sy: sy,
          inheritedStyle: style,
        );
      }
      return;
    }

    final dx = offsetX + _parseTranslateX(element.getAttribute('transform'));
    final dy = offsetY + _parseTranslateY(element.getAttribute('transform'));

    switch (tag) {
      case 'rect':
        final x = (_parseLength(element.getAttribute('x')) ?? 0) + dx;
        final y = (_parseLength(element.getAttribute('y')) ?? 0) + dy;
        final w = _parseLength(element.getAttribute('width')) ?? 0;
        final h = _parseLength(element.getAttribute('height')) ?? 0;
        final rx = _parseLength(element.getAttribute('rx')) ?? 0;
        if (w <= 0 || h <= 0) return;

        final x1 = (x * sx).round();
        final y1 = (y * sy).round();
        final x2 = ((x + w) * sx).round();
        final y2 = ((y + h) * sy).round();
        if (style.fillColor != null) {
          img.fillRect(
            canvas,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            radius: (rx * ((sx + sy) / 2)).round(),
            color: style.fillColor!,
          );
        }
        if (style.strokeColor != null && style.strokeWidth > 0) {
          img.drawRect(
            canvas,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            thickness: math.max(1, (style.strokeWidth * sx).round()),
            color: style.strokeColor!,
          );
        }
      case 'circle':
        final cx = (_parseLength(element.getAttribute('cx')) ?? 0) + dx;
        final cy = (_parseLength(element.getAttribute('cy')) ?? 0) + dy;
        final r = _parseLength(element.getAttribute('r')) ?? 0;
        if (r <= 0) return;
        final px = (cx * sx).round();
        final py = (cy * sy).round();
        final pr = math.max(1, (r * ((sx + sy) / 2)).round());
        if (style.fillColor != null) {
          img.fillCircle(
            canvas,
            x: px,
            y: py,
            radius: pr,
            color: style.fillColor!,
            antialias: true,
          );
        }
        if (style.strokeColor != null && style.strokeWidth > 0) {
          img.drawCircle(
            canvas,
            x: px,
            y: py,
            radius: pr,
            color: style.strokeColor!,
            antialias: true,
          );
        }
      case 'ellipse':
        final cx = (_parseLength(element.getAttribute('cx')) ?? 0) + dx;
        final cy = (_parseLength(element.getAttribute('cy')) ?? 0) + dy;
        final rx = _parseLength(element.getAttribute('rx')) ?? 0;
        final ry = _parseLength(element.getAttribute('ry')) ?? 0;
        if (rx <= 0 || ry <= 0) return;
        final pts = <img.Point>[
          for (int i = 0; i < 36; i++)
            img.Point(
              ((cx + rx * math.cos(2 * math.pi * i / 36)) * sx).round(),
              ((cy + ry * math.sin(2 * math.pi * i / 36)) * sy).round(),
            ),
        ];
        if (style.fillColor != null) {
          img.fillPolygon(canvas, vertices: pts, color: style.fillColor!);
        }
        if (style.strokeColor != null) {
          _strokePolyline(
            canvas,
            pts,
            style.strokeColor!,
            math.max(1, style.strokeWidth * sx),
            closed: true,
          );
        }
      case 'line':
        final x1 = (_parseLength(element.getAttribute('x1')) ?? 0) + dx;
        final y1 = (_parseLength(element.getAttribute('y1')) ?? 0) + dy;
        final x2 = (_parseLength(element.getAttribute('x2')) ?? 0) + dx;
        final y2 = (_parseLength(element.getAttribute('y2')) ?? 0) + dy;
        final color = style.strokeColor ?? style.fillColor;
        if (color != null) {
          img.drawLine(
            canvas,
            x1: (x1 * sx).round(),
            y1: (y1 * sy).round(),
            x2: (x2 * sx).round(),
            y2: (y2 * sy).round(),
            color: color,
            antialias: true,
            thickness: math.max(1, (style.strokeWidth * sx).round()),
          );
        }
      case 'polygon':
      case 'polyline':
        final nums = _parseNumberList(element.getAttribute('points') ?? '');
        final pts = <img.Point>[];
        for (int i = 0; i + 1 < nums.length; i += 2) {
          pts.add(
            img.Point(
              ((nums[i] + dx) * sx).round(),
              ((nums[i + 1] + dy) * sy).round(),
            ),
          );
        }
        if (pts.isEmpty) return;
        if (tag == 'polygon' && style.fillColor != null) {
          img.fillPolygon(canvas, vertices: pts, color: style.fillColor!);
        }
        if (style.strokeColor != null) {
          _strokePolyline(
            canvas,
            pts,
            style.strokeColor!,
            math.max(1, style.strokeWidth * sx),
            closed: tag == 'polygon',
          );
        }
      case 'path':
        final d = element.getAttribute('d');
        if (d == null || d.isEmpty) return;
        final subPaths = _parsePathToSubPolygons(d);
        for (final sub in subPaths) {
          final scaled = [
            for (final pt in sub.points)
              img.Point(((pt.x + dx) * sx).round(), ((pt.y + dy) * sy).round()),
          ];
          if (scaled.isEmpty) continue;
          if (style.fillColor != null && (sub.closed || scaled.length >= 3)) {
            img.fillPolygon(canvas, vertices: scaled, color: style.fillColor!);
          }
          if (style.strokeColor != null) {
            _strokePolyline(
              canvas,
              scaled,
              style.strokeColor!,
              math.max(1, style.strokeWidth * sx),
              closed: sub.closed,
            );
          }
        }
    }
  }

  static void _strokePolyline(
    img.Image canvas,
    List<img.Point> pts,
    img.Color color,
    num thickness, {
    required bool closed,
  }) {
    if (pts.length < 2) return;
    final t = math.max(1, thickness.round());
    for (int i = 0; i < pts.length - 1; i++) {
      img.drawLine(
        canvas,
        x1: pts[i].xi,
        y1: pts[i].yi,
        x2: pts[i + 1].xi,
        y2: pts[i + 1].yi,
        color: color,
        antialias: true,
        thickness: t,
      );
    }
    if (closed) {
      img.drawLine(
        canvas,
        x1: pts.last.xi,
        y1: pts.last.yi,
        x2: pts.first.xi,
        y2: pts.first.yi,
        color: color,
        antialias: true,
        thickness: t,
      );
    }
  }

  static List<({List<({double x, double y})> points, bool closed})>
      _parsePathToSubPolygons(String d) {
    final tokenRegex = RegExp(
      r'[MmLlHhVvCcQqZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    );
    final tokens = tokenRegex.allMatches(d).map((m) => m.group(0)!).toList();

    final result = <({List<({double x, double y})> points, bool closed})>[];
    var currentPts = <({double x, double y})>[];
    double cx = 0, cy = 0;
    double startX = 0, startY = 0;
    String cmd = '';
    int i = 0;

    bool isCmd(String s) =>
        s.length == 1 && 'MmLlHhVvCcQqZz'.contains(s);

    double nextNum() {
      if (i >= tokens.length || isCmd(tokens[i])) return 0;
      return double.tryParse(tokens[i++]) ?? 0;
    }

    while (i < tokens.length) {
      if (isCmd(tokens[i])) {
        cmd = tokens[i++];
        if (cmd == 'Z' || cmd == 'z') {
          if (currentPts.isNotEmpty) {
            result.add((points: currentPts, closed: true));
            currentPts = <({double x, double y})>[];
          }
          cx = startX;
          cy = startY;
          continue;
        }
      }

      if (i >= tokens.length && cmd != 'Z' && cmd != 'z') break;

      switch (cmd) {
        case 'M':
          if (currentPts.isNotEmpty) {
            result.add((points: currentPts, closed: false));
            currentPts = <({double x, double y})>[];
          }
          cx = nextNum();
          cy = nextNum();
          startX = cx;
          startY = cy;
          currentPts.add((x: cx, y: cy));
          cmd = 'L';
        case 'm':
          if (currentPts.isNotEmpty) {
            result.add((points: currentPts, closed: false));
            currentPts = <({double x, double y})>[];
          }
          cx += nextNum();
          cy += nextNum();
          startX = cx;
          startY = cy;
          currentPts.add((x: cx, y: cy));
          cmd = 'l';
        case 'L':
          cx = nextNum();
          cy = nextNum();
          currentPts.add((x: cx, y: cy));
        case 'l':
          cx += nextNum();
          cy += nextNum();
          currentPts.add((x: cx, y: cy));
        case 'H':
          cx = nextNum();
          currentPts.add((x: cx, y: cy));
        case 'h':
          cx += nextNum();
          currentPts.add((x: cx, y: cy));
        case 'V':
          cy = nextNum();
          currentPts.add((x: cx, y: cy));
        case 'v':
          cy += nextNum();
          currentPts.add((x: cx, y: cy));
        case 'C':
        case 'c':
          final rel = cmd == 'c';
          final x1 = (rel ? cx : 0) + nextNum();
          final y1 = (rel ? cy : 0) + nextNum();
          final x2 = (rel ? cx : 0) + nextNum();
          final y2 = (rel ? cy : 0) + nextNum();
          final x3 = (rel ? cx : 0) + nextNum();
          final y3 = (rel ? cy : 0) + nextNum();
          for (int s = 1; s <= 6; s++) {
            final t = s / 6.0;
            final mt = 1.0 - t;
            final px = mt * mt * mt * cx +
                3 * mt * mt * t * x1 +
                3 * mt * t * t * x2 +
                t * t * t * x3;
            final py = mt * mt * mt * cy +
                3 * mt * mt * t * y1 +
                3 * mt * t * t * y2 +
                t * t * t * y3;
            currentPts.add((x: px, y: py));
          }
          cx = x3;
          cy = y3;
        case 'Q':
        case 'q':
          final rel = cmd == 'q';
          final x1 = (rel ? cx : 0) + nextNum();
          final y1 = (rel ? cy : 0) + nextNum();
          final x2 = (rel ? cx : 0) + nextNum();
          final y2 = (rel ? cy : 0) + nextNum();
          for (int s = 1; s <= 5; s++) {
            final t = s / 5.0;
            final mt = 1.0 - t;
            final px = mt * mt * cx + 2 * mt * t * x1 + t * t * x2;
            final py = mt * mt * cy + 2 * mt * t * y1 + t * t * y2;
            currentPts.add((x: px, y: py));
          }
          cx = x2;
          cy = y2;
        default:
          i++;
      }
    }

    if (currentPts.isNotEmpty) {
      result.add((points: currentPts, closed: false));
    }
    return result;
  }

  static double? _parseLength(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw.trim().replaceAll(RegExp(r'(px|pt|dp|mm|cm|in)$'), '');
    return double.tryParse(cleaned);
  }

  static List<double> _parseNumberList(String raw) {
    final matches = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)').allMatches(raw);
    return [
      for (final m in matches)
        if (double.tryParse(m.group(0)!) != null) double.parse(m.group(0)!),
    ];
  }

  static double _parseTranslateX(String? transform) {
    if (transform == null) return 0;
    final m = RegExp(r'translate\(\s*([-+]?[\d.]+)').firstMatch(transform);
    return m != null ? (double.tryParse(m.group(1)!) ?? 0) : 0;
  }

  static double _parseTranslateY(String? transform) {
    if (transform == null) return 0;
    final m = RegExp(r'translate\(\s*[-+]?[\d.]+[\s,]+([-+]?[\d.]+)')
        .firstMatch(transform);
    return m != null ? (double.tryParse(m.group(1)!) ?? 0) : 0;
  }
}

class _SvgStyle {
  final img.Color? fillColor;
  final bool hasExplicitFill;
  final img.Color? strokeColor;
  final double strokeWidth;

  const _SvgStyle({
    this.fillColor,
    this.hasExplicitFill = false,
    this.strokeColor,
    this.strokeWidth = 1.0,
  });

  _SvgStyle mergeFrom(XmlElement element) {
    final styleMap = <String, String>{};
    final styleAttr = element.getAttribute('style');
    if (styleAttr != null) {
      for (final decl in styleAttr.split(';')) {
        final idx = decl.indexOf(':');
        if (idx > 0) {
          styleMap[decl.substring(0, idx).trim().toLowerCase()] =
              decl.substring(idx + 1).trim();
        }
      }
    }

    String? attr(String key) => styleMap[key] ?? element.getAttribute(key);

    final opacity = double.tryParse(attr('opacity') ?? '') ?? 1.0;
    final fillOpacity =
        (double.tryParse(attr('fill-opacity') ?? '') ?? 1.0) * opacity;
    final strokeOpacity =
        (double.tryParse(attr('stroke-opacity') ?? '') ?? 1.0) * opacity;

    img.Color? nextFill = hasExplicitFill
        ? fillColor
        : img.ColorRgba8(0, 0, 0, (255 * fillOpacity).round().clamp(0, 255));
    bool nextExplicitFill = hasExplicitFill;
    final fillRaw = attr('fill');
    if (fillRaw != null) {
      nextFill = _parseSvgColor(fillRaw, opacity: fillOpacity);
      nextExplicitFill = true;
    }

    img.Color? nextStroke = strokeColor;
    final strokeRaw = attr('stroke');
    if (strokeRaw != null) {
      nextStroke = _parseSvgColor(strokeRaw, opacity: strokeOpacity);
    }

    final sw = double.tryParse(
          (attr('stroke-width') ?? '').replaceAll('px', '').trim(),
        ) ??
        strokeWidth;

    return _SvgStyle(
      fillColor: nextFill,
      hasExplicitFill: nextExplicitFill,
      strokeColor: nextStroke,
      strokeWidth: sw,
    );
  }

  static img.Color? _parseSvgColor(String raw, {double opacity = 1.0}) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s == 'none' || s == 'transparent') return null;

    int a = (255 * opacity.clamp(0.0, 1.0)).round();
    int r = 0, g = 0, b = 0;

    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 3) {
        r = int.parse(hex[0] * 2, radix: 16);
        g = int.parse(hex[1] * 2, radix: 16);
        b = int.parse(hex[2] * 2, radix: 16);
      } else if (hex.length == 6) {
        r = int.parse(hex.substring(0, 2), radix: 16);
        g = int.parse(hex.substring(2, 4), radix: 16);
        b = int.parse(hex.substring(4, 6), radix: 16);
      } else if (hex.length == 8) {
        a = ((int.parse(hex.substring(0, 2), radix: 16) * opacity).round())
            .clamp(0, 255);
        r = int.parse(hex.substring(2, 4), radix: 16);
        g = int.parse(hex.substring(4, 6), radix: 16);
        b = int.parse(hex.substring(6, 8), radix: 16);
      }
      return img.ColorRgba8(r, g, b, a);
    }

    if (s.startsWith('rgb')) {
      final nums = RegExp(r'\d+').allMatches(s).map((m) => int.parse(m.group(0)!)).toList();
      if (nums.length >= 3) {
        return img.ColorRgba8(
          nums[0].clamp(0, 255),
          nums[1].clamp(0, 255),
          nums[2].clamp(0, 255),
          a,
        );
      }
    }

    const named = <String, int>{
      'black': 0x000000,
      'white': 0xFFFFFF,
      'red': 0xEF4444,
      'green': 0x22C55E,
      'blue': 0x3B82F6,
      'yellow': 0xEAB308,
      'orange': 0xF97316,
      'purple': 0xA855F7,
      'gray': 0x64748B,
      'grey': 0x64748B,
      'cyan': 0x06B6D4,
    };
    final value = named[s];
    if (value != null) {
      return img.ColorRgba8(
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
        a,
      );
    }
    return img.ColorRgba8(0, 0, 0, a);
  }
}
