import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../controllers/canvas_controller.dart';
import '../models/canvas_models.dart';
import '../services/export_service.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/infinite_canvas.dart';
import '../widgets/hsv_color_picker.dart';

enum _ShelfSection { all, favorites, locked, trash }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _ShelfSection _section = _ShelfSection.all;
  String _query = '';
  String? _folderId;

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
          final displayed = c.summaries.where((s) {
            final inSection = switch (_section) {
              _ShelfSection.all => !s.isDeleted,
              _ShelfSection.favorites => !s.isDeleted && s.isFavorite,
              _ShelfSection.locked => !s.isDeleted && s.isLocked,
              _ShelfSection.trash => s.isDeleted,
            };
            final inFolder = _folderId == null
                ? (s.isFolder || s.folderId == null)
                : !s.isFolder && s.folderId == _folderId;
            return inSection && inFolder &&
                s.title.toLowerCase().contains(_query.toLowerCase());
          }).toList();
          return Scaffold(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xff171717)
                  : const Color(0xfff4f3ef),
              drawer: MediaQuery.sizeOf(context).width < 700
                  ? _ShelfDrawer(
                      section: _section,
                      onChanged: (section) {
                        setState(() {
                          _section = section;
                          _folderId = null;
                        });
                        Navigator.pop(context);
                      })
                  : null,
              appBar: AppBar(
                  leading: _folderId == null
                      ? null
                      : IconButton(
                          tooltip: '返回书架',
                          onPressed: () => setState(() => _folderId = null),
                          icon: const Icon(Icons.arrow_back)),
                  titleSpacing: 20,
                  title: _folderId == null ? const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Infinite Paper'),
                        Text('YOUR NOTE SHELF',
                            style: TextStyle(fontSize: 10, letterSpacing: 1.4))
                      ]) : const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Folder'),
                        Text('TAP ← TO RETURN', style: TextStyle(fontSize: 10, letterSpacing: 1.2))
                      ]),
                  actions: [
                    IconButton(
                        tooltip: '搜索笔记',
                        onPressed: () async {
                          final result = await showSearch<String>(
                              context: context,
                              delegate: _NoteSearchDelegate(c.summaries));
                          if (result != null && context.mounted) {
                            setState(() => _query = result);
                          }
                        },
                        icon: const Icon(Icons.search)),
                    IconButton(
                        tooltip: '新建或导入',
                        onPressed: () => _createMenu(context, c, folderId: _folderId),
                        icon: const Icon(Icons.add_circle_outline))
                  ]),
              body: LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900
                    ? 5
                    : constraints.maxWidth >= 600
                        ? 4
                        : 2;
                final shelf = GridView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: .62,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 22),
                    itemCount: displayed.length + (_section == _ShelfSection.all ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_section == _ShelfSection.all && index == 0) {
                        return _ShelfNotebook(
                            isCreate: true,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            title: '新建笔记',
                            subtitle: '开始一张无限草稿纸',
                            onTap: () => _createMenu(context, c, folderId: _folderId));
                      }
                      final realIndex = index - (_section == _ShelfSection.all ? 1 : 0);
                      final s = displayed[realIndex];
                      return _ShelfNotebook(
                          color: colors[(index - 1) % colors.length],
                          title: s.title,
                          isFolder: s.isFolder,
                          subtitle: s.isFolder ? '文件夹' : '更新于 ${_date(s.updatedAt)}',
                          onTap: () async {
                            if (s.isFolder) {
                              setState(() => _folderId = s.id);
                            } else {
                              await _openSummary(context, c, s);
                            }
                          },
                          coverPath: s.coverPath,
                          onMore: () => _documentMenu(context, c, s));
                    });
                // 文件夹内隐藏书架左栏，页面层级一眼可分辨。
                if (constraints.maxWidth < 700 || _folderId != null) return shelf;
                return Row(children: [
                  SizedBox(width: 210, child: _FixedShelfSidebar(
                    section: _section,
                    onChanged: (section) => setState(() { _section = section; _folderId = null; }),
                  )),
                  const VerticalDivider(width: 1),
                  Expanded(child: shelf),
                ]);
              }));
        },
      );
}

