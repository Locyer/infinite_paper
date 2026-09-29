import 'dart:io';
import 'dart:math' as math;
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
  int? _selectionPointer;
  Offset? _lastPan;
  Offset? _lastSelectionWorld;
  _TransformHandle? _transformHandle;
  Rect? _transformStartBounds;
  Offset? _transformStartWorld;
  double _transformStartRotation = 0;
  bool _showSelectionActions = true;
  Offset? _eraserCursor;
  CanvasController get c => widget.controller;
  Offset world(Offset p) => c.document.viewport.screenToWorld(p);
  bool _isStylus(PointerEvent e) =>
      e.kind == ui.PointerDeviceKind.stylus ||
      e.kind == ui.PointerDeviceKind.invertedStylus;
  bool _shouldDraw(PointerEvent e) {
    if ({CanvasTool.pan, CanvasTool.select}.contains(c.tool)) return false;
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
    if (c.hasTransformBox &&
        (c.tool == CanvasTool.select || c.tool == CanvasTool.lasso) &&
        _startTransform(e)) {
      return;
    }
    if (!_shouldDraw(e)) {
      if (c.tool == CanvasTool.select) {
        final p = world(e.localPosition);
        if (c.selectAt(p)) {
          setState(() => _showSelectionActions = true);
          _selectionPointer = e.pointer;
          _lastSelectionWorld = p;
          c.beginMoveSelection();
        } else {
          _panPointer = e.pointer;
          _lastPan = e.localPosition;
        }
        return;
      }
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
      case CanvasTool.select:
        break;
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
    if (_selectionPointer == e.pointer) {
      final old = _lastSelectionWorld;
      final current = world(e.localPosition);
      _lastSelectionWorld = current;
      _updateTransform(current, old);
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
      case CanvasTool.select:
        break;
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
    if (_selectionPointer == e.pointer) {
      _selectionPointer = null;
      _lastSelectionWorld = null;
      _transformHandle = null;
      _transformStartBounds = null;
      _transformStartWorld = null;
      c.endTransform();
    }
    if (single) {
      switch (c.tool) {
        case CanvasTool.pen || CanvasTool.highlighter || CanvasTool.laser:
          c.endStroke();
        case CanvasTool.eraserPartial:
          c.endPartialErase();
        case CanvasTool.lasso:
          c.endLasso();
        case CanvasTool.eraserStroke || CanvasTool.pan || CanvasTool.select:
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
    final activePaths = c.document.images.map((item) => item.path).toSet();
    final stale = _images.keys
        .where((path) => !activePaths.contains(path))
        .toList();
    for (final path in stale) {
      _images.remove(path)?.dispose();
    }
    for (final item in c.document.images) {
      if (_images.containsKey(item.path)) continue;
      _decode(item.path);
    }
  }

  Future<void> _decode(String path) async {
    try {
      // 缓存用于编辑的预览图，避免高像素照片长期占满图形内存。
      final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(), targetWidth: 2048);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (mounted && c.document.images.any((item) => item.path == path)) {
        setState(() => _images[path] = frame.image);
        c.completedRepaint.value++;
      } else {
        frame.image.dispose();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }

  _SelectionGeometry? get _selectionGeometry {
    final bounds = c.selectionBounds;
    if (bounds == null || !c.hasTransformBox) return null;
    final viewport = c.document.viewport;
    return _SelectionGeometry(
        rect: Rect.fromPoints(
            viewport.offset + bounds.topLeft * viewport.scale,
            viewport.offset + bounds.bottomRight * viewport.scale),
        rotation: c.selectionRotation);
  }

  bool _startTransform(PointerDownEvent event) {
    final geometry = _selectionGeometry;
    if (geometry == null) return false;
    final handle = geometry.hitTest(event.localPosition);
    if (handle == null) return false;
    _selectionPointer = event.pointer;
    _transformHandle = handle;
    _transformStartBounds = c.selectionBounds;
    _transformStartWorld = world(event.localPosition);
    _transformStartRotation = c.selectionRotation;
    setState(() => _showSelectionActions = false);
    _lastSelectionWorld = _transformStartWorld;
    c.beginTransform();
    return true;
  }

  void _updateTransform(Offset current, Offset? previous) {
    final handle = _transformHandle;
    final source = _transformStartBounds;
    final start = _transformStartWorld;
    if (handle == null || source == null || start == null) return;
    if (handle == _TransformHandle.move) {
      if (previous != null) c.moveSelection(current - previous);
      return;
    }
    if (handle == _TransformHandle.rotate) {
      final center = source.center;
      final startAngle = math.atan2(start.dy - center.dy, start.dx - center.dx);
      final currentAngle = math.atan2(current.dy - center.dy, current.dx - center.dx);
      c.setSelectionRotation(
          _transformStartRotation + currentAngle - startAngle);
      return;
    }
    var left = source.left;
    var top = source.top;
    var right = source.right;
    var bottom = source.bottom;
    switch (handle) {
      case _TransformHandle.topLeft:
        left = current.dx;
        top = current.dy;
      case _TransformHandle.top:
        top = current.dy;
      case _TransformHandle.topRight:
        right = current.dx;
        top = current.dy;
      case _TransformHandle.bottomRight:
        right = current.dx;
        bottom = current.dy;
      case _TransformHandle.bottom:
        bottom = current.dy;
      case _TransformHandle.bottomLeft:
        left = current.dx;
        bottom = current.dy;
      case _TransformHandle.left:
        left = current.dx;
      case _TransformHandle.move || _TransformHandle.rotate:
        break;
    }
    if ({_TransformHandle.topLeft, _TransformHandle.topRight,
          _TransformHandle.bottomRight, _TransformHandle.bottomLeft}
        .contains(handle)) {
      final ratio = source.width / source.height;
      final height = (right - left) / ratio;
      if ({_TransformHandle.topLeft, _TransformHandle.topRight}.contains(handle)) {
        top = bottom - height;
      } else {
        bottom = top + height;
      }
    }
    const minimum = 8.0;
    if (right - left < minimum) {
      if ({_TransformHandle.topLeft, _TransformHandle.bottomLeft, _TransformHandle.left}
          .contains(handle)) {
        left = right - minimum;
      } else {
        right = left + minimum;
      }
    }
    if (bottom - top < minimum) {
      if ({_TransformHandle.topLeft, _TransformHandle.top, _TransformHandle.topRight}
          .contains(handle)) {
        top = bottom - minimum;
      } else {
        bottom = top + minimum;
      }
    }
    c.resizeSelectionTo(Rect.fromLTRB(left, top, right, bottom));
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
        if (_selectionPointer == e.pointer) {
          _selectionPointer = null;
          _lastSelectionWorld = null;
          _transformHandle = null;
          _transformStartBounds = null;
          _transformStartWorld = null;
          c.endTransform();
        }
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
        onLongPressStart: (details) {
          if (!c.hasClipboard ||
              !{CanvasTool.select, CanvasTool.lasso, CanvasTool.pan}
                  .contains(c.tool)) {
            return;
          }
          _showPasteMenu(details.localPosition);
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
                          selectionPath: c.selectionPath,
                          selectionPresentation: c.selectionPresentation,
                          laser: c.laserStrokes,
                          laserOpacity: c.laserOpacity)))),
          RepaintBoundary(
              child: ValueListenableBuilder<int>(
                  valueListenable: c.activeRepaint,
                  builder: (_, __, ___) => CustomPaint(
                      painter: _ActivePainter(
                          stroke: c.activeStroke,
                          lasso: c.lassoPoints,
                          viewport: c.document.viewport)))),
          if (c.hasSelection)
            Positioned.fill(
                child: _CanvasSelectionActions(
                    key: const Key('selection-transform-overlay'),
                    controller: c,
                    showActions: _showSelectionActions,
                    geometry: _selectionGeometry ??
                        _SelectionGeometry.fromBounds(
                            c.selectionBounds!, c.document.viewport))),
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

  Future<void> _showPasteMenu(Offset localPosition) async {
    final size = context.size;
    if (size == null) return;
    final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(localPosition.dx, localPosition.dy,
            size.width - localPosition.dx, size.height - localPosition.dy),
        items: const [
          PopupMenuItem(value: 'paste', child: SizedBox(width: 54, child: Text('粘贴'))),
        ]);
    if (action == 'paste') c.pasteAt(world(localPosition));
  }

}

enum _TransformHandle {
  move,
  topLeft,
  top,
  topRight,
  rotate,
  bottomRight,
  bottom,
  bottomLeft,
  left
}

class _SelectionGeometry {
  const _SelectionGeometry({required this.rect, required this.rotation});
  final Rect rect;
  final double rotation;
  factory _SelectionGeometry.fromBounds(Rect bounds, Viewport viewport) =>
      _SelectionGeometry(
          rect: Rect.fromPoints(viewport.offset + bounds.topLeft * viewport.scale,
              viewport.offset + bounds.bottomRight * viewport.scale),
          rotation: 0);

  Offset _rotate(Offset point) {
    final v = point - rect.center;
    final cos = math.cos(rotation), sin = math.sin(rotation);
    return rect.center + Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
  }

  Offset pointFor(_TransformHandle handle) => _rotate(switch (handle) {
        _TransformHandle.topLeft => rect.topLeft,
        _TransformHandle.top => rect.topCenter,
        _TransformHandle.topRight => rect.topRight,
        _TransformHandle.rotate => rect.centerRight + const Offset(34, 0),
        _TransformHandle.bottomRight => rect.bottomRight,
        _TransformHandle.bottom => rect.bottomCenter,
        _TransformHandle.bottomLeft => rect.bottomLeft,
        _TransformHandle.left => rect.centerLeft,
        _TransformHandle.move => rect.center,
      });

  _TransformHandle? hitTest(Offset screenPoint) {
    for (final handle in _TransformHandle.values.where((h) => h != _TransformHandle.move)) {
      if ((screenPoint - pointFor(handle)).distance <= 22) return handle;
    }
    final local = _rotateBack(screenPoint);
    return rect.inflate(8).contains(local) ? _TransformHandle.move : null;
  }

  Offset _rotateBack(Offset point) {
    final v = point - rect.center;
    final cos = math.cos(-rotation), sin = math.sin(-rotation);
    return rect.center + Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
  }
}

class _CanvasSelectionActions extends StatelessWidget {
  const _CanvasSelectionActions(
      {super.key, required this.controller, required this.geometry, required this.showActions});
  final CanvasController controller;
  final _SelectionGeometry geometry;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = controller.selection.any((id) => id.startsWith('i:'));
    final isText = controller.selection.any((id) => id.startsWith('t:'));
    final showBox = controller.hasTransformBox;
    final bubbleTop = geometry.rect.top > 92
        ? geometry.rect.top - 82
        : geometry.rect.bottom + 12;
    return Stack(children: [
      IgnorePointer(
          child: CustomPaint(
              painter: _SelectionOverlayPainter(
                  geometry: geometry,
                  showBox: showBox,
                  angle: controller.selectionRotation))),
      if (showActions) Positioned(
          top: bubbleTop,
          left: math.max(8, geometry.rect.left),
          child: Material(
              color: theme.colorScheme.surface.withValues(alpha: .96),
              elevation: 5,
              borderRadius: BorderRadius.circular(22),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (controller.selectionPresentation ==
                            SelectionPresentation.lassoPath)
                          TextButton.icon(
                              onPressed: controller.enableSelectionTransform,
                              icon: const Icon(Icons.open_in_full, size: 17),
                              label: const Text('调整大小')),
                        PopupMenuButton<int>(
                            tooltip: '修改选中颜色',
                            onSelected: controller.colorSelection,
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 0xff111827, child: Text('黑色')),
                              PopupMenuItem(value: 0xffdc2626, child: Text('红色')),
                              PopupMenuItem(value: 0xff2563eb, child: Text('蓝色')),
                              PopupMenuItem(value: 0xff16a34a, child: Text('绿色')),
                            ],
                            icon: const Icon(Icons.palette_outlined, size: 19)),
                        if (isText)
                          PopupMenuButton<String>(
                              tooltip: '文字格式',
                              onSelected: (value) {
                                switch (value) {
                                  case 'left': controller.formatSelectedText(alignment: TextAlign.left);
                                  case 'center': controller.formatSelectedText(alignment: TextAlign.center);
                                  case 'right': controller.formatSelectedText(alignment: TextAlign.right);
                                  case 'small': controller.formatSelectedText(fontSize: 16);
                                  case 'large': controller.formatSelectedText(fontSize: 28);
                                  case 'serif': controller.formatSelectedText(fontFamily: 'serif');
                                  case 'sans': controller.formatSelectedText(fontFamily: 'sans-serif');
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'left', child: Text('左对齐')),
                                PopupMenuItem(value: 'center', child: Text('居中对齐')),
                                PopupMenuItem(value: 'right', child: Text('右对齐')),
                                PopupMenuItem(value: 'small', child: Text('小字号')),
                                PopupMenuItem(value: 'large', child: Text('大字号')),
                                PopupMenuItem(value: 'serif', child: Text('衬线字体')),
                                PopupMenuItem(value: 'sans', child: Text('无衬线字体')),
                              ],
                              icon: const Icon(Icons.format_size, size: 19)),
                        if (isImage)
                          PopupMenuButton<String>(
                              tooltip: '裁剪',
                              onSelected: (value) => ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      content: Text('$value 模式将在下一步选择裁剪区域'))),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: '矩形裁剪', child: Text('矩形裁剪')),
                                PopupMenuItem(value: '自由裁剪', child: Text('自由裁剪')),
                              ],
                              icon: const Icon(Icons.crop_outlined, size: 19)),
                        IconButton(
                            tooltip: '复制',
                            onPressed: controller.copySelection,
                            icon: const Icon(Icons.copy_outlined, size: 19)),
                        IconButton(
                            tooltip: '剪切',
                            onPressed: () => controller.copySelection(cut: true),
                            icon: const Icon(Icons.content_cut, size: 19)),
                        IconButton(
                            tooltip: '删除',
                            onPressed: controller.deleteSelection,
                            icon: const Icon(Icons.delete_outline, size: 19)),
                       ])))))
    ]);
  }
}

