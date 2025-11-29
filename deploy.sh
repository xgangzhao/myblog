#!/bin/bash

# 一键部署 Hexo 博客脚本
# 使用方法: bash deploy.sh

echo "===== 🚀 开始部署 Hexo 博客 ====="

# Step 1: 清理旧文件
echo "🧹 清理缓存和旧文件..."
hexo clean

# Step 2: 生成新文件
echo "📦 生成静态文件..."
hexo generate

# Step 3: 部署到 GitHub Pages
echo "🌍 部署到 GitHub Pages..."
hexo deploy

# Step 4: 完成提示
echo "✅ 部署完成！访问你的博客: https://xgangzhao.github.io"
