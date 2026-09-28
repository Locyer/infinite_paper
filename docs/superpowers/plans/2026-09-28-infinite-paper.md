# 无限草稿纸 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付可在 Android 与 iOS 运行、离线保存并导出 PNG 到相册的 Flutter 无限草稿纸 MVP。

**Architecture:** 文档和笔画以世界坐标 JSON 存在应用文档目录；`CanvasController` 集中处理编辑状态、历史记录和节流写入。画布将 Viewport 作为 Canvas transform 应用，活动笔画独立重绘，导出以有限的内容包围盒 Picture 生成 PNG。

**Tech Stack:** Flutter 3.x、Dart、Provider、path_provider、image_gallery_saver_plus、permission_handler、CustomPainter。

**Spec:** `docs/superpowers/specs/2026-09-28-infinite-paper-design.md`

## Global Constraints

- 目标平台固定为 Android 和 iOS，Flutter 3.x/Dart。
- 全部用户数据只保存于本机；不得添加登录、网络、后端、广告、统计、付费或隐私页。
- 所有笔画点必须是世界坐标；不得实现无限尺寸 Bitmap。
- 缩放必须限制在 0.1x 到 8x；编辑后 500ms 防抖自动保存。
- 历史栈至少保留 100 个动作；删除和清空必须确认。
- PNG 按内容包围盒导出到相册，导出最长边不得超过 4096 像素。
- 每项完成后运行 `flutter analyze`；最终运行 `flutter test`。

## Review Focus

- 手指刚画下后第二根手指加入：临时笔画必须被丢弃而非部分保存。
- 极小或极大的缩放手势：视图比例保持在 0.1–8 范围内。
- 空白文档导出：不创建无意义图片，且 UI 明确提示。
- 损坏或缺失本地 JSON：应用仍能打开一个新空白文档。
- 一次擦除命中多条笔画：撤销必须恢复同一批笔画。

---

## File Structure

- `pubspec.yaml`：应用元信息及所需依赖。
- `lib/main.dart`：应用启动、主题 Provider 与首页装配。
- `lib/models/canvas_models.dart`：`StrokePoint`、`Stroke`、`Viewport`、`DocumentModel` 和几何工具。
- `lib/services/document_repository.dart`：文档索引与原子 JSON 读写。
- `lib/services/export_service.dart`：有界 PNG Picture 生成与相册写入。
- `lib/controllers/canvas_controller.dart`：编辑状态、手势坐标转换、历史、保存和文档操作。
- `lib/widgets/infinite_canvas.dart`：指针/缩放协调与 `CustomPainter`。
- `lib/widgets/bottom_toolbar.dart`：工具按钮与颜色/粗细选择。
- `lib/pages/home_page.dart`：应用页面、弹窗、草稿管理和设置。
- `test/canvas_models_test.dart`：模型、坐标和包围盒行为。
- `test/canvas_controller_test.dart`：缩放、撤销、橡皮和持久化行为。
- `test/widget_test.dart`：工具栏、确认和空导出提示。
- `android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`：相册权限说明。

### Task 1: Scaffold, world-coordinate data model, and local repository

**Files:**
- Create: `pubspec.yaml`, `lib/models/canvas_models.dart`, `lib/services/document_repository.dart`, `test/canvas_models_test.dart`
- Create via Flutter: `android/`, `ios/`, `lib/main.dart`, `test/widget_test.dart`

**Interfaces:**
- Produces `Viewport.screenToWorld(Offset)` and `Viewport.zoomAround(Offset,double)`.
- Produces `Stroke.bounds`, `Stroke.hitTest(Offset,double)` and JSON `toJson`/`fromJson` methods.
- Produces `DocumentRepository.loadIndex()`, `loadDocument(String)`, `saveDocument(DocumentModel)`, `deleteDocument(String)`.

- [ ] **Step 1: Create the Flutter platform scaffold and dependency manifest**

Run:

```powershell
flutter create --org com.locyer --platforms android,ios .
```

Set dependencies to `provider`, `path_provider`, `image_gallery_saver_plus`, `permission_handler`, `uuid`, and `flutter_lints`; run `flutter pub get`.