class _SelectionOverlayPainter extends CustomPainter {
  const _SelectionOverlayPainter(
      {required this.geometry, required this.showBox, required this.angle});
  final _SelectionGeometry geometry;
  final bool showBox;
  final double angle;
  @override
  void paint(Canvas canvas, Size size) {
    if (!showBox) return;
    final line = Paint()
      ..color = const Color(0xff2563eb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.translate(geometry.rect.center.dx, geometry.rect.center.dy);
    canvas.rotate(geometry.rotation);
    canvas.drawRect(geometry.rect.shift(-geometry.rect.center), line);
    canvas.restore();
    for (final handle in _TransformHandle.values.where((h) => h != _TransformHandle.move)) {
      final point = geometry.pointFor(handle);
      final fill = Paint()
        ..color = handle == _TransformHandle.rotate
            ? const Color(0xff2563eb)
            : Colors.white;
      canvas.drawCircle(point, handle == _TransformHandle.rotate ? 10 : 7, fill);
      canvas.drawCircle(point, handle == _TransformHandle.rotate ? 10 : 7, line);
      if (handle == _TransformHandle.rotate) {
        final text = TextPainter(
            text: const TextSpan(text: '↻', style: TextStyle(color: Colors.white, fontSize: 13)),
            textDirection: TextDirection.ltr)
          ..layout();
        text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
      }
    }
    final degrees = (angle * 180 / math.pi).round() % 360;
    final label = TextPainter(
        text: TextSpan(
            text: '$degrees°',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr)
      ..layout();
    final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(geometry.rect.center.dx - label.width / 2 - 6,
            geometry.rect.top - 28, label.width + 12, 22),
        const Radius.circular(11));
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xff1d4ed8));
    label.paint(canvas, labelRect.center - Offset(label.width / 2, label.height / 2));
  }
  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter old) =>
      old.geometry.rect != geometry.rect ||
      old.geometry.rotation != geometry.rotation ||
      old.showBox != showBox ||
      old.angle != angle;
}

