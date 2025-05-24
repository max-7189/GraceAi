import Foundation

class ChatGPTService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        print("ChatGPTService初始化完成，使用API Key: \(String(apiKey.prefix(8)))...")
    }
    
    // 发送消息到ChatGPT并获取响应
    func sendMessage(_ message: String, model: String = "gpt-3.5-turbo") async throws -> String {
        print("准备发送单条消息到ChatGPT，使用模型：\(model)")
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatGPTRequest(
            model: model,
            messages: [OpenAIChatMessage(role: "user", content: message)]
        )
        request.httpBody = try JSONEncoder().encode(requestBody)
        print("发送请求到ChatGPT，消息内容：\(message)")
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatGPTResponse.self, from: responseData)
        let result = response.choices.first?.message.content ?? ""
        print("收到ChatGPT响应，长度：\(result.count)字符")
        return result
    }
    
    // 发送带有历史记录的对话
    func sendConversation(_ messages: [OpenAIChatMessage], model: String = "gpt-3.5-turbo") async throws -> String {
        print("准备发送对话到ChatGPT，消息数量：\(messages.count)，使用模型：\(model)")
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatGPTRequest(model: model, messages: messages)
        request.httpBody = try JSONEncoder().encode(requestBody)
        print("发送对话请求到ChatGPT")
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatGPTResponse.self, from: responseData)
        let result = response.choices.first?.message.content ?? ""
        print("收到ChatGPT对话响应，长度：\(result.count)字符")
        return result
    }
}

// 请求和响应模型
struct ChatGPTRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
}

/// OpenAI专用的聊天消息模型，与本地模型的ChatMessage区分开
struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatGPTResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: OpenAIChatMessage
}
