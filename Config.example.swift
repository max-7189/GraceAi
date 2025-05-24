import Foundation

// 这是一个配置示例文件
// 请复制此文件为 Config.swift 并填入你的真实配置

struct Config {
    // OpenAI API密钥 - 请替换为你的真实密钥
    static let openAIApiKey = "your-openai-api-key-here"
    
    // 模型设置
    static let useLocalModel = true // 是否使用本地模型
    static let localModelURL = "http://192.168.1.9:8000" // 本地模型服务URL（请更新为你的IP地址）
    
    // OpenAI设置
    static let defaultChatModel = "gpt-4-0125-preview"
    static let defaultTTSVoice = "alloy"
} 