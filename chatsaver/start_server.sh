#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

echo -e "${YELLOW}启动DeepSeek本地服务...${NC}"

# 检查Python虚拟环境是否存在
if [ ! -d "deepseek-env" ]; then
    echo -e "${RED}错误: Python虚拟环境不存在${NC}"
    echo -e "请先运行: ${GREEN}python -m venv deepseek-env && source deepseek-env/bin/activate && pip install -r requirements.txt${NC}"
    exit 1
fi

# 检查模型是否存在
if [ ! -f "models/deepseek-llm-7b-chat.Q4_K_M.gguf" ]; then
    echo -e "${YELLOW}模型文件不存在，正在下载...${NC}"
    source deepseek-env/bin/activate
    python download_model.py
    
    # 检查下载是否成功
    if [ ! -f "models/deepseek-llm-7b-chat.Q4_K_M.gguf" ]; then
        echo -e "${RED}模型下载失败${NC}"
        exit 1
    fi
fi

# 激活Python虚拟环境并启动服务器
echo -e "${GREEN}激活Python环境并启动API服务...${NC}"
source deepseek-env/bin/activate
python server.py 