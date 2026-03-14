# SpeakMore Lite

A lightweight macOS menu bar app that converts speech to text using cloud-based multimodal AI models. Hold a hotkey, speak, and the transcribed text streams directly into your focused text field.

[中文说明](#中文说明)

---

## Features

- **One-step voice transcription** — Audio is sent to a multimodal AI model that performs speech recognition and text optimization in a single API call
- **Stream insertion** — Transcribed text is streamed in real-time into the currently focused text field via macOS Accessibility API
- **Floating editor** — When no text field is focused, results appear in a floating editor panel with copy/apply actions
- **Context-aware** — Automatically captures app name, window title, and document path to improve transcription accuracy
- **Short-term & long-term memory** — Learns your vocabulary, topics, and writing style over time
- **Custom prompts & terminology** — Define global or per-app transcription instructions and a terminology list for proper nouns and technical terms
- **History** — All transcriptions are saved with audio playback support
- **Floating widget** — A draggable mini button for quick access to recent transcriptions
- **Zero local dependencies** — No model downloads required; pure cloud-based, minimal install size

## Supported Providers

| Provider | API Format | Default Model |
|----------|-----------|---------------|
| Google Gemini | Gemini Native | gemini-2.5-flash |
| DashScope (Qwen) | OpenAI Compatible | qwen-omni-turbo |
| OpenRouter | OpenAI Compatible | google/gemini-2.5-flash |
| Custom | OpenAI Compatible | User-specified |

## Requirements

- macOS 14.0+
- Accessibility permission (for text insertion)
- Microphone permission
- An API key from a supported provider

## Getting Started

1. **Clone & build**
   ```bash
   git clone git@github.com:Maxwin-z/SpeakMore-macOS.git
   cd SpeakMore-macOS
   ```
   Open `SpeakMoreLite.xcodeproj` in Xcode and build (⌘B).

2. **Grant permissions**
   - System Settings → Privacy & Security → Accessibility → Enable SpeakMore Lite
   - Microphone permission is requested on first recording

3. **Configure API**
   - Open settings from the menu bar icon
   - Select a provider, enter your API key, and choose a model

4. **Use**
   - Hold the Fn key (or your custom hotkey) and speak
   - Release to send audio for transcription
   - Text streams into the focused text field or the floating editor

## Tech Stack

- **Language**: Swift 5.9
- **UI**: SwiftUI + AppKit (NSPanel)
- **Audio**: AVAudioEngine (16kHz mono Float32)
- **Text insertion**: Accessibility API → CGEvent fallback → Clipboard fallback
- **Storage**: Core Data + UserDefaults
- **Dependencies**: None (system frameworks only)

## License

All rights reserved.

---

<a name="中文说明"></a>

# SpeakMore Lite 中文说明

一款轻量级 macOS 菜单栏应用，通过云端多模态 AI 模型实现语音转文字。按住热键说话，转写结果实时流式插入到当前聚焦的文本框中。

## 功能特性

- **一步语音转写** — 音频直接发送到多模态大模型，一次 API 调用同时完成语音识别与文本优化
- **流式插入** — 转写文本通过 macOS 辅助功能 API 实时流式插入当前聚焦的文本框
- **浮动编辑面板** — 无聚焦文本框时，结果显示在浮动编辑面板中，支持复制/应用操作
- **上下文感知** — 自动获取当前应用名称、窗口标题、文档路径，提升转写准确性
- **短期记忆 & 长期记忆** — 自动学习你的词汇、话题和写作风格
- **自定义提示词与术语表** — 支持全局或按应用配置转写指令，以及高优先级术语列表（品牌名、技术术语等）
- **历史记录** — 所有转写记录均保存，支持音频回放
- **浮动小组件** — 可拖动的迷你按钮，快速访问最近的转写记录
- **零本地依赖** — 无需下载模型，纯云端服务，安装包极小

## 支持的服务商

| 服务商 | API 格式 | 默认模型 |
|--------|---------|---------|
| Google Gemini | Gemini Native | gemini-2.5-flash |
| 通义千问 (DashScope) | OpenAI Compatible | qwen-omni-turbo |
| OpenRouter | OpenAI Compatible | google/gemini-2.5-flash |
| 自定义 | OpenAI Compatible | 用户指定 |

## 系统要求

- macOS 14.0+
- 辅助功能权限（用于文本插入）
- 麦克风权限
- 支持的服务商 API Key

## 快速开始

1. **克隆与构建**
   ```bash
   git clone git@github.com:Maxwin-z/SpeakMore-macOS.git
   cd SpeakMore-macOS
   ```
   在 Xcode 中打开 `SpeakMoreLite.xcodeproj` 并构建（⌘B）。

2. **授予权限**
   - 系统设置 → 隐私与安全性 → 辅助功能 → 启用 SpeakMore Lite
   - 首次录音时系统会自动请求麦克风权限

3. **配置 API**
   - 点击菜单栏图标打开设置
   - 选择服务商，输入 API Key，选择模型

4. **使用**
   - 按住 Fn 键（或自定义热键）说话
   - 松开后音频发送至云端进行转写
   - 转写文本流式插入到聚焦的文本框或浮动编辑面板

## 技术栈

- **语言**: Swift 5.9
- **UI 框架**: SwiftUI + AppKit (NSPanel)
- **音频**: AVAudioEngine（16kHz 单声道 Float32）
- **文本插入**: 辅助功能 API → CGEvent 回退 → 剪贴板回退
- **存储**: Core Data + UserDefaults
- **外部依赖**: 无（仅使用系统框架）

## 许可

保留所有权利。
