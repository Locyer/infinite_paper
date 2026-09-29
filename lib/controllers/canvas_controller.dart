import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/canvas_models.dart';
import '../services/document_repository.dart';

/// 文档、工具、历史记录均集中在此处；内容历史最多保留 100 次。
class CanvasController extends ChangeNotifier with WidgetsBindingObserver {
  CanvasController({required DocumentRepository repository, Uuid? uuid})
      : _repository = repository,
        _uuid = uuid ?? const Uuid() {
    WidgetsBinding.instance.addObserver(this);
  }
  final DocumentRepository _repository;
  final Uuid _uuid;
  final ValueNotifier<int> completedRepaint = ValueNotifier(0),
      activeRepaint = ValueNotifier(0);
  final List<_Snapshot> _undoStack = [], _redoStack = [];
  Timer? _saveTimer, _laserTimer;
  late DocumentModel _document;
  List<DocumentSummary> _summaries = [];
  List<StrokePoint>? _activePoints;
  List<Offset>? _lassoPoints;
  List<Stroke>? _partialBefore;
  List<Stroke> _laserStrokes = [];
  List<_ClipboardObject> _clipboard = [];
  Set<String> _selection = {};
  CanvasTool _tool = CanvasTool.pen;
  AppThemeMode _themeMode = AppThemeMode.system;
  CanvasInputMode _inputMode = CanvasInputMode.penAndTouch;
  int _penColorValue = 0xff111827;
  int _highlighterColorValue = 0xffffeb3b;
  int _laserColorValue = 0xffff1744;
  double _penWidth = 3,
      _highlighterWidth = 16,
      _strokeEraserWidth = 20,
      _partialEraserWidth = 20,
      _laserWidth = 5;
  bool _zoomLocked = false, _ready = false;
  String? _saveError;
  bool get isReady => _ready;
  DocumentModel get document => _document;
  List<DocumentSummary> get summaries => List.unmodifiable(_summaries);
  CanvasTool get tool => _tool;
  AppThemeMode get themeMode => _themeMode;
  CanvasInputMode get inputMode => _inputMode;
  int get colorValue => switch (_tool) {
        CanvasTool.highlighter => _highlighterColorValue,
        CanvasTool.laser => _laserColorValue,
        _ => _penColorValue,
      };
  double get penWidth => _penWidth;
  double get highlighterWidth => _highlighterWidth;
  double get strokeEraserWidth => _strokeEraserWidth;
  double get partialEraserWidth => _partialEraserWidth;
  double get laserWidth => _laserWidth;
  bool get zoomLocked => _zoomLocked;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get saveError => _saveError;
  Set<String> get selection => Set.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;
  List<Stroke> get visibleStrokes =>
      _document.strokes.where((s) => !s.isErased).toList(growable: false);
  List<Offset>? get lassoPoints => _lassoPoints;
  List<Stroke> get laserStrokes => _laserStrokes;
  Stroke? get activeStroke {
    final p = _activePoints;
    if (p == null || p.isEmpty) return null;
    return Stroke.pen(
        id: 'active',
        points: p,
        colorValue: colorValue,
        width: _activeWidth,
        tool: _tool);
  }

  double get _activeWidth => switch (_tool) {
        CanvasTool.highlighter => _highlighterWidth,
        CanvasTool.laser => _laserWidth,
        _ => _penWidth
      };

  Future<void> open() async {
    _summaries = await _repository.loadIndex();
    for (final s in _summaries) {
      final loaded = await _repository.loadDocument(s.id);
      if (loaded != null) {
        _document = loaded;
        _ready = true;
        notifyListeners();
        return;
      }
    }
    await createDocument();
    _ready = true;
    notifyListeners();
  }

  Future<bool> switchDocument(String id) async {
    await flushSave();
    final loaded = await _repository.loadDocument(id);
    if (loaded == null) return false;
    _document = loaded;
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    _touchCompleted();
    notifyListeners();
    return true;
  }

