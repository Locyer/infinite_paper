import 'dart:async';
import 'dart:math' as math;
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
  DateTime? _laserFadeStartedAt;
  late DocumentModel _document;
  List<DocumentSummary> _summaries = [];
  List<StrokePoint>? _activePoints;
  List<Offset>? _lassoPoints;
  List<Stroke>? _partialBefore;
  List<Stroke> _laserStrokes = [];
  List<_ClipboardObject> _clipboard = [];
  Set<String> _selection = {};
  List<Offset>? _selectionPath;
  SelectionPresentation _selectionPresentation = SelectionPresentation.none;
  DocumentModel? _selectionMoveBefore;
  bool _selectionMoved = false;
  double _transformRotationApplied = 0;
  CanvasTool _tool = CanvasTool.pen;
  PenStyle _penStyle = PenStyle.fountain;
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
  PenStyle get penStyle => _penStyle;
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
  SelectionPresentation get selectionPresentation => _selectionPresentation;
  List<Offset>? get selectionPath => _selectionPath == null
      ? null
      : List.unmodifiable(_selectionPath!);
  bool get hasTransformBox =>
      _selectionPresentation == SelectionPresentation.object ||
      _selectionPresentation == SelectionPresentation.transformBox;
  bool selectionPathContains(Offset point) {
    final path = _selectionPath;
    return path != null && path.length > 2 && _inside(point, path);
  }
  double get selectionRotation {
    if (_selection.length != 1) return 0;
    final id = _selection.single;
    for (final image in _document.images) {
      if (id == 'i:${image.id}') return image.rotation;
    }
    for (final text in _document.texts) {
      if (id == 't:${text.id}') return text.rotation;
    }
    return 0;
  }
  bool get hasClipboard => _clipboard.isNotEmpty;
  List<Stroke> get visibleStrokes =>
      _document.strokes.where((s) => !s.isErased).toList(growable: false);
  List<Offset>? get lassoPoints => _lassoPoints;
  List<Stroke> get laserStrokes => _laserStrokes;
  /// 最近一次激光书写会让尚未完全消失的轨迹重新完整显示并重新计时。
  double get laserOpacity {
    final started = _laserFadeStartedAt;
    if (started == null || _laserStrokes.isEmpty) return 1;
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    return (1 - elapsed / 3000).clamp(0, 1).toDouble();
  }
  Stroke? get activeStroke {
    final p = _activePoints;
    if (p == null || p.isEmpty) return null;
    return Stroke.pen(
        id: 'active',
        points: p,
        colorValue: colorValue,
        width: _activeWidth,
        tool: _tool,
        penStyle: _penStyle);
  }

  double get _activeWidth => switch (_tool) {
        CanvasTool.highlighter => _highlighterWidth,
        CanvasTool.laser => _laserWidth,
        _ => _penWidth
      };

  Future<void> open() async {
    _summaries = await _repository.loadIndex();
    for (final s in _summaries.where((summary) => !summary.isDeleted)) {
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

  Future<bool> switchDocument(String id, {String? password}) async {
    await flushSave();
    final loaded = await _repository.loadDocument(id);
    if (loaded == null) return false;
    if (loaded.isLocked && loaded.lockPassword != password) return false;
    _document = loaded;
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.none;
    _touchCompleted();
    notifyListeners();
    return true;
  }

  Future<void> createDocument({String? title, String? folderId}) async {
    if (_ready) await flushSave();
    final now = DateTime.now();
    _document = DocumentModel(
        id: _uuid.v4(),
        title: title ?? '草稿 ${_summaries.length + 1}',
        createdAt: now,
        updatedAt: now,
        folderId: folderId);
    _undoStack.clear();
    _redoStack.clear();
    _selection = {};
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.none;
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
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.none;
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

  Future<void> setFavorite(bool value) async {
    _document = _document.copyWith(
        isFavorite: value, updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> setLocked(bool value) async {
    _document = _document.copyWith(isLocked: value, updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> setLockPassword(String password) async {
    if (password.trim().length < 4) return;
    _document = _document.copyWith(
        isLocked: true,
        lockPassword: password.trim(),
        updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> clearLockPassword() async {
    _document = _document.copyWith(
        isLocked: false, clearLock: true, updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  /// 文件夹是独立的书架对象，不会切换当前正在编辑的笔记。
  Future<String> createFolder(String title) async {
    final name = title.trim();
    if (name.isEmpty) throw ArgumentError.value(title, 'title', '文件夹名称不能为空');
    final now = DateTime.now();
    final folder = DocumentModel(
        id: _uuid.v4(),
        title: name,
        createdAt: now,
        updatedAt: now,
        isFolder: true);
    await _repository.saveDocument(folder);
    _summaries = await _repository.loadIndex();
    notifyListeners();
    return folder.id;
  }

  Future<void> assignCurrentDocumentToFolder(String? folderId) async {
    if (folderId != null && !_summaries.any((s) => s.id == folderId && s.isFolder)) {
      throw ArgumentError.value(folderId, 'folderId', '目标文件夹不存在');
    }
    _document = _document.copyWith(
        folderId: folderId,
        clearFolder: folderId == null,
        updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> renameFolder(String id, String title) async {
    final folder = await _repository.loadDocument(id);
    if (folder == null || !folder.isFolder || title.trim().isEmpty) return;
    await _repository.saveDocument(
        folder.copyWith(title: title.trim(), updatedAt: DateTime.now()));
    _summaries = await _repository.loadIndex();
    notifyListeners();
  }

  /// 删除文件夹时把其中笔记移回根目录，避免把内容一起误删。
  Future<void> deleteFolder(String id) async {
    for (final summary in _summaries.where((item) => item.folderId == id)) {
      final document = await _repository.loadDocument(summary.id);
      if (document != null) {
        await _repository.saveDocument(
            document.copyWith(clearFolder: true, updatedAt: DateTime.now()));
      }
    }
    await _repository.deleteDocument(id);
    _summaries = await _repository.loadIndex();
    notifyListeners();
  }

  /// 回收站采用软删除，个人笔记可在书架中恢复。
  Future<void> moveCurrentToTrash() async {
    _document = _document.copyWith(isDeleted: true, updatedAt: DateTime.now());
    await _saveNow();
    _ready = false;
    await open();
  }

  Future<void> restoreCurrentDocument() async {
    _document = _document.copyWith(isDeleted: false, updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> setCover(File source) async {
    final path = await _copyToAssetStore(source);
    _document = _document.copyWith(coverPath: path, updatedAt: DateTime.now());
    await _saveNow();
    notifyListeners();
  }

  Future<void> removeCover() async {
    _document = _document.copyWith(clearCover: true, updatedAt: DateTime.now());
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
    // 套索和选择工具共享同一份选择结果；切回书写工具才结束选择。
    if (!{CanvasTool.lasso, CanvasTool.select}.contains(value)) {
      _selection = {};
      _selectionPath = null;
      _selectionPresentation = SelectionPresentation.none;
    }
    notifyListeners();
  }

  void setPenStyle(PenStyle value) {
    _penStyle = value;
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
            width: _laserWidth,
            tool: CanvasTool.laser)
      ];
      _touchCompleted();
      _laserTimer?.cancel();
      _laserFadeStartedAt = DateTime.now();
      _laserTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (laserOpacity <= 0) {
          timer.cancel();
          _laserStrokes = [];
          _laserFadeStartedAt = null;
        }
        _touchCompleted();
      });
      return;
    }
    addCompletedStroke(Stroke.pen(
        id: _uuid.v4(),
        points: points,
        colorValue: colorValue,
        width: _activeWidth,
        tool: _tool,
        penStyle: _penStyle));
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
    var strokeWasSplit = false;
    final nextStrokes = <Stroke>[];
    for (final stroke in _document.strokes) {
      if (stroke.isErased) {
        nextStrokes.add(stroke);
        continue;
      }
      final parts = _splitStrokeForLasso(stroke, polygon);
      strokeWasSplit = strokeWasSplit || parts.length > 1;
      for (final part in parts) {
        nextStrokes.add(part.stroke);
        if (part.inside) selected.add('s:${part.stroke.id}');
      }
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
    if (strokeWasSplit) {
      _mutate((document) => document.copyWith(strokes: nextStrokes));
    }
    _selection = selected;
    _selectionPath = List.of(polygon);
    _selectionPresentation = selected.isEmpty
        ? SelectionPresentation.none
        : SelectionPresentation.lassoPath;
    _touchActive();
    notifyListeners();
  }

  List<_LassoStrokePart> _splitStrokeForLasso(
      Stroke stroke, List<Offset> polygon) {
    if (stroke.points.isEmpty) return [_LassoStrokePart(stroke, false)];
    final runs = <({bool inside, List<StrokePoint> points})>[];
    for (final point in stroke.points) {
      final inside = _inside(point.offset, polygon);
      if (runs.isEmpty || runs.last.inside != inside) {
        runs.add((inside: inside, points: [point]));
      } else {
        runs.last.points.add(point);
      }
    }
    if (runs.length == 1) {
      return [_LassoStrokePart(stroke, runs.single.inside)];
    }
    return runs
        .map((run) => _LassoStrokePart(
            stroke.copyWith(id: _uuid.v4(), points: run.points), run.inside))
        .toList();
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
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.none;
    _touchCompleted();
    notifyListeners();
  }

  /// 从最上层开始命中对象。图片、文本可直接点选，不再必须依赖套索。
  bool selectAt(Offset point) {
    String? selected;
    for (final text in _document.texts.reversed) {
      if (text.rect.contains(point)) {
        selected = 't:${text.id}';
        break;
      }
    }
    if (selected == null) {
      for (final image in _document.images.reversed) {
        if (image.rect.contains(point)) {
          selected = 'i:${image.id}';
          break;
        }
      }
    }
    if (selected == null) {
      for (final stroke in visibleStrokes.reversed) {
        if (stroke.hitTest(point, 10)) {
          selected = 's:${stroke.id}';
          break;
        }
      }
    }
    _selection = selected == null ? {} : {selected};
    _selectionPath = null;
    _selectionPresentation = selected == null
        ? SelectionPresentation.none
        : SelectionPresentation.object;
    _touchCompleted();
    notifyListeners();
    return selected != null;
  }

  /// 在世界坐标中整体拖动已选内容，图片、文字和笔迹始终同步移动。
  void beginMoveSelection() {
    if (_selection.isEmpty) return;
    _selectionMoveBefore = _document;
    _selectionMoved = false;
  }

  void moveSelection(Offset delta) {
    if (_selection.isEmpty || delta == Offset.zero) return;
    final transform = (DocumentModel d) => d.copyWith(
        strokes: d.strokes
            .map((s) => _selection.contains('s:${s.id}')
                ? s.copyWith(
                    points: s.points
                        .map((p) => StrokePoint(
                            x: p.x + delta.dx,
                            y: p.y + delta.dy,
                            pressure: p.pressure,
                            time: p.time))
                        .toList())
                : s)
            .toList(),
        images: d.images
            .map((i) => _selection.contains('i:${i.id}')
                ? i.copyWith(rect: i.rect.shift(delta))
                : i)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(rect: t.rect.shift(delta))
                : t)
            .toList());
    _applySelectionChange(transform);
  }

  void endMoveSelection() {
    final before = _selectionMoveBefore;
    _selectionMoveBefore = null;
    if (before == null || !_selectionMoved) return;
    _record(before: before, after: _document);
    _afterMutation();
  }

  void _applySelectionChange(
      DocumentModel Function(DocumentModel) transform) {
    if (_selectionMoveBefore == null) {
      _mutate(transform);
      return;
    }
    _selectionMoved = true;
    _document = transform(_document).copyWith(updatedAt: DateTime.now());
    _touchCompleted();
    notifyListeners();
  }

  /// 将自由套索命中的内容切换成整体变换框；不改写原始套索路径。
  void enableSelectionTransform() {
    if (_selection.isEmpty) return;
    _selectionPresentation = SelectionPresentation.transformBox;
    _touchCompleted();
    notifyListeners();
  }

  void beginTransform() {
    _transformRotationApplied = 0;
    beginMoveSelection();
  }

  void endTransform() => endMoveSelection();

  /// 把选择内容映射到新外接矩形，用于八个缩放控制柄。
  void resizeSelectionTo(Rect target) {
    final source = selectionBounds;
    if (_selection.isEmpty ||
        source == null ||
        target.width < 8 ||
        target.height < 8 ||
        source.width == 0 ||
        source.height == 0) return;
    Offset mapPoint(Offset point) => Offset(
        target.left + (point.dx - source.left) / source.width * target.width,
        target.top + (point.dy - source.top) / source.height * target.height);
    Rect mapRect(Rect rect) =>
        Rect.fromPoints(mapPoint(rect.topLeft), mapPoint(rect.bottomRight));
    final widthFactor = math.sqrt(
        (target.width / source.width) * (target.height / source.height));
    _applySelectionChange((d) => d.copyWith(
        strokes: d.strokes
            .map((s) => _selection.contains('s:${s.id}')
                ? s.copyWith(
                    points: s.points
                        .map((p) => StrokePoint(
                            x: mapPoint(p.offset).dx,
                            y: mapPoint(p.offset).dy,
                            pressure: p.pressure,
                            time: p.time))
                        .toList(),
                    width: s.width * widthFactor)
                : s)
            .toList(),
        images: d.images
            .map((i) => _selection.contains('i:${i.id}')
                ? i.copyWith(rect: mapRect(i.rect))
                : i)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(
                    rect: mapRect(t.rect), fontSize: t.fontSize * widthFactor)
                : t)
            .toList()));
  }

  /// 单个图片或文本按目标角度旋转，靠近直角时自动吸附。
  void setSelectionRotation(double radians) {
    final target = _snapAngle(radians);
    if (_selection.length != 1) {
      final delta = target - _transformRotationApplied;
      _transformRotationApplied = target;
      rotateSelection(delta);
      return;
    }
    _applySelectionChange((d) => d.copyWith(
        images: d.images
            .map((i) => _selection.contains('i:${i.id}')
                ? i.copyWith(rotation: target)
                : i)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(rotation: target)
                : t)
            .toList()));
  }

  double _snapAngle(double angle) {
    final turn = math.pi * 2;
    var normalized = angle % turn;
    if (normalized < 0) normalized += turn;
    const threshold = math.pi / 45; // 4 度。
    for (var step = 0; step < 4; step++) {
      final cardinal = step * math.pi / 2;
      final distance = (normalized - cardinal).abs();
      if (distance < threshold || turn - distance < threshold) {
        return cardinal == turn ? 0 : cardinal;
      }
    }
    return normalized;
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
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.none;
  }

  void copySelection({bool cut = false}) {
    _clipboard = _selectedObjects();
    if (cut) deleteSelection();
  }

  void pasteSelection() {
    pasteAt(null);
  }

  /// 锚定粘贴用于套索/选择状态下的长按菜单；空值保持原来的错位粘贴。
  void pasteAt(Offset? anchor) {
    if (_clipboard.isEmpty) return;
    final sourceBounds = _clipboardBounds();
    final delta = anchor == null
        ? const Offset(24, 24)
        : anchor - (sourceBounds?.topLeft ?? Offset.zero);
    final addS = <Stroke>[], addI = <CanvasImage>[], addT = <CanvasText>[];
    for (final o in _clipboard) {
      switch (o) {
        case _ClipStroke(:final value):
          addS.add(value.copyWith(
              id: _uuid.v4(),
              points: value.points
                  .map((p) => StrokePoint(
                      x: p.x + delta.dx,
                      y: p.y + delta.dy,
                      pressure: p.pressure,
                      time: p.time))
                  .toList()));
        case _ClipImage(:final value):
          addI.add(value.copyWith(
              id: _uuid.v4(), rect: value.rect.shift(delta)));
        case _ClipText(:final value):
          addT.add(value.copyWith(
              id: _uuid.v4(), rect: value.rect.shift(delta)));
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
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.transformBox;
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

  Rect? _clipboardBounds() {
    Rect? result;
    for (final object in _clipboard) {
      final bounds = switch (object) {
        _ClipStroke(:final value) => value.bounds.inflate(value.width / 2),
        _ClipImage(:final value) => value.rect,
        _ClipText(:final value) => value.rect,
      };
      result = result == null ? bounds : result.expandToInclude(bounds);
    }
    return result;
  }
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

  void formatSelectedText({TextAlign? alignment, String? fontFamily, double? fontSize}) {
    if (_selection.isEmpty) return;
    _mutate((d) => d.copyWith(texts: d.texts.map((text) =>
        _selection.contains('t:${text.id}') ? text.copyWith(
            alignment: alignment, fontFamily: fontFamily,
            fontSize: fontSize?.clamp(10, 72).toDouble()) : text).toList()));
  }

  /// 旋转图片/文本；多个对象会围绕共同的选择中心旋转。
  void rotateSelection(double radians) {
    if (_selection.isEmpty) return;
    final bounds = selectionBounds;
    if (bounds == null) return;
    final center = bounds.center;
    Offset rotatedCenter(Rect rect) {
      final v = rect.center - center;
      final cos = math.cos(radians), sin = math.sin(radians);
      return center + Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
    }
    Rect movedRect(Rect rect) => rect.shift(rotatedCenter(rect) - rect.center);
    _mutate((d) => d.copyWith(
        images: d.images
            .map((i) => _selection.contains('i:${i.id}')
                ? i.copyWith(rect: movedRect(i.rect), rotation: i.rotation + radians)
                : i)
            .toList(),
        texts: d.texts
            .map((t) => _selection.contains('t:${t.id}')
                ? t.copyWith(rect: movedRect(t.rect), rotation: t.rotation + radians)
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
    final path = await _copyToAssetStore(source);
    final image = CanvasImage(
        id: _uuid.v4(),
        path: path,
        rect: Rect.fromLTWH(world.dx, world.dy, 240, 180));
    _mutate((d) => d.copyWith(images: [...d.images, image]));
    _selection = {'i:${image.id}'};
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.object;
    _tool = CanvasTool.select;
    notifyListeners();
  }

  Future<String> _copyToAssetStore(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final assets = Directory('${dir.path}${Platform.pathSeparator}canvas_assets');
    if (!await assets.exists()) await assets.create(recursive: true);
    final ext = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.'))
        : '.jpg';
    final target = File('${assets.path}${Platform.pathSeparator}${_uuid.v4()}$ext');
    await source.copy(target.path);
    return target.path;
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
    _selection = {'t:${item.id}'};
    _selectionPath = null;
    _selectionPresentation = SelectionPresentation.object;
    _tool = CanvasTool.select;
    notifyListeners();
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

class _LassoStrokePart {
  const _LassoStrokePart(this.stroke, this.inside);
  final Stroke stroke;
  final bool inside;
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
