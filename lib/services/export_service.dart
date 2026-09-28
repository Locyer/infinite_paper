import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/canvas_models.dart';

class ExportResult {
  const ExportResult._({this.success = false, this.message = ''});
  const ExportResult.success() : this._(success: true, message: '已保存到相册');
  const ExportResult.failure(String message) : this._(message: message);

  final bool success;
  final String message;
}

class ExportService {
  Future<ExportResult> exportDocument(DocumentModel document) async {
    final strokes =
        document.strokes.where((stroke) => !stroke.isErased).toList();
    if (strokes.isEmpty && document.images.isEmpty && document.texts.isEmpty) {
      return const ExportResult.failure('画布为空，暂无内容可导出');
    }

    try {
      final bounds = _contentBounds(document, strokes).inflate(32);
      final longest =
          bounds.width > bounds.height ? bounds.width : bounds.height;
      final scale = (4096 / longest).clamp(0.000001, 2.0).toDouble();
      final width = (bounds.width * scale).ceil().clamp(1, 4096).toInt();
      final height = (bounds.height * scale).ceil().clamp(1, 4096).toInt();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      _paintBackground(canvas, ui.Size(width.toDouble(), height.toDouble()),
          document.background);
      canvas.scale(scale);
      canvas.translate(-bounds.left, -bounds.top);
      for (final stroke in strokes) {
        _paintStroke(canvas, stroke);
      }
      for (final item in document.images) {
        final decoded = await _loadImage(item.path);
        if (decoded != null) {
          canvas.drawImageRect(decoded, ui.Rect.fromLTWH(0, 0, decoded.width.toDouble(), decoded.height.toDouble()), item.rect, ui.Paint());
          decoded.dispose();
        }
      }
      for (final item in document.texts) {
        final painter = TextPainter(text: TextSpan(text: item.text, style: TextStyle(color: ui.Color(item.colorValue), fontSize: item.fontSize, height: 1.2)), textDirection: ui.TextDirection.ltr, maxLines: 6, ellipsis: '…')..layout(maxWidth: item.rect.width);
        painter.paint(canvas, item.rect.topLeft);
      }
      final image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return const ExportResult.failure('PNG 编码失败');
      final temporary = File(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
        'infinite_paper_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      final result = await ImageGallerySaverPlus.saveFile(temporary.path);
      if (await temporary.exists()) await temporary.delete();
      if (result is Map && result['isSuccess'] == true) {
        return const ExportResult.success();
      }
      return const ExportResult.failure('相册保存失败');
    } catch (_) {
      return const ExportResult.failure('导出失败，请稍后重试');
    }
  }

  ui.Rect _contentBounds(DocumentModel document, List<Stroke> strokes) {
    ui.Rect? bounds;
    for (final stroke in strokes.skip(1)) {
      bounds = (bounds ?? stroke.bounds).expandToInclude(stroke.bounds);
    }
    if (strokes.isNotEmpty) bounds = (bounds ?? strokes.first.bounds).expandToInclude(strokes.first.bounds);
    for (final item in document.images) { bounds = (bounds ?? item.rect).expandToInclude(item.rect); }
    for (final item in document.texts) { bounds = (bounds ?? item.rect).expandToInclude(item.rect); }
    final value = bounds!;
    return ui.Rect.fromLTRB(
      value.left, value.top,
      value.right == value.left ? value.right + 1 : value.right,
      value.bottom == value.top ? value.bottom + 1 : value.bottom,
    );
  }

  void _paintBackground(
      ui.Canvas canvas, ui.Size size, CanvasBackground background) {
    canvas.drawRect(
        ui.Offset.zero & size, ui.Paint()..color = const ui.Color(0xffffffff));
    if (background != CanvasBackground.grid) return;
    final paint = ui.Paint()
      ..color = const ui.Color(0xffe5e7eb)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 24) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += 24) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y), paint);
    }
  }

  void _paintStroke(ui.Canvas canvas, Stroke stroke) {
    final paint = ui.Paint()
      ..color = stroke.tool == CanvasTool.highlighter ? stroke.color.withValues(alpha: .3) : stroke.color
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..isAntiAlias = true
      ..strokeWidth = stroke.width;
    if (stroke.tool == CanvasTool.highlighter) paint.blendMode = ui.BlendMode.multiply;
    canvas.drawPath(stroke.path, paint);
  }

  Future<ui.Image?> _loadImage(String path) async {
    try { final codec = await ui.instantiateImageCodec(await File(path).readAsBytes()); return (await codec.getNextFrame()).image; } catch (_) { return null; }
  }
}
