import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../controllers/canvas_controller.dart';
import '../models/canvas_models.dart';
import '../services/export_service.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/infinite_canvas.dart';
import '../widgets/hsv_color_picker.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Consumer<CanvasController>(
        builder: (context, c, _) {
          if (!c.isReady)
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          final colors = [
            const Color(0xffdbeafe),
            const Color(0xfffef3c7),
            const Color(0xffd1fae5),
            const Color(0xfffce7f3),
            const Color(0xffe9d5ff),
          ];
          return Scaffold(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xff171717)
                  : const Color(0xfff4f3ef),
              appBar: AppBar(
                  titleSpacing: 20,
                  title: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Infinite Paper'),
                        Text('YOUR NOTE SHELF',
                            style: TextStyle(fontSize: 10, letterSpacing: 1.4))
                      ]),
                  actions: [
                    IconButton(
                        tooltip: '新建笔记',
                        onPressed: () async {
                          await c.createDocument();
                          if (context.mounted) _openEditor(context);
                        },
                        icon: const Icon(Icons.add_circle_outline))
                  ]),
              body: LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900
                    ? 5
                    : constraints.maxWidth >= 600
                        ? 4
                        : 2;
                return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: .62,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 22),
                    itemCount: c.summaries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _ShelfNotebook(
                            isCreate: true,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            title: '新建笔记',
                            subtitle: '开始一张无限草稿纸',
                            onTap: () async {
                              await c.createDocument();
                              if (context.mounted) _openEditor(context);
                            });
                      }
                      final s = c.summaries[index - 1];
                      return _ShelfNotebook(
                          color: colors[(index - 1) % colors.length],
                          title: s.title,
                          subtitle: '更新于 ${_date(s.updatedAt)}',
                          onTap: () async {
                            if (await c.switchDocument(s.id) && context.mounted) {
                              _openEditor(context);
                            }
                          },
                          onMore: () => _documentMenu(context, c, s));
                    });
              }));
        },
      );
}

Future<void> _documentMenu(
    BuildContext context, CanvasController controller, DocumentSummary summary) async {
  final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
              child: Wrap(children: [
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(context, 'rename')),
            ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制'),
                onTap: () => Navigator.pop(context, 'copy')),
            ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete')),
          ])));
  if (action == null) return;
  await controller.switchDocument(summary.id);
  if (!context.mounted) return;
  if (action == 'rename') {
    _rename(context, controller);
  } else if (action == 'copy') {
    await controller.duplicateDocument();
  } else if (action == 'delete' &&
      await _confirm(context, '删除笔记', '删除后无法恢复。')) {
    await controller.removeCurrentDocument();
  }
}

class _ShelfNotebook extends StatelessWidget {
  const _ShelfNotebook({
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.isCreate = false,
      this.onMore});
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool isCreate;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Container(
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withValues(alpha: .07)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 10,
                          offset: const Offset(0, 6))
                    ]),
                child: Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(painter: _PaperLinesPainter())),
                  Positioned(
                      left: 12,
                      top: 12,
                      bottom: 12,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                              8,
                              (_) => Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                      color: Color(0xff64748b),
                                      shape: BoxShape.circle))))),
                  Center(
                      child: Icon(isCreate ? Icons.add : Icons.draw_outlined,
                          size: isCreate ? 48 : 34,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: .72))),
                  if (onMore != null)
                    Positioned(
                        top: 2,
                        right: 1,
                        child: IconButton(
                            tooltip: '笔记操作',
                            onPressed: onMore,
                            icon: const Icon(Icons.more_horiz)))
                ]))),
        const SizedBox(height: 8),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall)
      ]));
}

class _PaperLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff94a3b8).withValues(alpha: .2)
      ..strokeWidth = 1;
    for (var y = 24.0; y < size.height; y += 18) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 8, y), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _PaperLinesPainter oldDelegate) => false;
}

void _openEditor(BuildContext context) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => const EditorPage()));

