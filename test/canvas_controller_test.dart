import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_paper/controllers/canvas_controller.dart';
import 'package:infinite_paper/models/canvas_models.dart';
import 'package:infinite_paper/services/document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CanvasController controller;
  late MemoryDocumentRepository repository;

  setUp(() async {
    repository = MemoryDocumentRepository();
    controller = CanvasController(repository: repository);
    await controller.open();
  });

  Stroke sampleStroke(String id) => Stroke.pen(
        id: id,
        colorValue: 0xff000000,
        width: 2,
        points: const [
          StrokePoint(x: 0, y: 0, pressure: 1, time: 0),
          StrokePoint(x: 10, y: 0, pressure: 1, time: 1),
        ],
      );

  test('undo and redo restore a group of erased strokes', () {
    controller.addCompletedStroke(sampleStroke('a'));
    controller.addCompletedStroke(sampleStroke('b'));
    controller.eraseAt(const Offset(5, 0));
    expect(controller.visibleStrokes, isEmpty);
    controller.undo();
    expect(controller.visibleStrokes, hasLength(2));
    controller.redo();
    expect(controller.visibleStrokes, isEmpty);
  });

  test('cancelling active stroke never adds a partial stroke', () {
    controller.beginStroke(const Offset(0, 0), pressure: 1);
    controller.appendPoint(const Offset(4, 0), pressure: 1);
    controller.cancelActiveStroke();
    controller.endStroke();
    expect(controller.visibleStrokes, isEmpty);
  });

  test('new edit drops redo history', () {
    controller.addCompletedStroke(sampleStroke('a'));
    controller.undo();
    controller.addCompletedStroke(sampleStroke('b'));
    expect(controller.canRedo, isFalse);
  });

  test('creating a document flushes edits in the previous document', () async {
    final originalId = controller.document.id;
    controller.addCompletedStroke(sampleStroke('saved-before-switch'));

    await controller.createDocument();

    final restored = await repository.loadDocument(originalId);
    expect(restored?.strokes, hasLength(1));
  });
}
