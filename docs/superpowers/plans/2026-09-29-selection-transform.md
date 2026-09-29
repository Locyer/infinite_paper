# Selection Transform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a single-frame object editor and a freeform lasso that becomes transformable only when the user requests it.

**Architecture:** Keep object IDs in `CanvasController`, add a presentation mode and gesture-scoped transform session, and draw the complete selection overlay in `InfiniteCanvas`. Page controls call controller actions and do not mutate the document directly.

**Tech Stack:** Flutter 3.x, Dart, CustomPainter, Listener, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-29-selection-transform-design.md`

## Global Constraints

- Preserve world-coordinate rendering and the current local JSON document format.
- A drag records at most one undo snapshot.
- A lasso path remains freeform until the explicit “调整大小” action.
- Android release remains `com.locyer.infinite_paper` and local-only.

## Review Focus

- A tap on a rotated image must select it without accidentally beginning a pen stroke.
- A zero-distance drag must not add an undo step.
- A rotation near a cardinal angle must snap without oscillating.
- Lasso action before “调整大小” must retain the original polygon.
- Transforming multiple lasso-selected strokes must use one outer bounding box.

### Task 1: Controller selection presentation and transforms

**Files:**
- Modify: `lib/controllers/canvas_controller.dart`
- Test: `test/canvas_controller_test.dart`

**Interfaces:**
- Produces `selectionMode`, `selectionPath`, `enableSelectionTransform()`, `beginTransform()`, `updateTransform()`, `endTransform()`.

- [ ] **Step 1: Write failing controller tests**

```dart
test('lasso keeps its polygon until transform is explicitly enabled', () {
  controller.endLasso();
  expect(controller.selectionMode, SelectionPresentation.lassoPath);
  controller.enableSelectionTransform();
  expect(controller.selectionMode, SelectionPresentation.transformBox);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/canvas_controller_test.dart`

Expected: FAIL because `selectionMode` is absent.

- [ ] **Step 3: Implement presentation mode and transform session**

```dart
enum SelectionPresentation { none, object, lassoPath, transformBox }
void enableSelectionTransform() => _selectionPresentation = SelectionPresentation.transformBox;
```

- [ ] **Step 4: Run controller tests to verify they pass**

Run: `flutter test test/canvas_controller_test.dart`

Expected: PASS.

### Task 2: Canvas overlay and handle gestures

**Files:**
- Modify: `lib/widgets/infinite_canvas.dart`
- Modify: `lib/pages/home_page.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes controller selection presentation and transform methods.
- Produces an object overlay with move, resize, rotate, angle and contextual actions.

- [ ] **Step 1: Write a failing widget test**

```dart
testWidgets('select tool exposes one transform overlay for an image', (tester) async {
  await tester.tap(find.byTooltip('选择/移动'));
  expect(find.byKey(const Key('selection-transform-overlay')), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because the overlay key is absent.

- [ ] **Step 3: Implement overlay, handles and contextual action bar**

```dart
enum TransformHandle { move, topLeft, top, topRight, rightRotate, bottomRight, bottom, bottomLeft, left }
```

- [ ] **Step 4: Run widget and full tests**

Run: `flutter test`

Expected: PASS.

### Task 3: Verify and release

**Files:**
- Modify: `pubspec.yaml`
- Create: `releases/vNEXT/NOTES.md`

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`

Expected: no error diagnostics.

- [ ] **Step 2: Build and inspect release metadata**

Run: `flutter build apk --release`

Expected: successful APK with incremented version code.

- [ ] **Step 3: Archive and tag**

```powershell
Copy-Item build/app/outputs/flutter-apk/app-release.apk releases/vNEXT/InfinitePaper-vNEXT.apk
git tag -a vNEXT -m "Infinite Paper vNEXT"
```
