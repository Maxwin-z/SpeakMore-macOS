# SpeakMore Lite — 产品需求文档

> 版本: 1.0
> 日期: 2026-03-14
> 状态: 草稿

---

## 1. 产品概述

SpeakMore Lite 是 SpeakMore 的精简版本，**仅保留远端多模态语音转写能力**，移除本地 WhisperKit 模型和独立的文本增强（Chat API）路径。用户按住热键说话，音频直接发送到远端多模态大模型，一步完成转写与增强，结果流式插入到当前聚焦的文本框或浮动编辑面板中。

### 1.1 与完整版的核心差异

| 维度 | SpeakMore Full | SpeakMore Lite |
|------|---------------|----------------|
| 本地 STT (WhisperKit) | 支持 6 种模型 (~75MB–3GB) | **移除** |
| 文本增强 (ChatService) | 独立 LLM 增强路径 | **移除** |
| 多模态转写 | 可选开启 | **唯一转写路径** |
| SPM 依赖 | WhisperKit ≥0.9.0 | **无外部依赖** |
| 安装包体积 | 较大（含 WhisperKit 框架） | 极小（纯网络服务） |
| 首次使用 | 需下载模型 / 或配置多模态 | 仅需配置 API Key |

### 1.2 目标用户

- 网络条件良好，偏好使用云端模型的用户
- 对安装包体积敏感的用户
- 已有 Gemini / 通义千问 / OpenRouter API Key 的用户

---

## 2. 核心数据流

```
用户按下热键 (Fn / 自定义)
  │
  ├─ 捕获当前聚焦元素 (Accessibility API)
  ├─ 获取实时环境上下文 (App 名称、窗口标题、文档路径)
  │
  ▼
开始录音 (AVAudioEngine, 16kHz mono Float32)
  │  显示录音动画 (RecordingOverlayPanel)
  │
用户松开热键
  │
  ▼
停止录音 → 音频编码为 Base64 WAV
  │
  ├─ 构建系统提示词 (上下文层叠)
  │    ├─ 基础转写指令
  │    ├─ 术语表 (最高优先级)
  │    ├─ 用户画像 (长期记忆)
  │    ├─ 近期上下文 (短期记忆)
  │    ├─ 当前环境 (实时上下文)
  │    └─ 用户自定义指令
  │
  ▼
发送到多模态 API (SSE 流式)
  │
  ├─ 有聚焦文本框 → 流式逐 chunk 插入
  └─ 无聚焦文本框 → 流式显示在编辑面板
  │
  ▼
流式结束
  ├─ 保存到历史记录 (Core Data)
  ├─ 记录语音条目用于上下文学习
  └─ 显示完成状态
```

---

## 3. 功能模块

### 3.1 多模态语音转写（核心）

**描述**：将录制的音频直接发送到远端多模态大模型，一次 API 调用同时完成语音识别与文本优化。

**支持的服务商**：

| 服务商 | API 格式 | 默认模型 |
|--------|---------|---------|
| Google Gemini | Gemini Native | gemini-2.5-flash |
| 通义千问 (DashScope) | OpenAI Compatible | qwen-omni-turbo |
| OpenRouter | OpenAI Compatible | google/gemini-2.5-flash |
| 自定义 | OpenAI Compatible | 用户指定 |

**技术要点**：
- 音频编码：Float32 16kHz mono → 16-bit PCM WAV → Base64
- 传输协议：HTTPS POST，SSE 流式响应
- Gemini 使用 `inlineData` 格式传递音频，其他服务商使用 `input_audio` 格式
- 超时与错误处理：HTTP 状态码检测，错误信息透传

**配置项**：
- 服务商选择
- API Key
- Endpoint (支持自定义)
- 模型选择（预设列表 + 自定义模型 ID）

### 3.2 文本输入与插入

**描述**：将转写结果插入到用户当前聚焦的文本输入框，或在浮动编辑面板中展示。

**两种插入模式**：

1. **直接插入模式**（有聚焦文本框时）
   - 通过 Accessibility API 直接写入字符
   - 回退方案 1：CGEvent 模拟键盘输入
   - 回退方案 2：剪贴板 + Cmd+V 粘贴
   - 支持「替换应用」：追踪已插入字符数，用户编辑后可替换原文

2. **编辑面板模式**（无聚焦文本框时）
   - 400×240 浮动面板，流式显示转写内容
   - 支持实时编辑
   - 三个操作按钮：关闭、复制到剪贴板、应用到目标应用

**捕获的环境信息**（在热键按下时立即获取）：
- 聚焦的 AXUIElement
- App 名称、Bundle ID
- 窗口标题
- 文档路径

### 3.3 上下文系统

**描述**：多层上下文信息自动注入到多模态 API 的系统提示词中，提升转写的准确性和上下文相关性。

#### 3.3.1 短期记忆 (ContextSnapshot)

- **触发条件**：累计 10 次语音输入或 500 个字符
- **数据来源**：最近 1 小时的录音文本 + 用户纠正差异
- **提取维度**：
  - 当前话题 (topic)
  - 当前意图 (currentIntent)
  - 领域聚焦 (domainFocus)
  - 近期词汇 (recentVocabulary)
  - 实体词云 (entityCloud)