class _ShelfDrawer extends StatelessWidget {
  const _ShelfDrawer({required this.section, required this.onChanged});
  final _ShelfSection section;
  final ValueChanged<_ShelfSection> onChanged;

  @override
  Widget build(BuildContext context) => Drawer(
        child: SafeArea(
          child: Column(children: [
            const ListTile(
              leading: Icon(Icons.auto_stories_outlined),
              title: Text('INFINITE PAPER', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('YOUR NOTE SHELF'),
            ),
            const Divider(),
            _item(Icons.notes_outlined, '全部笔记', _ShelfSection.all),
            _item(Icons.star_border, '我的收藏', _ShelfSection.favorites),
            _item(Icons.lock_outline, '已加锁笔记', _ShelfSection.locked),
            _item(Icons.delete_outline, '最近删除', _ShelfSection.trash),
          ]),
        ),
      );

  Widget _item(IconData icon, String title, _ShelfSection value) => Builder(
      builder: (context) => ListTile(
          leading: Icon(icon),
          selected: section == value,
          title: Text(title),
          onTap: () => onChanged(value)));
}

class _FixedShelfSidebar extends StatelessWidget {
  const _FixedShelfSidebar({required this.section, required this.onChanged});
  final _ShelfSection section;
  final ValueChanged<_ShelfSection> onChanged;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(22, 26, 12, 18),
          child: Text('我的笔记', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        _row(Icons.notes_outlined, '全部笔记', _ShelfSection.all),
        _row(Icons.star_border, '我的收藏', _ShelfSection.favorites),
        _row(Icons.lock_outline, '已加锁笔记', _ShelfSection.locked),
        _row(Icons.delete_outline, '最近删除', _ShelfSection.trash),
      ]));
  Widget _row(IconData icon, String title, _ShelfSection value) => Builder(
      builder: (context) => ListTile(
          dense: true, leading: Icon(icon), title: Text(title),
          selected: section == value, onTap: () => onChanged(value)));
}

class _NoteSearchDelegate extends SearchDelegate<String> {
  _NoteSearchDelegate(this.notes);
  final List<DocumentSummary> notes;
  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))
      ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, ''), icon: const Icon(Icons.arrow_back));
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  Widget _results(BuildContext context) {
    final result = notes.where((n) => !n.isDeleted &&
        n.title.toLowerCase().contains(query.toLowerCase()));
    return ListView(children: result.map((n) => ListTile(
      leading: const Icon(Icons.menu_book_outlined), title: Text(n.title),
      onTap: () => close(context, n.title))).toList());
  }
}

Future<void> _openSummary(BuildContext context, CanvasController controller,
    DocumentSummary summary) async {
  if (summary.isDeleted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在“更多”中恢复笔记后再编辑')));
    return;
  }
  String? password;
  if (summary.isLocked) {
    password = await _passwordDialog(context, title: '输入笔记密码');
    if (password == null) return;
  }
  if (await controller.switchDocument(summary.id, password: password) && context.mounted) {
    _openEditor(context);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码不正确，无法打开笔记')));
  }
}

