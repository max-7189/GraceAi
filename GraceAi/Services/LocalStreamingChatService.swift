import Foundation

/// 本地流式聊天服务
/// 注意：本文件使用的是LocalLLMService.swift中定义的LocalChatMessage结构体
class LocalStreamingChatService {
    private let llmService = LocalLLMService()
    
    // 跟踪响应是否完成
    private(set) var isResponseComplete = false
    private var lastUserMessage = ""
    private var useChainOfThought = true
    
    init() {
        print("LocalStreamingChatService初始化完成")
    }
    
    // 发送消息并获取真实流式返回
    func sendStreamingMessage(
        _ message: String,
        model: String = "local", // 忽略模型参数，使用本地模型
        systemPrompt: String? = nil,
        onReceive: @escaping (String, Bool) -> Void
    ) {
        // 重置完成状态
        isResponseComplete = false
        lastUserMessage = message
        
        print("LocalStreamingChatService - 开始处理消息: \(message)")
        
        // 检查本地服务是否可用
        Task {
            let isServiceAvailable = await llmService.checkHealth()
            print("LocalStreamingChatService - 服务可用性: \(isServiceAvailable)")
            
            if !isServiceAvailable {
                await MainActor.run {
                    print("LocalStreamingChatService - 服务不可用")
                    onReceive("本地AI服务不可用，请确保服务器已启动", true)
                    self.isResponseComplete = true
                }
                return
            }
            
            // 准备聊天消息
            var messages: [LocalChatMessage] = []
            
            // 添加系统提示（如果有）
            if let systemPrompt = systemPrompt {
                messages.append(LocalChatMessage.system(systemPrompt))
            } else {
                // 默认系统提示
                messages.append(LocalChatMessage.system("你是一个有用的AI助手，名叫GraceAI。请用中文回答问题。回答要简洁、准确。"))
            }
            
            // 添加用户消息
            messages.append(LocalChatMessage.user(message))
            
            // 使用流式API
            print("LocalStreamingChatService - 使用流式API请求")
            
            // 包装回调以在主线程中执行
            let mainThreadCallback: (String, Bool) -> Void = { chunk, isComplete in
                DispatchQueue.main.async {
                    if isComplete {
                        print("LocalStreamingChatService - 流式响应完成")
                        self.isResponseComplete = true
                    }
                    onReceive(chunk, isComplete)
                }
            }
            
            // 调用流式API
            self.llmService.streamChatCompletion(
                messages: messages,
                enableChainOfThought: self.useChainOfThought,
                onReceive: mainThreadCallback
            )
        }
    }
    
    // 切换思考链模式
    func toggleChainOfThought() {
        useChainOfThought.toggle()
    }
} 