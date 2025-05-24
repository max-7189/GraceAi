import Foundation

struct Config {
    // 从Info.plist或环境变量读取API密钥
    static let openAIApiKey: String = {
        // 优先从Info.plist读取
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let apiKey = plist["OPENAI_API_KEY"] as? String,
           !apiKey.isEmpty {
            return apiKey
        }
        
        // 其次从环境变量读取
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        
        // 如果都没有，返回空字符串并打印警告
        print("⚠️ 警告: 未找到OpenAI API密钥，请在Info.plist中设置OPENAI_API_KEY")
        return ""
    }()
    
    // 模型设置
    static let useLocalModel = true // 是否使用本地模型
    static let localModelURL = "http://192.168.1.9:8000" // 本地模型服务URL（使用主机真实IP地址）
    
    // OpenAI设置
    static let defaultChatModel = "gpt-4-0125-preview"
    static let defaultTTSVoice = "alloy"
}