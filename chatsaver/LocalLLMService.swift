import Foundation

/// 本地LLM服务类，用于与本地运行的DeepSeek API服务交互
class LocalLLMService {
    private let baseURL: String
    
    init(baseURL: String = "http://localhost:8000") {
        self.baseURL = baseURL
    }
    
    /// 检查API服务是否在线
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            print("无效的API URL")
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            print("健康检查失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 聊天补全请求
    func chatCompletion(messages: [ChatMessage], enableChainOfThought: Bool = false) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw NSError(domain: "LocalLLMService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无效的API URL"])
        }
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.7,
            "top_p": 0.95,
            "max_tokens": 2048,
            "stream": false,
            "enable_chain_of_thought": enableChainOfThought
        ]
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 发送请求
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "LocalLLMService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    throw NSError(domain: "LocalLLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API错误: \(errorMessage)"])
                }
                throw NSError(domain: "LocalLLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API请求失败: \(httpResponse.statusCode)"])
            }
            
            // 解析响应
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            } else {
                throw NSError(domain: "LocalLLMService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "无法解析API响应"])
            }
            
        } catch {
            throw error
        }
    }
}

/// 聊天消息模型
struct ChatMessage {
    let role: String  // "system", "user", "assistant"
    let content: String
    
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }
    
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }
    
    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

/// 示例使用方法
/*
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
        
        // 常规聊天补全
        let standardResponse = try await llmService.chatCompletion(messages: messages)
        print("回复(标准):\n\(standardResponse)")
    } catch {
        print("聊天补全失败: \(error.localizedDescription)")
    }
}
*/ 