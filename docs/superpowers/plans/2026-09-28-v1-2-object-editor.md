# v1.2.0 Object Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a stylus-first editing experience with HSV color selection, eraser cursor, transformed image/text/lasso selections, and a bookshelf home screen.

**Architecture:** Persist rotation on object models and keep selection interaction state in `CanvasController`. `InfiniteCanvas` converts controls between screen and world coordinates, paints content and selection overlays separately, and a focused HSV widget owns color interpolation.

**Tech Stack:** Flutter 3.x/Dart, CustomPainter, Listener/GestureDetector, Provider, JSON local storage, image_picker.

**Spec:** `docs/superpowers/specs/2026-09-28-v1-2-object-editor-design.md`

## Global Constraints

- Preserve offline-only storage and Android 16 support.
- Keep document coordinates world-based; never allocate an infinite image.
- Use JSON defaults so v1.1.0 documents load without migration.
- Version must become `1.2.0+3`; APK is only stored under `releases/v1.2.0/`.
- App display name must be `Infinite Paper`; do not change Android package ID.

## Review Focus

- Finger-pan mode must never prevent a stylus stroke from starting.
- Loading legacy image/text JSON without rotation must result in `0` rotation.
- An eraser cursor must disappear on pointer up/cancel and size must follow zoom.
- A selected rotated object must keep its visual center fixed during handle scaling.
- A blank bookshelf and a large list of notes must both keep a visible new-note card.

---

### Task 1: Versioned models and selection state

**Files:**
- Modify: `lib/models/canvas_models.dart`
- Modify: `lib/controllers/canvas_controller.dart`
- Modify: `test/canvas_models_test.dart`
- Modify: `test/canvas_controller_test.dart`

**Interfaces:**
- Produces `CanvasImage.rotation`, `CanvasText.rotation`, `SelectionTransform`, `selectObject`, `transformSelection` and `insert*AtViewportCenter`.

- [ ] **Step 1: Write failing JSON compatibility tests**

```dart
expect(CanvasImage.fromJson({'id':'i','path':'x','x':0,'y':0,'width':1,'height':1}).rotation, 0);
expect(CanvasText.fromJson({...}).rotation, 0);
```

- [ ] **Step 2: Implement model defaults and controller transform methods**

```dart
CanvasImage copyWith({double? rotation}) => CanvasImage(..., rotation: rotation ?? this.rotation);
void transformSelection({required Offset center, required double scale, required double rotation});
```

- [ ] **Step 3: Test controller selection transform and undo/redo**

```dart
controller.selectObject('i:image');
controller.transformSelection(center: const Offset(10, 10), scale: 2, rotation: .5);
controller.undo();
```

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/canvas_models_test.dart test/canvas_controller_test.dart
git commit -am "feat: add transformable canvas objects"
```

### Task 2: Stylus input arbitration and eraser cursor

**Files:**
- Modify: `lib/widgets/infinite_canvas.dart`
- Modify: `lib/controllers/canvas_controller.dart`
- Test: `test/canvas_controller_test.dart`

**Interfaces:**
- Consumes `CanvasInputMode`, current tool, eraser widths.
- Produces `eraserCursorWorld` and `setEraserCursor`.

- [ ] **Step 1: Write a failing controller test for cursor clear**

```dart
controller.setEraserCursor(const Offset(1, 2));
controller.clearEraserCursor();
expect(controller.eraserCursorWorld, isNull);
```

- [ ] **Step 2: Route a touch pointer to pan and stylus pointer to drawing when fingerPan is enabled**

```dart
final touchesPan = inputMode == CanvasInputMode.fingerPan && event.kind == PointerDeviceKind.touch;
if (touchesPan) beginPan(event); else beginToolAction(event);
```

- [ ] **Step 3: Paint cursor circle in active layer and size preview in tool sheets**

```dart
canvas.drawCircle(cursor, eraserWidth / 2, Paint()..style = PaintingStyle.stroke);
```

- [ ] **Step 4: Run analyzer/tests and commit**

### Task 3: HSV palette and contextual tool controls

**Files:**
- Create: `lib/widgets/hsv_color_picker.dart`
- Modify: `lib/widgets/bottom_toolbar.dart`
- Modify: `lib/pages/home_page.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces `HsvColorPicker(colorValue, onChanged)` and `ToolSizePreview(diameter)`.

- [ ] **Step 1: Write a widget test for an HSV picker callback**

```dart
await tester.drag(find.byKey(const Key('hue-slider')), const Offset(0, 40));
expect(color, isNot(initial));
```

- [ ] **Step 2: Implement local HSV custom paint and drag hit tests**

```dart
final hue = HSVColor.fromColor(Color(value)).hue;
final next = HSVColor.fromAHSV(1, hue, saturation, brightness).toColor().value;
```

- [ ] **Step 3: Remove generic bottom color button; render color section only for ink tools**

- [ ] **Step 4: Run widget tests/analyzer and commit**

### Task 4: Object controls and lasso transform mode

**Files:**
- Modify: `lib/widgets/infinite_canvas.dart`
- Modify: `lib/pages/home_page.dart`
- Modify: `lib/controllers/canvas_controller.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes `selectionBounds`, `rotation`, selected ids.
- Produces hit targets for corner scale handles and top rotation handle.

- [ ] **Step 1: Write selection UI tests**

```dart
expect(find.byKey(const Key('selection-rotate-handle')), findsOneWidget);
expect(find.text('矩形裁剪'), findsOneWidget);
```

- [ ] **Step 2: Paint dashed rotated frame, handles, and toolbar**

```dart
canvas.save(); canvas.translate(center.dx, center.dy); canvas.rotate(rotation); canvas.drawRect(localBounds, dashedPaint); canvas.restore();
```

- [ ] **Step 3: Implement scale/rotation pointer drag and immediate object selection on tap**

- [ ] **Step 4: Add lasso “调整大小” action to enter the same transform controls**

- [ ] **Step 5: Run tests/analyzer and commit**

### Task 5: Centered insertion and bookshelf home screen

**Files:**
- Modify: `lib/pages/home_page.dart`
- Modify: `lib/controllers/canvas_controller.dart`
- Create: `lib/widgets/notebook_shelf_card.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces `NotebookShelfCard` and `viewportCenterWorld(Size)`.

- [ ] **Step 1: Write widget tests for new note card and centered insertion helper**

- [ ] **Step 2: Use `(viewport.screenToWorld(size.center))` for all image/text insertion**

- [ ] **Step 3: Replace list tiles with responsive shelf grid and local painted covers**

- [ ] **Step 4: Run test/analyze and commit**

### Task 6: App identity, release verification and archive

**Files:**
- Modify: `pubspec.yaml`, `README.md`, `RELEASES.md`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Create: `releases/v1.2.0/SHA256.txt`, `releases/v1.2.0/NOTES.md`

- [ ] **Step 1: Set `version: 1.2.0+3` and all display names to `Infinite Paper` while retaining `com.locyer.infinite_paper`**
- [ ] **Step 2: Run full verification**

```powershell
flutter analyze
flutter test
flutter build apk --release
```

- [ ] **Step 3: Archive exact APK and SHA-256 locally, then commit source and tag**

```powershell
git commit -am "feat: refine object editor v1.2.0"
git tag -a v1.2.0 -m "无限草稿纸 v1.2.0"
git push origin main --tags
```
