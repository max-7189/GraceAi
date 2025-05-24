import Foundation
import AVFoundation

class StreamingSpeechService: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var amplitudes: [CGFloat] = Array(repeating: 0, count: 10)
    
    private let apiKey: String
    private let ttsEndpoint = "https://api.openai.com/v1/audio/speech"
    private var audioPlayers: [AVAudioPlayer] = []
    private var audioQueue: [Data] = []
    private var isProcessingQueue = false
    private var amplitudeUpdateTimer: Timer?
    
    init(apiKey: String = Config.openAIApiKey) {
        self.apiKey = apiKey
        
        // 必须在使用self之前调用super.init()
        super.init()
        
        // 初始化完成后再创建定时器
        self.amplitudeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAmplitudes()
        }
        
        print("StreamingSpeechService初始化完成，使用API Key: \(String(apiKey.prefix(8)))...")
    }
    
    deinit {
        amplitudeUpdateTimer?.invalidate()
    }
    
    // 将文本转换为语音并立即播放
    func speakImmediately(text: String, voice: String = Config.defaultTTSVoice) {
        guard !text.isEmpty else { return }
        
        Task {
            do {
                let audioData = try await synthesizeSpeech(text: text, voice: voice)
                self.playAudioImmediately(data: audioData)
            } catch {
                print("语音合成出错: \(error.localizedDescription)")
            }
        }
    }
    
    // 将文本添加到语音队列中
    func speakInQueue(text: String, voice: String = Config.defaultTTSVoice) {
        guard !text.isEmpty else { return }
        
        Task {
            do {
                let audioData = try await synthesizeSpeech(text: text, voice: voice)
                await MainActor.run {
                    self.audioQueue.append(audioData)
                    self.processAudioQueue()
                }
            } catch {
                print("语音合成出错: \(error.localizedDescription)")
            }
        }
    }
    
    // 语音合成
    func synthesizeSpeech(text: String, voice: String = Config.defaultTTSVoice) async throws -> Data {
        var request = URLRequest(url: URL(string: ttsEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建请求体
        let requestBody = SpeechRequest(
            model: "tts-1",
            input: text,
            voice: voice
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 验证响应
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                throw NSError(domain: "TTSError", code: 1, userInfo: [NSLocalizedDescriptionKey: "TTS API错误: \(errorText)"])
            } else {
                throw NSError(domain: "TTSError", code: 1, userInfo: [NSLocalizedDescriptionKey: "TTS API错误"])
            }
        }
        
        return data
    }
    
    // 直接播放音频
    func playAudioImmediately(data: Data) {
        do {
            // 停止当前播放
            stopAllAudio()
            
            // 设置音频会话
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 创建新播放器
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            
            // 启用音频电平监控
            player.isMeteringEnabled = true
            
            // 存储播放器
            audioPlayers.append(player)
            
            // 播放
            player.play()
            isSpeaking = true
            
        } catch {
            print("播放音频失败: \(error.localizedDescription)")
        }
    }
    
    // 处理音频队列
    private func processAudioQueue() {
        // 如果已经在处理队列或队列为空，则不执行
        guard !isProcessingQueue && !audioQueue.isEmpty else { return }
        
        isProcessingQueue = true
        
        do {
            // 获取并移除队列中的第一个音频
            let audioData = audioQueue.removeFirst()
            
            // 设置音频会话
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // 创建新播放器
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            
            // 启用音频电平监控
            player.isMeteringEnabled = true
            
            // 存储播放器
            audioPlayers.append(player)
            
            // 播放
            player.play()
            isSpeaking = true
            
        } catch {
            print("播放队列音频失败: \(error.localizedDescription)")
            isProcessingQueue = false
            // 尝试处理下一个
            processAudioQueue()
        }
    }
    
    // 停止所有音频播放
    func stopAllAudio() {
        for player in audioPlayers {
            if player.isPlaying {
                player.stop()
            }
        }
        
        audioPlayers.removeAll()
        audioQueue.removeAll()
        isSpeaking = false
        isProcessingQueue = false
    }
    
    // 更新振幅数据（模拟语音波形）
    private func updateAmplitudes() {
        if isSpeaking {
            // 检查是否有正在播放的音频
            let isAnyPlaying = audioPlayers.contains { $0.isPlaying }
            
            if isAnyPlaying {
                // 获取当前播放的音频振幅
                if let player = audioPlayers.first(where: { $0.isPlaying }),
                   player.isPlaying {
                    
                    player.updateMeters() // 更新音频电平
                    
                    // 获取当前音频电平并转换为振幅
                    let amplitude = max(0.05, min(1.0, pow(10, player.averagePower(forChannel: 0) / 20) * 3))
                    
                    // 更新振幅数组
                    DispatchQueue.main.async {
                        var newAmplitudes = self.amplitudes
                        newAmplitudes.removeFirst()
                        newAmplitudes.append(CGFloat(amplitude))
                        self.amplitudes = newAmplitudes
                    }
                }
            } else {
                // 如果没有音频在播放，但isSpeaking仍为true，则重置状态
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.amplitudes = Array(repeating: 0, count: 10)
                }
            }
        } else {
            // 不在说话时，确保振幅为0
            if amplitudes.contains(where: { $0 > 0 }) {
                DispatchQueue.main.async {
                    self.amplitudes = Array(repeating: 0, count: 10)
                }
            }
        }
    }
}

// 扩展AVAudioPlayer委托
extension StreamingSpeechService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // 从列表中移除已完成的播放器
        if let index = audioPlayers.firstIndex(of: player) {
            audioPlayers.remove(at: index)
        }
        
        // 处理队列中的下一个音频
        isProcessingQueue = false
        if !audioQueue.isEmpty {
            processAudioQueue()
        } else if audioPlayers.isEmpty {
            // 如果没有更多音频，更新状态
            isSpeaking = false
        }
    }
}

// 语音合成请求模型
struct SpeechRequest: Codable {
    let model: String
    let input: String
    let voice: String
} 