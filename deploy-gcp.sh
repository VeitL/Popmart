#!/bin/bash

echo "🚀 开始部署到 Google Cloud Run..."

# 检查是否已安装 gcloud CLI
if ! command -v gcloud &> /dev/null; then
    echo "❌ 错误：未安装 gcloud CLI"
    echo "请访问 https://cloud.google.com/sdk/docs/install 安装"
    exit 1
fi

# 设置项目变量
PROJECT_ID=${1:-"your-project-id"}
SERVICE_NAME="popmart-stock-checker"
REGION="asia-northeast1"  # 东京区域，对中国用户延迟较低

echo "📋 配置信息："
echo "  项目ID: $PROJECT_ID"
echo "  服务名: $SERVICE_NAME"
echo "  区域: $REGION"
echo "  源码目录: backend/"

# 确认部署
read -p "确认要部署吗？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消部署"
    exit 1
fi

echo "🔧 设置 gcloud 配置..."
gcloud config set project $PROJECT_ID

echo "🐳 构建并部署到 Cloud Run..."
gcloud run deploy $SERVICE_NAME \
    --source backend \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --port 8080 \
    --memory 1Gi \
    --timeout 300 \
    --max-instances 10 \
    --set-env-vars NODE_ENV=production

if [ $? -eq 0 ]; then
    echo "✅ 部署成功！"
    echo "🌐 您的API URL："
    gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'
    echo ""
    echo "🧪 测试命令："
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)')
    echo "  curl $SERVICE_URL/health"
    echo "  curl '$SERVICE_URL/api/check-stock-puppeteer?productId=1708'"
else
    echo "❌ 部署失败"
    exit 1
fi 