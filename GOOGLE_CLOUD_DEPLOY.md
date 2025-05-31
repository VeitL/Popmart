# 🚀 Google Cloud Run 部署指南

## 📋 前期准备

### 1. 安装 Google Cloud CLI
```bash
# macOS (使用 Homebrew)
brew install google-cloud-sdk

# 或下载安装包
# https://cloud.google.com/sdk/docs/install
```

### 2. 创建 Google Cloud 项目
1. 访问 [Google Cloud Console](https://console.cloud.google.com)
2. 创建新项目或选择现有项目
3. 记下您的项目ID (例如: `my-popmart-project`)

### 3. 启用必要的API
```bash
# 登录
gcloud auth login

# 设置项目
gcloud config set project YOUR_PROJECT_ID

# 启用必要的API
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
```

## 🚀 快速部署

### 方法一：使用自动化脚本
```bash
# 运行部署脚本
./deploy-gcp.sh YOUR_PROJECT_ID
```

### 方法二：手动部署
```bash
cd backend

# 部署到 Cloud Run
gcloud run deploy popmart-stock-checker \
    --source . \
    --platform managed \
    --region asia-northeast1 \
    --allow-unauthenticated \
    --port 8080 \
    --memory 1Gi \
    --timeout 300 \
    --max-instances 10
```

## 🔧 配置说明

### Dockerfile 优化
- ✅ 使用 Alpine Linux 减少镜像大小
- ✅ 预安装 Chromium 支持 Puppeteer
- ✅ 安全的非root用户运行
- ✅ 中文字体支持

### Cloud Run 配置
- **内存**: 1GB (足够运行Puppeteer)
- **超时**: 300秒 (允许复杂爬取操作)
- **最大实例**: 10个 (控制成本)
- **区域**: asia-northeast1 (东京，低延迟)

## 💰 成本估算

### 免费额度 (每月)
- ✅ 200万请求
- ✅ 360,000 GB-秒计算时间
- ✅ 2百万GB出站流量

### 超出免费额度后
- **请求**: $0.40 / 百万请求
- **计算**: $0.00002400 / GB-秒
- **网络**: $0.12 / GB

### 实际使用估算
假设每天检查100次库存，每次3秒：
- **月请求数**: ~3,000 (远低于200万免费额度)
- **计算时间**: ~270 GB-秒 (远低于36万免费额度)
- **结论**: 完全免费！

## 📱 更新iOS应用

部署成功后，更新iOS应用中的后端URL：

```swift
// Popmart/Services/StockCheckService.swift
private var baseURL: String {
    return UserDefaults.standard.string(forKey: "backendURL") ?? 
           "https://popmart-stock-checker-xxx-xx.a.run.app"
}
```

## 🧪 测试部署

```bash
# 获取服务URL
SERVICE_URL=$(gcloud run services describe popmart-stock-checker \
    --region asia-northeast1 --format 'value(status.url)')

# 测试健康检查
curl $SERVICE_URL/health

# 测试Puppeteer API
curl "$SERVICE_URL/api/check-stock-puppeteer?productId=1708"

# 测试简单API
curl "$SERVICE_URL/api/check-stock-simple?productId=1708"
```

## 🔍 监控和调试

### 查看日志
```bash
gcloud run services logs read popmart-stock-checker \
    --region asia-northeast1 --limit 50
```

### 查看服务状态
```bash
gcloud run services describe popmart-stock-checker \
    --region asia-northeast1
```

### 性能优化
1. **预热请求**: 设置定时器避免冷启动
2. **缓存策略**: 在内存中缓存常用数据
3. **并发控制**: 限制同时运行的Puppeteer实例

## 🚨 常见问题

### 1. 构建失败
```bash
# 检查 Dockerfile 语法
docker build -t test-image backend/

# 查看构建日志
gcloud builds log BUILD_ID
```

### 2. Puppeteer无法启动
- ✅ 已在Dockerfile中安装所有必要依赖
- ✅ 设置了正确的可执行路径
- ✅ 配置了中文字体支持

### 3. 内存不足
```bash
# 增加内存配置
gcloud run services update popmart-stock-checker \
    --memory 2Gi --region asia-northeast1
```

### 4. 超时问题
```bash
# 增加超时时间
gcloud run services update popmart-stock-checker \
    --timeout 600 --region asia-northeast1
```

## 🔄 CI/CD 自动化

### GitHub Actions (可选)
创建 `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Cloud Run

on:
  push:
    branches: [ main ]
    paths: [ 'backend/**' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - uses: google-github-actions/setup-gcloud@v0
      with:
        project_id: ${{ secrets.GCP_PROJECT_ID }}
        service_account_key: ${{ secrets.GCP_SA_KEY }}
    
    - run: |
        cd backend
        gcloud run deploy popmart-stock-checker \
          --source . --region asia-northeast1 \
          --allow-unauthenticated
```

## ✅ 部署完成检查清单

- [ ] gcloud CLI 已安装并认证
- [ ] Google Cloud 项目已创建
- [ ] 必要的 API 已启用
- [ ] 服务成功部署到 Cloud Run
- [ ] 健康检查通过
- [ ] Puppeteer API 正常工作
- [ ] iOS 应用已更新后端URL
- [ ] 库存检查功能正常

## 🎉 恭喜！

您的Popmart库存检查器现在运行在Google Cloud Run上，享受：
- ✅ 200万免费请求/月
- ✅ 企业级稳定性和安全性
- ✅ 自动扩缩容
- ✅ 全球CDN加速

有问题随时联系！ 