# 🚀 Render手动配置指南（推荐）

## ❌ 遇到Docker错误？

如果您看到 `open Dockerfile: no such file or directory` 错误，说明Render在尝试使用Docker模式。

**解决方案：直接在Render界面手动配置（更简单！）**

## 🎯 正确的配置步骤

### 1. 删除当前服务
1. 登录 [render.com](https://render.com)
2. 找到您的 `popmart-stock-checker` 服务
3. 点击 "Settings" → "Delete Service"

### 2. 重新创建服务
1. 点击 "New +" → "Web Service"
2. 连接您的GitHub仓库：`https://github.com/VeitL/Popmart`
3. **重要配置**：

```
Service Details:
- Name: popmart-stock-checker
- Region: Oregon (US West)
- Branch: main
- Root Directory: backend
- Runtime: Node
- Build Command: npm install
- Start Command: npm start

Environment Variables:
- NODE_ENV = production
- PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = false
- PUPPETEER_ARGS = --no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage

Advanced:
- Plan: Free
- Auto-Deploy: Yes
```

### 3. 等待部署完成
- 初次部署需要5-10分钟
- Render会自动安装Chromium
- 成功后您的URL就是：`https://popmart-stock-checker.onrender.com`

## 🧪 测试部署

部署成功后，测试这些端点：

```bash
# 1. 基本健康检查
curl https://popmart-stock-checker.onrender.com/health

# 2. 测试简单API
curl https://popmart-stock-checker.onrender.com/api/test

# 3. 测试Puppeteer API（真正的JavaScript执行）
curl https://popmart-stock-checker.onrender.com/api/check-stock-puppeteer?productId=1708
```

## ✅ 成功标志

如果看到以下响应，说明部署成功：

```json
{
  "status": "healthy",
  "timestamp": "2025-05-31T...",
  "puppeteer": "ready"
}
```

## 🔄 更新iOS应用

部署成功后，更新iOS应用配置：

```swift
// Popmart/Services/StockCheckService.swift
private var baseURL: String {
    return UserDefaults.standard.string(forKey: "backendURL") ?? "https://popmart-stock-checker.onrender.com"
}
```

## 💡 为什么手动配置更好？

1. **更可靠**：避免yaml配置错误
2. **更简单**：Render界面直观易懂
3. **更灵活**：可以随时调整配置
4. **自动优化**：Render会自动为Node.js应用配置最佳环境

## 🚨 常见问题

### Q: 构建仍然失败？
A: 确保 "Root Directory" 设置为 `backend`

### Q: Puppeteer无法启动？
A: 检查环境变量，特别是 `PUPPETEER_ARGS`

### Q: 内存不足？
A: 免费版有512MB限制，Puppeteer刚好够用

## 🎉 预期结果

成功部署后，您将获得：
- ✅ 完全免费的Puppeteer支持
- ✅ 真正的JavaScript渲染能力
- ✅ 24/7在线的API服务
- ✅ 每月750小时免费使用时间

立即重新配置，几分钟内就能获得完美的Puppeteer支持！ 