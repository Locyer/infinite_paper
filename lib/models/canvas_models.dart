import 'dart:math' as math;
import 'dart:ui';

/// 画布工具。laser 仅驻留内存，不保存到文档。
enum CanvasTool {
  pen,
  highlighter,
  laser,
  eraserStroke,
  eraserPartial,
  select,
  lasso,
  pan
}

/// 普通画笔的笔尖效果。它独立于荧光笔、激光笔等其它工具的设置。
enum PenStyle { fountain, pencil, ballpoint, brush, calligraphy }

enum CanvasBackground { blank, grid, warm }

enum AppThemeMode { system, light, dark }

enum CanvasInputMode { penAndTouch, stylusOnly, fingerPan }

/// 选择内容的展示形式。自由套索不会自动变成矩形控制框。
enum SelectionPresentation { none, object, lassoPath, transformBox }

class StrokePoint {
  const StrokePoint(
      {required this.x,
      required this.y,
      required this.pressure,
      required this.time});
  final double x;
  final double y;
  final double pressure;
  final int time;
  Offset get offset => Offset(x, y);
  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'pressure': pressure, 'time': time};
  factory StrokePoint.fromJson(Map<String, dynamic> j) => StrokePoint(
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      pressure: (j['pressure'] as num? ?? 1).toDouble(),
      time: (j['time'] as num? ?? 0).toInt());
  @override
  bool operator ==(Object o) =>
      o is StrokePoint &&
      o.x == x &&
      o.y == y &&
      o.pressure == pressure &&
      o.time == time;
  @override
  int get hashCode => Object.hash(x, y, pressure, time);
}

class Viewport {
  const Viewport({this.scale = 1, this.offset = Offset.zero});
  static const minScale = 0.001, maxScale = 15.0;
  final double scale;
  final Offset offset;
  Offset screenToWorld(Offset screen) => (screen - offset) / scale;
  Viewport zoomAround(Offset focal, double factor) {
    final p = screenToWorld(focal);
    final s = (scale * factor).clamp(minScale, maxScale).toDouble();
    return Viewport(scale: s, offset: focal - p * s);
  }

  Viewport pan(Offset delta) => Viewport(scale: scale, offset: offset + delta);
  Map<String, dynamic> toJson() =>
      {'scale': scale, 'offsetX': offset.dx, 'offsetY': offset.dy};
  factory Viewport.fromJson(Map<String, dynamic>? j) => Viewport(
      scale: ((j?['scale'] as num?) ?? 1)
          .toDouble()
          .clamp(minScale, maxScale)
          .toDouble(),
      offset: Offset(((j?['offsetX'] as num?) ?? 0).toDouble(),
          ((j?['offsetY'] as num?) ?? 0).toDouble()));
}

class Stroke {
  Stroke(
      {required this.id,
      required List<StrokePoint> points,
      required this.colorValue,
      required this.width,
      this.tool = CanvasTool.pen,
      this.penStyle = PenStyle.fountain,
      this.isErased = false})
      : points = List.unmodifiable(points);
  factory Stroke.pen(
          {required String id,
          required List<StrokePoint> points,
          required int colorValue,
          required double width,
          CanvasTool tool = CanvasTool.pen,
          PenStyle penStyle = PenStyle.fountain}) =>
      Stroke(
          id: id,
          points: points,
          colorValue: colorValue,
          width: width,
          tool: tool,
          penStyle: penStyle);
  final String id;
  final List<StrokePoint> points;
  final int colorValue;
  final double width;
  final CanvasTool tool;
  final PenStyle penStyle;
  final bool isErased;
  Path? _cachedPath;
  Rect? _cachedBounds;
  Color get color => Color(colorValue);
  Path get path => _cachedPath ??= _buildPath();
  Rect get bounds => _cachedBounds ??= _buildBounds();
  Stroke copyWith(
          {String? id,
          List<StrokePoint>? points,
          int? colorValue,
          double? width,
          CanvasTool? tool,
          PenStyle? penStyle,
          bool? isErased}) =>
      Stroke(
          id: id ?? this.id,
          points: points ?? this.points,
          colorValue: colorValue ?? this.colorValue,
          width: width ?? this.width,
          tool: tool ?? this.tool,
          penStyle: penStyle ?? this.penStyle,
          isErased: isErased ?? this.isErased);
  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points.map((p) => p.toJson()).toList(),
        'color': colorValue,
        'width': width,
        'tool': tool.name,
        'penStyle': penStyle.name,
        'erased': isErased
      };
  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
      id: j['id'] as String,
      points: (j['points'] as List<dynamic>? ?? const [])
          .map((e) => StrokePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      colorValue: (j['color'] as num? ?? 0xff111827).toInt(),
      width: (j['width'] as num? ?? 3).toDouble(),
      tool: _toolFromName(j['tool'] as String?),
      penStyle: _penStyleFromName(j['penStyle'] as String?),
      isErased: j['erased'] as bool? ?? false);
  bool hitTest(Offset p, double radius) {
    final threshold = radius + width / 2;
    if (points.isEmpty) return false;
    if (points.length == 1)
      return (points.first.offset - p).distance <= threshold;
    for (var i = 1; i < points.length; i++) {
      if (distanceToSegment(p, points[i - 1].offset, points[i].offset) <=
          threshold) return true;
    }
    return false;
  }

  Path _buildPath() {
    final r = Path();
    if (points.isEmpty) return r;
    r.moveTo(points.first.x, points.first.y);
    if (points.length == 1) {
      r.lineTo(points.first.x + .01, points.first.y + .01);
      return r;
    }
    for (var i = 1; i < points.length - 1; i++) {
      final p = points[i], n = points[i + 1];
      r.quadraticBezierTo(p.x, p.y, (p.x + n.x) / 2, (p.y + n.y) / 2);
    }
    r.lineTo(points.last.x, points.last.y);
    return r;
  }

  Rect _buildBounds() {
    if (points.isEmpty) return Rect.zero;
    var l = points.first.x, r = l, t = points.first.y, b = t;
    for (final p in points.skip(1)) {
      l = math.min(l, p.x);
      r = math.max(r, p.x);
      t = math.min(t, p.y);
      b = math.max(b, p.y);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final v = b - a;
    final d = v.dx * v.dx + v.dy * v.dy;
    if (d == 0) return (p - a).distance;
    final k =
        (((p.dx - a.dx) * v.dx + (p.dy - a.dy) * v.dy) / d).clamp(0.0, 1.0);
    return (p - Offset(a.dx + v.dx * k, a.dy + v.dy * k)).distance;
  }
}

