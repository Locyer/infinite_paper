import 'package:flutter/material.dart';
import '../controllers/canvas_controller.dart';
import '../models/canvas_models.dart';

class BottomToolbar extends StatelessWidget {
  const BottomToolbar(
      {super.key,
      required this.controller,
      required this.onConfigure,
      required this.onExport,
      required this.onInsertImage,
      required this.onInsertText,
      required this.onSettings});
  final CanvasController controller;
  final void Function(CanvasTool) onConfigure;
  final VoidCallback onExport, onInsertImage, onInsertText, onSettings;
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
          top: false,
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _tool(Icons.edit, '画笔', CanvasTool.pen),
                _tool(Icons.highlight, '荧光笔', CanvasTool.highlighter),
                _tool(Icons.gesture, '激光笔', CanvasTool.laser),
                _tool(Icons.auto_fix_high, '整笔橡皮', CanvasTool.eraserStroke),
                _tool(
                    Icons.cleaning_services, '局部橡皮', CanvasTool.eraserPartial),
                _tool(Icons.touch_app_outlined, '选择/移动', CanvasTool.select),
                _tool(Icons.gesture_outlined, '套索', CanvasTool.lasso),
                _tool(Icons.pan_tool_alt_outlined, '移动', CanvasTool.pan),
                IconButton(
                    tooltip: '撤销',
                    onPressed: controller.canUndo ? controller.undo : null,
                    icon: const Icon(Icons.undo)),
                IconButton(
                    tooltip: '重做',
                    onPressed: controller.canRedo ? controller.redo : null,
                    icon: const Icon(Icons.redo)),
                IconButton(
                    tooltip: '插入图片',
                    onPressed: onInsertImage,
                    icon: const Icon(Icons.image_outlined)),
                IconButton(
                    tooltip: '插入文本',
                    onPressed: onInsertText,
                    icon: const Icon(Icons.text_fields)),
                IconButton(
                    tooltip: '导出 PNG',
                    onPressed: onExport,
                    icon: const Icon(Icons.ios_share)),
                IconButton(
                    tooltip: '设置',
                    onPressed: onSettings,
                    icon: const Icon(Icons.tune)),
              ]))));
  Widget _tool(IconData icon, String tip, CanvasTool value) => GestureDetector(
      onDoubleTap: () => onConfigure(value),
      child: IconButton(
          tooltip: '$tip（双击设置）',
          onPressed: () => controller.setTool(value),
          onLongPress: () => onConfigure(value),
          icon: Icon(icon),
          style: IconButton.styleFrom(
              backgroundColor:
                  controller.tool == value ? const Color(0x332563eb) : null)));
}
