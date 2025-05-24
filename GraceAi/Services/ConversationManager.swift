import Foundation
import SwiftUI
import Combine

// 会话状态枚举
enum ConversationState {
    case idle
    case listening
    case processing
    case speaking
}

class ConversationManager: ObservableObject {
    // 公开状态
    @Published var state: ConversationState = .idle
    @Published var messages: [Message] = []
    @Published var currentTranscription = ""
    @Published var processingMessage = ""
    @Published var isUsingLocalModel = Config.useLocalModel
    
    // 服务
    private let voiceService = VoiceService(apiKey: Config.openAIApiKey)
    private let speechRecognizer = OpenAISpeechRecognizer(apiKey: Config.openAIApiKey)
    private var chatService: Any // 类型擦除，因为有两种不同的服务类型
    
    // 配置
    private let selectedVoice: String
    private var cancellables = Set<AnyCancellable>()
    
    // TTS相关状态 - 串行化版本
    private var isPlayingAudio = false
    private var audioQueue: [Data] = [] // 音频数据队列
    private var sentenceBuffer = "" // 句子缓冲区
    
    // TTS队列管理
    private var ttsQueue: [String] = [] // 等待TTS的句子队列
    private var isProcessingTTS = false // 是否正在处理TTS
    
    // 初始化
    init(selectedVoice: String = Config.defaultTTSVoice) {
        self.selectedVoice = selectedVoice
        
        // 根据配置选择使用本地模型或OpenAI
        if Config.useLocalModel {
            print("ConversationManager - 初始化为本地DeepSeek模型")
            self.chatService = LocalStreamingChatService()
            self.isUsingLocalModel = true
        } else {
            print("ConversationManager - 初始化为OpenAI模型")
            self.chatService = StreamingChatService()
            self.isUsingLocalModel = false
        }
        
        print("ConversationManager - 初始化完成，使用\(isUsingLocalModel ? "本地DeepSeek模型" : "OpenAI模型")")
    }
    
    // 麦克风按钮点击处理
    func handleMicrophoneTap() {
        switch state {
        case .idle:
            startListening()
        case .listening:
            stopListening()
        case .speaking:
            // 打断AI的回复，开始新的对话
            state = .idle
            startListening()
        case .processing:
            // 正在处理中，不做任何操作
            break
        }
    }
    
