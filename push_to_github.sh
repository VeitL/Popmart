#!/bin/bash

# Popmart项目自动推送到GitHub脚本
# 使用方法: ./push_to_github.sh "你的提交信息"

set -e

echo "🚀 开始推送代码到GitHub..."

# 检查是否提供了提交信息
if [ $# -eq 0 ]; then
    echo "❌ 请提供提交信息"
    echo "用法: ./push_to_github.sh \"你的提交信息\""
    exit 1
fi

COMMIT_MESSAGE="$1"

# 检查是否有变更
if [[ -z $(git status --porcelain) ]]; then
    echo "ℹ️  没有检测到代码变更"
    exit 0
fi

echo "📝 添加所有变更文件..."
git add -A

echo "💾 提交变更..."
git commit -m "$COMMIT_MESSAGE"

echo "📤 推送到GitHub..."
git push origin main

echo "✅ 代码已成功推送到 https://github.com/VeitL/Popmart.git"
echo "🎯 提交信息: $COMMIT_MESSAGE"

# 显示最新的提交信息
echo ""
echo "📊 最新提交信息:"
git log --oneline -1 