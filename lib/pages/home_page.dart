import 'dart:io';
import 'dart:ui';
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
          return Scaffold(
            appBar: AppBar(title: const Text('无限草稿纸')),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                await c.createDocument();
                if (context.mounted) _openEditor(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('新建笔记'),
            ),
            body: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: c.summaries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final s = c.summaries[index];
                return Card(
                    child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.draw_outlined)),
                  title: Text(s.title),
                  subtitle: Text('更新于 ${_date(s.updatedAt)}'),
                  onTap: () async {
                    if (await c.switchDocument(s.id) && context.mounted)
                      _openEditor(context);
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      await c.switchDocument(s.id);
                      if (!context.mounted) return;
                      if (value == 'copy') await c.duplicateDocument();
                      if (value == 'delete' &&
                          await _confirm(context, '删除笔记', '删除后无法恢复。'))
                        await c.removeCurrentDocument();
                      if (value == 'rename' && context.mounted)
                        _rename(context, c);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'copy', child: Text('复制')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ));
              },
            ),
          );
        },
      );
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
  if (tool == CanvasTool.lasso || tool == CanvasTool.pan) {
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
      _ => '工具设置'
    };

class _ColorSliders extends StatelessWidget {
  const _ColorSliders({required this.controller, required this.refresh});
  final CanvasController controller;
  final StateSetter refresh;
  @override
  Widget build(BuildContext context) {
    final color = Color(controller.colorValue);
    Widget bar(
            String n, int value, ValueChanged<double> change, Color active) =>
        Row(children: [
          SizedBox(width: 24, child: Text(n)),
          Expanded(
              child: Slider(
                  min: 0,
                  max: 255,
                  value: value.toDouble(),
                  activeColor: active,
                  onChanged: change))
        ]);
    return Column(children: [
      bar('R', color.red, (v) {
        controller.setColor(
            Color.fromARGB(255, v.round(), color.green, color.blue).value);
        refresh(() {});
      }, Colors.red),
      bar('G', color.green, (v) {
        controller.setColor(
            Color.fromARGB(255, color.red, v.round(), color.blue).value);
        refresh(() {});
      }, Colors.green),
      bar('B', color.blue, (v) {
        controller.setColor(
            Color.fromARGB(255, color.red, color.green, v.round()).value);
        refresh(() {});
      }, Colors.blue)
    ]);
  }
}

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
        Row(children: [
          Expanded(child: Text('大小：${value.toStringAsFixed(0)}')),
          Container(width: value.clamp(8, 48), height: value.clamp(8, 48), decoration: BoxDecoration(shape: BoxShape.circle, color: {CanvasTool.eraserStroke, CanvasTool.eraserPartial}.contains(tool) ? Colors.transparent : Color(controller.colorValue), border: Border.all(color: Theme.of(context).colorScheme.onSurface))),
        ]),
        Slider(
            min: 1,
            max: 100,
            value: value,
            onChanged: (v) {
              set(v);
              refresh(() {});
            })
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