class _CompletedPainter extends CustomPainter {
  _CompletedPainter(
      {required this.document,
      required this.viewport,
      required this.images,
      required this.dark,
      required this.selection,
      required this.selectionPath,
      required this.selectionPresentation,
      required this.laser,
      required this.laserOpacity});
  final DocumentModel document;
  final Viewport viewport;
  final Map<String, ui.Image> images;
  final bool dark;
  final Set<String> selection;
  final List<Offset>? selectionPath;
  final SelectionPresentation selectionPresentation;
  final List<Stroke> laser;
  final double laserOpacity;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = dark
              ? const Color(0xff171717)
              : document.background == CanvasBackground.warm
                  ? const Color(0xfffffbeb)
                  : const Color(0xfffcfcfc));
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
    for (final i in document.images) {
      if (i.rect.overlaps(visible)) {
        final image = images[i.path];
        if (image != null) {
          canvas.save();
          canvas.translate(i.rect.center.dx, i.rect.center.dy);
          canvas.rotate(i.rotation);
          canvas.drawImageRect(
              image,
              Rect.fromLTWH(
                  0, 0, image.width.toDouble(), image.height.toDouble()),
              i.rect.shift(-i.rect.center),
              Paint());
          canvas.restore();
        }
      }
    }
    for (final t in document.texts) {
      if (t.rect.overlaps(visible)) {
        _text(canvas, t);
      }
    }
    // 图片和文本是底图；墨迹始终在它们上面，便于批注。
    for (final s in document.strokes) {
      if (!s.isErased && s.bounds.inflate(s.width).overlaps(visible)) {
        _stroke(canvas, s);
      }
    }
    for (final s in laser) {
      _stroke(canvas, s, laser: true, opacity: laserOpacity);
    }
    if (selectionPresentation == SelectionPresentation.lassoPath &&
        selectionPath != null && selectionPath!.length > 2) {
      final path = Path()..moveTo(selectionPath!.first.dx, selectionPath!.first.dy);
      for (final point in selectionPath!.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0x222563eb));
      canvas.drawPath(
          _dashed(path, 8 / viewport.scale, 5 / viewport.scale),
          Paint()
            ..color = const Color(0xff2563eb)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / viewport.scale);
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
    if (stroke != null) _stroke(canvas, stroke!, laser: stroke!.tool == CanvasTool.laser);
    final p = lasso;
    if (p != null && p.isNotEmpty) {
      final path = Path()..moveTo(p.first.dx, p.first.dy);
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
      canvas.drawPath(
          _dashed(path, 8 / viewport.scale, 5 / viewport.scale),
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

Path _dashed(Path source, double dash, double gap) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      result.addPath(metric.extractPath(distance, (distance + dash).clamp(0, metric.length)), Offset.zero);
      distance += dash + gap;
    }
  }
  return result;
}