Future<void> _documentMenu(
    BuildContext context, CanvasController controller, DocumentSummary summary) async {
  if (summary.isFolder) {
    final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(child: Wrap(children: [
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('重命名文件夹'),
                  onTap: () => Navigator.pop(sheet, 'rename')),
              ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除文件夹（笔记移回书架）', style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(sheet, 'delete')),
            ])));
    if (!context.mounted) return;
    if (action == 'rename') {
      final name = await _folderName(context);
      if (!context.mounted) return;
      if (name != null) await controller.renameFolder(summary.id, name);
    } else if (action == 'delete' &&
        await _confirm(context, '删除文件夹', '文件夹内笔记会移回书架，不会删除。')) {
      await controller.deleteFolder(summary.id);
    }
    return;
  }
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
                leading: Icon(summary.isFavorite ? Icons.star : Icons.star_border),
                title: Text(summary.isFavorite ? '取消收藏' : '添加收藏'),
                onTap: () => Navigator.pop(context, 'favorite')),
            ListTile(
                leading: Icon(summary.isLocked ? Icons.lock_open_outlined : Icons.lock_outline),
                title: Text(summary.isLocked ? '取消加锁' : '加锁笔记'),
                onTap: () => Navigator.pop(context, 'lock')),
            if (!summary.isFolder)
              ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('移动到文件夹'),
                  onTap: () => Navigator.pop(context, 'folder')),
            ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('添加或更换封面'),
                onTap: () => Navigator.pop(context, 'cover')),
            if (summary.isDeleted)
              ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('恢复笔记'),
                  onTap: () => Navigator.pop(context, 'restore')),
            ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(summary.isDeleted ? '彻底删除' : '移到最近删除',
                    style: const TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete')),
          ])));
  if (action == null) return;
  if (summary.isLocked) {
    if (!context.mounted) return;
    final password = await _passwordDialog(context, title: '输入笔记密码');
    if (!context.mounted ||
        password == null ||
        !await controller.switchDocument(summary.id, password: password)) {
      return;
    }
  } else {
    await controller.switchDocument(summary.id);
  }
  if (!context.mounted) return;
  if (action == 'rename') {
    _rename(context, controller);
  } else if (action == 'copy') {
    await controller.duplicateDocument();
  } else if (action == 'favorite') {
    await controller.setFavorite(!summary.isFavorite);
  } else if (action == 'lock') {
    if (summary.isLocked) {
      await controller.clearLockPassword();
    } else {
      final password = await _passwordDialog(context, title: '设置笔记密码', confirmation: true);
      if (password != null) await controller.setLockPassword(password);
    }
  } else if (action == 'folder') {
    final folderId = await _chooseFolder(context, controller);
    if (folderId != null) {
      await controller.assignCurrentDocumentToFolder(
          folderId == '_root' ? null : folderId);
    }
  } else if (action == 'cover') {
    final selected = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (selected != null) await controller.setCover(File(selected.path));
  } else if (action == 'restore') {
    await controller.restoreCurrentDocument();
  } else if (action == 'delete' &&
      await _confirm(context, summary.isDeleted ? '彻底删除笔记' : '移到最近删除',
          summary.isDeleted ? '彻底删除后无法恢复。' : '可在“最近删除”中恢复。')) {
    if (summary.isDeleted) {
      await controller.removeCurrentDocument();
    } else {
      await controller.moveCurrentToTrash();
    }
  }
}

Future<String?> _chooseFolder(
    BuildContext context, CanvasController controller) => showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('书架根目录'),
                  onTap: () => Navigator.pop(sheet, '_root')),
              ...controller.summaries
                  .where((item) => item.isFolder && !item.isDeleted)
                  .map((folder) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.title),
                      onTap: () => Navigator.pop(sheet, folder.id)))
            ])));

Future<String?> _passwordDialog(BuildContext context,
    {required String title, bool confirmation = false}) async {
  final first = TextEditingController();
  final second = TextEditingController();
  final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: Text(title),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: first,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: const InputDecoration(labelText: '密码（至少 4 位）')),
                if (confirmation)
                  TextField(
                      controller: second,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '确认密码')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      if (first.text.trim().length < 4 ||
                          (confirmation && first.text != second.text)) return;
                      Navigator.pop(dialog, first.text.trim());
                    },
                    child: const Text('确定'))
              ]));
  first.dispose();
  second.dispose();
  return result;
}

