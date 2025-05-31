#!/bin/bash

echo "🚀 Simple deployment to Google Cloud Run..."

cd backend

echo "🐳 Building with simple Dockerfile..."
cp Dockerfile.simple Dockerfile

gcloud run deploy popmart-stock-checker \
    --source . \
    --platform managed \
    --region asia-northeast1 \
    --allow-unauthenticated \
    --port 8080 \
    --memory 512Mi \
    --timeout 300 \
    --max-instances 5 \
    --set-env-vars NODE_ENV=production

if [ $? -eq 0 ]; then
    echo "✅ 部署成功！"
    SERVICE_URL=$(gcloud run services describe popmart-stock-checker --region asia-northeast1 --format 'value(status.url)')
    echo "🌐 服务URL: $SERVICE_URL"
    echo "🧪 测试: curl $SERVICE_URL/health"
else
    echo "❌ 部署失败"
fi 