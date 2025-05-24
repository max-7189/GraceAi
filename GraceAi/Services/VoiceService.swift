import Foundation
import AVFoundation

class VoiceService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let apiKey: String
    private let whisperEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let ttsEndpoint = "https://api.openai.com/v1/audio/speech"
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var audioDataBuffer = Data()
    private var wavHeaderData: Data?
    @Published var transcribedText = ""
    @Published var isPlayingAudio = false
    
    var onAudioPlaybackFinished: (() -> Void)?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        print("VoiceService初始化完成，使用API Key: \(String(apiKey.prefix(8)))...")
    }
    
    // 开始录音
    func startRecording(completion: @escaping (Bool) -> Void) {
        print("准备开始录音...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 修改音频会话类别和模式，避免音频反馈
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            let inputNode = audioEngine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            
            // 使用更高质量的录音格式
            let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: hardwareFormat.sampleRate,
                                              channels: 1,
                                              interleaved: false)!
            
            // 创建WAV文件头 - 使用目标采样率16kHz而不是原始采样率
            createWavHeader(sampleRate: 16000.0) // 使用与重采样相同的采样率
            
            // 增加缓冲区大小以提高稳定性
            inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                let audioData = self.convertAudioBufferToData(buffer)
                DispatchQueue.main.async {
                    self.audioDataBuffer.append(audioData)
                }
            }
            
            try audioEngine.start()
            print("录音引擎启动成功，使用硬件采样率：\(hardwareFormat.sampleRate)Hz")
            completion(true)
        } catch {
            print("录音设置失败: \(error.localizedDescription)")
            completion(false)
        }
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
    
    // 停止录音并进行语音识别
    func stopRecording() {
        print("停止录音...")
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil // 释放资源
        
        // 验证音频数据
        guard !audioDataBuffer.isEmpty else {
            print("错误：没有收集到音频数据")
            return
        }
        
        print("收集到的音频数据大小：\(audioDataBuffer.count)字节")
        
        // 更新WAV文件头中的大小信息
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
        
        // 创建音频数据的本地副本用于异步处理
        let audioDataForProcessing = finalAudioData
        let capturedTranscribedText = transcribedText // 捕获当前值
        
        // 发送录音数据进行识别
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let transcription = try await self.transcribeAudio(audioDataForProcessing)
                if transcription.isEmpty {
                    print("警告：识别结果为空")
                }
                
                DispatchQueue.main.async {
                    self.transcribedText = transcription
                }
            } catch {
                print("语音识别失败: \(error.localizedDescription)")
            }
            
            // 清空缓存
            DispatchQueue.main.async {
                self.audioDataBuffer = Data()
                self.wavHeaderData = nil
            }
        }
        print("录音已停止，正在进行语音识别...")
    }
    
    // 发送音频数据到Whisper API进行识别
    // 分段处理音频数据
    private func splitAudioData(_ audioData: Data, maxSizeInBytes: Int = 25 * 1024 * 1024) -> [Data] {
        var audioChunks: [Data] = []
        let headerSize = 44 // WAV文件头大小
        let dataSize = audioData.count - headerSize
        
        // 如果音频数据小于最大限制，直接返回
        if audioData.count <= maxSizeInBytes {
            return [audioData]
        }
        
        // 提取WAV文件头
        let header = audioData.prefix(headerSize)
        let audioContent = audioData.suffix(from: headerSize)
        
        // 计算每个块的大小（确保是偶数，因为我们使用16位采样）
        let maxChunkSize = (maxSizeInBytes - headerSize) & ~1
        let chunksCount = Int(ceil(Double(dataSize) / Double(maxChunkSize)))
        
        for i in 0..<chunksCount {
            var chunk = Data()
            let startIndex = i * maxChunkSize
            let endIndex = min(startIndex + maxChunkSize, dataSize)
            
            // 复制WAV文件头
            chunk.append(header)
            
            // 添加音频数据
            let chunkData = audioContent[startIndex..<endIndex]
            chunk.append(chunkData)
            
            // 更新文件头中的大小信息
            let chunkSize: UInt32 = UInt32(chunk.count - 8)
            let dataChunkSize: UInt32 = UInt32(chunkData.count)
            
            // 更新RIFF块大小
            chunk.withUnsafeMutableBytes { ptr in
                ptr.storeBytes(of: chunkSize.littleEndian, toByteOffset: 4, as: UInt32.self)
            }
            
            // 更新data块大小
            chunk.withUnsafeMutableBytes { ptr in
                ptr.storeBytes(of: dataChunkSize.littleEndian, toByteOffset: 40, as: UInt32.self)
            }
            
            audioChunks.append(chunk)
        }
        
        return audioChunks
    }
    
    // 修改转写方法以支持分段处理
    private func transcribeAudio(_ audioData: Data) async throws -> String {
        print("开始音频转写，音频数据大小: \(audioData.count)字节")
        guard audioData.count > 44 else { // WAV文件头至少44字节
            throw NSError(domain: "VoiceService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "音频数据不完整或为空"])
        }
        
        // 保存音频文件到应用的Documents目录
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "GraceAI_recording_\(timestamp).wav"
        let audioFilePath = documentsPath.appendingPathComponent(fileName)
        
        do {
            try audioData.write(to: audioFilePath)
            print("\n音频文件已保存到Documents目录：\n\(audioFilePath.path)\n")
        } catch {
            print("保存音频文件失败: \(error.localizedDescription)")
        }
        
        // 添加音频数据验证
        print("音频数据前44字节(WAV头)：\(audioData.prefix(44).map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // 分段处理音频数据
        let audioChunks = splitAudioData(audioData)
        var completeTranscription = ""
        
        // 依次处理每个音频段
        for (index, chunk) in audioChunks.enumerated() {
            print("处理第\(index + 1)/\(audioChunks.count)段音频，大小: \(chunk.count)字节")
            
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
            body.append("verbose_json\r\n".data(using: .utf8)!)
            
            // 添加音频文件
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(chunk)
            body.append("\r\n".data(using: .utf8)!)
            
            // 添加结束标记
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "VoiceService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
                }
                
                // 打印响应状态码和响应数据
                print("API响应状态码: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("API响应内容: \(responseString)")
                }
                
                guard httpResponse.statusCode == 200 else {
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? String {
                        throw NSError(domain: "VoiceService", code: httpResponse.statusCode,
                                     userInfo: [NSLocalizedDescriptionKey: "API错误: \(errorMessage)"])
                    }
                    throw NSError(domain: "VoiceService", code: httpResponse.statusCode,
                                 userInfo: [NSLocalizedDescriptionKey: "API请求失败"])
                }
                
                let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
                completeTranscription += whisperResponse.text + " "
                print("第\(index + 1)段音频转写成功，文本长度: \(whisperResponse.text.count)字符")
                
                // 如果不是最后一段，添加适当的延迟以避免API限制
                if index < audioChunks.count - 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 等待1秒
                }
            } catch {
                print("音频转写失败: \(error.localizedDescription)")
                throw error
            }
        }
        
        return completeTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    // 使用TTS API进行语音合成
    func synthesizeSpeech(text: String, voice: String = "alloy") async throws -> Data {
        print("开始语音合成，文本长度: \(text.count)字符，使用声音: \(voice)")
        
        // 文本验证
        guard !text.isEmpty else {
            throw NSError(domain: "VoiceService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "文本内容为空"])
        }
        
        // 创建请求
        var request = URLRequest(url: URL(string: ttsEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建请求体
        let requestBody = TTSRequest(model: "tts-1", input: text, voice: voice)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        // 设置超时
        request.timeoutInterval = 20.0
        
        // 发送请求
        do {
            let (audioData, response) = try await URLSession.shared.data(for: request)
            
            // 验证响应
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "VoiceService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
            }
            
            // 检查状态码
            guard httpResponse.statusCode == 200 else {
                var errorMessage = "API请求失败: HTTP \(httpResponse.statusCode)"
                
                // 尝试解析错误信息
                if let errorData = try? JSONSerialization.jsonObject(with: audioData) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = "API错误: \(message)"
                }
                
                throw NSError(domain: "VoiceService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            // 验证音频数据
            guard audioData.count > 1000 else {
                throw NSError(domain: "VoiceService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "返回的音频数据太小，可能无效: \(audioData.count)字节"])
            }
            
            print("语音合成完成，音频数据大小: \(audioData.count)字节")
            return audioData
        } catch {
            // 抛出更具体的错误
            if let nsError = error as? NSError {
                if nsError.domain == NSURLErrorDomain {
                    throw NSError(domain: "VoiceService", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "网络请求失败: \(nsError.localizedDescription)"])
                }
            }
            throw error
        }
    }
    
    // 播放合成的语音
    func playAudio(data: Data) {
        print("准备播放音频，数据大小: \(data.count)字节")
        
        // 验证音频数据
        guard data.count > 1000 else {
            print("音频数据太小，可能无效: \(data.count)字节")
            self.onAudioPlaybackFinished?()
            return
        }
        
        do {
            // 停止当前播放
            if isPlayingAudio {
                print("停止当前正在播放的音频")
                audioPlayer?.stop()
                audioPlayer = nil
            }
            
            // 设置音频会话
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("音频会话设置成功，类别: \(audioSession.category), 模式: \(audioSession.mode)")
            
            // 创建音频播放器
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            
            guard let player = audioPlayer else {
                print("创建音频播放器失败")
                self.onAudioPlaybackFinished?()
                return
            }
            
            // 准备播放
            if player.prepareToPlay() {
                print("音频播放器准备完成，音频时长: \(player.duration)秒")
            } else {
                print("音频播放器准备失败")
            }
            
            // 设置播放参数
            player.volume = 1.0
            
            // 开始播放
            if player.play() {
                print("音频播放开始")
                isPlayingAudio = true
            } else {
                print("音频播放失败")
                isPlayingAudio = false
                self.onAudioPlaybackFinished?()
            }
        } catch {
            print("音频播放设置错误: \(error.localizedDescription)")
            isPlayingAudio = false
            self.onAudioPlaybackFinished?()
        }
    }
    
    // AVAudioPlayerDelegate方法
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("音频播放完成，成功: \(flag)")
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.onAudioPlaybackFinished?()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("音频解码错误: \(error?.localizedDescription ?? "未知错误")")
        DispatchQueue.main.async {
            self.isPlayingAudio = false
            self.onAudioPlaybackFinished?()
        }
    }
}

// 响应模型
struct WhisperResponse: Codable {
    let text: String
    let words: [WhisperWord]?
}

struct WhisperWord: Codable {
    let word: String
    let start: Double
    let end: Double
}

struct TTSRequest: Codable {
    let model: String
    let input: String
    let voice: String
}