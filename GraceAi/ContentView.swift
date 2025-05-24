//
//  ContentView.swift
//  GraceAi
//
//  Created by 赵子源 on 2025/2/10.
//

import SwiftUI
import AVFoundation
import Speech
import Combine

// 可用的TTS声音列表
private let availableVoices = [
    "alloy": "Alloy (中性平衡)",
    "echo": "Echo (清晰中性)",
    "fable": "Fable (温暖叙事)",
    "onyx": "Onyx (深沉有力)",
    "nova": "Nova (友好女声)",
    "shimmer": "Shimmer (明亮积极)"
]

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var selectedVoice = Config.defaultTTSVoice
    @State private var showingVoiceSelector = false
    
    var body: some View {
        ZStack {
            // 主内容区域
            VStack {
                // 消息列表
                ScrollViewReader { scrollView in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(conversationManager.messages) { message in
                                MessageView(message: message)
                                    .id(message.id)
                            }
                            
                            // 如果正在监听，显示用户输入预览
                            if !conversationManager.currentTranscription.isEmpty {
                                MessageView(
                                    message: Message(
                                        content: conversationManager.currentTranscription,
                                        isUser: true,
                                        isProcessing: true
                                    )
                                )
                            }
                            
                            // 如果正在处理，显示处理指示器
                            if conversationManager.state == .processing && !conversationManager.processingMessage.isEmpty {
                                HStack {
                                    Text(conversationManager.processingMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    ProgressView()
                                }
                                .padding()
                                .id("processingIndicator")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: conversationManager.messages.count) { _ in
                        // 消息更新时滚动到底部
                        if let lastMessage = conversationManager.messages.last {
                            withAnimation {
                                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: conversationManager.state) { newState in
                        // 状态更新时滚动到处理指示器
                        if newState == .processing {
                            withAnimation {
                                scrollView.scrollTo("processingIndicator", anchor: .bottom)
                            }
                        }
                    }
                }
                
                // 底部控制区域
                VStack(spacing: 16) {
                    // 状态指示区域
                    HStack {
                        switch conversationManager.state {
                        case .idle:
                            Text("点击麦克风开始对话")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        case .listening:
                            HStack {
                                Text("正在聆听...")
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                                AudioWaveformView(
                                    amplitudes: conversationManager.microphoneAmplitudes,
                                    color: .blue
                                )
                                .frame(width: 60, height: 20)
                            }
                        case .processing:
                            HStack {
                                Text("正在思考...")
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                                ProgressView()
                            }
                        case .speaking:
                            HStack {
                                Text("正在回复...")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                                AudioWaveformView(
                                    amplitudes: conversationManager.speakingAmplitudes,
                                    color: .green
                                )
                                .frame(width: 60, height: 20)
                            }
                        }
                        
                        Spacer()
                        
                        // 本地模型指示
                        HStack(spacing: 8) {
                            Circle()
                                .fill(conversationManager.isUsingLocalModel ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(conversationManager.isUsingLocalModel ? "本地模型" : "在线模型")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        
                        // 语音选择按钮
                        Button(action: {
                            showingVoiceSelector.toggle()
                        }) {
                            Label("语音", systemImage: "waveform")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // 麦克风按钮
                    Button(action: {
                        conversationManager.handleMicrophoneTap()
                    }) {
                        ZStack {
                            Circle()
                                .fill(buttonBackgroundColor)
                                .frame(width: 70, height: 70)
                                .shadow(radius: 3)
                            
                            Image(systemName: buttonIconName)
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    // 添加长按手势切换模型
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 1.0)
                            .onEnded { _ in
                                // 提供触觉反馈
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                
                                // 切换模型
                                conversationManager.toggleModelType()
                                
                                // 显示提示
                                let modelType = conversationManager.isUsingLocalModel ? "本地DeepSeek模型" : "OpenAI在线模型"
                                conversationManager.messages.append(Message(content: "已切换到\(modelType)", isUser: false))
                            }
                    )
                }
                .padding(.bottom)
            }
            
            // 语音选择弹出窗口
            if showingVoiceSelector {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        Text("选择语音")
                            .font(.headline)
                            .padding()
                        
                        Divider()
                        
                        ScrollView {
                            ForEach(Array(availableVoices.keys.sorted()), id: \.self) { key in
                                Button(action: {
                                    selectedVoice = key
                                    showingVoiceSelector = false
                                }) {
                                    HStack {
                                        Text(availableVoices[key] ?? key)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if key == selectedVoice {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding()
                                    .contentShape(Rectangle())
                                }
                                
                                if key != availableVoices.keys.sorted().last {
                                    Divider()
                                }
                            }
                        }
                        .frame(height: 250)
                        
                        Divider()
                        
                        Button(action: {
                            showingVoiceSelector = false
                        }) {
                            Text("取消")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                    )
                    .padding()
                }
                .background(
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            showingVoiceSelector = false
                        }
                )
                .transition(.opacity)
                .animation(.easeInOut, value: showingVoiceSelector)
            }
        }
        .onAppear {
            // 请求必要的权限
            requestPermissions()
        }
    }
    
    // 麦克风按钮背景颜色
    private var buttonBackgroundColor: Color {
        switch conversationManager.state {
        case .idle:
            return .blue
        case .listening:
            return .red
        case .processing:
            return .orange
        case .speaking:
            return .green
        }
    }
    
    // 麦克风按钮图标
    private var buttonIconName: String {
        switch conversationManager.state {
        case .idle:
            return "mic"
        case .listening:
            return "mic.fill"
        case .processing:
            return "ellipsis"
        case .speaking:
            return "waveform"
        }
    }
    
    // 请求权限
    private func requestPermissions() {
        // 请求麦克风权限
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("麦克风权限被拒绝")
            }
        }
        
        // 请求语音识别权限
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                print("语音识别权限被拒绝")
            }
        }
    }
}

// 消息气泡视图
struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if message.isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .padding(.trailing, 10)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(10)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if message.isSpeaking {
                        HStack(spacing: 2) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("正在朗读")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 10)
                    }
                }
                Spacer()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