Future<void> _createMenu(BuildContext context, CanvasController controller,
    {String? folderId}) async {
  final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(child: Wrap(children: [
            ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('新建笔记'),
                onTap: () => Navigator.pop(sheet, 'note')),
            ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('新建文件夹'),
                onTap: () => Navigator.pop(sheet, 'folder')),
            ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('导入图片'),
                onTap: () => Navigator.pop(sheet, 'image')),
            ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('导入 PDF'),
                onTap: () => Navigator.pop(sheet, 'pdf')),
          ])));
  if (action == null || !context.mounted) return;
  if (action == 'note') {
    await controller.createDocument(folderId: folderId);
    if (context.mounted) _openEditor(context);
  } else if (action == 'folder') {
    final name = await _folderName(context);
    if (name != null && context.mounted) {
      await controller.createFolder(name);
    }
  } else if (action == 'image') {
    final image = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (image == null) return;
    await controller.createDocument(
        title: '图片 ${DateTime.now().toString().substring(0, 16)}', folderId: folderId);
    await controller.insertImage(File(image.path), const Offset(-120, -90));
    if (context.mounted) _openEditor(context);
  } else if (action == 'pdf') {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ['pdf']);
    final file = picked?.files.singleOrNull;
    if (file == null) return;
    await controller.createDocument(title: file.name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false), ''), folderId: folderId);
    controller.insertText(
        'PDF 附件\n${file.name}\n${file.path ?? '已选择本机文件'}',
        const Offset(-120, -60));
    if (context.mounted) _openEditor(context);
  }
}

Future<String?> _folderName(BuildContext context) async {
  final input = TextEditingController();
  final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: const Text('新建文件夹'),
              content: TextField(
                  controller: input,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '文件夹名称')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, input.text.trim()),
                    child: const Text('创建'))
              ]));
  input.dispose();
  return result?.isEmpty ?? true ? null : result;
}

class _ShelfNotebook extends StatelessWidget {
  const _ShelfNotebook({
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.isCreate = false,
      this.isFolder = false,
      this.coverPath,
      this.onMore});
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool isCreate;
  final bool isFolder;
  final String? coverPath;
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
                      child: isFolder
                          ? const SizedBox()
                          : CustomPaint(painter: _PaperLinesPainter())),
                  if (coverPath != null)
                    Positioned.fill(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.file(File(coverPath!), fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox()))),
                  if (!isFolder) Positioned(
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
                      child: Icon(isCreate ? Icons.add : isFolder ? Icons.folder_rounded : Icons.draw_outlined,
                          size: isCreate ? 48 : 34,
                          color: isFolder
                              ? const Color(0xffd97706)
                              : Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
                                  .withValues(alpha: .72))),
                ]))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          if (onMore != null) SizedBox(width: 30, height: 30, child: IconButton(
              padding: EdgeInsets.zero, tooltip: '笔记操作', onPressed: onMore,
              icon: const Icon(Icons.more_horiz, size: 19)))
        ]),
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

void _openEditor(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => const EditorPage(),
        transitionsBuilder: (_, animation, __, child) {
          // 纯合成层的缩放、位移、淡入；不抓取卡片位图，内存开销极低。
          final curve = CurvedAnimation(
              parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
              opacity: Tween<double>(begin: .15, end: 1).animate(curve),
              child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(.045, .035), end: Offset.zero)
                      .animate(curve),
                  child: ScaleTransition(
                      scale: Tween<double>(begin: .92, end: 1).animate(curve),
                      alignment: Alignment.center,
                      child: child)));
        }));

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
                      if (tool == CanvasTool.pen) ...[
                        const Text('笔尖'),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 8, children: PenStyle.values
                            .map((style) => ChoiceChip(
                                label: Text(_penStyleName(style)),
                                selected: c.penStyle == style,
                                onSelected: (_) {
                                  c.setPenStyle(style);
                                  refresh(() {});
                                }))
                            .toList()),
                        const SizedBox(height: 12),
                      ],
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

String _penStyleName(PenStyle style) => switch (style) {
      PenStyle.fountain => '钢笔',
      PenStyle.pencil => '铅笔',
      PenStyle.ballpoint => '圆珠笔',
      PenStyle.brush => '毛笔',
      PenStyle.calligraphy => '秀丽笔',
    };

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
                          value: CanvasBackground.grid, child: Text('网格')),
                      DropdownMenuItem(
                          value: CanvasBackground.warm, child: Text('奶白护眼'))
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
