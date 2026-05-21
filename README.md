# OpenEar 🎙️

> 开源版"听脑"——录音 → 自动转写 → AI 生成摘要 / 待办 / 会议纪要 / Q&A → 一键导出 Markdown / Word / PDF。

完全本地化存储，所有第三方密钥仅保存在你的手机安全存储里，绝不上传任何服务器。

## 功能

- 🎙️ **录音**：高质量 AAC-LC（16 kHz 单声道，最适合 ASR）
- 📥 **导入**：支持从相册 / 文件管理器导入已有音频（.mp3 / .m4a / .wav）
- 📝 **转写**：阿里云"录音文件识别 4.0"，支持中英混合、**说话人分离**（区分发言人 A/B/C…）
- 🤖 **AI 分析**：调用任意 OpenAI 兼容 LLM，并行生成
  - 摘要（核心议题 / 关键结论 / 后续行动）
  - 待办（Markdown 任务列表，含负责人 / 截止时间）
  - 会议纪要（结构化章节）
  - Q&A（5–10 组精华问答）
- 💾 **本地存储**：所有录音、转写、AI 结果都保存在本机 SQLite
- 🔍 **全文搜索**：标题 / 转写 / 摘要 / 待办 / 纪要 / Q&A 任意维度
- 📤 **导出**：Markdown / Word (.docx) / PDF，系统原生分享面板

## 技术栈

| 维度 | 选型 |
| --- | --- |
| 框架 | Flutter 3.22+ / Dart 3.4+ |
| 状态管理 | flutter_riverpod |
| 路由 | go_router |
| 数据库 | sqflite（纯 SQL，无需 build_runner） |
| 录音 / 播放 | record + just_audio |
| 安全存储 | flutter_secure_storage（EncryptedSharedPreferences） |
| HTTP | dio |
| 加密签名 | crypto（自实现阿里云 RPC / OSS 签名） |
| 导出 | pdf + printing + archive（手拼 OOXML） |

## 目录结构

```
lib/
├── main.dart                    # 入口
├── app.dart                     # MaterialApp 根
├── providers.dart               # Riverpod 全局 Provider + 处理管线
├── core/                        # 主题、路由、工具函数
├── data/
│   ├── models/                  # Recording / AppSettings 等
│   ├── database/                # sqflite 数据库
│   ├── repositories/            # SettingsRepository
│   └── services/
│       ├── audio_recorder_service.dart    # 录音
│       ├── audio_player_service.dart      # 播放
│       ├── aliyun_signer.dart             # 阿里云 RPC 签名
│       ├── aliyun_oss_service.dart        # OSS 上传 / 预签名
│       ├── aliyun_asr_service.dart        # 录音文件识别（Token + Submit + 轮询）
│       ├── llm_service.dart               # OpenAI 兼容协议
│       └── export_service.dart            # MD / DOCX / PDF
├── features/
│   ├── home/                    # 录音列表
│   ├── recorder/                # 录音界面
│   ├── detail/                  # 详情（5 个 Tab：概览/摘要/待办/纪要/Q&A）
│   ├── search/                  # 全文搜索
│   └── settings/                # 配置阿里云 + LLM
└── widgets/                     # 通用组件
```

## 快速开始

### 1. 安装 Flutter SDK（Windows）

