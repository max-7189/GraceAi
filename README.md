# GraceAi

GraceAi是一个语音驱动的AI助手iOS应用，支持与本地DeepSeek LLM模型和OpenAI模型的集成。

## 功能特性

- 🗣️ **语音交互**: 实时语音识别和语音合成
- 🤖 **多模型支持**: 支持本地DeepSeek模型和OpenAI模型
- 📱 **原生iOS应用**: 使用SwiftUI构建的现代界面
- 🔄 **流式响应**: 实时文本流显示，边生成边播放
- 🎯 **句子级TTS**: 智能句子检测，按句播放语音
- 🔗 **SSE支持**: 服务器端事件流，低延迟响应

## 项目结构

```
GraceAi/
├── GraceAi/                    # iOS应用主目录
│   ├── Services/               # 核心服务
│   │   ├── ConversationManager.swift      # 对话管理
│   │   ├── LocalLLMService.swift          # 本地LLM服务
│   │   ├── VoiceService.swift             # 语音合成服务
│   │   └── OpenAISpeechRecognizer.swift   # 语音识别服务
│   ├── Views/                  # UI视图
│   ├── Models/                 # 数据模型
│   └── Config.swift            # 配置文件
├── chatsaver/                  # 本地DeepSeek服务器
│   ├── server.py               # FastAPI服务器
│   ├── requirements.txt        # Python依赖
│   └── start_server.sh         # 启动脚本
└── GraceAi.xcodeproj          # Xcode项目文件
```

## 安装和配置

### 1. 克隆仓库

```bash
git clone https://github.com/max-7189/GraceAi.git
cd GraceAi
```

### 2. 配置API密钥

#### 方法一：Info.plist配置（推荐）
在 `GraceAi/Info.plist` 中添加：
```xml
<key>OPENAI_API_KEY</key>
<string>your-openai-api-key-here</string>
```

#### 方法二：环境变量
```bash
export OPENAI_API_KEY="your-openai-api-key-here"
```

### 3. 设置本地DeepSeek服务器（可选）

如果要使用本地模型：

1. 安装Python依赖：
```bash
cd chatsaver
pip install -r requirements.txt
```

2. 下载模型：
```bash
python download_model.py
```

3. 启动服务器：
```bash
./start_server.sh
```

4. 更新网络配置：
   - 在 `Config.swift` 中设置 `useLocalModel = true`
   - 更新 `localModelURL` 为你的本地IP地址

### 4. 运行iOS应用

1. 在Xcode中打开 `GraceAi.xcodeproj`
2. 选择目标设备或模拟器
3. 点击运行

## 使用说明

1. **语音交互**: 点击麦克风按钮开始语音输入
2. **模型切换**: 在设置中切换本地模型和OpenAI模型
3. **实时对话**: 支持流式响应，边生成边播放语音

## 技术栈

- **iOS**: SwiftUI, AVFoundation, Speech Framework
- **AI模型**: OpenAI GPT-4, 本地DeepSeek LLM
- **服务器**: Python FastAPI, SSE流式响应
- **语音**: OpenAI TTS, OpenAI Whisper

## 系统要求

- iOS 15.0+
- Xcode 14.0+
- Python 3.8+ (用于本地服务器)

## 许可证

本项目采用MIT许可证。

## 贡献

欢迎提交Issue和Pull Request！

## 联系方式

如有问题，请在GitHub上创建Issue。 