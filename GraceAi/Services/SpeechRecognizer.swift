import Foundation
import Speech
import AVFoundation

class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isSpeechDetected = false
    @Published var amplitudes: [CGFloat] = Array(repeating: 0, count: 10)
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var lastTranscriptionTime = Date()
    
    // 检测语音停顿的阈值（秒）
    private let silenceThreshold: TimeInterval = 1.5
    
    // 开始流式语音识别
    func startRecognition(onUpdate: @escaping (String, Bool) -> Void) throws {
        // 重置转录
        transcript = ""
        isSpeechDetected = false
        
        // 1. 确保没有正在进行的识别任务
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // 2. 设置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // 3. 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // 4. 确保请求和识别器有效
        guard let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available"])
        }
        
        // 5. 设置部分结果回调
        recognitionRequest.shouldReportPartialResults = true
        
        // 6. 开始识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                // 更新转录内容
                self.transcript = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // 更新最后转录时间
                self.lastTranscriptionTime = Date()
                
                // 重置静默定时器
                self.resetSilenceTimer(onUpdate: onUpdate)
                
                // 回调通知进度
                onUpdate(self.transcript, isFinal)
            }
            
            // 处理错误或完成状态
            if error != nil || isFinal {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // 确保只在错误情况下调用回调，避免重复
                if error != nil && !isFinal {
                    onUpdate(self.transcript, true)
                }
            }
        }
        
        // 7. 设置音频输入
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // 提供音频数据给识别请求
            self.recognitionRequest?.append(buffer)
            
            // 计算音频振幅并更新UI
            self.updateAmplitudes(buffer: buffer, format: recordingFormat)
        }
        
        // 8. 启动音频引擎
        audioEngine.prepare()
        try audioEngine.start()
        
        // 9. 启动静默检测
        startSilenceDetection(onUpdate: onUpdate)
    }
    
    // 停止识别
    func stopRecognition() {
        // 停止音频引擎
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // 取消之前的识别任务
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // 结束音频请求
        if let recognitionRequest = recognitionRequest {
            recognitionRequest.endAudio()
            self.recognitionRequest = nil
        }
        
        // 取消静默定时器
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    // 更新音频振幅数据
    private func updateAmplitudes(buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        var maxAmplitude: Float = 0.0
        
        // 查找最大振幅
        for i in 0..<frameLength {
            let amplitude = abs(channelData[i])
            if amplitude > maxAmplitude {
                maxAmplitude = amplitude
            }
        }
        
        // 判断是否检测到语音
        let speechThreshold: Float = 0.03
        self.isSpeechDetected = maxAmplitude > speechThreshold
        
        // 更新振幅显示数据
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 将新的振幅添加到数组末尾并移除最旧的
            var newAmplitudes = self.amplitudes
            newAmplitudes.removeFirst()
            newAmplitudes.append(CGFloat(maxAmplitude * 10)) // 放大效果
            
            self.amplitudes = newAmplitudes
        }
    }
    
    // 启动静默检测
    private func startSilenceDetection(onUpdate: @escaping (String, Bool) -> Void) {
        resetSilenceTimer(onUpdate: onUpdate)
    }
    
    // 重置静默定时器
    private func resetSilenceTimer(onUpdate: @escaping (String, Bool) -> Void) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentTime = Date()
            let timeSinceLastTranscription = currentTime.timeIntervalSince(self.lastTranscriptionTime)
            
            // 如果检测到语音，但之后有一段时间没有新的转录更新，且有识别请求正在进行，则认为用户已停止说话
            if self.isSpeechDetected && 
               timeSinceLastTranscription > self.silenceThreshold && 
               !self.transcript.isEmpty && 
               self.recognitionRequest != nil {
                
                // 停止识别，但不重复调用回调，让recognitionTask的完成回调来处理
                self.stopRecognition()
            }
        }
    }
} 