class EditorPage extends StatelessWidget {
  const EditorPage({super.key});
  @override
  Widget build(BuildContext context) => Consumer<CanvasController>(
        builder: (context, c, _) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
                tooltip: '全部笔记',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back)),
            title: PopupMenuButton<String>(
              tooltip: '切换笔记',
              onSelected: (id) => c.switchDocument(id),
              itemBuilder: (_) => c.summaries
                  .map((s) => PopupMenuItem(value: s.id, child: Text(s.title)))
                  .toList(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child: Text(c.document.title,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.expand_more)
              ]),
            ),
            actions: [
              if (c.saveError != null)
                const Icon(Icons.error_outline, color: Colors.red),
              IconButton(
                  tooltip: '新建',
                  onPressed: c.createDocument,
                  icon: const Icon(Icons.note_add_outlined)),
            ],
          ),
          body: Column(children: [
            Expanded(
                child: Stack(children: [
              InfiniteCanvas(controller: c),
              if (c.hasSelection)
                Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: _SelectionBar(
                        controller: c,
                        onColor: () =>
                            _toolOptions(context, c, CanvasTool.pen))),
            ])),
            BottomToolbar(
                controller: c,
                onConfigure: (t) => _toolOptions(context, c, t),
                onExport: () => _export(context, c),
                onInsertImage: () => _insertImage(context, c),
                onInsertText: () => _insertText(context, c),
                onSettings: () => _settings(context, c)),
          ]),
        ),
      );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller, required this.onColor});
  final CanvasController controller;
  final VoidCallback onColor;
  @override
  Widget build(BuildContext context) => Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            IconButton(
                tooltip: '删除',
                onPressed: controller.deleteSelection,
                icon: const Icon(Icons.delete_outline)),
            IconButton(
                tooltip: '复制',
                onPressed: controller.copySelection,
                icon: const Icon(Icons.copy_outlined)),
            IconButton(
                tooltip: '剪切',
                onPressed: () => controller.copySelection(cut: true),
                icon: const Icon(Icons.content_cut)),
            IconButton(
                tooltip: '粘贴',
                onPressed: controller.pasteSelection,
                icon: const Icon(Icons.content_paste)),
            IconButton(
                tooltip: '缩小',
                onPressed: () => controller.scaleSelection(.8),
                icon: const Icon(Icons.zoom_out)),
            IconButton(
                tooltip: '放大',
                onPressed: () => controller.scaleSelection(1.25),
                icon: const Icon(Icons.zoom_in)),
            IconButton(
                tooltip: '左转 15°',
                onPressed: () => controller.rotateSelection(-.261799),
                icon: const Icon(Icons.rotate_left)),
            IconButton(
                tooltip: '右转 15°',
                onPressed: () => controller.rotateSelection(.261799),
                icon: const Icon(Icons.rotate_right)),
            IconButton(
                tooltip: '颜色',
                onPressed: onColor,
                icon: const Icon(Icons.palette_outlined)),
            IconButton(
                tooltip: '取消选择',
                onPressed: controller.clearSelection,
                icon: const Icon(Icons.close)),
          ])));
}

const _quickColors = [
  0xff111827,
  0xffdc2626,
  0xffea580c,
  0xff16a34a,
  0xff2563eb,
  0xff7c3aed,
  0xffec4899,
  0xfffacc15
];
void _toolOptions(BuildContext context, CanvasController c, CanvasTool tool) {
  if (tool == CanvasTool.lasso || tool == CanvasTool.pan || tool == CanvasTool.select) {
    c.setTool(tool);
    return;
  }
  c.setTool(tool);
  showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
          builder: (context, refresh) => SafeArea(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_toolName(tool),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _quickColors
                              .map((v) => InkWell(
                                  onTap: () {
                                    c.setColor(v);
                                    refresh(() {});
                                  },
                                  child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Color(v),
                                      child: c.colorValue == v
                                          ? const Icon(Icons.check,
                                              color: Colors.white)
                                          : null)))
                              .toList()),
                      if (!{CanvasTool.eraserStroke, CanvasTool.eraserPartial}.contains(tool)) ...[
                        const SizedBox(height: 12),
                        HsvColorPicker(colorValue: c.colorValue, onChanged: (value) { c.setColor(value); refresh(() {}); }),
                      ],
                      _WidthSlider(controller: c, tool: tool, refresh: refresh),
                    ]),
              ))));
}

String _toolName(CanvasTool t) => switch (t) {
      CanvasTool.pen => '画笔设置',
      CanvasTool.highlighter => '荧光笔设置',
      CanvasTool.laser => '激光笔设置',
      CanvasTool.eraserStroke => '整笔橡皮设置',
      CanvasTool.eraserPartial => '局部橡皮设置',
      CanvasTool.select => '选择工具',
      _ => '工具设置'
    };

class _WidthSlider extends StatelessWidget {
  const _WidthSlider(
      {required this.controller, required this.tool, required this.refresh});
  final CanvasController controller;
  final CanvasTool tool;
  final StateSetter refresh;
  double get value => switch (tool) {
        CanvasTool.highlighter => controller.highlighterWidth,
        CanvasTool.laser => controller.laserWidth,
        CanvasTool.eraserStroke => controller.strokeEraserWidth,
        CanvasTool.eraserPartial => controller.partialEraserWidth,
        _ => controller.penWidth
      };
  void set(double v) {
    switch (tool) {
      case CanvasTool.highlighter:
        controller.setHighlighterWidth(v);
      case CanvasTool.laser:
        controller.setLaserWidth(v);
      case CanvasTool.eraserStroke:
        controller.setStrokeEraserWidth(v);
      case CanvasTool.eraserPartial:
        controller.setPartialEraserWidth(v);
      default:
        controller.setPenWidth(v);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('大小：${value.toStringAsFixed(0)}'),
            Slider(
                min: 1,
                max: 100,
                value: value,
                onChanged: (v) {
                  set(v);
                  refresh(() {});
                })
          ])),
          // 固定预览区宽高，圆变大时不会挤动滑杆或底部面板。
          SizedBox(
              width: 96,
              height: 96,
              child: Center(
                  child: Container(
                      width: value.clamp(8, 64),
                      height: value.clamp(8, 64),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: {CanvasTool.eraserStroke, CanvasTool.eraserPartial}
                                  .contains(tool)
                              ? Colors.transparent
                              : Color(controller.colorValue),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.onSurface)))))
        ])
      ]);
}

