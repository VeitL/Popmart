#!/bin/bash

echo "🔧 Popmart URL诊断和修复工具"
echo "=============================================="
echo ""

# 检查当前配置
echo "📋 1. 当前配置检查..."
BACKEND_URL="https://popmart-full-215643545724.asia-northeast1.run.app"
echo "   预期后端URL: ${BACKEND_URL}"

# 检查URL格式
echo "🔍 2. URL格式验证..."
if [[ $BACKEND_URL =~ ^https://[a-zA-Z0-9.-]+\.run\.app$ ]]; then
    echo "   ✅ URL格式正确"
else
    echo "   ❌ URL格式错误"
fi

# 检查网络连接
echo "🌐 3. 网络连接测试..."
if ping -c 1 google.com &> /dev/null; then
    echo "   ✅ 网络连接正常"
else
    echo "   ❌ 网络连接失败"
fi

# 测试后端服务
echo "📡 4. 后端服务测试..."
echo "   检查健康端点..."
HEALTH_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" "${BACKEND_URL}/health" 2>/dev/null)

if [[ $? -eq 0 ]]; then
    HTTP_CODE=$(echo "$HEALTH_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$HEALTH_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')
    
    if [[ $HTTP_CODE -eq 200 ]]; then
        echo "   ✅ 后端服务正常运行"
        echo "   响应: $RESPONSE_BODY" | jq '.' 2>/dev/null || echo "   响应: $RESPONSE_BODY"
    else
        echo "   ❌ 后端服务返回错误: HTTP $HTTP_CODE"
    fi
else
    echo "   ❌ 无法连接到后端服务"
    echo "   可能原因:"
    echo "     - Cloud Run服务可能暂停"
    echo "     - 网络防火墙阻止"
    echo "     - URL配置错误"
fi

echo ""

# 测试特定API
echo "🔄 5. API功能测试..."
echo "   测试库存检查API..."
API_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" "${BACKEND_URL}/api/check-stock?productId=1708" 2>/dev/null)

if [[ $? -eq 0 ]]; then
    HTTP_CODE=$(echo "$API_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$API_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')
    
    if [[ $HTTP_CODE -eq 200 ]]; then
        echo "   ✅ API接口正常"
        echo "$RESPONSE_BODY" | jq '.success, .productId, .stockStatus' 2>/dev/null || echo "   响应: $RESPONSE_BODY"
    else
        echo "   ❌ API返回错误: HTTP $HTTP_CODE"
    fi
else
    echo "   ❌ API调用失败"
fi

echo ""

# iOS应用配置建议
echo "📱 6. iOS应用配置验证..."
echo "   检查StockCheckService.swift中的baseURL..."

# 检查iOS配置文件
if grep -q "popmart-full-215643545724.asia-northeast1.run.app" Popmart/Services/StockCheckService.swift; then
    echo "   ✅ StockCheckService.swift URL配置正确"
else
    echo "   ❌ StockCheckService.swift URL配置可能有问题"
fi

if grep -q "popmart-full-215643545724.asia-northeast1.run.app" Popmart/Views/SettingsView.swift; then
    echo "   ✅ SettingsView.swift URL配置正确"
else
    echo "   ❌ SettingsView.swift URL配置可能有问题"
fi

echo ""

# 故障排除建议
echo "🛠️  7. 故障排除建议："
echo "   如果遇到'无效的后端URL'错误："
echo "   1. 确认网络连接正常"
echo "   2. 重启iOS模拟器"
echo "   3. 清理iOS应用数据"
echo "   4. 重新构建iOS项目"
echo "   5. 检查Cloud Run服务状态"

echo ""

# 修复命令
echo "🔧 8. 快速修复命令："
echo "   重新部署Cloud Run服务："
echo "   gcloud run deploy popmart-full --source backend --region asia-northeast1"
echo ""
echo "   重新构建iOS应用："
echo "   xcodebuild -scheme Popmart -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' clean build"

echo ""
echo "🎯 诊断完成！" 