- **存储**：Core Data `ContextSnapshot` 实体
- **注入位置**：系统提示词的【近期上下文】部分

#### 3.3.2 长期记忆 (UserProfile)

- **触发条件**：每天生成一次
- **数据来源**：近 7 天的所有上下文快照 + 用户纠正记录
- **提取维度**：
  - 用户身份 (identity)
  - 主要领域 (primaryDomains)
  - 语言习惯 (languageHabits)
  - 常用实体 (fixedEntities)
- **存储**：Core Data `UserProfile` 实体
- **注入位置**：系统提示词的【用户画像】部分

#### 3.3.3 实时上下文 (RealtimeContext)

- **捕获时机**：每次热键按下时
- **信息**：当前 App 名称、窗口标题、文档路径
- **注入位置**：系统提示词的【当前环境】部分

#### 3.3.4 上下文生成方式（Lite 版调整）

完整版中，短期/长期记忆的生成依赖独立的 ChatService（文本 LLM）。Lite 版移除了 ChatService，因此上下文生成需要复用多模态 API 的文本能力：

- 使用多模态服务商的**纯文本 chat/completions 接口**（不带音频）生成快照和画像
- 仅需额外发送一个文本请求，无需独立的 API 配置
- 配置来源：复用多模态 API 的 endpoint 和 API Key

#### 3.3.5 用户纠正反馈

- 当用户在编辑面板中手动修改转写结果并应用时，保存编辑差异
- 纠正差异作为高置信度信号注入到下一次快照/画像生成中
- 词级差异检测：对比原始输出与用户编辑版本

#### 3.3.6 隐私保护

在发送文本用于上下文分析前，自动脱敏：
- 手机号 → `[手机号]`
- 身份证号 → `[身份证号]`
- 邮箱地址 → `[邮箱]`
- API 密钥等敏感字符串 → `[密钥]`

### 3.4 提示词管理

**描述**：用户可自定义转写指令，支持全局和按应用配置。

- **通用提示词**：对所有应用生效的转写偏好
- **应用专属提示词**：按 Bundle ID 匹配，优先级高于通用提示词
- **术语表**：高优先级术语列表，确保转写时使用指定写法（如品牌名、技术术语）
- **存储**：UserDefaults（PromptConfiguration JSON）

**提示词层叠顺序**（优先级从低到高）：
1. 基础转写指令
2. 术语表（最高纠正优先级）
3. 用户画像
4. 近期上下文
5. 当前环境
6. 用户自定义指令

### 3.5 历史记录

**描述**：保存所有转写记录，支持查看、复制、编辑。

**Recording 实体字段**：
- `id`: UUID
- `createdAt`: 时间戳
- `title`: 文本前 50 字符
- `originalText`: 转写结果文本
- `enhancedText`: 保留字段（Lite 版中为 nil）
- `userEditedText`: 用户编辑后的文本
- `durationSeconds`: 录音时长
- `audioFilePath`: 音频文件路径 (WAV)
- `sourceApp`: 来源应用名称
- `sttModelName`: 使用的模型标识（如 `multimodal:gemini-2.5-flash`）
- `llmModelName`: 保留字段（Lite 版中为 nil）

**音频存储**：`~/.byutech.SpeakMore/Recordings/{uuid}.wav`（16-bit PCM, 16kHz mono）

**历史界面**：
- 列表视图：按时间倒序，显示标题、时间、来源应用
- 详情视图：完整文本、音频播放、元数据
- 操作：复制文本、重新播放音频

### 3.6 浮动组件

**描述**：屏幕上的快捷交互入口。

- **浮动小组件 (FloatingWidgetPanel)**：40×40 可拖动按钮，点击弹出历史快捷面板
- **历史弹出面板 (HistoryPopoverPanel)**：显示最近 5 条记录，支持快速复制/编辑
- **录音动画面板 (RecordingOverlayPanel)**：录音时的均衡器动画 + 进度指示
- **完成状态胶囊**：转写完成后短暂显示，可点击打开编辑面板

---

## 4. 设置界面

### 4.1 权限管理
- 辅助功能权限状态检测 + 跳转系统设置
- Fn 键配置检查 + 跳转键盘设置

### 4.2 热键配置
- 默认：Fn 键（按住说话，松开结束）
- 支持自定义热键组合（修饰键 + 按键）
- 热键录制器 UI

### 4.3 多模态 API 配置
- 服务商选择（Gemini / DashScope / OpenRouter / 自定义）
- API Key 输入
- Endpoint 配置（自定义服务商）
- 模型选择（预设列表 + 自定义模型 ID）
- 连接测试（可选）

### 4.4 提示词与术语
- 通用提示词编辑
- 应用专属提示词管理（添加 / 编辑 / 删除）
- 术语表编辑（标签式 CRUD）

### 4.5 上下文预览
- 当前短期记忆内容展示
- 当前长期画像内容展示
- 手动刷新按钮
- 词汇/实体标签手动编辑

