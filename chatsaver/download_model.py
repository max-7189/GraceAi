#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import subprocess
import sys

def download_model():
    """
    下载DeepSeek v2 GGUF模型
    """
    print("开始下载DeepSeek v2 GGUF模型...")
    
    # 由于原始模型太大，我们选择使用deepseek-llm-7b-chat的Q4量化版本作为示例
    # 实际项目中可以根据需要选择合适的模型和量化版本
    model_url = "https://huggingface.co/TheBloke/deepseek-llm-7b-chat-GGUF/resolve/main/deepseek-llm-7b-chat.Q4_K_M.gguf"
    output_path = "models/deepseek-llm-7b-chat.Q4_K_M.gguf"
    
    # 确保目录存在
    os.makedirs("models", exist_ok=True)
    
    # 检查文件是否已存在
    if os.path.exists(output_path):
        print(f"模型文件已存在: {output_path}")
        return output_path
    
    # 下载模型
    try:
        print(f"正在下载模型，这可能需要一些时间...")
        # 使用curl下载
        subprocess.run([
            "curl", "-L", model_url, 
            "-o", output_path
        ], check=True)
        
        # 验证文件是否成功下载
        if os.path.exists(output_path) and os.path.getsize(output_path) > 1000000:  # 大于1MB
            print(f"模型下载成功！保存路径: {output_path}")
            return output_path
        else:
            print("下载似乎成功，但文件大小异常")
            return None
    except Exception as e:
        print(f"模型下载失败: {str(e)}")
        return None

if __name__ == "__main__":
    download_model() 