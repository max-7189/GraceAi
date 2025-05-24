import Foundation

class StreamingChatService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    // 跟踪响应是否完成
    private(set) var isResponseComplete = false
    
    init(apiKey: String = Config.openAIApiKey) {
        self.apiKey = apiKey
        print("StreamingChatService初始化完成，使用API Key: \(String(apiKey.prefix(8)))...")
    }
    
    // 发送流式请求并处理增量响应
    func sendStreamingMessage(
        _ message: String,
        model: String = Config.defaultChatModel,
        systemPrompt: String? = nil,
        onReceive: @escaping (String, Bool) -> Void
    ) {
        // 重置完成状态
        isResponseComplete = false
        
        // 1. 创建请求
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 2. 构建消息数组
        var messages: [OpenAIChatMessage] = []
        
        // 添加系统提示（如果有）
        if let systemPrompt = systemPrompt {
            messages.append(OpenAIChatMessage(role: "system", content: systemPrompt))
        }
        
        // 添加用户消息
        messages.append(OpenAIChatMessage(role: "user", content: message))
        
        // 3. 创建请求体
        let requestBody = StreamingChatRequest(
            model: model,
            messages: messages,
            stream: true
        )
        
        // 4. 序列化请求
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            onReceive("请求序列化失败", true)
            return
        }
        
        request.httpBody = jsonData
        
        // 5. 创建和启动任务
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // 错误处理
            if let error = error {
                DispatchQueue.main.async {
                    onReceive("网络错误: \(error.localizedDescription)", true)
                }
                return
            }
            
            // 检查HTTP响应
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    onReceive("无效的响应", true)
                }
                return
            }
            
            // 检查状态码
            if httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    if let data = data, let errorMessage = String(data: data, encoding: .utf8) {
                        onReceive("API错误: \(errorMessage)", true)
                    } else {
                        onReceive("API错误: HTTP \(httpResponse.statusCode)", true)
                    }
                }
                return
            }
            
            // 处理数据
            guard let data = data else {
                DispatchQueue.main.async {
                    onReceive("没有返回数据", true)
                }
                return
            }
            
            // 解析SSE格式的流数据
            self.processStreamData(data, onReceive: onReceive)
        }
        
        task.resume()
    }
    
    // 处理流数据
    private func processStreamData(_ data: Data, onReceive: @escaping (String, Bool) -> Void) {
        // 将数据转换为字符串
        guard let text = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async {
                onReceive("无法解码响应数据", true)
                self.isResponseComplete = true
            }
            return
        }
        
        // 将SSE格式的数据分割为行
        let lines = text.components(separatedBy: "\n\n")
        var fullContent = ""
        var isComplete = false
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonText = line.dropFirst(6) // 移除 "data: " 前缀
                
                // 检查是否为完成标记
                if jsonText == "[DONE]" {
                    isComplete = true
                    break
                }
                
                // 尝试解析JSON
                if let data = jsonText.data(using: .utf8),
                   let response = try? JSONDecoder().decode(StreamingChatResponse.self, from: data),
                   let choice = response.choices.first,
                   let content = choice.delta.content {
                    
                    fullContent += content
                    
                    // 检查当前行是否为最后一行
                    isComplete = choice.finish_reason != nil
                    
                    // 回调部分内容
                    DispatchQueue.main.async {
                        onReceive(content, isComplete)
                    }
                }
            }
        }
        
        // 更新完成状态
        if isComplete {
            self.isResponseComplete = true
        }
        
        // 如果没有正确解析出内容但有数据，返回一个错误
        if fullContent.isEmpty && !isComplete {
            DispatchQueue.main.async {
                onReceive("无法解析响应内容", true)
                self.isResponseComplete = true
            }
        }
    }
}

// 流式请求模型
struct StreamingChatRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
}

// 流式响应模型
struct StreamingChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [StreamingChoice]
}

struct StreamingChoice: Codable {
    let index: Int
    let delta: DeltaContent
    let finish_reason: String?
}

struct DeltaContent: Codable {
    let content: String?
} 