Future<void> _export(BuildContext context, CanvasController c) async {
  final result = await ExportService().exportDocument(c.document);
  if (context.mounted)
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
}

Future<void> _insertImage(BuildContext context, CanvasController c) async {
  final selected = await ImagePicker()
      .pickImage(source: ImageSource.gallery, imageQuality: 90);
  if (selected == null) return;
  if (!context.mounted) return;
  final size = MediaQuery.sizeOf(context);
  await c.insertImage(
      File(selected.path),
      c.document.viewport.screenToWorld(Offset(size.width / 2, size.height / 2)));
  if (context.mounted)
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('图片已插入画布')));
}

void _insertText(BuildContext context, CanvasController c) {
  final input = TextEditingController();
  showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
              title: const Text('插入文本框'),
              content:
                  TextField(controller: input, autofocus: true, maxLines: 4),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d), child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      final size = MediaQuery.sizeOf(context);
                      c.insertText(
                          input.text,
                          c.document.viewport.screenToWorld(
                              Offset(size.width / 2, size.height / 2)));
                      Navigator.pop(d);
                    },
                    child: const Text('插入'))
              ])).whenComplete(input.dispose);
}

void _settings(BuildContext context, CanvasController c) {
  showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('设置')),
            ListTile(
                title: const Text('输入方式'),
                subtitle: Text(switch (c.inputMode) {
                  CanvasInputMode.penAndTouch => '手指和触控笔都书写',
                  CanvasInputMode.stylusOnly => '仅触控笔书写，手指移动',
                  CanvasInputMode.fingerPan => '手指移动，触控笔书写'
                }),
                trailing: DropdownButton<CanvasInputMode>(
                    value: c.inputMode,
                    onChanged: (v) {
                      if (v != null) c.setInputMode(v);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: CanvasInputMode.penAndTouch,
                          child: Text('全部书写')),
                      DropdownMenuItem(
                          value: CanvasInputMode.stylusOnly,
                          child: Text('仅触控笔')),
                      DropdownMenuItem(
                          value: CanvasInputMode.fingerPan, child: Text('手指移动'))
                    ])),
            SwitchListTile(
                title: const Text('锁定缩放倍数'),
                subtitle: const Text('锁定后双指仅平移'),
                value: c.zoomLocked,
                onChanged: c.setZoomLocked),
            ListTile(
                title: const Text('主题'),
                trailing: DropdownButton<AppThemeMode>(
                    value: c.themeMode,
                    onChanged: (v) {
                      if (v != null) c.setThemeMode(v);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: AppThemeMode.system, child: Text('跟随系统')),
                      DropdownMenuItem(
                          value: AppThemeMode.light, child: Text('浅色')),
                      DropdownMenuItem(
                          value: AppThemeMode.dark, child: Text('深色'))
                    ])),
            ListTile(
                title: const Text('背景'),
                trailing: DropdownButton<CanvasBackground>(
                    value: c.document.background,
                    onChanged: (v) {
                      if (v != null) c.setBackground(v);
                    },
                    items: const [
                      DropdownMenuItem(
                          value: CanvasBackground.blank, child: Text('空白')),
                      DropdownMenuItem(
                          value: CanvasBackground.grid, child: Text('网格'))
                    ])),
            ListTile(
                leading:
                    const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                title:
                    const Text('清空当前画布', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (await _confirm(context, '清空画布', '将清除所有笔画、图片和文本，可立即撤销。'))
                    c.clearDocument();
                }),
          ])));
}

void _rename(BuildContext context, CanvasController c) {
  final input = TextEditingController(text: c.document.title);
  showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
              title: const Text('重命名'),
              content:
                  TextField(controller: input, autofocus: true, maxLength: 40),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d), child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      c.renameDocument(input.text);
                      Navigator.pop(d);
                    },
                    child: const Text('保存'))
              ])).whenComplete(input.dispose);
}

Future<bool> _confirm(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
        context: context,
        builder: (d) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('确认'))
            ])) ??
    false;
String _date(DateTime time) => time.toLocal().toString().substring(0, 16);
