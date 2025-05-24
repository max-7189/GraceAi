#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import json
import time
from typing import List, Optional, Dict, Any, Iterator
from pydantic import BaseModel, Field
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
import uvicorn
from llama_cpp import Llama

# 模型路径
MODEL_PATH = "models/deepseek-llm-7b-chat.Q4_K_M.gguf"

# 检查模型文件是否存在
if not os.path.exists(MODEL_PATH):
    raise FileNotFoundError(f"模型文件不存在: {MODEL_PATH}，请先运行 download_model.py 下载模型")

# 加载模型（异步加载，避免阻塞服务启动）
print(f"正在加载模型: {MODEL_PATH}...")
model = Llama(
    model_path=MODEL_PATH,
    n_ctx=4096,           # 上下文窗口大小
    n_batch=512,          # 批处理大小
    n_gpu_layers=-1,      # 使用所有可用的GPU层
    verbose=True          # 显示详细日志
)
print("模型加载完成！")

# 创建FastAPI应用
app = FastAPI(title="DeepSeek API Server")

# 添加CORS中间件，允许跨域请求
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 允许所有来源
    allow_credentials=True,
    allow_methods=["*"],  # 允许所有方法
    allow_headers=["*"],  # 允许所有头
)

# 请求模型
class ChatMessage(BaseModel):
    role: str
    content: str

class ChatCompletionRequest(BaseModel):
    messages: List[ChatMessage]
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 0.95
    max_tokens: Optional[int] = 2048
    stream: Optional[bool] = False
    enable_chain_of_thought: Optional[bool] = False

# 响应模型
class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: List[Dict[str, Any]]
    usage: Dict[str, int]

# DeepSeek 提示词模板
def create_prompt(messages: List[ChatMessage], enable_cot: bool = False) -> str:
    prompt = ""
    
    for message in messages:
        if message.role == "system":
            prompt += f"<|system|>\n{message.content}</s>\n"
        elif message.role == "user":
            prompt += f"<|user|>\n{message.content}</s>\n"
        elif message.role == "assistant":
            prompt += f"<|assistant|>\n{message.content}</s>\n"
    
    # 添加助手角色前缀以便模型继续
    prompt += "<|assistant|>\n"
    
    # 如果启用思考链，添加思考链提示词
    if enable_cot:
        prompt += "让我思考一下。\n\n"
    
    return prompt

# 生成SSE流式响应
def generate_stream_response(request: ChatCompletionRequest) -> Iterator[str]:
    """生成SSE格式的流式响应"""
    try:
        # 创建提示词
        prompt = create_prompt(request.messages, request.enable_chain_of_thought)
        
        # 创建唯一ID
        completion_id = f"chatcmpl-{hash(prompt) & 0xffffffff:08x}"
        model_name = os.path.basename(MODEL_PATH)
        created_time = int(time.time())
        
        # 使用流式生成
        stream = model.create_completion(
            prompt=prompt,
            temperature=request.temperature,
            top_p=request.top_p,
            max_tokens=request.max_tokens,
            stop=["</s>", "<|user|>"],  # DeepSeek的停止标记
            echo=False,
            stream=True  # 启用流式生成
        )
        
        print(f"开始流式生成，prompt长度: {len(prompt)}")
        
        # 发送初始的流数据（开始标记）
        start_chunk = {
            "id": completion_id,
            "object": "chat.completion.chunk",
            "created": created_time,
            "model": model_name,
            "choices": [
                {
                    "index": 0,
                    "delta": {"role": "assistant", "content": ""},
                    "finish_reason": None
                }
            ]
        }
        yield f"data: {json.dumps(start_chunk)}\n\n"
        
        # 流式发送生成的文本
        chunk_count = 0
        for chunk in stream:
            chunk_count += 1
            print(f"处理第{chunk_count}个chunk: {chunk}")
            
            if "choices" in chunk and len(chunk["choices"]) > 0:
                choice = chunk["choices"][0]
                print(f"Choice内容: {choice}")
                
                if "text" in choice and choice["text"]:
                    # 直接发送文本块，不再进行累积处理
                    text_content = choice["text"]
                    
                    # 创建增量响应
                    delta_chunk = {
                        "id": completion_id,
                        "object": "chat.completion.chunk",
                        "created": created_time,
                        "model": model_name,
                        "choices": [
                            {
                                "index": 0,
                                "delta": {"content": text_content},
                                "finish_reason": None
                            }
                        ]
                    }
                    
                    print(f"发送流块: '{text_content}'")
                    yield f"data: {json.dumps(delta_chunk)}\n\n"
                
                # 检查是否完成
                if choice.get("finish_reason"):
                    print(f"检测到完成原因: {choice.get('finish_reason')}")
                    # 发送结束标记
                    end_chunk = {
                        "id": completion_id,
                        "object": "chat.completion.chunk",
                        "created": created_time,
                        "model": model_name,
                        "choices": [
                            {
                                "index": 0,
                                "delta": {},
                                "finish_reason": choice["finish_reason"]
                            }
                        ]
                    }
                    yield f"data: {json.dumps(end_chunk)}\n\n"
                    break
            else:
                print(f"Chunk没有choices或choices为空: {chunk}")
        
        # 发送流结束标记
        yield "data: [DONE]\n\n"
        print(f"流式生成完成，总共处理了{chunk_count}个chunk")
        
    except Exception as e:
        print(f"流式生成错误: {e}")
        error_chunk = {
            "error": {
                "message": str(e),
                "type": "internal_error"
            }
        }
        yield f"data: {json.dumps(error_chunk)}\n\n"

# 路由：健康检查
@app.get("/health")
async def health_check():
    return {"status": "ok", "model": os.path.basename(MODEL_PATH)}

# 路由：聊天补全
@app.post("/v1/chat/completions")
async def chat_completion(request: ChatCompletionRequest):
    try:
        # 如果请求流式响应
        if request.stream:
            print("处理流式请求")
            return StreamingResponse(
                generate_stream_response(request),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "X-Accel-Buffering": "no"  # 禁用nginx缓冲
                }
            )
        
        # 非流式响应（原有逻辑）
        print("处理非流式请求")
        prompt = create_prompt(request.messages, request.enable_chain_of_thought)
        
        # 使用模型生成回复
        completion = model.create_completion(
            prompt=prompt,
            temperature=request.temperature,
            top_p=request.top_p,
            max_tokens=request.max_tokens,
            stop=["</s>", "<|user|>"],  # DeepSeek的停止标记
            echo=False
        )
        
        # 整理响应
        response = {
            "id": f"chatcmpl-{hash(prompt) & 0xffffffff:08x}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": os.path.basename(MODEL_PATH),
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": completion["choices"][0]["text"].strip()
                    },
                    "finish_reason": completion["choices"][0]["finish_reason"]
                }
            ],
            "usage": {
                "prompt_tokens": completion["usage"]["prompt_tokens"],
                "completion_tokens": completion["usage"]["completion_tokens"],
                "total_tokens": completion["usage"]["total_tokens"]
            }
        }
        
        return response
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 主函数
if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True) 