void _stroke(Canvas canvas, Stroke s, {bool laser = false, double opacity = 1}) {
  final high = s.tool == CanvasTool.highlighter;
  final style = s.penStyle;
  final pencil = !laser && !high && style == PenStyle.pencil;
  final brush = !laser && !high && style == PenStyle.brush;
  final calligraphy = !laser && !high && style == PenStyle.calligraphy;
  final ballpoint = !laser && !high && style == PenStyle.ballpoint;
  final p = Paint()
    ..color = high
        ? s.color.withValues(alpha: .3)
        : (laser
            ? s.color.withValues(alpha: .8 * opacity)
            : pencil
                ? s.color.withValues(alpha: .58)
                : brush
                    ? s.color.withValues(alpha: .9)
                    : s.color.withValues(alpha: ballpoint ? .96 : 1))
    ..style = PaintingStyle.stroke
    ..strokeWidth = s.width * (pencil ? .78 : brush ? 1.45 : ballpoint ? .84 : calligraphy ? 1.22 : 1)
    ..strokeCap = calligraphy ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (high) p.blendMode = BlendMode.multiply;
  canvas.drawPath(s.path, p);
  // 铅笔保留一层淡淡的石墨边缘，既轻量也让笔触与墨水笔区分明显。
  if (pencil && s.points.length > 1) {
    canvas.drawPath(s.path, p
      ..color = s.color.withValues(alpha: .13)
      ..strokeWidth = s.width * 1.25);
  }
  if (s.points.length == 1)
    canvas.drawCircle(
        s.points.first.offset, s.width / 2, p..style = PaintingStyle.fill);
}

void _text(Canvas canvas, CanvasText t) {
  final painter = TextPainter(
      text: TextSpan(
          text: t.text,
          style: TextStyle(
              color: Color(t.colorValue), fontSize: t.fontSize, height: 1.2,
              fontFamily: t.fontFamily)),
      textDirection: TextDirection.ltr,
      textAlign: t.alignment,
      maxLines: 6,
      ellipsis: '…')
    ..layout(maxWidth: t.rect.width);
  canvas.save();
  canvas.translate(t.rect.center.dx, t.rect.center.dy);
  canvas.rotate(t.rotation);
  painter.paint(canvas, t.rect.topLeft - t.rect.center);
  canvas.restore();
}
