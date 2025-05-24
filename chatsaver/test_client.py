#!/usr/bin/env python
# -*- coding: utf-8 -*-

import requests
import json
import time

def test_chat_completion(enable_cot=False):
    """测试聊天补全API"""
    
    url = "http://localhost:8000/v1/chat/completions"
    
    # 构建请求数据
    payload = {
        "messages": [
            {
                "role": "system",
                "content": "你是一个有用的AI助手，名叫GraceAI。请用中文回答问题。"
            },
            {
                "role": "user",
                "content": "计算23乘以45等于多少？请解释计算过程。"
            }
        ],
        "temperature": 0.7,
        "top_p": 0.95,
        "max_tokens": 1024,
        "stream": False,
        "enable_chain_of_thought": enable_cot
    }
    
    print(f"发送请求到 {url}...")
    print(f"思考链模式: {'启用' if enable_cot else '禁用'}")
    
    # 发送请求
    try:
        start_time = time.time()
        response = requests.post(url, json=payload)
        end_time = time.time()
        
        # 检查响应状态
        if response.status_code == 200:
            result = response.json()
            
            print(f"\n响应时间: {end_time - start_time:.2f}秒")
            print("\n模型回复:")
            print("=" * 50)
            print(result["choices"][0]["message"]["content"])
            print("=" * 50)
            
            print("\n使用情况:")
            print(f"提示词标记数: {result['usage']['prompt_tokens']}")
            print(f"补全标记数: {result['usage']['completion_tokens']}")
            print(f"总标记数: {result['usage']['total_tokens']}")
        else:
            print(f"请求失败: {response.status_code}")
            print(response.text)
    
    except Exception as e:
        print(f"发生错误: {str(e)}")

if __name__ == "__main__":
    # 检查API服务健康状态
    try:
        health_response = requests.get("http://localhost:8000/health")
        if health_response.status_code == 200:
            print("API服务运行正常！")
            print(f"模型: {health_response.json()['model']}")
            
            # 使用思考链模式
            print("\n========= 测试思考链模式 =========")
            test_chat_completion(enable_cot=True)
            
            # 不使用思考链模式
            print("\n========= 测试标准模式 =========")
            test_chat_completion(enable_cot=False)
        else:
            print(f"API服务健康检查失败: {health_response.status_code}")
    except Exception as e:
        print(f"无法连接到API服务: {str(e)}")
        print("请确保服务器已启动 (python server.py)") 