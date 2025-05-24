# GraceAI 应用的渐进式RAG长期记忆实现方案

## 1. 概述

本文档描述在GraceAI iOS应用中实现"渐进式构建的长期记忆能力"的技术方案。该方案基于检索增强生成(RAG)技术，通过在用户与AI助手交互过程中逐步积累重要信息，构建个性化知识库，从而使AI助手能够"记住"用户的偏好、背景和重要信息。

## 2. RAG基本原理

RAG(检索增强生成)是结合检索系统和生成式AI的混合技术：

1. **检索(Retrieval)**: 从知识库中找到与当前查询相关的信息
2. **增强(Augmentation)**: 将检索到的信息提供给语言模型
3. **生成(Generation)**: 语言模型结合检索信息生成更准确、更个性化的回答

渐进式RAG的特点是知识库最初为空，随着用户交互逐步丰富，形成个性化的长期记忆系统。

## 3. iOS实现架构

### 3.1 整体架构

```
┌─────────────────┐     ┌──────────────────┐     ┌───────────────────┐
│                 │     │                  │     │                   │
│  对话界面(UI)    │ ←→  │  记忆管理系统    │ ←→  │  大语言模型集成    │
│                 │     │                  │     │                   │
└─────────────────┘     └──────────────────┘     └───────────────────┘
                              ↑     ↓
                        ┌──────────────────┐
                        │                  │
                        │  向量数据库      │
                        │                  │
                        └──────────────────┘
```

### 3.2 核心组件

1. **嵌入生成器(EmbeddingGenerator)**
   - 将文本转换为向量表示
   - 可使用轻量级模型本地处理或调用API

2. **记忆存储(MemoryStore)**
   - 管理向量数据库
   - 提供高效检索机制

3. **记忆管理器(MemoryManager)**
   - 决定哪些信息值得记住
   - 处理记忆的添加、检索和遗忘

4. **上下文增强器(ContextEnhancer)**
   - 将检索到的记忆整合到当前对话上下文

## 4. 关键技术实现

### 4.1 记忆结构设计

```swift
struct Memory {
    let id: UUID
    let content: String           // 记忆内容
    let timestamp: Date           // 创建时间
    let embedding: [Float]        // 向量表示
    let importance: Float         // 重要性得分
    let source: MemorySource      // 来源(用户输入/AI回复/系统等)
    let associatedTags: [String]  // 相关标签
}

enum MemorySource {
    case userInput
    case aiResponse
    case systemGenerated
}
```

### 4.2 重要性评估机制

记忆的重要性评估可通过以下几种方式实现：

1. **基于规则的评估**
   - 包含个人信息(姓名、爱好、习惯)的内容权重更高
   - 包含时间、地点、事件等具体信息的内容权重更高
   - 用户明确表达的偏好或不喜欢的内容权重更高

2. **基于模型的评估**
   - 使用小型分类器模型评估内容重要性
   - 或通过调用LLM API评估内容的长期价值

```swift
func evaluateImportance(_ content: String) -> Float {
    var score: Float = 0.0
    
    // 1. 检查是否包含个人信息特征
    if containsPersonalInfo(content) {
        score += 0.3
    }
    
    // 2. 检查是否包含具体事件/时间/地点
    if containsEventInfo(content) {
        score += 0.25
    }
    
    // 3. 检查是否表达了明确的偏好
    if containsPreference(content) {
        score += 0.4
    }
    
    // 4. 考虑内容长度和信息密度
    score += min(0.1, Float(content.count) / 1000.0)
    
    return min(1.0, score)
}
```

### 4.3 向量数据库实现

在iOS中实现向量数据库可采用以下方案：

1. **基于SQLite的实现**

```swift
class SQLiteVectorStore {
    private let db: Connection
    
    init() throws {
        // 初始化SQLite数据库
        db = try Connection("memories.sqlite3")
        
        // 创建表
        try db.run(memories.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(embeddingBlob)  // BLOB类型存储向量
            t.column(importance)
            t.column(source)
        })
    }
    
    // 添加记忆
    func addMemory(_ memory: Memory) throws {
        // 将向量转换为Blob数据
        let embeddingData = Data(bytes: memory.embedding, 
                                count: memory.embedding.count * MemorySize.of(Float.self))
        
        try db.run(memories.insert(
            id <- memory.id.uuidString,
            content <- memory.content,
            timestamp <- memory.timestamp,
            embeddingBlob <- embeddingData,
            importance <- memory.importance,
            source <- memory.source.rawValue
        ))
    }
    
    // 检索相似记忆
    func searchSimilarMemories(embedding: [Float], limit: Int = 5) throws -> [Memory] {
        // 在实际应用中，这里需要实现向量相似度搜索
        // 简单方案可以取出所有向量计算相似度，但不够高效
        // 更好的方案是使用SQLite扩展或自定义索引结构
        
        // 此处为简化示例
        let allMemories = try fetchAllMemories()
        
        return allMemories
            .map { (memory: $0, similarity: cosineSimilarity(embedding, $0.embedding)) }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0.memory }
    }
}
```

2. **分层记忆存储**

可实现短期、中期和长期记忆层级：

