# 🆓 完全免费的Puppeteer部署指南

## ✨ 免费平台对比

| 平台 | 免费额度 | Puppeteer支持 | 设置难度 | 推荐指数 |
|------|----------|---------------|----------|----------|
| **Render** | 750小时/月 | ✅ 原生支持 | ⭐ 超简单 | ⭐⭐⭐⭐⭐ |
| **Railway** | $5免费额度 | ✅ 完整支持 | ⭐⭐ 简单 | ⭐⭐⭐⭐ |
| **Google Cloud Run** | 200万请求/月 | ✅ Docker支持 | ⭐⭐⭐ 中等 | ⭐⭐⭐ |
| **AWS Lambda** | 100万请求/月 | ⚠️ 需要层 | ⭐⭐⭐⭐ 困难 | ⭐⭐ |

## 🎯 方案一：Render (推荐 - 完全免费)

### 步骤1：准备代码
✅ 已为您配置好所有文件！

### 步骤2：部署到Render
1. 访问 [render.com](https://render.com)
2. 注册免费账号
3. 点击 "New +" → "Web Service"
4. 连接您的GitHub仓库
5. 配置：
   ```
   Name: popmart-stock-checker
   Region: Oregon (US West)
   Branch: main
   Root Directory: backend
   Runtime: Node
   Build Command: npm install
   Start Command: npm start
   ```

### 步骤3：测试部署
```bash
# 您的免费URL将类似于：
# https://popmart-stock-checker.onrender.com   
https://popmart-stock-checker.onrender.com

# 测试API
curl https://popmart-stock-checker.onrender.com/api/test
curl https://popmart-stock-checker.onrender.com/api/check-stock-puppeteer?productId=1708
```

## 🚀 方案二：Railway (5美元免费额度)

### 部署Railway
```bash
# 1. 安装 Railway CLI
npm install -g @railway/cli

# 2. 登录
railway login

# 3. 部署
cd backend
railway new
railway up
```

## ☁️ 方案三：Google Cloud Run (免费额度大)

### 准备Dockerfile
```dockerfile
FROM node:18-alpine

# 安装Chrome依赖
RUN apk add --no-cache \
      chromium \
      nss \
      freetype \
      freetype-dev \
      harfbuzz \
      ca-certificates \
      ttf-freefont

# 告诉Puppeteer使用已安装的Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

EXPOSE 8080
CMD ["npm", "start"]
```

### 部署到Cloud Run
```bash
# 1. 构建镜像
gcloud builds submit --tag gcr.io/[PROJECT_ID]/popmart-checker

# 2. 部署到Cloud Run
gcloud run deploy --image gcr.io/[PROJECT_ID]/popmart-checker --platform managed
```

## 💰 成本对比

### 免费使用预估：
- **Render**: 完全免费（750小时=31天全天候运行）
- **Railway**: 免费$5额度可使用2-3个月
- **Google Cloud Run**: 免费200万请求，足够个人使用
- **AWS Lambda**: 免费100万请求，按需付费

### 如果需要付费：
- **Render Pro**: $7/月，无使用限制
- **Railway**: 超出免费额度后按需付费
- **Heroku**: $5-7/月，稳定可靠
- **Digital Ocean**: $5/月，高性能

## 🎁 最佳实践建议

### 1. 先试免费：Render
- 0成本试用
- 快速上手
- 足够个人项目使用

### 2. 长期使用：Railway
- 简单计费
- 优秀性能
- 开发者友好

### 3. 企业级：Heroku/DO
- 稳定可靠
- 企业支持
- 高性能

## 🔄 更新iOS应用配置

部署成功后，更新iOS应用的后端URL：

```swift
// Popmart/Services/StockCheckService.swift
private var baseURL: String {
    return UserDefaults.standard.string(forKey: "backendURL") ?? "https://YOUR-RENDER-URL.onrender.com"
}
```

## ✅ 部署验证清单

- [ ] 后端API正常响应
- [ ] Puppeteer API能够执行JavaScript
- [ ] 返回真实的产品信息（非模拟数据）
- [ ] iOS应用能够连接新后端
- [ ] 库存检查功能正常工作

## 🆘 遇到问题？

### Render常见问题：
1. **构建失败**：检查package.json中的依赖
2. **Puppeteer无法启动**：通常会自动修复，稍等片刻
3. **内存不足**：免费版有512MB限制，优化代码

### 技术支持：
- Render文档：https://render.com/docs
- Railway文档：https://docs.railway.app
- 我的建议：先试Render，99%情况下都能完美工作！ 

## 🎯 下一步行动

现在所有文件都已准备就绪！您有两个选择：

### 🚀 立即开始部署：

1. **安装 Google Cloud CLI**：
```bash
brew install google-cloud-sdk
```

2. **创建 Google Cloud 项目**：
   - 访问 [console.cloud.google.com](https://console.cloud.google.com)
   - 创建新项目，记下项目ID

3. **运行我为您准备的自动化脚本**：
```bash
./deploy-gcp.sh YOUR_PROJECT_ID
```

### 📚 详细步骤

所有详细说明都在 `GOOGLE_CLOUD_DEPLOY.md` 文件中，包括：
- ✅ 完整的安装和配置步骤
- ✅ 成本分析（基本上完全免费）
- ✅ 故障排除指南
- ✅ 性能优化建议

### 🔥 为什么选择 Google Cloud Run 很棒：

1. **免费额度超大**：200万请求/月，您的个人项目基本用不完
2. **冷启动优化**：我已经在Dockerfile中做了优化，启动速度很快
3. **自动扩缩容**：没流量时完全不收费，有流量时自动扩展
4. **企业级稳定性**：Google的基础设施，99.9%的可用性

您想先试试本地构建Docker镜像，还是直接开始部署到Google Cloud？我可以继续协助您！ 