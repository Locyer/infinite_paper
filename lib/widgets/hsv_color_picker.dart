import 'package:flutter/material.dart';

/// 本地绘制的色相条与饱和度/明度面板，不依赖网络或第三方色板。
class HsvColorPicker extends StatelessWidget {
  const HsvColorPicker({super.key, required this.colorValue, required this.onChanged});
  final int colorValue;
  final ValueChanged<int> onChanged;
  @override Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(Color(colorValue));
    return SizedBox(height: 220, child: Row(children: [
      Expanded(child: LayoutBuilder(builder: (_, box) => GestureDetector(
        onPanDown: (d) => _pickSquare(d.localPosition, box.biggest, hsv.hue),
        onPanUpdate: (d) => _pickSquare(d.localPosition, box.biggest, hsv.hue),
        child: Stack(children: [
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()])), child: const SizedBox.expand()),
          DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black])), child: const SizedBox.expand()),
          Positioned(left: hsv.saturation * box.maxWidth - 12, top: (1 - hsv.value) * box.maxHeight - 12, child: const _Ring()),
        ]),
      ))),
      const SizedBox(width: 14),
      SizedBox(width: 28, child: LayoutBuilder(builder: (_, box) => GestureDetector(
        key: const Key('hue-slider'),
        onPanDown: (d) => _pickHue(d.localPosition.dy, box.maxHeight, hsv),
        onPanUpdate: (d) => _pickHue(d.localPosition.dy, box.maxHeight, hsv),
        child: Stack(children: [
          DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.red, Colors.purple, Colors.blue, Colors.cyan, Colors.green, Colors.yellow, Colors.red])), child: const SizedBox.expand()),
          Positioned(top: hsv.hue / 360 * box.maxHeight - 2, left: -4, right: -4, child: const Divider(thickness: 3, color: Colors.white)),
        ]),
      ))),
    ]));
  }
  void _pickSquare(Offset p, Size size, double hue) { final s = (p.dx / size.width).clamp(0.0, 1.0); final v = (1 - p.dy / size.height).clamp(0.0, 1.0); onChanged(HSVColor.fromAHSV(1, hue, s, v).toColor().value); }
  void _pickHue(double y, double height, HSVColor old) { onChanged(HSVColor.fromAHSV(1, (y / height).clamp(0.0, 1.0) * 360, old.saturation, old.value).toColor().value); }
}
class _Ring extends StatelessWidget { const _Ring(); @override Widget build(BuildContext context) => Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)])); }