  Future<void> createDocument({String? title}) async {
    if (_ready) await flushSave();
    final now = DateTime.now();
    _document = DocumentModel(
        id: _uuid.v4(),
        title: title ?? '草稿 ${_summaries.length + 1}',
        createdAt: now,
        updatedAt: now);
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    await _saveNow();
    _touchCompleted();
    notifyListeners();
  }

  Future<void> duplicateDocument() async {
    if (_ready) await flushSave();
    final now = DateTime.now();
    _document = DocumentModel(
        id: _uuid.v4(),
        title: '${_document.title} 副本',
        createdAt: now,
        updatedAt: now,
        viewport: _document.viewport,
        strokes:
            _document.strokes.map((s) => s.copyWith(id: _uuid.v4())).toList(),
        images:
            _document.images.map((i) => i.copyWith(id: _uuid.v4())).toList(),
        texts: _document.texts.map((t) => t.copyWith(id: _uuid.v4())).toList(),
        background: _document.background);
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    await _saveNow();
    _touchCompleted();
    notifyListeners();
  }

  Future<void> renameDocument(String title) async {
    if (title.trim().isEmpty) return;
    _document =
        _document.copyWith(title: title.trim(), updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> removeCurrentDocument() async {
    final id = _document.id;
    await _repository.deleteDocument(id);
    _summaries.removeWhere((s) => s.id == id);
    _ready = false;
    await open();
  }

  void setTool(CanvasTool value) {
    cancelActiveStroke();
    _tool = value;
    _selection = value == CanvasTool.lasso ? _selection : {};
    notifyListeners();
  }

  void setColor(int value) {
    switch (_tool) {
      case CanvasTool.highlighter: _highlighterColorValue = value;
      case CanvasTool.laser: _laserColorValue = value;
      default: _penColorValue = value;
    }
    notifyListeners();
  }

  void setPenWidth(double v) {
    _penWidth = v.clamp(1, 80).toDouble();
    notifyListeners();
  }

  void setHighlighterWidth(double v) {
    _highlighterWidth = v.clamp(4, 100).toDouble();
    notifyListeners();
  }

  void setStrokeEraserWidth(double v) {
    _strokeEraserWidth = v.clamp(4, 120).toDouble();
    notifyListeners();
  }

  void setPartialEraserWidth(double v) {
    _partialEraserWidth = v.clamp(2, 120).toDouble();
    notifyListeners();
  }

  void setLaserWidth(double v) {
    _laserWidth = v.clamp(1, 50).toDouble();
    notifyListeners();
  }

  void setInputMode(CanvasInputMode value) {
    _inputMode = value;
    notifyListeners();
  }

  void setZoomLocked(bool value) {
    _zoomLocked = value;
    notifyListeners();
  }

  void setThemeMode(AppThemeMode value) {
    _themeMode = value;
    notifyListeners();
  }

  void setBackground(CanvasBackground value) {
    _mutate((d) => d.copyWith(background: value));
  }

  void beginStroke(Offset point, {required double pressure}) {
    if (!{CanvasTool.pen, CanvasTool.highlighter, CanvasTool.laser}
        .contains(_tool)) return;
    _activePoints = [_pointFrom(point, pressure)];
    _touchActive();
  }

  void appendPoint(Offset point, {required double pressure}) {
    final points = _activePoints;
    if (points == null) return;
    final candidate = _pointFrom(point, pressure);
    if ((candidate.offset - points.last.offset).distance < .25) return;
    points.add(candidate);
    _touchActive();
  }

  void endStroke() {
    final points = _activePoints;
    _activePoints = null;
    _touchActive();
    if (points == null || points.isEmpty) return;
    if (_tool == CanvasTool.laser) {
      _laserStrokes = [
        ..._laserStrokes,
        Stroke.pen(
            id: _uuid.v4(),
            points: points,
            colorValue: colorValue,
            width: _laserWidth)
      ];
      _touchCompleted();
      _laserTimer?.cancel();
      _laserTimer = Timer(const Duration(seconds: 3), () {
        _laserStrokes = [];
        _touchCompleted();
      });
      return;
    }
    addCompletedStroke(Stroke.pen(
        id: _uuid.v4(),
        points: points,
        colorValue: colorValue,
        width: _activeWidth,
        tool: _tool));
  }

  void cancelActiveStroke() {
    _activePoints = null;
    _lassoPoints = null;
    _partialBefore = null;
    _touchActive();
  }

  void addCompletedStroke(Stroke stroke) =>
      _mutate((d) => d.copyWith(strokes: [...d.strokes, stroke]));
  void eraseAt(Offset point) {
    final ids = _document.strokes
        .where((s) => !s.isErased && s.hitTest(point, _strokeEraserWidth / 2))
        .map((s) => s.id)
        .toSet();
    if (ids.isEmpty) return;
    _mutate((d) => d.copyWith(
        strokes: d.strokes
            .map((s) => ids.contains(s.id) ? s.copyWith(isErased: true) : s)
            .toList()));
  }

  void beginPartialErase() {
    _partialBefore = _document.strokes;
  }

  void partialEraseAt(Offset point) {
    final r = _partialEraserWidth / 2;
    final next = <Stroke>[];
    for (final s in _document.strokes) {
      if (s.isErased || !s.bounds.inflate(s.width / 2 + r).contains(point)) {
        next.add(s);
      } else {
        next.addAll(_cutStroke(s, point, r));
      }
    }
    _document = _document.copyWith(strokes: next, updatedAt: DateTime.now());
    _touchCompleted();
  }

  void endPartialErase() {
    final before = _partialBefore;
    _partialBefore = null;
    if (before == null) return;
    final after = _document.strokes;
    if (!_sameStrokeIds(before, after))
      _record(before: _document.copyWith(strokes: before), after: _document);
    else
      _document = _document.copyWith(strokes: before);
    _afterMutation();
  }

  List<Stroke> _cutStroke(Stroke s, Offset eraser, double radius) {
    if (s.points.length < 2)
      return (s.points.isNotEmpty &&
              (s.points.first.offset - eraser).distance <= radius + s.width / 2)
          ? []
          : [s];
    final parts = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    for (final p in s.points) {
      if ((p.offset - eraser).distance > radius + s.width / 2) {
        current.add(p);
      } else if (current.isNotEmpty) {
        if (current.length >= 2) parts.add(current);
        current = [];
      }
    }
    if (current.length >= 2) parts.add(current);
    return parts
        .asMap()
        .entries
        .map((e) =>
            s.copyWith(id: e.key == 0 ? s.id : _uuid.v4(), points: e.value))
        .toList();
  }

  bool _sameStrokeIds(List<Stroke> a, List<Stroke> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) =>
          a[i].id == b[i].id && a[i].points.length == b[i].points.length);

  void beginLasso(Offset p) {
    _lassoPoints = [p];
    _touchActive();
  }

  void appendLasso(Offset p) {
    final a = _lassoPoints;
    if (a == null || (a.last - p).distance < 2) return;
    a.add(p);
    _touchActive();
  }

  void endLasso() {
    final polygon = _lassoPoints;
    _lassoPoints = null;
    if (polygon == null || polygon.length < 3) {
      _touchActive();
      return;
    }
    final selected = <String>{};
    for (final s in visibleStrokes) {
      if (s.points.any((p) => _inside(p.offset, polygon)))
        selected.add('s:${s.id}');
    }
    for (final i in _document.images) {
      if (_inside(i.rect.center, polygon) ||
          i.rect.corners.any((p) => _inside(p, polygon)))
        selected.add('i:${i.id}');
    }
    for (final t in _document.texts) {
      if (_inside(t.rect.center, polygon) ||
          t.rect.corners.any((p) => _inside(p, polygon)))
        selected.add('t:${t.id}');
    }
    _selection = selected;
    _touchActive();
    notifyListeners();
  }

  bool _inside(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if (((a.dy > p.dy) != (b.dy > p.dy)) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)
        inside = !inside;
    }
    return inside;
  }