```swift
class HierarchicalMemoryStore {
    private var shortTermMemories: [Memory] = []  // 最近对话，内存存储
    private var mediumTermMemories: [Memory] = [] // 重要记忆，内存+持久化
    private let longTermStore: SQLiteVectorStore  // 最重要记忆，完全持久化
    
    // 记忆提升机制
    func promoteMemories() {
        // 将短期记忆中重要性高的提升到中期
        let importantShortTermMemories = shortTermMemories
            .filter { $0.importance > 0.5 && $0.timestamp < Date().addingTimeInterval(-86400) }
        
        mediumTermMemories.append(contentsOf: importantShortTermMemories)
        shortTermMemories.removeAll { importantShortTermMemories.contains($0) }
        
        // 将多次访问的中期记忆提升到长期
        let frequentlyAccessedMemories = mediumTermMemories
            .filter { $0.accessCount > 3 && $0.importance > 0.7 }
        
        for memory in frequentlyAccessedMemories {
            try? longTermStore.addMemory(memory)
        }
        
        mediumTermMemories.removeAll { frequentlyAccessedMemories.contains($0) }
    }
}
```

### 4.4 上下文增强

在向LLM发送请求时，结合检索到的记忆增强提示：

```swift
func generateEnhancedPrompt(userQuery: String, conversation: [Message]) -> String {
    // 1. 为查询生成嵌入
    let queryEmbedding = embeddingGenerator.generateEmbedding(for: userQuery)
    
    // 2. 检索相关记忆
    let relevantMemories = memoryStore.searchSimilarMemories(embedding: queryEmbedding)
    
    // 3. 构建增强提示
    var enhancedPrompt = "以下是用户的一些重要信息，请在回答时考虑这些信息：\n\n"
    
    for memory in relevantMemories {
        enhancedPrompt += "- \(memory.content)\n"
    }
    
    enhancedPrompt += "\n当前对话：\n"
    for message in conversation {
        let role = message.isUser ? "用户" : "助手"
        enhancedPrompt += "\(role): \(message.content)\n"
    }
    
    enhancedPrompt += "\n用户最新问题: \(userQuery)\n"
    
    return enhancedPrompt
}
```

## 5. 资源优化策略

为确保在iOS设备上高效运行，可采用以下优化策略：

1. **选择性记忆**
   - 只存储超过重要性阈值的信息
   - 定期压缩和合并相似记忆

2. **分批处理**
   - 嵌入生成和向量搜索操作在后台线程执行
   - 使用操作队列控制并发

3. **渐进式加载**
   - 应用启动时只加载最重要/最常用的记忆
   - 按需加载其他记忆

4. **记忆遗忘机制**
   - 随时间降低不常访问记忆的重要性
   - 定期清理低于阈值的记忆

## 6. 隐私考虑

1. **本地存储优先**
   - 记忆数据优先存储在设备本地
   - 可选的加密同步到iCloud

2. **用户控制**
   - 提供查看和删除特定记忆的界面
   - 允许用户设置哪些类型信息可被记住

3. **数据最小化**
   - 只存储对提升用户体验必要的信息
   - 避免存储敏感个人数据

## 7. 进一步改进方向

1. **多模态记忆**
   - 支持图像、音频等多模态信息的记忆

2. **主动学习**
   - AI助手主动提问以填补知识空白

3. **情感记忆**
   - 记录并理解用户情感状态和偏好

4. **时间感知**
   - 根据时间背景调整记忆重要性
   - 识别季节性、周期性事件

## 8. 参考实现示例

```swift
class GraceAIMemorySystem {
    private let embeddingGenerator: EmbeddingGenerator
    private let memoryStore: MemoryStore
    private let memoryManager: MemoryManager
    
    init() {
        // 初始化组件
        self.embeddingGenerator = LocalEmbeddingGenerator() // 或APIEmbeddingGenerator()
        self.memoryStore = SQLiteMemoryStore()
        self.memoryManager = MemoryManager(store: memoryStore, 
                                           embeddingGenerator: embeddingGenerator)
    }
    
    // 处理新对话轮次
    func processConversationTurn(userInput: String, aiResponse: String) {
        // 1. 评估并存储用户输入
        if let userMemory = memoryManager.createMemoryIfImportant(
            content: userInput, 
            source: .userInput
        ) {
            memoryStore.addMemory(userMemory)
        }
        
        // 2. 评估并存储AI回复
        if let aiMemory = memoryManager.createMemoryIfImportant(
            content: aiResponse, 
            source: .aiResponse
        ) {
            memoryStore.addMemory(aiMemory)
        }
        
        // 3. 从对话中提取实体和关系
        let entities = EntityExtractor.extractEntities(from: userInput + " " + aiResponse)
        for entity in entities {
            if let entityMemory = memoryManager.createEntityMemory(entity) {
                memoryStore.addMemory(entityMemory)
            }
        }
    }
    
    // 为下一次AI响应增强上下文
    func enhanceContext(for userQuery: String, conversation: [Message]) -> String {
        let relevantMemories = memoryManager.retrieveRelevantMemories(for: userQuery)
        return PromptBuilder.buildEnhancedPrompt(
            userQuery: userQuery,
            conversation: conversation,
            memories: relevantMemories
        )
    }
}
```

## 9. 总结

在iOS应用中实现渐进式RAG长期记忆是完全可行的，即使在资源有限的移动设备上也能高效运行。关键在于精心设计记忆存储结构、采用高效的检索算法、实施智能的记忆管理策略，以及优化资源使用。

这种实现使GraceAI能够随着使用而变得越来越个性化，真正理解并"记住"用户，从而提供更有价值、更贴心的对话体验。 