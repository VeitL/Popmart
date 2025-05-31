# Popmart Stock Checker Backend

基于 Vercel + Puppeteer 的 Popmart 商品库存检查后端服务。

## 🚀 快速部署

### 1. 准备工作
```bash
# 安装 Vercel CLI
npm i -g vercel

# 登录 Vercel 账号
vercel login
```

### 2. 部署到 Vercel
```bash
# 在 backend 目录下运行
cd backend
vercel

# 首次部署会询问：
# Set up and deploy? [Y/n] y
# Which scope? [选择你的用户名/团队]
# Link to existing project? [N/y] n
# What's your project's name? popmart-stock-checker
# In which directory is your code located? ./
```

### 3. 获取部署URL
部署完成后会得到类似这样的URL：
```
https://popmart-stock-checker-xxx.vercel.app
```

## 📡 API 接口

### 检查库存状态
```
GET /api/check-stock?productId=1707
```

**参数：**
- `productId` (可选): 产品ID，默认为1707
- `url` (可选): 完整的产品URL

**响应示例：**
```json
{
  "success": true,
  "data": {
    "productId": "1707",
    "productName": "THE-MONSTERS Let's Checkmate Series",
    "inStock": true,
    "stockReason": "找到可用的加入购物车按钮",
    "price": "€89.90",
    "url": "https://www.popmart.com/de/products/1707/...",
    "timestamp": "2025-05-31T15:15:00.000Z",
    "debug": {
      "hasAddToCartButton": true,
      "hasDisabledButton": false,
      "hasSoldOutText": false,
      "buttonText": "In den Warenkorb"
    }
  }
}
```

## 🔧 本地开发

```bash
# 安装依赖
npm install

# 本地运行
vercel dev

# 访问 http://localhost:3000/api/check-stock
```

## 📱 iOS 集成

在 iOS 应用中调用此 API：

```swift
func checkStockStatus(completion: @escaping (Bool) -> Void) {
    let url = URL(string: "https://your-deployment-url.vercel.app/api/check-stock?productId=1707")!
    URLSession.shared.dataTask(with: url) { data, _, error in
        guard let data = data, error == nil else {
            completion(false)
            return
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = json["data"] as? [String: Any],
           let inStock = dataDict["inStock"] as? Bool {
            completion(inStock)
        } else {
            completion(false)
        }
    }.resume()
}
```

## 🛠 技术栈

- **Runtime**: Node.js 18.x
- **Browser**: Puppeteer + Chromium
- **Platform**: Vercel Serverless Functions
- **Memory**: 1024MB
- **Timeout**: 30 seconds

## 📝 注意事项

1. 每次请求会启动一个新的浏览器实例
2. 响应时间通常在 5-15 秒之间
3. Vercel 免费计划有请求限制
4. 建议在 iOS 端实现缓存机制

## 🔄 更新部署

```bash
# 修改代码后重新部署
vercel --prod
``` 