# OpenEar 🎙️

> An open-source AI voice-note app — Record → Auto-Transcribe → AI-Generated Summary / Todos / Meeting Minutes / Q&A → Export to Markdown / Word / PDF.

[English](./README.md) · [简体中文](./README_zh.md)

Fully local-first storage. All third-party credentials are encrypted on-device and never uploaded to any server.

## Features

- 🎙️ **Recording**: High-quality AAC-LC (16 kHz mono, optimized for ASR)
- 📥 **Import**: Import existing audio from gallery / file manager (.mp3 / .m4a / .wav)
- 📝 **Transcription**: Tencent Cloud "File Speech Recognition" with Chinese-English mixed support and **speaker diarization** (labels speakers A/B/C…)
- 🤖 **AI Analysis**: Calls any OpenAI-compatible LLM, generates in parallel:
  - Summary (key topics / conclusions / next steps)
  - Todos (Markdown task list with owner / deadline)
  - Meeting Minutes (structured sections)
  - Q&A (5–10 essential question-answer pairs)
- 💾 **Local Storage**: All recordings, transcripts and AI results stored in on-device SQLite
- 🔍 **Full-Text Search**: Search across title / transcript / summary / todos / minutes / Q&A
- 📤 **Export**: Markdown / Word (.docx) / PDF via native share sheet

## Tech Stack

| Layer | Choice |
| --- | --- |
| Framework | Flutter 3.22+ / Dart 3.4+ |
| State Management | flutter_riverpod |
| Routing | go_router |
| Database | sqflite (raw SQL, no build_runner) |
| Recording / Playback | record + just_audio |
| Secure Storage | flutter_secure_storage (EncryptedSharedPreferences) |
| HTTP | dio |
| Crypto / Signing | crypto (custom Tencent Cloud TC3-HMAC-SHA256 + COS signers) |
| Export | pdf + printing + archive (manual OOXML) |

## Project Structure

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # MaterialApp root
├── providers.dart               # Riverpod providers + processing pipeline
├── core/                        # Theme, router, utils
├── data/
│   ├── models/                  # Recording / AppSettings
│   ├── database/                # sqflite database
│   ├── repositories/            # SettingsRepository
│   └── services/
│       ├── audio_recorder_service.dart    # Recording
│       ├── audio_player_service.dart      # Playback
│       ├── cos_service.dart               # Tencent Cloud COS upload + presign
│       ├── tencent_asr_service.dart       # File Speech Recognition (TC3 sign + poll)
│       ├── llm_service.dart               # OpenAI-compatible client
│       └── export_service.dart            # MD / DOCX / PDF export
├── features/
│   ├── home/                    # Recording list
│   ├── recorder/                # Recording UI
│   ├── detail/                  # Detail (5 tabs: Overview/Summary/Todos/Minutes/Q&A)
│   ├── search/                  # Full-text search
│   └── settings/                # Tencent Cloud + LLM config
└── widgets/                     # Shared widgets
```

## Quick Start

### 1. Install Flutter SDK (Windows)

1. Download and unzip the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable channel 3.24+ recommended)
2. Add `flutter\bin` to system `Path` environment variable
3. Install [Android Studio](https://developer.android.com/studio) and use **SDK Manager** to install the latest Android SDK + Build Tools + Platform-Tools
4. Run in terminal:

```powershell
flutter doctor --android-licenses    # Accept all licenses
flutter doctor                        # Should be all green
```

### 2. Initialize Android Platform Folder

The repo only keeps key override files. You need to let Flutter generate the Android scaffold first:

```powershell
cd OpenEar
flutter create --platforms=android --org com.openear --project-name openear .
```

> This step **only creates** missing platform folders (android/, windows/ etc.) and **does not overwrite** the existing `lib/` or `pubspec.yaml`.

The pre-configured `android/app/src/main/AndroidManifest.xml` will replace the generated default (it includes microphone, network and other permissions).

### 3. Install Dependencies and Run

```powershell
flutter pub get
flutter run                # After connecting an Android device or starting an emulator
```

## Configure Third-Party Services

Open the Settings page (top-right of the home screen) and fill in:

### A. Tencent Cloud

For "File Speech Recognition", you need:

1. **API Credentials** (recommended: use a [CAM sub-account](https://console.cloud.tencent.com/cam))
   - Required policies: `QcloudCOSFullAccess`, `QcloudAAIFullAccess` (or just `ReadOnlyAccess` + `QcloudCOSFullAccess` + ASR-specific)
   - Get `SecretId` and `SecretKey` from [API Key Management](https://console.cloud.tencent.com/cam/capi)
2. **COS Bucket**
   - Create a bucket on [COS Console](https://console.cloud.tencent.com/cos/bucket)
   - Choose any region (e.g. `ap-chengdu`), private access is fine
   - Recording uploads will be auto-pre-signed for ASR pulls (24h validity)
3. **AppID** — found in the top-right corner of the Tencent Cloud console (numeric)
4. **Activate Batch Traffic** for File Speech Recognition on the [ASR Console](https://console.cloud.tencent.com/asr) (one-time, pay-as-you-go after activation)

Reference pricing: Tencent Cloud File Speech Recognition is approximately **¥1.5 / hour** of audio. COS storage ~¥0.099/GB/month, traffic ~¥0.5/GB.

### B. LLM (Large Language Model)

The app includes preset chips that auto-fill Base URL and model name on tap:

| Provider | Base URL | Recommended Model |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Tongyi Qianwen | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| Zhipu GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash` |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| SiliconFlow | `https://api.siliconflow.cn/v1` | `Qwen/Qwen2.5-7B-Instruct` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |

