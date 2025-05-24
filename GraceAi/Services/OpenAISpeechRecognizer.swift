import Foundation
import AVFoundation

class OpenAISpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isSpeechDetected = false
    @Published var amplitudes: [CGFloat] = Array(repeating: 0, count: 10)
    
    private let apiKey: String
    private let whisperEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    private var audioEngine: AVAudioEngine?
    private var audioDataBuffer = Data()
    private var wavHeaderData: Data?
    private var silenceTimer: Timer?
    private var lastTranscriptionTime = Date()
    private var onUpdateCallback: ((String, Bool) -> Void)?
    private var isRecognizing = false
    
    // 增量转录控制参数
    private var lastTranscriptionRequestTime = Date()
    private var minimumTranscriptionInterval: TimeInterval = 2.0 // 最短请求间隔
    private var minimumAudioBufferSize = 16000 // 最小音频数据量约1秒(16kHz采样率)
    private var silenceCounter = 0 // 静音帧计数器
    private var speechFramesCount = 0 // 有语音的帧计数器
    private var consecutiveSilenceFramesThreshold = 15 // 连续静音帧阈值
    private var isIncrementalTranscriptionInProgress = false // 正在进行增量转录
    private var totalAudioDuration: TimeInterval = 0 // 录音总时长
    private let energyLevels: [Float] = [] // 存储能量水平历史
    
    // 错误处理和重试
    private var transcriptionErrorCount = 0
    private let maxTranscriptionErrors = 3
    
    // 检测语音停顿的阈值（秒）
    private let silenceThreshold: TimeInterval = 1.5
    
    init(apiKey: String = Config.openAIApiKey) {
        self.apiKey = apiKey
        print("OpenAISpeechRecognizer初始化完成，使用API Key: \(String(apiKey.prefix(8)))...")
    }
    
    // 开始流式语音识别
    func startRecognition(onUpdate: @escaping (String, Bool) -> Void) throws {
        guard !isRecognizing else {
            print("语音识别已经在进行中")
            return
        }
        
        // 重置状态
        transcript = ""
        isSpeechDetected = false
        audioDataBuffer = Data()
        onUpdateCallback = onUpdate
        silenceCounter = 0
        speechFramesCount = 0
        totalAudioDuration = 0
        lastTranscriptionRequestTime = Date()
        transcriptionErrorCount = 0
        
        // 设置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { 
                throw NSError(domain: "OpenAISpeechRecognizerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建音频引擎"])
            }
            
            let inputNode = audioEngine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            
            // 使用更高质量的录音格式
            let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: hardwareFormat.sampleRate,
                                              channels: 1,
                                              interleaved: false)!
            
            // 创建WAV文件头 - 使用目标采样率16kHz
            createWavHeader(sampleRate: 16000.0)
            
            // 增加缓冲区大小以提高稳定性
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // 转换音频数据
                let audioData = self.convertAudioBufferToData(buffer)
                
                // 更新音频振幅数据和语音活跃度分析
                let isSpeech = self.updateAmplitudesAndDetectSpeech(buffer: buffer)
                
                // 附加到数据缓冲区
                DispatchQueue.main.async {
                    // 更新录音总时长
                    self.totalAudioDuration += Double(buffer.frameLength) / buffer.format.sampleRate
                    
                    // 添加音频数据到缓冲区
                    self.audioDataBuffer.append(audioData)
                    self.lastTranscriptionTime = Date() // 更新最后检测到声音的时间
                    
                    // 更新语音/静音计数
                    if isSpeech {
                        self.speechFramesCount += 1
                        self.silenceCounter = 0
                    } else {
                        self.silenceCounter += 1
                    }
                    
                    // 基于多因素决定是否触发增量转录
                    if self.shouldPerformIncrementalTranscription() {
                        self.performIncrementalTranscription()
                    }
                }
            }
            
            try audioEngine.start()
            isRecognizing = true
            print("流式语音识别引擎启动成功")
            
            // 启动静默检测
            startSilenceDetection()
            
        } catch {
            throw error
        }
    }
    
    // 判断是否应该执行增量转录 - 多因素智能决策
    private func shouldPerformIncrementalTranscription() -> Bool {
        // 如果正在进行转录，不启动新的
        if isIncrementalTranscriptionInProgress {
            return false
        }
        
        // 如果音频数据太少，不转录
        if audioDataBuffer.count < minimumAudioBufferSize {
            return false
        }
        
        // 时间因素：确保与上次请求有足够间隔
        let timeSinceLastRequest = Date().timeIntervalSince(lastTranscriptionRequestTime)
        if timeSinceLastRequest < minimumTranscriptionInterval {
            return false
        }
        
        // 错误控制：如果连续错误过多，延长等待时间
        if transcriptionErrorCount >= maxTranscriptionErrors {
            if timeSinceLastRequest < minimumTranscriptionInterval * 2 {
                return false
            }
        }
        
        // 语音活跃度和静音检测因素
        let hasSufficientSpeech = speechFramesCount > 20 // 至少有一定量的语音帧
        let hasSignificantSilence = silenceCounter >= consecutiveSilenceFramesThreshold // 检测到明显停顿
        
        // 时长因素：录音时间够长
        let hasMinimumDuration = totalAudioDuration >= 1.0 // 至少1秒
        
        // 组合多个因素做决策
        // 1. 录音足够长且时间间隔足够，同时有足够的语音内容
        if hasMinimumDuration && hasSufficientSpeech && timeSinceLastRequest >= minimumTranscriptionInterval {
            return true
        }
        
        // 2. 检测到明显的语音停顿（可能句子结束）
        if hasSufficientSpeech && hasSignificantSilence {
            return true
        }
        
        // 3. 录音时间很长（积累了大量数据）
        if totalAudioDuration > 5.0 && timeSinceLastRequest >= minimumTranscriptionInterval {
            return true
        }
        
        return false
    }
    
    // 创建WAV文件头
    private func createWavHeader(sampleRate: Double) {
        var header = Data()
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let bytesPerSample = bitsPerSample / 8
        
        // RIFF Chunk
        header.append("RIFF".data(using: .utf8)!) // ChunkID (4字节)
        header.append(Data(repeating: 0, count: 4)) // ChunkSize (4字节，稍后更新)
        header.append("WAVE".data(using: .utf8)!) // Format (4字节)
        
        // fmt Chunk
        header.append("fmt ".data(using: .utf8)!) // Subchunk1ID (4字节)
        withUnsafeBytes(of: UInt32(16).littleEndian) { header.append(Data($0)) } // Subchunk1Size (4字节)
        withUnsafeBytes(of: UInt16(1).littleEndian) { header.append(Data($0)) } // AudioFormat, PCM = 1 (2字节)
        withUnsafeBytes(of: numChannels.littleEndian) { header.append(Data($0)) } // NumChannels (2字节)
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { header.append(Data($0)) } // SampleRate (4字节)
        
        // ByteRate = SampleRate * NumChannels * BitsPerSample/8
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bytesPerSample)
        withUnsafeBytes(of: byteRate.littleEndian) { header.append(Data($0)) } // ByteRate (4字节)
        
        // BlockAlign = NumChannels * BitsPerSample/8
        let blockAlign = numChannels * bytesPerSample
        withUnsafeBytes(of: blockAlign.littleEndian) { header.append(Data($0)) } // BlockAlign (2字节)
        withUnsafeBytes(of: bitsPerSample.littleEndian) { header.append(Data($0)) } // BitsPerSample (2字节)
        
        // data Chunk
        header.append("data".data(using: .utf8)!) // Subchunk2ID (4字节)
        header.append(Data(repeating: 0, count: 4)) // Subchunk2Size (4字节，稍后更新)
        
        wavHeaderData = header
    }
    
    // 将AudioBuffer转换为Data，并进行重采样
    private func convertAudioBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        // 创建重采样引擎
        let targetSampleRate: Double = 16000.0 // Whisper API要求的采样率
        let converter = AVAudioConverter(from: buffer.format, to: AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                                     sampleRate: targetSampleRate,
                                                                     channels: 1,
                                                                     interleaved: false)!)!
        
        // 计算目标帧数，确保精确转换
        let ratio = targetSampleRate / buffer.format.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        // 创建目标PCM缓冲区
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                                frameCapacity: targetFrameCount) else {
            print("创建目标PCM缓冲区失败")
            return Data()
        }
        targetBuffer.frameLength = targetFrameCount
        
        // 执行重采样，使用高质量转换
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        let conversionSuccess = converter.convert(to: targetBuffer,
                                                error: &error,
                                                withInputFrom: inputBlock)
        
        if conversionSuccess != .haveData {
            print("重采样失败: \(error?.localizedDescription ?? "未知错误")")
            return Data()
        }
        
        // 获取音频数据
        let channels = UnsafeBufferPointer(start: targetBuffer.floatChannelData, count: 1)
        let frames = UnsafeBufferPointer(start: channels[0], count: Int(targetBuffer.frameLength))
        
        // 转换音频采样数据为16位整数
        var pcmData = Data()
        for frame in frames {
            let clampedSample = max(-1.0, min(1.0, frame))
            let intSample = Int16(clampedSample * 32767.0)
            withUnsafeBytes(of: intSample.littleEndian) { pcmData.append(contentsOf: $0) }
        }
        
        return pcmData
    }
    
    // 更新音频振幅数据并检测是否有语音
    private func updateAmplitudesAndDetectSpeech(buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        let frameLength = Int(buffer.frameLength)
        
        var maxAmplitude: Float = 0.0
        var energySum: Float = 0.0
        
        // 查找最大振幅和计算能量
        for i in 0..<frameLength {
            let amplitude = abs(channelData[i])
            energySum += amplitude * amplitude
            if amplitude > maxAmplitude {
                maxAmplitude = amplitude
            }
        }
        
        // 计算平均能量
        let avgEnergy = energySum / Float(frameLength)
        
        // 判断是否检测到语音（使用更复杂的判断逻辑）
        let speechThreshold: Float = 0.03
        let energyThreshold: Float = 0.001
        let isSpeechDetected = maxAmplitude > speechThreshold || avgEnergy > energyThreshold
        
        self.isSpeechDetected = isSpeechDetected
        
        // 更新振幅显示数据
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 将新的振幅添加到数组末尾并移除最旧的
            var newAmplitudes = self.amplitudes
            newAmplitudes.removeFirst()
            newAmplitudes.append(CGFloat(maxAmplitude * 10)) // 放大效果
            
            self.amplitudes = newAmplitudes
        }
        
        return isSpeechDetected
    }
    
    // 执行增量转录
    private func performIncrementalTranscription() {
        guard isRecognizing, !audioDataBuffer.isEmpty, !isIncrementalTranscriptionInProgress else { return }
        
        // 设置标志，防止重复请求
        isIncrementalTranscriptionInProgress = true
        
        // 创建WAV文件
        guard let headerData = wavHeaderData else {
            print("错误：WAV文件头未创建")
            isIncrementalTranscriptionInProgress = false
            return
        }
        
        // 创建WAV文件头的本地副本
        var finalAudioData = headerData
        let audioDataSize = UInt32(audioDataBuffer.count)
        let totalFileSize = UInt32(finalAudioData.count + audioDataBuffer.count)
        
        // 更新RIFF块大小
        finalAudioData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: (totalFileSize - 8).littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        
        // 更新data块大小
        finalAudioData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: audioDataSize.littleEndian, toByteOffset: 40, as: UInt32.self)
        }
        
        // 合并WAV文件头和音频数据
        finalAudioData.append(audioDataBuffer)
        
        // 更新最后请求时间
        lastTranscriptionRequestTime = Date()
        
        // 发送给OpenAI API进行转录
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let transcription = try await self.transcribeAudio(finalAudioData)
                
                DispatchQueue.main.async {
                    // 重置错误计数
                    self.transcriptionErrorCount = 0
                    
                    // 更新转录文本
                    if !transcription.isEmpty {
                        self.transcript = transcription
                        
                        // 通知回调
                        self.onUpdateCallback?(transcription, false)
                    }
                    
                    // 完成转录，重置标志
                    self.isIncrementalTranscriptionInProgress = false
                }
            } catch {
                print("增量转录失败: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    // 增加错误计数
                    self.transcriptionErrorCount += 1
                    
                    // 重置标志以允许后续尝试
                    self.isIncrementalTranscriptionInProgress = false
                    
                    // 如果错误太多，增加请求间隔
                    if self.transcriptionErrorCount >= self.maxTranscriptionErrors {
                        self.minimumTranscriptionInterval = min(5.0, self.minimumTranscriptionInterval * 1.5)
                        print("增加请求间隔至 \(self.minimumTranscriptionInterval)秒，由于连续错误")
                    }
                }
            }
        }
    }
    
    // 停止识别
    func stopRecognition() {
        guard isRecognizing else { return }
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // 确保进行最终的转录
        processFinalTranscription()
        
        isRecognizing = false
    }
    
    // 处理最终转录
    private func processFinalTranscription() {
        guard !audioDataBuffer.isEmpty else {
            // 如果没有音频数据，直接通知完成
            DispatchQueue.main.async {
                self.onUpdateCallback?(self.transcript, true)
            }
            return
        }
        
        // 创建WAV文件
        guard let headerData = wavHeaderData else {
            print("错误：WAV文件头未创建")
            return
        }
        
        // 创建WAV文件头的本地副本
        var finalAudioData = headerData
        let audioDataSize = UInt32(audioDataBuffer.count)
        let totalFileSize = UInt32(finalAudioData.count + audioDataBuffer.count)
        
        // 更新RIFF块大小
        finalAudioData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: (totalFileSize - 8).littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        
        // 更新data块大小
        finalAudioData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: audioDataSize.littleEndian, toByteOffset: 40, as: UInt32.self)
        }
        
        // 合并WAV文件头和音频数据
        finalAudioData.append(audioDataBuffer)
        
        // 发送给OpenAI API进行转录
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let transcription = try await self.transcribeAudio(finalAudioData)
                
                DispatchQueue.main.async {
                    // 更新转录文本
                    if !transcription.isEmpty {
                        self.transcript = transcription
                    }
                    
                    // 通知回调完成
                    self.onUpdateCallback?(self.transcript, true)
                    
                    // 清空缓存
                    self.audioDataBuffer = Data()
                    self.wavHeaderData = nil
                }
            } catch {
                print("最终转录失败: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    // 通知回调完成，即使有错误
                    self.onUpdateCallback?(self.transcript, true)
                    
                    // 清空缓存
                    self.audioDataBuffer = Data()
                    self.wavHeaderData = nil
                }
            }
        }
    }
    
    // 启动静默检测
    private func startSilenceDetection() {
        silenceTimer?.invalidate()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecognizing else { return }
            
            let currentTime = Date()
            let timeSinceLastTranscription = currentTime.timeIntervalSince(self.lastTranscriptionTime)
            
            // 如果检测到语音，但之后有一段时间没有新的转录更新，则认为用户已停止说话
            if self.isSpeechDetected && 
               timeSinceLastTranscription > self.silenceThreshold && 
               !self.audioDataBuffer.isEmpty {
                
                print("检测到静默，停止识别")
                self.stopRecognition()
            }
        }
    }
    
    // 发送音频数据到Whisper API进行识别
    private func transcribeAudio(_ audioData: Data) async throws -> String {
        var request = URLRequest(url: URL(string: whisperEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        // 添加model参数
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // 添加language参数，指定语言为中文
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("zh\r\n".data(using: .utf8)!)
        
        // 添加response_format参数
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // 添加音频文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加结束标记
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "OpenAISpeechRecognizerError", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorJson["error"] as? String {
                    throw NSError(domain: "OpenAISpeechRecognizerError", code: httpResponse.statusCode,
                                 userInfo: [NSLocalizedDescriptionKey: "API错误: \(errorMessage)"])
                }
                throw NSError(domain: "OpenAISpeechRecognizerError", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "API请求失败"])
            }
            
            struct WhisperResponse: Decodable {
                let text: String
            }
            
            let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
            return whisperResponse.text
        } catch {
            throw error
        }
    }
} 