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

  test('laser has an active stroke before the pen leaves the screen', () {
    controller.setTool(CanvasTool.laser);
    controller.beginStroke(const Offset(1, 2), pressure: 1);
    controller.appendPoint(const Offset(4, 2), pressure: 1);
    expect(controller.activeStroke, isNotNull);
    expect(controller.activeStroke?.tool, CanvasTool.laser);
  });

  test('each ink tool keeps its own color', () {
    controller.setTool(CanvasTool.pen);
    controller.setColor(0xff111111);
    controller.setTool(CanvasTool.highlighter);
    controller.setColor(0xff222222);
    controller.setTool(CanvasTool.pen);
    expect(controller.colorValue, 0xff111111);
  });

  test('select tool can hit an inserted text object and move it', () {
    controller.insertText('可移动文本', const Offset(40, 60));
    final original = controller.document.texts.single;

    expect(controller.selectAt(const Offset(60, 75)), isTrue);
    expect(controller.selection, contains('t:${original.id}'));

    controller.moveSelection(const Offset(25, -10));
    expect(controller.document.texts.single.rect.topLeft,
        const Offset(65, 50));
  });

  test('clipboard pastes selected text at the requested world position', () {
    controller.insertText('可复制文本', const Offset(20, 30));
    controller.selectAt(const Offset(30, 40));
    controller.copySelection();

    controller.pasteAt(const Offset(200, 300));

    expect(controller.document.texts, hasLength(2));
    expect(controller.document.texts.last.rect.topLeft,
        const Offset(200, 300));
  });
}