Just enter your API key. **Any OpenAI `chat/completions`-compatible service works** — including self-hosted Ollama / vLLM / LM Studio.

## Workflow

```
Record / Import audio
       ↓
Save locally (recordings/*.m4a) + SQLite metadata
       ↓
Upload to Tencent Cloud COS (private bucket + presigned URL)
       ↓
Submit File Speech Recognition task → poll → get sentences with speaker IDs
       ↓
4 parallel LLM calls: Summary / Todos / Minutes / Q&A
       ↓
Write all results back to SQLite, render in 5 detail tabs
       ↓
Export to Markdown / DOCX / PDF anytime
```

> The whole pipeline lives in `ProcessingPipeline` in `lib/providers.dart`. Each step writes `Recording.status` back to the DB; on failure the status becomes `failed` with an error message, and the detail page offers a one-click retry.

## Notes

- **PDF Chinese fonts**: By default the `printing` package downloads Noto Sans SC from Google Fonts (cached after first run). If Google CDN is blocked, you can:
  1. Download [Noto Sans SC](https://fonts.google.com/noto/specimen/Noto+Sans+SC) Regular and Bold TTFs
  2. Place them in `assets/fonts/`
  3. Update `_buildPdf` in `lib/data/services/export_service.dart` to load via `pw.Font.ttf(...)`
- **Recording path**: `Application Documents/recordings/` (app-private, removed when the app is uninstalled)
- **Settings encryption**: All API keys are encrypted by `flutter_secure_storage` and stored in Android EncryptedSharedPreferences

## FAQ

**Q: What if I don't have iOS?**
A: A single Dart codebase compiles to both iOS and Android. The README only walks through Android; for iOS, get access to a Mac and run `flutter create --platforms=ios .`.

**Q: Can it work offline?**
A: Recordings, transcripts and AI results are stored locally; but "transcription" and "AI analysis" themselves are cloud services (Tencent Cloud + LLM) that require an internet connection.

**Q: Want to swap to local Whisper / Ollama?**
A: Sure. `TencentAsrService` and `LlmService` interfaces are minimal — write a `WhisperService` (faster-whisper server) and / or set `LlmService.baseUrl` to `http://192.168.x.x:11434/v1` (Ollama).

## License

MIT