PenStyle _penStyleFromName(String? name) => switch (name) {
      'pencil' => PenStyle.pencil,
      'ballpoint' => PenStyle.ballpoint,
      'brush' => PenStyle.brush,
      'calligraphy' => PenStyle.calligraphy,
      _ => PenStyle.fountain,
    };

CanvasTool _toolFromName(String? name) => switch (name) {
      'highlighter' => CanvasTool.highlighter,
      'eraser' || 'eraserStroke' => CanvasTool.eraserStroke,
      _ => CanvasTool.pen
    };

class CanvasImage {
  const CanvasImage({required this.id, required this.path, required this.rect, this.rotation = 0});
  final String id;
  final String path;
  final Rect rect;
  final double rotation;
  CanvasImage copyWith({String? id, String? path, Rect? rect, double? rotation}) => CanvasImage(
      id: id ?? this.id, path: path ?? this.path, rect: rect ?? this.rect, rotation: rotation ?? this.rotation);
  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height, 'rotation': rotation
      };
  factory CanvasImage.fromJson(Map<String, dynamic> j) => CanvasImage(
      id: j['id'] as String,
      path: j['path'] as String,
      rect: Rect.fromLTWH(
          (j['x'] as num).toDouble(),
          (j['y'] as num).toDouble(),
          (j['width'] as num).toDouble(),
          (j['height'] as num).toDouble()), rotation: (j['rotation'] as num? ?? 0).toDouble());
}

class CanvasText {
  const CanvasText(
      {required this.id,
      required this.text,
      required this.rect,
      required this.colorValue,
      required this.fontSize, this.rotation = 0, this.alignment = TextAlign.left,
      this.fontFamily});
  final String id;
  final String text;
  final Rect rect;
  final int colorValue;
  final double fontSize;
  final double rotation;
  final TextAlign alignment;
  final String? fontFamily;
  CanvasText copyWith(
          {String? id,
          String? text,
          Rect? rect,
          int? colorValue,
          double? fontSize, double? rotation, TextAlign? alignment, String? fontFamily}) =>
      CanvasText(
          id: id ?? this.id,
          text: text ?? this.text,
          rect: rect ?? this.rect,
          colorValue: colorValue ?? this.colorValue,
          fontSize: fontSize ?? this.fontSize, rotation: rotation ?? this.rotation,
          alignment: alignment ?? this.alignment, fontFamily: fontFamily ?? this.fontFamily);
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
        'color': colorValue,
        'fontSize': fontSize, 'rotation': rotation, 'alignment': alignment.name,
        'fontFamily': fontFamily
      };
  factory CanvasText.fromJson(Map<String, dynamic> j) => CanvasText(
      id: j['id'] as String,
      text: j['text'] as String,
      rect: Rect.fromLTWH(
          (j['x'] as num).toDouble(),
          (j['y'] as num).toDouble(),
          (j['width'] as num).toDouble(),
          (j['height'] as num).toDouble()),
      colorValue: (j['color'] as num? ?? 0xff111827).toInt(),
      fontSize: (j['fontSize'] as num? ?? 18).toDouble(), rotation: (j['rotation'] as num? ?? 0).toDouble(),
      alignment: switch (j['alignment']) { 'center' => TextAlign.center, 'right' => TextAlign.right, 'justify' => TextAlign.justify, _ => TextAlign.left },
      fontFamily: j['fontFamily'] as String?);
}

