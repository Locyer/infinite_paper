# Infinite Paper

一个完全离线、仅本机保存的 Flutter 无限画布草稿纸。笔画以世界坐标 JSON 保存，不使用无限 Bitmap，因此可自由向四周平移、缩放和书写。

## 已实现功能（v1.1.0）

- 首页列出全部本地笔记；编辑页顶部可随时切换、新建、重命名、复制和删除笔记
- 世界坐标无限画布、双指平移；缩放范围 0.001x–15x，可锁定缩放倍数
- 手指/触控笔书写模式切换：可设置为手指移动、仅触控笔书写
- 普通笔、荧光笔、三秒后消失的激光笔；工具双击或长按可调颜色和大小
- RGB 色板、快捷颜色、整笔橡皮和按轨迹切割的局部橡皮
- 套索选择笔画、文本、图片，并支持删除、复制、剪切、粘贴、缩放和改色
- 插入相册图片和文本框；图片复制至应用私有目录，本地持久化
- 100 步撤销/重做、自动保存、空白/网格、深浅主题和内容包围盒 PNG 导出相册
- 激光笔实时跟随显示、普通笔/荧光笔/激光笔独立颜色和大小；墨迹始终位于图片与文本上层

## 首次准备

本工作区生成时的机器没有 Flutter SDK，且无法连接 GitHub 下载官方 SDK，因此未能在此处生成 Flutter 自动创建的 Android Gradle Wrapper 和 iOS Xcode 工程文件。安装 Flutter 3.x 后，在项目根目录执行一次以下命令补齐这些**平台样板文件**；它会保留 `lib/`、`test/`、`pubspec.yaml` 和本项目已有的相册权限声明。

```powershell
flutter create --org com.locyer --platforms android,ios .
```

执行后检查 `android/app/src/main/AndroidManifest.xml` 与 `ios/Runner/Info.plist` 中保留了本项目的相册权限条目；若被 Flutter 模板覆盖，请从本仓库对应文件恢复以下内容：

- Android：`WRITE_EXTERNAL_STORAGE`（`maxSdkVersion="28"`）
- iOS：`NSPhotoLibraryAddUsageDescription`

## 运行与检查

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

连接真机后，运行 `flutter devices` 取得设备 ID，再用 `flutter run -d <device-id>` 指定目标。

## Android APK

```powershell
flutter build apk --release
```

输出文件为 `build/app/outputs/flutter-apk/app-release.apk`。将它复制到 Android 手机安装即可；首次侧载时在系统设置中允许当前文件管理器安装未知来源应用。

### 本地版本归档

每次发布的 APK、SHA-256 与发布说明统一放在 `releases/v版本号/`，例如 `releases/v1.1.0/`。该目录不提交二进制到 Git；源码版本以 Git 标签（如 `v1.1.0`）为准。

## iPhone 免费签名侧载

1. 在 macOS 安装 Flutter、Xcode 和 CocoaPods，执行上面的首次准备与 `flutter pub get`。
2. 用 Xcode 打开 `ios/Runner.xcworkspace`，选择 Runner target 的 **Signing & Capabilities**。
3. 登录自己的 Apple ID，选择 Personal Team，并把 Bundle Identifier 改成唯一值，例如 `com.yourname.infinitepaper`。
4. 连接 iPhone，选择它作为运行目标，点击 Run；在手机的“设置 → 通用 → VPN 与设备管理”信任你的开发者证书。

免费 Apple ID 可直接真机运行，但签名通常约七天到期，需要再次用 Xcode 连接并运行；这是 Apple 的免费签名限制。

## 后续扩展

- PDF 导出与打印排版
- 笔画分块索引，优化超大草稿的局部加载
- 文档 JSON 手动备份/导入
