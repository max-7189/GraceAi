import Foundation

/// 本地LLM服务类，用于与本地运行的DeepSeek API服务交互
class LocalLLMService {
    private let baseURL: String
    
    init(baseURL: String = Config.localModelURL) {
        self.baseURL = baseURL
        print("LocalLLMService初始化，baseURL: \(baseURL)")
    }
    
    /// 检查API服务是否在线
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            print("无效的API URL: \(baseURL)/health")
            return false
        }
        
        print("开始健康检查: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("非HTTP响应")
                return false
            }
            
            print("健康检查响应状态码: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("健康检查响应内容: \(responseString)")
            }
            
            return httpResponse.statusCode == 200
        } catch {
            print("健康检查失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 流式聊天补全请求
    func streamChatCompletion(
        messages: [LocalChatMessage],
        enableChainOfThought: Bool = false,
        onReceive: @escaping (String, Bool) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            print("无效的API URL: \(baseURL)/v1/chat/completions")
            onReceive("无效的API URL", true)
            return
        }
        
        print("准备发送流式聊天请求到: \(url.absoluteString)")
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.7,
            "top_p": 0.95,
            "max_tokens": 2048,
            "stream": true, // 启用流式
            "enable_chain_of_thought": enableChainOfThought
        ]
        
        print("请求体: \(requestBody)")
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("JSON序列化失败: \(error.localizedDescription)")
            onReceive("JSON序列化失败: \(error.localizedDescription)", true)
            return
        }
        
        // 设置更长的超时时间
        request.timeoutInterval = 60
        
        // 创建SSE处理器
        let sseHandler = SSEHandler(onReceive: onReceive)
        
        // 使用处理器创建会话并发送请求
        sseHandler.startRequest(request)
        
        print("已启动流式请求任务")
    }
    
    /// SSE处理器类，用于处理流式响应
    private class SSEHandler: NSObject, URLSessionDataDelegate {
        private let onReceive: (String, Bool) -> Void
        private var buffer = Data()
        private var session: URLSession!
        private var task: URLSessionDataTask?
        
        init(onReceive: @escaping (String, Bool) -> Void) {
            self.onReceive = onReceive
            super.init()
            
            // 创建会话，将自己设为delegate
            let config = URLSessionConfiguration.default
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        
        func startRequest(_ request: URLRequest) {
            // 创建并启动数据任务
            task = session.dataTask(with: request)
            task?.resume()
        }
        
        // 接收数据流的delegate方法
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            print("SSEHandler - 接收到\(data.count)字节的数据")
            
            // 打印前50个字节的十六进制表示，帮助调试
            let hexString = data.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
            print("接收数据(十六进制): \(hexString)")
            
            // 如果可能，打印为字符串
            if let str = String(data: data.prefix(50), encoding: .utf8) {
                print("接收数据(字符串): \"\(str)\"")
            }
            
            buffer.append(data)
            
            // 处理缓冲区中的数据
            processBuffer()
        }
        
        // 完成时的delegate方法
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                print("SSE流错误: \(error.localizedDescription)")
                onReceive("连接错误: \(error.localizedDescription)", true)
            } else {
                print("SSE流正常结束")
                onReceive("", true)
            }
            
            // 清理会话
            self.task = nil
        }
        
        // 处理HTTP响应
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let httpResponse = response as? HTTPURLResponse else {
                print("非HTTP响应")
                completionHandler(.cancel)
                return
            }
            
            print("收到HTTP响应，状态码：\(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                // 允许继续接收数据
                completionHandler(.allow)
            } else {
                print("错误的HTTP状态码：\(httpResponse.statusCode)")
                completionHandler(.cancel)
                onReceive("服务器返回错误：\(httpResponse.statusCode)", true)
            }
        }
        
        // 处理SSE格式的缓冲区
        private func processBuffer() {
            // 将缓冲区转换为字符串
            guard let bufferString = String(data: buffer, encoding: .utf8) else {
                print("无法将数据缓冲区转换为字符串")
                return
            }
            
            // 按行分割处理
            let lines = bufferString.components(separatedBy: "\n")
            var processedBytes = 0
            
            // 处理除最后一行外的所有完整行（最后一行可能不完整）
            for i in 0..<(lines.count - 1) {
                let line = lines[i]
                let lineBytes = line.utf8.count + 1 // +1 for \n
                
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 跳过空行
                if trimmedLine.isEmpty {
                    processedBytes += lineBytes
                    continue
                }
                
                // 检查结束标记
                if trimmedLine.contains("[DONE]") {
                    print("接收到SSE结束标记: \(trimmedLine)")
                    onReceive("", true)
                    buffer.removeAll()
                    return
                }
                
                // 处理数据行
                if trimmedLine.hasPrefix("data: ") {
                    let jsonString = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !jsonString.isEmpty && jsonString != "[DONE]" {
                        do {
                            guard let jsonData = jsonString.data(using: .utf8) else {
                                print("无法将JSON字符串转换为数据: \(jsonString)")
                                processedBytes += lineBytes
                                continue
                            }
                            
                            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                            
                            if let choices = json?["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                print("成功提取到内容片段: '\(content)'")
                                onReceive(content, false)
                            } else {
                                // 这可能是一个没有content的心跳包，正常忽略
                                if let json = json {
                                    print("JSON中没有content字段（可能是心跳包）")
                                }
                            }
                        } catch {
                            print("JSON解析错误: \(error.localizedDescription)")
                            print("问题JSON: \(jsonString)")
                        }
                    }
                }
                
                processedBytes += lineBytes
            }
            
            // 从缓冲区移除已处理的字节
            if processedBytes > 0 && processedBytes <= buffer.count {
                buffer.removeFirst(processedBytes)
                print("从缓冲区移除了 \(processedBytes) 字节，剩余: \(buffer.count) 字节")
            }
        }
    }
    
    /// 聊天补全请求
    func chatCompletion(messages: [LocalChatMessage], enableChainOfThought: Bool = false) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            print("无效的API URL: \(baseURL)/v1/chat/completions")
            throw NSError(domain: "LocalLLMService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无效的API URL"])
        }
        
        print("准备发送聊天请求到: \(url.absoluteString)")
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.7,
            "top_p": 0.95,
            "max_tokens": 2048,
            "stream": false,
            "enable_chain_of_thought": enableChainOfThought
        ]
        
        print("请求体: \(requestBody)")
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 设置更长的超时时间
        request.timeoutInterval = 60
        
        // 发送请求
        do {
            print("发送请求...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("非HTTP响应")
                throw NSError(domain: "LocalLLMService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            print("聊天请求响应状态码: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("响应JSON片段: \(responseString.prefix(200))...")
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    print("API错误: \(errorMessage)")
                    throw NSError(domain: "LocalLLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API错误: \(errorMessage)"])
                }
                print("API请求失败: \(httpResponse.statusCode)")
                throw NSError(domain: "LocalLLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API请求失败: \(httpResponse.statusCode)"])
            }
            
            // 解析响应
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let choices = json?["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("成功解析响应内容，长度: \(content.count)字符")
                    return content
                } else {
                    print("解析响应失败，无法提取内容")
                    throw NSError(domain: "LocalLLMService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "无法解析API响应"])
                }
            } catch {
                print("JSON解析错误: \(error.localizedDescription)")
                throw error
            }
        } catch {
            print("网络请求错误: \(error.localizedDescription)")
            throw error
        }
    }
}

/// 本地DeepSeek模型专用的聊天消息模型，与OpenAI的OpenAIChatMessage区分开
struct LocalChatMessage {
    let role: String  // "system", "user", "assistant"
    let content: String
    
    static func system(_ content: String) -> LocalChatMessage {
        LocalChatMessage(role: "system", content: content)
    }
    
    static func user(_ content: String) -> LocalChatMessage {
        LocalChatMessage(role: "user", content: content)
    }
    
    static func assistant(_ content: String) -> LocalChatMessage {
        LocalChatMessage(role: "assistant", content: content)
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
    let messages: [LocalChatMessage] = [
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