- [ ] **Step 2: Write the failing model tests**

```dart
test('viewport converts screen coordinates through scale and translation', () {
  const viewport = Viewport(scale: 2, offset: Offset(10, 20));
  expect(viewport.screenToWorld(const Offset(30, 50)), const Offset(10, 15));
});

test('zoomAround clamps scale and keeps focal world point stable', () {
  const viewport = Viewport(scale: 1, offset: Offset.zero);
  final zoomed = viewport.zoomAround(const Offset(100, 80), 100);
  expect(zoomed.scale, 8);
  expect(zoomed.screenToWorld(const Offset(100, 80)), const Offset(100, 80));
});

test('stroke json round trip keeps world points and bounds', () {
  final stroke = Stroke.pen(
    id: 's', color: 0xff000000, width: 4,
    points: [const StrokePoint(x: -2, y: 3), const StrokePoint(x: 8, y: 9)],
  );
  final restored = Stroke.fromJson(stroke.toJson());
  expect(restored.bounds, const Rect.fromLTRB(-2, 3, 8, 9));
});
```

- [ ] **Step 3: Run the test to verify RED**

Run: `flutter test test/canvas_models_test.dart`

Expected: FAIL because `Viewport`, `StrokePoint`, and `Stroke` do not exist.

- [ ] **Step 4: Implement the minimal immutable models and repository**

```dart
class Viewport {
  const Viewport({required this.scale, required this.offset});
  final double scale;
  final Offset offset;

  Offset screenToWorld(Offset screen) => (screen - offset) / scale;
  Viewport zoomAround(Offset focal, double factor) {
    final world = screenToWorld(focal);
    final nextScale = (scale * factor).clamp(0.1, 8.0).toDouble();
    return Viewport(scale: nextScale, offset: focal - world * nextScale);
  }
}
```

Implement JSON conversion, cached non-serialized `Path`, bounds and distance-to-segment hit test. Implement repository writes by `File('$path.tmp').writeAsString(...)` then rename after deleting any existing target.

- [ ] **Step 5: Run model tests and static analysis**

Run: `flutter test test/canvas_models_test.dart; flutter analyze`

Expected: all model tests pass and analyze has no errors.

### Task 2: Editing controller, 100-step history, persistence, and export service

**Files:**
- Create: `lib/controllers/canvas_controller.dart`, `lib/services/export_service.dart`, `test/canvas_controller_test.dart`
- Modify: `lib/models/canvas_models.dart`, `pubspec.yaml`

**Interfaces:**
- Consumes Task 1 `DocumentModel`, `Stroke`, `Viewport`, `DocumentRepository`.
- Produces `CanvasController.beginStroke`, `appendPoint`, `endStroke`, `eraseAt`, `undo`, `redo`, `updateViewport`, `createDocument`, `duplicateDocument`, `renameDocument`, `removeDocument`, `clearDocument`.
- Produces `ExportService.exportDocument(DocumentModel, CanvasBackground)`.

- [ ] **Step 1: Write failing controller tests**

```dart
test('undo and redo restore an erased group of strokes', () async {
  final controller = CanvasController(repository: memoryRepository);
  await controller.open();
  controller.addCompletedStroke(sampleStroke('a'));
  controller.addCompletedStroke(sampleStroke('b'));
  controller.eraseAt(const Offset(5, 0), 10);
  expect(controller.visibleStrokes, isEmpty);
  controller.undo();
  expect(controller.visibleStrokes, hasLength(2));
  controller.redo();
  expect(controller.visibleStrokes, isEmpty);
});

test('second pointer cancels unfinished stroke', () async {
  final controller = CanvasController(repository: memoryRepository);
  await controller.open();
  controller.beginStroke(const Offset(0, 0), pressure: 1);
  controller.cancelActiveStroke();
  controller.endStroke();
  expect(controller.visibleStrokes, isEmpty);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/canvas_controller_test.dart`

Expected: FAIL because `CanvasController` and its editing API do not exist.

- [ ] **Step 3: Implement controller actions and bounded PNG export**

