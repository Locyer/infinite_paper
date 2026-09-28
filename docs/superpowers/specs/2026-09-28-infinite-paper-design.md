# 无限草稿纸设计

## 目标

创建一个仅本机使用的 Flutter 3.x Android/iOS 无限画布草稿纸：离线打开即画，可无限平移、0.1x–8x 缩放、绘制、按笔画擦除、撤销/重做、多文档、自动恢复和 PNG 相册导出。

## 范围与取舍

- 不含登录、网络、后端、广告、统计、付费、隐私页或商店审核逻辑。
- 采用 Provider、`path_provider` 和 JSON，而非数据库；每个文档一个 JSON，索引单独保存，便于恢复和备份。
- PNG 默认保存到系统相册；PDF 不是 MVP 范围。
- 擦除采用“按笔画命中”策略：橡皮路径附近的完整笔画被标记删除，可撤销。

## 架构

### 数据层

`DocumentModel` 包含 id、标题、创建/更新时间、`Viewport`（scale、offsetX、offsetY）和 `Stroke` 列表。

`Stroke` 含世界坐标 `StrokePoint` 列表、ARGB 颜色、世界单位宽度、工具类别、删除标记和缓存用的运行时 `Path`。序列化不保存缓存；加载后懒构建 Path。

`DocumentRepository` 使用应用文档目录的 `documents_index.json` 与 `documents/<id>.json`。所有写入先写临时文件再替换，索引按更新时间排序。

### 画布与交互

`CanvasController` 是 `ChangeNotifier`，维护当前文档、工具、当前临时笔画、`UndoableAction` 栈（上限 100）和 500ms 防抖保存。它将屏幕坐标转换为世界坐标，避免任何无限位图。

`InfiniteCanvas` 使用 `Listener` 接收 pressure 与 stylus 指针，再以 `GestureDetector` 仲裁缩放和双击撤销。单笔输入开始绘画；第二根手指一出现，取消当前临时笔画并进入平移/缩放。平移、缩放围绕双指焦点更新 Viewport，缩放范围钳制至 0.1–8。

`CustomPainter` 先画屏幕空间背景（空白或网格），再 `canvas.translate`、`canvas.scale` 到世界空间，按视口世界矩形裁剪并画有效笔画和临时笔画。缓存的笔画 Path 不会在每帧从点列表重建。

### 页面

单页由安全区内的画布和底部工具条构成。工具条提供笔、橡皮、颜色、粗细、撤销、重做、新建、导出和设置。文档管理与设置由 Material bottom sheet 提供：新建、重命名、复制、切换、删除和清空二次确认；设置切换浅/深/系统主题与空白/网格背景。

### 导出

`ExportService` 计算所有未删除笔画的世界包围盒并加入内边距；空画布给出提示。它通过 `PictureRecorder` 在有限目标尺寸重绘背景与笔画，按最长边不超过 4096 px 计算输出比例，编码 PNG 后调用相册保存插件。导出期间 UI 显示进度并报告失败原因。

## 错误处理

- 缺少或损坏单个文档 JSON 时跳过该文档，保留索引并提示；若没有可用文档，则创建空白文档。
- 本地写入、相册保存与权限失败以 SnackBar 告知，不丢失内存中的编辑。
- 删除和清空都必须确认；自动保存失败不会清除未保存状态，下一次编辑或退出继续尝试。

## 测试与验收

- 单元测试覆盖坐标变换、缩放钳制、笔画包围盒、JSON 往返、撤销重做与按笔画橡皮命中。
- Widget 测试覆盖工具切换、空画布导出提示和二次确认。
- 每个模块完成后执行 `flutter analyze`，最后执行 `flutter test`；目标是零 analyze error。

## 平台配置

- iOS `Info.plist` 添加相册写入说明；在 Xcode 中使用个人 Apple ID 的免费团队签名并真机部署。
- Android 按 SDK 版本声明媒体写入权限，并由插件处理新版本 MediaStore。