---

## 5. 技术规格

### 5.1 基本信息
- **Bundle ID**: `cn.byutech.SpeakMoreLite`（或复用 `cn.byutech.SpeakMore`，待定）
- **平台**: macOS 14.0+
- **语言**: Swift 5.9
- **UI 框架**: SwiftUI + AppKit (NSPanel)
- **应用类型**: 菜单栏应用 (LSUIElement = true)
- **界面语言**: 简体中文

### 5.2 SPM 依赖
无。所有功能使用系统框架实现。

### 5.3 系统框架
- **AVFoundation**: 音频录制 (AVAudioEngine)
- **ApplicationServices**: 辅助功能 API (AXUIElement)
- **CoreGraphics**: 事件监听 (CGEventTap)、按键模拟
- **Carbon.HIToolbox**: 键码常量
- **AppKit**: NSPanel 窗口管理、NSEvent 监听
- **CoreData**: 历史记录、上下文快照、用户画像持久化

### 5.4 权限要求 (Entitlements)
- `com.apple.security.device.audio-input` — 麦克风录音
- `com.apple.security.network.client` — 网络请求（API 调用）

### 5.5 本地数据存储
- **数据库**: `~/.byutech.SpeakMore/SpeakMore.sqlite` (Core Data)
- **音频文件**: `~/.byutech.SpeakMore/Recordings/{uuid}.wav`
- **用户配置**: UserDefaults
  - `multimodalConfig` — API 配置
  - `promptConfiguration` — 提示词配置
  - `customHotkey` — 热键配置
  - `contextProfile.*` — 上下文计数器
  - `SpeakMore.widgetVisible` / `widgetPositionX` / `widgetPositionY` — 浮动组件状态

---

## 6. 从完整版移除的文件

以下文件/组件在 Lite 版中**不需要**：

| 文件 | 原因 |
|------|------|
| `WhisperManager.swift` | 本地 STT 模型管理 |
| `ChatService.swift` | 独立文本增强 API 客户端 |
| `ChatConfigStore.swift` | 文本增强 API 配置 |
| `EnhancementPreset.swift` | 预设增强规则（保守/平衡/专业） |
| WhisperKit SPM 依赖 | 不再需要本地推理 |

### 需要修改的文件

| 文件 | 修改内容 |
|------|---------|
| `AppViewModel.swift` | 移除 WhisperKit/ChatService 相关逻辑，多模态成为唯一路径 |
| `ContextProfileService.swift` | 将上下文生成从 ChatService 改为使用多模态 API 的文本接口 |
| `MultimodalConfigStore.swift` | `isEnabled` 字段不再需要（始终启用），简化配置 |
| `SettingsScreen.swift` | 移除模型下载、文本增强配置区域 |
| `PromptsScreen.swift` | 移除 EnhancementPresetSection（预设选择器） |
| `project.yml` | 移除 WhisperKit 依赖 |

---

## 7. 首次使用引导

1. **权限授予**
   - 提示用户授予辅助功能权限（用于文本插入）
   - 提示用户授予麦克风权限（首次录音时系统弹窗）

2. **API 配置**
   - 引导用户选择服务商
   - 输入 API Key
   - 选择模型
   - 可选：发送测试请求验证配置

3. **热键测试**
   - 提示用户尝试按住 Fn 键说话
   - 确认转写结果正常

---

## 8. 状态机

```
idle ──(热键按下)──→ recording ──(热键松开)──→ transcribing
  ▲                                               │
  │                                    (音频编码 + API 调用)
  │                                               │
  │                                               ▼
  │                                           inserting
  │                                          ╱         ╲
  │                           (有文本框)                 (无文本框)
  │                          ╱                              ╲
  └──── idle ◄──── 流式插入完成              showingResult(text)
                                                    │
                                            (关闭/复制/应用)
                                                    │
                                                    ▼
                                                  idle
```

**状态说明**：
- `idle`: 等待用户操作
- `recording`: 正在录音，显示录音动画
- `transcribing`: 录音结束，准备发送到 API
- `inserting`: 流式接收并插入文本
- `showingResult(text)`: 在编辑面板中显示结果，等待用户操作

---

## 9. 错误处理

| 场景 | 处理方式 |
|------|---------|
| API 未配置 | 首次使用引导 → 设置页面 |
| API Key 无效 / 过期 | 显示 HTTP 错误信息，引导检查配置 |
| 网络不可用 | 显示网络错误提示 |
| 录音为空（时间过短） | 静默忽略，回到 idle |
| 辅助功能权限未授予 | 显示权限引导，提供跳转按钮 |
| 流式传输中断 | 保留已接收部分，提示用户 |
| 文本插入失败 | 自动回退到编辑面板模式 |

---

## 10. 后续考虑（不在 v1.0 范围内）

- 离线回退：检测网络不可用时提示用户
- 多语言支持：界面国际化
- 音频压缩：使用 Opus 编码减少上传体积
- 流式音频：边录边传，减少等待时间
- 快捷键自定义扩展：支持双击、三击等触发方式
