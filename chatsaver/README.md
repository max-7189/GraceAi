# GraceAI 本地DeepSeek模型服务

这个目录包含了在本地运行DeepSeek语言模型的必要代码，并提供了API接口供GraceAI应用使用。

## 特性

- 本地运行DeepSeek模型，无需互联网连接
- 支持思考链(Chain of Thought)功能
- 兼容OpenAI风格的API接口
- 针对M系列芯片进行了优化
- 提供Swift客户端代码，易于集成

## 快速开始

### 先决条件

- Python 3.8+
- pip包管理器
- 至少8GB内存（推荐16GB以上）
- 足够的存储空间（至少5GB用于模型文件）

### 安装步骤

1. 创建Python虚拟环境并安装依赖项：

```bash
python -m venv deepseek-env
source deepseek-env/bin/activate
pip install -r requirements.txt
```

2. 下载模型（如果尚未下载）：

```bash
python download_model.py
```

3. 启动服务器：

```bash
./start_server.sh
```

或者直接运行：

```bash
source deepseek-env/bin/activate
python server.py
```

4. 测试服务器：

```bash
python test_client.py
```

## 与GraceAI应用集成

1. 将`LocalLLMService.swift`文件添加到Xcode项目中
2. 在需要使用本地语言模型的地方实例化`LocalLLMService`类
3. 使用`chatCompletion`方法发送请求并获取响应

示例代码：

```swift
Task {
    let llmService = LocalLLMService()
    
    // 检查服务健康状态
    let isHealthy = await llmService.checkHealth()
    if !isHealthy {
        print("本地LLM服务不可用")
        return
    }
    
    // 准备聊天消息
    let messages: [ChatMessage] = [
        .system("你是一个有用的AI助手，名叫GraceAI。请用中文回答问题。"),
        .user("计算23乘以45等于多少？请解释计算过程。")
    ]
    
    do {
        // 带思考链的聊天补全
        let responseWithCoT = try await llmService.chatCompletion(messages: messages, enableChainOfThought: true)
        print("回复(带思考链):\n\(responseWithCoT)")
    } catch {
        print("聊天补全失败: \(error.localizedDescription)")
    }
}
```

## API参考

### 健康检查

```
GET /health
```

响应：
```json
{
  "status": "ok",
  "model": "deepseek-llm-7b-chat.Q4_K_M.gguf"
}
```

### 聊天补全

```
POST /v1/chat/completions
```

请求体：
```json
{
  "messages": [
    {
      "role": "system",
      "content": "你是一个有用的AI助手，名叫GraceAI。请用中文回答问题。"
    },
    {
      "role": "user",
      "content": "计算23乘以45等于多少？请解释计算过程。"
    }
  ],
  "temperature": 0.7,
  "top_p": 0.95,
  "max_tokens": 1024,
  "stream": false,
  "enable_chain_of_thought": true
}
```

响应：
```json
{
  "id": "chatcmpl-xxxx",
  "object": "chat.completion",
  "created": 1699123456,
  "model": "deepseek-llm-7b-chat.Q4_K_M.gguf",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "让我思考一下。\n\n23乘以45可以通过以下步骤计算：\n1) 先计算23乘以5: 23 × 5 = 115\n2) 再计算23乘以40: 23 × 40 = 920\n3) 最后将两个结果相加: 115 + 920 = 1035\n\n因此，23乘以45等于1035。"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 49,
    "completion_tokens": 98,
    "total_tokens": 147
  }
}
```

## 模型信息

本项目使用的是DeepSeek LLM 7B Chat模型的GGUF格式，经过了Q4_K_M量化处理，以提供良好的性能和资源消耗平衡。

## 故障排除

1. 如果服务无法启动，请检查Python环境和依赖项是否正确安装
2. 如果模型加载失败，请确保有足够的内存和存储空间
3. 如果API请求失败，请检查请求格式是否正确 