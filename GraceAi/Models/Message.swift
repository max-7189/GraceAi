import Foundation

struct Message: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp = Date()
    
    // 可选状态属性，例如，是否正在处理中，是否正在朗读等
    var isProcessing: Bool = false
    var isSpeaking: Bool = false
} 