  void clearSelection() {
    _selection = {};
    _touchCompleted();
    notifyListeners();
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    final ids = _selection;
    _mutate((d) => d.copyWith(
        strokes: d.strokes
            .map((s) =>
                ids.contains('s:${s.id}') ? s.copyWith(isErased: true) : s)
            .toList(),
        images: d.images.where((i) => !ids.contains('i:${i.id}')).toList(),
        texts: d.texts.where((t) => !ids.contains('t:${t.id}')).toList()));
    _selection = {};
  }

  void copySelection({bool cut = false}) {
    _clipboard = _selectedObjects();
    if (cut) deleteSelection();
  }

  void pasteSelection() {
    if (_clipboard.isEmpty) return;
    final addS = <Stroke>[], addI = <CanvasImage>[], addT = <CanvasText>[];
    for (final o in _clipboard) {
      switch (o) {
        case _ClipStroke(:final value):
          addS.add(value.copyWith(
              id: _uuid.v4(),
              points: value.points
                  .map((p) => StrokePoint(
                      x: p.x + 24,
                      y: p.y + 24,
                      pressure: p.pressure,
                      time: p.time))
                  .toList()));
        case _ClipImage(:final value):
          addI.add(value.copyWith(
              id: _uuid.v4(), rect: value.rect.shift(const Offset(24, 24))));
        case _ClipText(:final value):
          addT.add(value.copyWith(
              id: _uuid.v4(), rect: value.rect.shift(const Offset(24, 24))));
      }
    }
    _mutate((d) => d.copyWith(
        strokes: [...d.strokes, ...addS],
        images: [...d.images, ...addI],
        texts: [...d.texts, ...addT]));
    _selection = {
      ...addS.map((x) => 's:${x.id}'),
      ...addI.map((x) => 'i:${x.id}'),
      ...addT.map((x) => 't:${x.id}')
    };
  }

