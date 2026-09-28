import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Viewport;

import '../controllers/canvas_controller.dart';
import '../models/canvas_models.dart';

/// 世界坐标渲染：只绘制视口内对象，绝不创建无限大的 Bitmap。
class InfiniteCanvas extends StatefulWidget {
  const InfiniteCanvas({super.key, required this.controller});
  final CanvasController controller;
  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

class _InfiniteCanvasState extends State<InfiniteCanvas> {
  final Set<int> _pointers = {};
  final Map<String, ui.Image> _images = {};
  bool _transforming = false;
  double _lastScale = 1;
  int? _panPointer;
  Offset? _lastPan;
  Offset? _eraserCursor;
  CanvasController get c => widget.controller;
  Offset world(Offset p) => c.document.viewport.screenToWorld(p);
  bool _isStylus(PointerEvent e) =>
      e.kind == ui.PointerDeviceKind.stylus ||
      e.kind == ui.PointerDeviceKind.invertedStylus;
  bool _shouldDraw(PointerEvent e) {
    if (c.tool == CanvasTool.pan) return false;
    if (c.inputMode == CanvasInputMode.fingerPan &&
        e.kind == ui.PointerDeviceKind.touch) return false;
    if (c.inputMode == CanvasInputMode.stylusOnly && !_isStylus(e))
      return false;
    return e.kind == ui.PointerDeviceKind.touch || _isStylus(e);
  }

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      _transforming = true;
      c.cancelActiveStroke();
      return;
    }
    if (!_shouldDraw(e)) {
      _panPointer = e.pointer;
      _lastPan = e.localPosition;
      return;
    }
    final p = world(e.localPosition);
    if ({CanvasTool.eraserStroke, CanvasTool.eraserPartial}.contains(c.tool)) {
      setState(() => _eraserCursor = e.localPosition);
    }
    switch (c.tool) {
      case CanvasTool.pen || CanvasTool.highlighter || CanvasTool.laser:
        c.beginStroke(p, pressure: e.pressure);
      case CanvasTool.eraserStroke:
        c.eraseAt(p);
      case CanvasTool.eraserPartial:
        c.beginPartialErase();
        c.partialEraseAt(p);
      case CanvasTool.lasso:
        c.beginLasso(p);
      case CanvasTool.pan:
        _panPointer = e.pointer;
        _lastPan = e.localPosition;
    }
  }

  void _move(PointerMoveEvent e) {
    if (_transforming || _pointers.length != 1) return;
    if (_panPointer == e.pointer) {
      final old = _lastPan;
      _lastPan = e.localPosition;
      if (old != null) c.panViewport(e.localPosition - old);
      return;
    }
    final p = world(e.localPosition);
    if ({CanvasTool.eraserStroke, CanvasTool.eraserPartial}.contains(c.tool)) {
      setState(() => _eraserCursor = e.localPosition);
    }
    switch (c.tool) {
      case CanvasTool.pen || CanvasTool.highlighter || CanvasTool.laser:
        c.appendPoint(p, pressure: e.pressure);
      case CanvasTool.eraserStroke:
        c.eraseAt(p);
      case CanvasTool.eraserPartial:
        c.partialEraseAt(p);
      case CanvasTool.lasso:
        c.appendLasso(p);
      case CanvasTool.pan:
        break;
    }
  }

  void _end(PointerEvent e) {
    final single = _pointers.length == 1 && !_transforming;
    _pointers.remove(e.pointer);
    if (_panPointer == e.pointer) {
      _panPointer = null;
      _lastPan = null;
    }
    if (single) {
      switch (c.tool) {
        case CanvasTool.pen || CanvasTool.highlighter || CanvasTool.laser:
          c.endStroke();
        case CanvasTool.eraserPartial:
          c.endPartialErase();
        case CanvasTool.lasso:
          c.endLasso();
        case CanvasTool.eraserStroke || CanvasTool.pan:
          break;
      }
    }
    if (_pointers.isEmpty) _transforming = false;
    if (_pointers.isEmpty) setState(() => _eraserCursor = null);
  }

  @override
  void didUpdateWidget(covariant InfiniteCanvas old) {
    super.didUpdateWidget(old);
    _loadImages();
  }

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  void _loadImages() {
    for (final item in c.document.images) {
      if (_images.containsKey(item.path)) continue;
      _decode(item.path);
    }
  }

  Future<void> _decode(String path) async {
    try {
      final codec =
          await ui.instantiateImageCodec(await File(path).readAsBytes());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _images[path] = frame.image);
        c.completedRepaint.value++;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _loadImages();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        c.cancelActiveStroke();
        if (_pointers.isEmpty) _transforming = false;
        if (_pointers.isEmpty) setState(() => _eraserCursor = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) {
          _lastScale = 1;
          if (_pointers.length > 1) {
            _transforming = true;
            c.cancelActiveStroke();
          }
        },
        onScaleUpdate: (d) {
          if (_pointers.length < 2) return;
          _transforming = true;
          c.panViewport(d.focalPointDelta);
          final delta = d.scale / _lastScale;
          if (delta != 1) c.updateViewportForScale(d.localFocalPoint, delta);
          _lastScale = d.scale;
        },
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
              child: ValueListenableBuilder<int>(
                  valueListenable: c.completedRepaint,
                  builder: (_, __, ___) => CustomPaint(
                      painter: _CompletedPainter(
                          document: c.document,
                          viewport: c.document.viewport,
                          images: _images,
                          dark: dark,
                          selection: c.selection,
                          laser: c.laserStrokes)))),
          RepaintBoundary(
              child: ValueListenableBuilder<int>(
                  valueListenable: c.activeRepaint,
                  builder: (_, __, ___) => CustomPaint(
                      painter: _ActivePainter(
                          stroke: c.activeStroke,
                          lasso: c.lassoPoints,
                          viewport: c.document.viewport)))),
          if (_eraserCursor != null)
            Positioned(
              left: _eraserCursor!.dx - _eraserDiameter / 2,
              top: _eraserCursor!.dy - _eraserDiameter / 2,
              child: IgnorePointer(child: Container(width: _eraserDiameter, height: _eraserDiameter,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .08), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5))),
              ),
            ),
          Positioned(
              bottom: 12,
              right: 12,
              child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                            '${(c.document.viewport.scale * 100).toStringAsFixed(c.document.viewport.scale < .1 ? 2 : 0)}%'),
                        const SizedBox(width: 4),
                        InkWell(
                            onTap: () => c.setZoomLocked(!c.zoomLocked),
                            child: Icon(
                                c.zoomLocked ? Icons.lock : Icons.lock_open,
                                size: 17))
                      ])))),
        ]),
      ),
    );
  }

  double get _eraserDiameter => (c.tool == CanvasTool.eraserPartial ? c.partialEraserWidth : c.strokeEraserWidth) * c.document.viewport.scale;

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }
}