1. 下载并解压 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)（推荐 stable 通道 3.24+）
2. 把 `flutter\bin` 加入系统环境变量 `Path`
3. 安装 [Android Studio](https://developer.android.com/studio) 并通过 **SDK Manager** 安装最新 Android SDK + Build Tools + Platform-Tools
4. 命令行执行：

```powershell
flutter doctor --android-licenses    # 同意 license
flutter doctor                        # 应当全绿
```

> 你已经有 Java 21 ✅，再装好 Flutter SDK + Android SDK 即可。

### 2. 初始化 Android 平台目录

仓库里只保留了关键覆盖文件，需要先让 Flutter 生成 Android 工程骨架：

```powershell
cd d:\SomeIdeas\OpenEar
flutter create --platforms=android --org com.openear --project-name openear .
```

> 这一步**只会创建**缺少的平台目录（android/、windows/ 等），**不会覆盖**已经存在的 `lib/`、`pubspec.yaml`。

我们准备好的 `android/app/src/main/AndroidManifest.xml` 会覆盖生成的默认 manifest（包含录音、网络等权限）。

### 3. 安装依赖并运行

```powershell
flutter pub get
flutter run                # 连接 Android 设备或启动模拟器后
```

## 配置三方服务

打开 App 右上角"设置"，填写以下凭证：

### A. 阿里云

为了"录音文件识别"，你需要：

1. **AccessKey**（建议使用 [RAM 子账号](https://ram.console.aliyun.com/users)）
   - 必需权限策略：`AliyunOSSFullAccess`、`AliyunNLSFullAccess`
2. **OSS Bucket**
   - 到 [OSS 控制台](https://oss.console.aliyun.com/) 新建一个 Bucket
   - 区域选你常用的（如 `oss-cn-shanghai`），权限选"私有"即可
   - App 上传后会自动生成 24h 有效的预签名 URL 给 ASR 拉取
3. **智能语音 AppKey**
   - 到 [智能语音交互控制台](https://nls-portal.console.aliyun.com/) → 项目管理 → 创建项目
   - 服务勾选 **录音文件识别**，复制项目 AppKey

参考价格：阿里云录音文件识别约 **¥1.5 / 小时**（按实际识别时长计费）；OSS 存储 ~¥0.12/GB/月、流量 ~¥0.5/GB（同区域 ECS / CDN 内部互访不计流量）。

### B. 大模型 (LLM)

App 内置了几个预设，点击即可自动填好 Base URL：

| 服务 | Base URL | 推荐模型 |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash` |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| SiliconFlow | `https://api.siliconflow.cn/v1` | `Qwen/Qwen2.5-7B-Instruct` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |

填入对应平台的 API Key 即可。**任何兼容 OpenAI `chat/completions` 协议的服务都能用**——包括你自部署的 Ollama / vLLM / LM Studio。

## 工作流程

```
录音 / 导入音频
      ↓
保存到本地（recordings/*.m4a）+ SQLite 元数据
      ↓
上传 OSS（私有桶 + 预签名 URL）
      ↓
阿里云"录音文件识别" SubmitTask → 轮询 → 拿回带说话人 ID 的句子列表
      ↓
并行 4 路 LLM 调用：摘要 / 待办 / 纪要 / Q&A
      ↓
全部写回 SQLite，详情页 5 个 Tab 渲染
      ↓
任意时刻可导出 Markdown / DOCX / PDF
```

> 整个管线在 `lib/providers.dart` 的 `ProcessingPipeline` 中实现，每一步都会把 `Recording.status` 写回数据库；任意步骤失败时状态会标为 `failed` 并记录错误信息，详情页可以一键"重新处理"。

## 注意事项

- **PDF 导出的中文字体**：默认通过 `printing` 包从 Google Fonts 下载思源黑体（首次需联网，会缓存）。如果国内访问 Google CDN 受限，可以：
  1. 下载 [Noto Sans SC](https://fonts.google.com/noto/specimen/Noto+Sans+SC) 的 `Regular` 与 `Bold` TTF
  2. 放到 `assets/fonts/`
  3. 在 `lib/data/services/export_service.dart` 的 `_buildPdf` 中改成 `pw.Font.ttf(...)` 加载本地字体
- **录音保存路径**：`Application Documents/recordings/`（应用私有目录，卸载 App 会一并删除）
- **设置加密**：所有 API Key 经 `flutter_secure_storage` 加密后存入 Android EncryptedSharedPreferences

## 常见问题

**Q: 我没有 iOS 怎么办？**
A: Flutter 一套 Dart 代码可同时编译 iOS / Android。当前 README 只演示 Android；想出 iOS 包时找一台 Mac 跑 `flutter create --platforms=ios .` 即可。

**Q: 可以离线吗？**
A: 已录制的内容、转写、AI 结果都在本地数据库；但"转写"和"AI 分析"两步本身是云端服务（阿里云 + LLM），需要联网。

**Q: 想换成本地 Whisper / Ollama？**
A: 完全可以。`AliyunAsrService` 与 `LlmService` 接口都很薄，可以另写一个 `WhisperService`（faster-whisper 服务端）/ 把 `LlmService.baseUrl` 改成 `http://192.168.x.x:11434/v1`（Ollama）即可。

## License

MIT