Implement each history action as a reversible object. Cap undo at 100 and clear redo on new edits. `scheduleSave()` resets a 500ms `Timer`; `dispose()` flushes pending saves. For erase, collect every non-deleted stroke whose `hitTest(worldPoint, eraserRadius)` is true into one action. For export, calculate bounds, expand by 32 world units, choose `min(2.0, 4096 / longestSide)`, paint to a `PictureRecorder`, encode `toImage` and save through `ImageGallerySaverPlus.saveImage`.

```dart
void updateViewportForScale(Offset focal, double scaleDelta) {
  _document = _document.copyWith(
    viewport: _document.viewport.zoomAround(focal, scaleDelta),
  );
  notifyListeners();
  scheduleSave();
}
```

- [ ] **Step 4: Run controller tests and static analysis**

Run: `flutter test test/canvas_controller_test.dart; flutter analyze`

Expected: controller tests pass and analyze has no errors.

### Task 3: Infinite painter, responsive UI, platform configuration, and user-facing tests

**Files:**
- Create: `lib/widgets/infinite_canvas.dart`, `lib/widgets/bottom_toolbar.dart`, `lib/pages/home_page.dart`
- Modify: `lib/main.dart`, `test/widget_test.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

**Interfaces:**
- Consumes Task 2 `CanvasController`, `CanvasTool`, `CanvasBackground`, and `ExportService`.
- Produces a `HomePage` that owns app chrome and an `InfiniteCanvas` that only performs painting and pointer routing.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('toolbar switches to eraser and shows undo control', (tester) async {
  await tester.pumpWidget(const InfinitePaperApp(repository: MemoryRepository()));
  await tester.tap(find.byTooltip('橡皮擦'));
  await tester.pump();
  expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
  expect(find.byTooltip('撤销'), findsOneWidget);
});

testWidgets('exporting a blank document explains why it cannot export', (tester) async {
  await tester.pumpWidget(const InfinitePaperApp(repository: MemoryRepository()));
  await tester.tap(find.byTooltip('导出 PNG'));
  await tester.pump();
  expect(find.text('画布为空，暂无内容可导出'), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget test to verify RED**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because `InfinitePaperApp`, toolbar, and home page do not exist.

- [ ] **Step 3: Implement painter and page composition**

Use a `RepaintBoundary` around the canvas. `InfiniteCanvas` tracks active pointer IDs: stylus or finger starts a stroke only when no scale gesture exists; a second pointer calls `cancelActiveStroke`; `onScaleUpdate` updates translation and zoom. The painter paints background before world transform, clips the calculated visible world rect, then paints cached paths. Add semantic tooltips, Material 3 bottom toolbar, sheets for colors/width/documents/settings, double-tap undo, and confirmation dialogs for clear/delete. Configure `NSPhotoLibraryAddUsageDescription` and Android media permissions.

- [ ] **Step 4: Run widget tests and static analysis**

Run: `flutter test test/widget_test.dart; flutter analyze`

Expected: widget tests pass and analyze has no errors.

### Task 4: End-to-end verification and manual device smoke test

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes all application interfaces from Tasks 1–3.
- Produces Chinese usage/build instructions including Android APK and iOS free signing steps.

- [ ] **Step 1: Add exact run and distribution instructions**

Document `flutter pub get`, `flutter run`, `flutter build apk --release`, installation of `build/app/outputs/flutter-apk/app-release.apk`, opening `ios/Runner.xcworkspace` in Xcode, selecting a Personal Team, changing a unique bundle identifier, trusting the developer profile, and free-signing constraints.

- [ ] **Step 2: Verify the full automated suite**

Run: `flutter test; flutter analyze`

Expected: all tests pass and analyze has no errors.

- [ ] **Step 3: Build Android release artifact**

Run: `flutter build apk --release`

Expected: command exits 0 and creates `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 4: Perform device smoke-test checklist when a device is attached**

Run: `flutter devices`

For each listed Android/iOS device, run `flutter run -d <device-id>` and verify drawing, pinch pan/zoom, erasing, undo/redo, restart recovery, document management, theme/background switching, and photo-album export. If no physical device is connected, record the exact skipped condition in README and do not claim device verification.
