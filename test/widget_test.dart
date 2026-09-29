import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_paper/controllers/canvas_controller.dart';
import 'package:infinite_paper/main.dart';
import 'package:infinite_paper/services/document_repository.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('toolbar switches to eraser and shows undo control',
      (tester) async {
    await tester.pumpWidget(
      InfinitePaperApp(repository: MemoryDocumentRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('整笔橡皮（双击设置）'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('撤销'), findsOneWidget);
  });

  testWidgets('exporting a blank document explains why it cannot export',
      (tester) async {
    await tester.pumpWidget(
      InfinitePaperApp(repository: MemoryDocumentRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导出 PNG'));
    await tester.pump();
    expect(find.text('画布为空，暂无内容可导出'), findsOneWidget);
  });

  testWidgets('selected text exposes one contextual transform overlay',
      (tester) async {
    await tester.pumpWidget(
      InfinitePaperApp(repository: MemoryDocumentRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿 1'));
    await tester.pumpAndSettle();
    final controller = Provider.of<CanvasController>(
        tester.element(find.byType(Scaffold).first),
        listen: false);
    controller.insertText('可编辑文本', const Offset(30, 40));
    await tester.pump();

    expect(find.byKey(const Key('selection-transform-overlay')), findsOneWidget);
    expect(find.byTooltip('复制'), findsOneWidget);
  });
}
