# nnez-yisu

`nnez-yisu` 是一个基于 Flutter 的校园卡消费助手。项目主要面向 Android 使用，保留 Windows 构建用于桌面测试；构建和发布通过 GitHub Actions 完成，不要求在本地执行完整打包流程。

## 功能

- 校园卡账号初始化与本地登录状态管理
- 余额、近 30 天消费流水、充值记录同步
- 首页展示余额、月度消费汇总、消费日历和近期记录
- 细目页支持按月份或单日查看消费与充值明细
- 账户挂失 / 解挂
- JSON 数据导入 / 导出
- Android 桌面组件显示余额
- 应用内定时刷新与启动时自动刷新
- GitHub Releases 更新检查与安装包下载

## 技术栈

- Flutter / Dart / Material Design 3
- `shared_preferences` 保存轻量状态
- `sqflite` / `sqflite_common_ffi` 保存本地流水
- `workmanager` 执行后台同步
- `home_widget` 提供 Android 桌面组件
- GitHub Actions 构建 Android APK 和 Windows 压缩包

## 目录结构

```text
.github/workflows/      GitHub Actions 云端构建与发布
android/                Android 原生配置、桌面组件、签名配置
assets/                 应用图标等资源
lib/core/               时间工具、消费分类逻辑
lib/models/             校园卡资料、流水、充值、汇总模型
lib/pages/              首页、细目、设置、关于、数据管理页面
lib/services/           API、本地存储、数据库、更新、日志等服务
lib/widgets/            可复用 UI 组件
test/                   Flutter 测试
windows/                Windows 测试构建壳
```

## 云端构建

主要工作流是 `.github/workflows/android-apk.yml`：

- `push` 到 `main` 自动触发
- 支持在 GitHub Actions 页面手动触发
- 执行 `flutter pub get`、`flutter analyze`、`flutter test`
- 构建 Android arm64 APK
- 构建 Windows release 压缩包
- 创建或更新对应 GitHub Release

Android release 签名依赖仓库 Secrets：

- `KEYSTORE_BASE64`：release keystore 的 Base64 内容
- `KEY_PROPERTIES`：写入 `android/key.properties` 的签名配置

构建时会注入：

```bash
--dart-define=APP_UPDATE_REPOSITORY=${{ github.repository }}
```

应用内更新检查会使用该仓库的 GitHub Releases。未注入时，更新检查会显示“未配置更新仓库”。

## 本地开发

本地只建议做轻量检查：

```bash
flutter pub get
flutter analyze
flutter test
```

完整 release 构建交给 GitHub Actions 执行。

## 隐私说明

仓库不应提交真实校园卡号、姓名、Cookie、密码、签名密钥、构建产物、本地缓存或 `knowledge/` 目录。运行时产生的账号、密码、流水、日志和导出文件只保存在用户设备本地。