class _CompletedPainter extends CustomPainter {
  _CompletedPainter(
      {required this.document,
      required this.viewport,
      required this.images,
      required this.dark,
      required this.selection,
      required this.laser});
  final DocumentModel document;
  final Viewport viewport;
  final Map<String, ui.Image> images;
  final bool dark;
  final Set<String> selection;
  final List<Stroke> laser;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = dark ? const Color(0xff171717) : const Color(0xfffcfcfc));
    final visible = Rect.fromLTRB(
        -viewport.offset.dx / viewport.scale,
        -viewport.offset.dy / viewport.scale,
        (size.width - viewport.offset.dx) / viewport.scale,
        (size.height - viewport.offset.dy) / viewport.scale);
    canvas.save();
    canvas.translate(viewport.offset.dx, viewport.offset.dy);
    canvas.scale(viewport.scale);
    canvas.clipRect(visible);
    if (document.background == CanvasBackground.grid) _grid(canvas, visible);
    for (final s in document.strokes) {
      if (!s.isErased && s.bounds.inflate(s.width).overlaps(visible))
        _stroke(canvas, s);
    }
    for (final i in document.images) {
      if (i.rect.overlaps(visible)) {
        final image = images[i.path];
        if (image != null)
          canvas.drawImageRect(
              image,
              Rect.fromLTWH(
                  0, 0, image.width.toDouble(), image.height.toDouble()),
              i.rect,
              Paint());
        _select(canvas, i.rect, selection.contains('i:${i.id}'));
      }
    }
    for (final t in document.texts) {
      if (t.rect.overlaps(visible)) {
        _text(canvas, t);
        _select(canvas, t.rect, selection.contains('t:${t.id}'));
      }
    }
    for (final s in laser) {
      _stroke(canvas, s, laser: true);
    }
    for (final s
        in document.strokes.where((s) => selection.contains('s:${s.id}'))) {
      _select(canvas, s.bounds.inflate(s.width / 2), true);
    }
    canvas.restore();
  }

  void _grid(Canvas canvas, Rect v) {
    var step = 24.0;
    while (step * viewport.scale < 18) step *= 5;
    while (step * viewport.scale > 120) step /= 5;
    final p = Paint()
      ..color = (dark ? const Color(0xff3b3b3b) : const Color(0xffe5e7eb))
      ..strokeWidth = 1 / viewport.scale;
    final sx = (v.left / step).floor() * step,
        sy = (v.top / step).floor() * step;
    for (var x = sx; x <= v.right; x += step)
      canvas.drawLine(Offset(x, v.top), Offset(x, v.bottom), p);
    for (var y = sy; y <= v.bottom; y += step)
      canvas.drawLine(Offset(v.left, y), Offset(v.right, y), p);
  }

  void _select(Canvas c, Rect r, bool selected) {
    if (!selected) return;
    final p = Paint()
      ..color = const Color(0xff2563eb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / viewport.scale;
    c.drawRect(r.inflate(3 / viewport.scale), p);
  }

  @override
  bool shouldRepaint(covariant _CompletedPainter old) => true;
}

class _ActivePainter extends CustomPainter {
  _ActivePainter(
      {required this.stroke, required this.lasso, required this.viewport});
  final Stroke? stroke;
  final List<Offset>? lasso;
  final Viewport viewport;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(viewport.offset.dx, viewport.offset.dy);
    canvas.scale(viewport.scale);
    if (stroke != null) _stroke(canvas, stroke!);
    final p = lasso;
    if (p != null && p.isNotEmpty) {
      final path = Path()..moveTo(p.first.dx, p.first.dy);
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff2563eb)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / viewport.scale);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ActivePainter old) => true;
}

void _stroke(Canvas canvas, Stroke s, {bool laser = false}) {
  final high = s.tool == CanvasTool.highlighter;
  final p = Paint()
    ..color = high
        ? s.color.withValues(alpha: .3)
        : (laser ? s.color.withValues(alpha: .8) : s.color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (high) p.blendMode = BlendMode.multiply;
  canvas.drawPath(s.path, p);
  if (s.points.length == 1)
    canvas.drawCircle(
        s.points.first.offset, s.width / 2, p..style = PaintingStyle.fill);
}

void _text(Canvas canvas, CanvasText t) {
  final painter = TextPainter(
      text: TextSpan(
          text: t.text,
          style: TextStyle(
              color: Color(t.colorValue), fontSize: t.fontSize, height: 1.2)),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…')
    ..layout(maxWidth: t.rect.width);
  painter.paint(canvas, t.rect.topLeft);
}