  List<_ClipboardObject> _selectedObjects() => [
        ..._document.strokes
            .where((s) => _selection.contains('s:${s.id}'))
            .map(_ClipStroke.new),
        ..._document.images
            .where((i) => _selection.contains('i:${i.id}'))
            .map(_ClipImage.new),
        ..._document.texts
            .where((t) => _selection.contains('t:${t.id}'))
            .map(_ClipText.new)
      ];
  void scaleSelection(double factor) {
    if (_selection.isEmpty) return;
    final b = selectionBounds;
    if (b == null) return;
    final c = b.center;
    Offset point(Offset p) => c + (p - c) * factor;
    Rect rect(Rect r) =>
        Rect.fromPoints(point(r.topLeft), point(r.bottomRight));
    _mutate((d) => d.copyWith(
        strokes: d.strokes
            .map((s) => _selection.contains('s:${s.id}')
                ? s.copyWith(
                    points: s.points
                        .map((p) => StrokePoint(
                            x: point(p.offset).dx,
                            y: point(p.offset).dy,
                            pressure: p.pressure,
                            time: p.time))
                        .toList(),
                    width: s.width * factor)
                : s)
            .toList(),
        images: d.images
            .map((i) => _selection.contains('i:${i.id}')
                ? i.copyWith(rect: rect(i.rect))
                : i)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(rect: rect(t.rect), fontSize: t.fontSize * factor)
                : t)
            .toList()));
  }

  void colorSelection(int color) {
    if (_selection.isEmpty) return;
    _mutate((d) => d.copyWith(
        strokes: d.strokes
            .map((s) => _selection.contains('s:${s.id}')
                ? s.copyWith(colorValue: color)
                : s)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(colorValue: color)
                : t)
            .toList()));
  }

  Rect? get selectionBounds {
    Rect? result;
    for (final s
        in _document.strokes.where((s) => _selection.contains('s:${s.id}'))) {
      result = result == null
          ? s.bounds.inflate(s.width / 2)
          : result.expandToInclude(s.bounds.inflate(s.width / 2));
    }
    for (final i
        in _document.images.where((i) => _selection.contains('i:${i.id}'))) {
      result = result == null ? i.rect : result.expandToInclude(i.rect);
    }
    for (final t
        in _document.texts.where((t) => _selection.contains('t:${t.id}'))) {
      result = result == null ? t.rect : result.expandToInclude(t.rect);
    }
    return result;
  }

  Future<void> insertImage(File source, Offset world) async {
    final dir = await getApplicationDocumentsDirectory();
    final assets =
        Directory('${dir.path}${Platform.pathSeparator}canvas_assets');
    if (!await assets.exists()) await assets.create(recursive: true);
    final ext = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.'))
        : '.jpg';
    final target =
        File('${assets.path}${Platform.pathSeparator}${_uuid.v4()}$ext');
    await source.copy(target.path);
    final image = CanvasImage(
        id: _uuid.v4(),
        path: target.path,
        rect: Rect.fromLTWH(world.dx, world.dy, 240, 180));
    _mutate((d) => d.copyWith(images: [...d.images, image]));
  }

  void insertText(String text, Offset world) {
    if (text.trim().isEmpty) return;
    final item = CanvasText(
        id: _uuid.v4(),
        text: text.trim(),
        rect: Rect.fromLTWH(world.dx, world.dy, 220, 80),
        colorValue: colorValue,
        fontSize: 18);
    _mutate((d) => d.copyWith(texts: [...d.texts, item]));
  }

  void clearDocument() {
    _mutate((d) => d.copyWith(
        strokes: d.strokes.map((s) => s.copyWith(isErased: true)).toList(),
        images: const [],
        texts: const []));
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final x = _undoStack.removeLast();
    _redoStack.add(_Snapshot(_document));
    _document = x.document;
    _afterMutation();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final x = _redoStack.removeLast();
    _undoStack.add(_Snapshot(_document));
    _document = x.document;
    _afterMutation();
  }

  void updateViewportForScale(Offset focal, double delta) {
    if (_zoomLocked) return;
    _document = _document.copyWith(
        viewport: _document.viewport.zoomAround(focal, delta),
        updatedAt: DateTime.now());
    _touchCompleted();
    _touchActive();
    notifyListeners();
    scheduleSave();
  }

  void panViewport(Offset delta) {
    _document = _document.copyWith(
        viewport: _document.viewport.pan(delta), updatedAt: DateTime.now());
    _touchCompleted();
    _touchActive();
    notifyListeners();
    scheduleSave();
  }

  void _mutate(DocumentModel Function(DocumentModel) transform) {
    final before = _document;
    _document = transform(_document).copyWith(updatedAt: DateTime.now());
    _record(before: before, after: _document);
    _afterMutation();
  }

  void _record({required DocumentModel before, required DocumentModel after}) {
    _undoStack.add(_Snapshot(before));
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _afterMutation() {
    _touchCompleted();
    notifyListeners();
    scheduleSave();
  }

  StrokePoint _pointFrom(Offset p, double pressure) => StrokePoint(
      x: p.dx,
      y: p.dy,
      pressure: pressure.clamp(.1, 2).toDouble(),
      time: DateTime.now().millisecondsSinceEpoch);
  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500),
        () => unawaited(_saveNow().catchError((_) {})));
  }

  Future<void> flushSave() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  Future<void> _saveNow() async {
    try {
      await _repository.saveDocument(_document);
      _summaries = await _repository.loadIndex();
      _saveError = null;
    } catch (_) {
      _saveError = '自动保存失败，编辑仍保留在当前页面';
      notifyListeners();
      rethrow;
    }
  }

  void _touchCompleted() => completedRepaint.value++;
  void _touchActive() => activeRepaint.value++;
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_ready &&
        {
          AppLifecycleState.inactive,
          AppLifecycleState.paused,
          AppLifecycleState.detached
        }.contains(s)) unawaited(flushSave().catchError((_) {}));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _laserTimer?.cancel();
    if (_ready) unawaited(_saveNow());
    WidgetsBinding.instance.removeObserver(this);
    completedRepaint.dispose();
    activeRepaint.dispose();
    super.dispose();
  }
}

class _Snapshot {
  const _Snapshot(this.document);
  final DocumentModel document;
}

sealed class _ClipboardObject {
  const _ClipboardObject();
}

class _ClipStroke extends _ClipboardObject {
  const _ClipStroke(this.value);
  final Stroke value;
}

class _ClipImage extends _ClipboardObject {
  const _ClipImage(this.value);
  final CanvasImage value;
}

class _ClipText extends _ClipboardObject {
  const _ClipText(this.value);
  final CanvasText value;
}

extension on Rect {
  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];
}
