import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_paper/models/canvas_models.dart';

void main() {
  test('viewport converts screen coordinates through scale and translation',
      () {
    const viewport = Viewport(scale: 2, offset: Offset(10, 20));
    expect(viewport.screenToWorld(const Offset(30, 50)), const Offset(10, 15));
  });

  test('zoom clamps scale and keeps focal world point stable', () {
    const viewport = Viewport();
    final zoomed = viewport.zoomAround(const Offset(100, 80), 100);
    expect(zoomed.scale, Viewport.maxScale);
    expect(zoomed.screenToWorld(const Offset(100, 80)), const Offset(100, 80));
  });

  test('stroke json round trip keeps points and bounds', () {
    final stroke = Stroke.pen(
      id: 's',
      colorValue: 0xff000000,
      width: 4,
      points: const [
        StrokePoint(x: -2, y: 3, pressure: 1, time: 0),
        StrokePoint(x: 8, y: 9, pressure: 1, time: 1),
      ],
    );
    final restored = Stroke.fromJson(stroke.toJson());
    expect(restored.bounds, const Rect.fromLTRB(-2, 3, 8, 9));
    expect(restored.points, stroke.points);
  });

  test('stroke preserves its selected pen style when saved', () {
    final stroke = Stroke.pen(
        id: 'brush',
        colorValue: 0xff123456,
        width: 6,
        penStyle: PenStyle.calligraphy,
        points: const [StrokePoint(x: 1, y: 1, pressure: 1, time: 0)]);
    expect(Stroke.fromJson(stroke.toJson()).penStyle, PenStyle.calligraphy);
  });

  test('summary persists shelf status and cover metadata', () {
    final summary = DocumentSummary(
        id: 'note', title: '收藏', updatedAt: DateTime(2026),
        isFavorite: true, isLocked: true, isDeleted: true, coverPath: '/cover.png');
    final restored = DocumentSummary.fromJson(summary.toJson());
    expect(restored.isFavorite && restored.isLocked && restored.isDeleted, isTrue);
    expect(restored.coverPath, '/cover.png');
  });

  test('summary persists real folder and lock metadata', () {
    final summary = DocumentSummary(
        id: 'note', title: '数学', updatedAt: DateTime(2026),
        folderId: 'folder-1', isFolder: false);
    expect(DocumentSummary.fromJson(summary.toJson()).folderId, 'folder-1');
    expect(DocumentSummary.fromJson(summary.toJson()).isFolder, isFalse);
  });

  test('stroke hit test finds a nearby segment but not a distant point', () {
    final stroke = Stroke.pen(
      id: 's',
      colorValue: 0xff000000,
      width: 2,
      points: const [
        StrokePoint(x: 0, y: 0, pressure: 1, time: 0),
        StrokePoint(x: 10, y: 0, pressure: 1, time: 1),
      ],
    );
    expect(stroke.hitTest(const Offset(5, 3), 2), isTrue);
    expect(stroke.hitTest(const Offset(5, 10), 2), isFalse);
  });

  test('legacy canvas objects default to zero rotation', () {
    final image = CanvasImage.fromJson(
        {'id': 'i', 'path': 'x', 'x': 0, 'y': 0, 'width': 10, 'height': 10});
    final text = CanvasText.fromJson({'id': 't', 'text': 'x', 'x': 0, 'y': 0, 'width': 10, 'height': 10});
    expect(image.rotation, 0);
    expect(text.rotation, 0);
  });
}
