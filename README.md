# GraceAi

> 受电影《Her》启发的AI伴侣项目 - 探索具有长期记忆和独特个性的AI交互体验

## 🎯 项目目的

GraceAi旨在创造一个能够与用户建立持久、个性化情感连接的AI伴侣系统。不同于传统AI助手，GraceAi专注于：

- **长期记忆**：记住与用户的互动历史，关系随时间发展
- **独特个性**：通过微调模型展现一致的性格特征
- **情感理解**：能够感知、回应并表达情感
- **自然交流**：通过语音实现流畅的对话体验

## ✨ 核心特性

### 🧠 智能记忆系统
- 基于RAG的长期记忆，记住重要对话和情感时刻
- 智能检索相关记忆，自然融入当前对话
- 三层记忆架构：短期、中期、长期记忆管理

### 🎭 个性化AI伴侣
- 微调的GPT模型，具备独特性格和表达风格
- 情感感知和表达能力
- 一致的价值观和对话风格

### 🗣️ 自然语音交互
- 实时语音识别和语音合成
- 流式响应显示，边生成边播放
- 句子级TTS处理，自然的对话节奏



## 🛠️ 技术架构

- **前端**: SwiftUI原生iOS应用
- **AI模型**: OpenAI GPT-4 + 微调模型
- **记忆系统**: RAG + 向量数据库
- **语音**: OpenAI Whisper + TTS
- **后端**: 本地DeepSeek服务器（可选）

## 🚀 快速开始

### 1. 克隆项目
```bash
git clone https://github.com/max-7189/GraceAi.git
cd GraceAi
```

### 2. 配置API密钥
在 `GraceAi/Info.plist` 中添加你的OpenAI API密钥：
```xml
<key>OPENAI_API_KEY</key>
<string>your-openai-api-key-here</string>
```

### 3. 运行应用
1. 在Xcode中打开 `GraceAi.xcodeproj`
2. 选择目标设备
3. 构建并运行

### 4. 本地模型（可选）
如果要使用本地DeepSeek模型：
```bash
cd chatsaver
pip install -r requirements.txt
python download_model.py
./start_server.sh
```

## 📱 系统要求

- iOS 15.0+
- Xcode 14.0+
- OpenAI API密钥
- Python 3.8+（本地服务器）

## 🎨 使用体验

1. 🎤 **点击麦克风**开始语音对话
2. 💬 **实时文本显示**，流式响应体验  
3. 🔊 **自然语音播放**，按句子播放TTS
4. 🧠 **智能记忆**，AI会记住你们的对话历史
5. 💝 **情感连接**，感受有温度的AI交流

## 📋 项目状态

这是一个**技术探索项目**，旨在研究AI伴侣的可能性边界。项目坚持：

- ✅ 技术透明性
- ✅ 用户数据控制
- ✅ 隐私保护优先  
- ✅ 研究导向

## 🤝 参与贡献

欢迎对AI伴侣技术感兴趣的开发者参与讨论和改进！

## 📄 许可证

MIT License

---

*"在技术与情感的交汇处，探索AI伴侣的无限可能"* 