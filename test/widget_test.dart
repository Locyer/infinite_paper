import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_paper/main.dart';
import 'package:infinite_paper/services/document_repository.dart';

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
}