class DocumentSummary {
  const DocumentSummary(
      {required this.id,
      required this.title,
      required this.updatedAt,
      this.isFavorite = false,
      this.isLocked = false,
      this.isDeleted = false,
      this.coverPath});
  final String id;
  final String title;
  final DateTime updatedAt;
  final bool isFavorite;
  final bool isLocked;
  final bool isDeleted;
  final String? coverPath;
  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'favorite': isFavorite,
        'locked': isLocked,
        'deleted': isDeleted,
        'coverPath': coverPath,
      };
  factory DocumentSummary.fromJson(Map<String, dynamic> j) => DocumentSummary(
      id: j['id'] as String,
      title: j['title'] as String,
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      isFavorite: j['favorite'] as bool? ?? false,
      isLocked: j['locked'] as bool? ?? false,
      isDeleted: j['deleted'] as bool? ?? false,
      coverPath: j['coverPath'] as String?);
}

class DocumentModel {
  DocumentModel(
      {required this.id,
      required this.title,
      required this.createdAt,
      required this.updatedAt,
      this.viewport = const Viewport(),
      List<Stroke> strokes = const [],
      List<CanvasImage> images = const [],
      List<CanvasText> texts = const [],
      this.background = CanvasBackground.blank,
      this.isFavorite = false,
      this.isLocked = false,
      this.isDeleted = false,
      this.coverPath})
      : strokes = List.unmodifiable(strokes),
        images = List.unmodifiable(images),
        texts = List.unmodifiable(texts);
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Viewport viewport;
  final List<Stroke> strokes;
  final List<CanvasImage> images;
  final List<CanvasText> texts;
  final CanvasBackground background;
  final bool isFavorite;
  final bool isLocked;
  final bool isDeleted;
  final String? coverPath;
  DocumentModel copyWith(
          {String? title,
          DateTime? updatedAt,
          Viewport? viewport,
          List<Stroke>? strokes,
          List<CanvasImage>? images,
          List<CanvasText>? texts,
          CanvasBackground? background,
          bool? isFavorite,
          bool? isLocked,
          bool? isDeleted,
          String? coverPath,
          bool clearCover = false}) =>
      DocumentModel(
          id: id,
          title: title ?? this.title,
          createdAt: createdAt,
          updatedAt: updatedAt ?? this.updatedAt,
          viewport: viewport ?? this.viewport,
          strokes: strokes ?? this.strokes,
          images: images ?? this.images,
          texts: texts ?? this.texts,
          background: background ?? this.background,
          isFavorite: isFavorite ?? this.isFavorite,
          isLocked: isLocked ?? this.isLocked,
          isDeleted: isDeleted ?? this.isDeleted,
          coverPath: clearCover ? null : coverPath ?? this.coverPath);
  DocumentSummary get summary =>
      DocumentSummary(
          id: id,
          title: title,
          updatedAt: updatedAt,
          isFavorite: isFavorite,
          isLocked: isLocked,
          isDeleted: isDeleted,
          coverPath: coverPath);
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'viewport': viewport.toJson(),
        'background': background.name,
        'favorite': isFavorite,
        'locked': isLocked,
        'deleted': isDeleted,
        'coverPath': coverPath,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'images': images.map((i) => i.toJson()).toList(),
        'texts': texts.map((t) => t.toJson()).toList()
      };
  factory DocumentModel.fromJson(Map<String, dynamic> j) => DocumentModel(
      id: j['id'] as String,
      title: j['title'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      viewport: Viewport.fromJson(j['viewport'] as Map<String, dynamic>?),
      background: switch (j['background']) {
        'grid' => CanvasBackground.grid,
        'warm' => CanvasBackground.warm,
        _ => CanvasBackground.blank,
      },
      isFavorite: j['favorite'] as bool? ?? false,
      isLocked: j['locked'] as bool? ?? false,
      isDeleted: j['deleted'] as bool? ?? false,
      coverPath: j['coverPath'] as String?,
      strokes: (j['strokes'] as List<dynamic>? ?? const [])
          .map((e) => Stroke.fromJson(e as Map<String, dynamic>))
          .toList(),
      images: (j['images'] as List<dynamic>? ?? const [])
          .map((e) => CanvasImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      texts: (j['texts'] as List<dynamic>? ?? const [])
          .map((e) => CanvasText.fromJson(e as Map<String, dynamic>))
          .toList());
}