    // 开始监听
    private func startListening() {
        do {
            try speechRecognizer.startRecognition { [weak self] transcript, isFinal in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.currentTranscription = transcript
                    
                    if isFinal && !transcript.isEmpty {
                        // 用户说完话了，处理转录文本
                        self.handleFinalTranscription(transcript)
                    }
                }
            }
            
            // 更新状态
            state = .listening
        } catch {
            print("无法启动语音识别: \(error.localizedDescription)")
            // 显示错误消息
            messages.append(Message(content: "无法启动语音识别，请检查麦克风权限。", isUser: false))
        }
    }
    
    // 停止监听
    private func stopListening() {
        speechRecognizer.stopRecognition()
        
        // 如果已经有内容，状态将在回调中处理
        // 如果没有内容，则切换回空闲状态
        if currentTranscription.isEmpty {
            state = .idle
        }
    }
    
    // 处理最终转录文本
    private func handleFinalTranscription(_ transcript: String) {
        // 防止处理空转录
        if transcript.isEmpty {
            state = .idle
            return
        }
        
        // 防止重复处理同一转录（如果最后一条是相同内容的用户消息）
        if let lastMessage = messages.last, lastMessage.isUser && lastMessage.content == transcript {
            return
        }
        
        // 更新状态
        state = .processing
        
        // 添加用户消息
        let userMessage = Message(content: transcript, isUser: true)
        messages.append(userMessage)
        
        // 清空当前转录
        currentTranscription = ""
        processingMessage = "思考中..."
        
        // 创建模拟思考的延迟效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // 发送到AI服务并处理流式响应
            self.sendToAI(transcript)
        }
    }
    
    // 发送到AI服务并接收流式响应
    private func sendToAI(_ text: String) {
        // 重置状态
        sentenceBuffer = ""
        audioQueue.removeAll()
        ttsQueue.removeAll()
        isPlayingAudio = false
        isProcessingTTS = false
        
        // 创建新的AI消息气泡
        let aiMessage = Message(content: "", isUser: false)
        messages.append(aiMessage)
        state = .speaking
        processingMessage = ""
        
        print("ConversationManager - 开始发送文本到AI: '\(text)'")
        
        // 根据使用的服务类型调用不同的方法
        if let localService = chatService as? LocalStreamingChatService {
            localService.sendStreamingMessage(text) { [weak self] partialResponse, isComplete in
                DispatchQueue.main.async {
                    self?.handleStreamingResponse(partialResponse, isComplete)
                }
            }
        } else if let openAIService = chatService as? StreamingChatService {
            openAIService.sendStreamingMessage(text) { [weak self] partialResponse, isComplete in
                DispatchQueue.main.async {
                    self?.handleStreamingResponse(partialResponse, isComplete)
                }
            }
        }
    }
    
    // 处理流式响应 - 修复版本
    private func handleStreamingResponse(_ partialResponse: String, _ isComplete: Bool) {
        // 如果是流结束信号且内容为空，直接返回
        if isComplete && partialResponse.isEmpty {
            print("流式响应结束")
            // 处理剩余缓冲区内容
            processRemainingBuffer()
            return
        }
        
        // 如果有内容，处理文本显示和TTS
        if !partialResponse.isEmpty {
            // 1. 文本显示：直接累积显示
            updateTextDisplay(partialResponse)
            
            // 2. TTS处理：只对新增文本进行句子检测
            sentenceBuffer += partialResponse
            checkAndProcessSentences()
        }
        
        // 如果流完成，处理最后的句子
        if isComplete {
            processRemainingBuffer()
        }
    }
    
    // 更新文本显示
    private func updateTextDisplay(_ newText: String) {
        // 更新最后一条AI消息（我们在sendToAI开始时已经创建了新的AI消息）
        if let lastIndex = messages.indices.last {
            messages[lastIndex].content += newText
        }
    }
    
    // 检测并处理完整句子 - 修复版本
    private func checkAndProcessSentences() {
        let sentenceEndings = ["。", "！", "？", ".", "!", "?"]
        
        while !sentenceBuffer.isEmpty {
            var foundSentence = false
            var earliestRange: Range<String.Index>? = nil
            
            // 找到最早出现的句子结束标记
            for ending in sentenceEndings {
                if let range = sentenceBuffer.range(of: ending) {
                    if earliestRange == nil || range.upperBound < earliestRange!.upperBound {
                        earliestRange = range
                    }
                }
            }
            
            // 如果找到完整句子
            if let range = earliestRange {
                let sentence = String(sentenceBuffer[..<range.upperBound])
                let cleanSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanSentence.isEmpty {
                    print("检测到完整句子: '\(cleanSentence)'")
                    // 发送到TTS
                    processSentenceForTTS(cleanSentence)
                }
                
                // 从缓冲区移除已处理的句子
                sentenceBuffer = String(sentenceBuffer[range.upperBound...])
                foundSentence = true
            }
            
            // 如果没有找到完整句子，跳出循环
            if !foundSentence {
                break
            }
        }
    }
    
    // 处理剩余缓冲区内容（流结束时）
    private func processRemainingBuffer() {
        if !sentenceBuffer.isEmpty {
            let cleanSentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanSentence.isEmpty {
                print("处理最后句子: '\(cleanSentence)'")
                processSentenceForTTS(cleanSentence)
            }
            sentenceBuffer = ""
        }
    }
    
    // 处理单个句子的TTS - 串行化版本
    private func processSentenceForTTS(_ sentence: String) {
        print("将句子添加到TTS队列: '\(sentence)'")
        ttsQueue.append(sentence)
        processNextTTS()
    }
    
    // 处理下一个TTS请求（串行执行）
    private func processNextTTS() {
        // 如果正在处理TTS或队列为空，直接返回
        guard !isProcessingTTS, !ttsQueue.isEmpty else {
            return
        }
        
        // 取出第一个句子
        let sentence = ttsQueue.removeFirst()
        isProcessingTTS = true
        
        print("开始处理TTS，句子: '\(sentence)'，剩余队列: \(ttsQueue.count)")
        
        Task {
            do {
                let audioData = try await voiceService.synthesizeSpeech(text: sentence, voice: selectedVoice)
                await MainActor.run {
                    print("TTS完成，音频大小: \(audioData.count)字节")
                    // 添加到播放队列
                    audioQueue.append(audioData)
                    // 标记TTS处理完成
                    isProcessingTTS = false
                    // 尝试播放当前音频
                    playNextAudio()
                    // 处理下一个TTS
                    processNextTTS()
                }
            } catch {
                await MainActor.run {
                    print("TTS失败: \(error.localizedDescription)")
                    isProcessingTTS = false
                    // 即使失败也要继续处理下一个
                    processNextTTS()
                }
            }
        }
    }
    
    // 播放下一个音频
    private func playNextAudio() {
        // 如果正在播放或队列为空，直接返回
        guard !isPlayingAudio, !audioQueue.isEmpty else {
            return
        }
        
        // 取出第一个音频
        let audioData = audioQueue.removeFirst()
        
        print("开始播放音频，剩余队列: \(audioQueue.count)")
        isPlayingAudio = true
        
        // 设置播放完成回调
        voiceService.onAudioPlaybackFinished = { [weak self] in
            guard let self = self else { return }
            self.isPlayingAudio = false
            print("音频播放完成")
            
            // 播放下一个
            self.playNextAudio()
            
            // 如果队列为空且不在speaking状态，切换到idle
            if self.audioQueue.isEmpty && self.state == .speaking {
                self.state = .idle
                print("所有音频播放完成，状态变为idle")
            }
        }
        
        // 播放音频
        voiceService.playAudio(data: audioData)
    }
    
    // 获取语音波形振幅
    var microphoneAmplitudes: [CGFloat] {
        return speechRecognizer.amplitudes
    }
    
    // 获取语音合成振幅
    var speakingAmplitudes: [CGFloat] {
        return voiceService.isPlayingAudio ? 
            Array(repeating: CGFloat.random(in: 0.3...0.7), count: 10) : 
            Array(repeating: 0, count: 10)
    }
    
    // 切换使用本地模型或OpenAI
    func toggleModelType() {
        isUsingLocalModel.toggle()
        
        // 更新服务
        if isUsingLocalModel {
            chatService = LocalStreamingChatService()
            print("切换到本地DeepSeek模型")
        } else {
            chatService = StreamingChatService()
            print("切换到OpenAI模型")
        }
    }
} 
 
