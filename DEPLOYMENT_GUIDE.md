# Popmart库存监控应用 - 完整部署指南

## 📋 项目概述

这是一个用于监控Popmart产品库存状态的iOS应用，包含以下功能：
- 实时检查指定产品的库存状态
- 支持自定义产品URL检查
- 后端API服务（部署在Vercel上）
- 智能故障转移机制
- 本地备用检查机制
- Hermes自动提交服务集成

## 🎯 快速开始

### 1. 环境要求
- **iOS开发**：Xcode 16+，iOS 18.5+
- **后端服务**：Node.js 18+，Vercel CLI
- **网络**：稳定的互联网连接

### 2. 项目结构
```
Popmart/
├── backend/                 # 后端API服务
│   ├── api/
│   │   ├── check-stock.js          # 主要API（使用Puppeteer）
│   │   ├── check-stock-simple.js   # 备用API（使用fetch+cheerio）
│   │   └── test.js                 # 测试端点
│   ├── package.json
│   └── vercel.json
├── Popmart/                # iOS应用
│   ├── Services/
│   │   ├── StockCheckService.swift    # 库存检查服务
│   │   └── ProductMonitor.swift       # 产品监控服务
│   ├── Views/
│   │   ├── ContentView.swift          # 主界面
│   │   └── SettingsView.swift         # 设置页面
│   └── Models/
└── DEPLOYMENT_GUIDE.md
```

## 🚀 部署步骤

### 步骤1：部署后端服务

1. **进入后端目录**
   ```bash
   cd backend
   ```

2. **安装依赖**
   ```bash
   npm install
   ```

3. **部署到Vercel**
   ```bash
   npx vercel --prod
   ```

4. **记录API URL**
   部署成功后，记录返回的生产URL，例如：
   ```
   https://popmart-stock-checker-xxxxxx-your-projects.vercel.app
   ```

### 步骤2：配置iOS应用

1. **打开Xcode项目**
   ```bash
   open Popmart.xcodeproj
   ```

2. **更新后端URL**
   在 `StockCheckService.swift` 中更新默认URL：
   ```swift
   private var baseURL: String {
       return UserDefaults.standard.string(forKey: "backendURL") ?? "YOUR_VERCEL_URL_HERE"
   }
   ```

3. **构建并运行**
   ```bash
   xcodebuild -project Popmart.xcodeproj -scheme Popmart -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build
   ```

## 🔧 API架构说明

### 主要API端点

#### 1. 检查库存（主要方案）
- **端点**：`/api/check-stock`
- **方法**：GET
- **参数**：
  - `productId`：产品ID（默认：1707）
  - `url`：完整产品URL（可选）
- **技术**：Puppeteer + Chromium
- **特点**：功能最全面，但可能受Vercel限制影响

#### 2. 检查库存（备用方案）
- **端点**：`/api/check-stock-simple`
- **方法**：GET
- **参数**：同上
- **技术**：fetch + cheerio HTML解析
- **特点**：轻量级，稳定性更好

#### 3. 测试连接
- **端点**：`/api/test`
- **方法**：GET
- **用途**：验证后端服务状态

### 智能故障转移机制

iOS应用实现了智能的API故障转移：

1. **优先使用**：Puppeteer API（功能最全面）
2. **自动切换**：如果主API失败，自动切换到简单API
3. **用户提示**：在设置页面提供测试按钮

```swift
// StockCheckService.swift 中的实现
func checkStock(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
    // 首先尝试主要的API（使用Puppeteer）
    checkStockWithPuppeteer(productId: productId) { [weak self] result in
        switch result {
        case .success(let data):
            completion(.success(data))
        case .failure(_):
            // 如果主要API失败，尝试简单API
            print("主要API失败，尝试简单API...")
            self?.checkStockSimple(productId: productId, completion: completion)
        }
    }
}
```

## 🛠️ 故障排除指南

### ❌ 问题1：后端API测试失败

**错误信息**: "The data couldn't be read because it is missing"

**原因分析**:
- Vercel上的Chromium库缺少系统依赖
- 网络连接问题  
- 后端服务URL配置错误

**✅ 解决方案**:

1. **验证后端服务状态**
   ```bash
   curl "YOUR_VERCEL_URL/api/test"
   ```
   
   **期望结果**:
   ```json
   {
     "success": true,
     "message": "后端服务正常运行",
     "timestamp": "2025-05-31T14:43:27.159Z"
   }
   ```

2. **测试简单API**
   ```bash
   curl "YOUR_VERCEL_URL/api/check-stock-simple?productId=1707"
   ```
   
   **期望结果**:
   ```json
   {
     "success": true,
     "data": {
       "productId": "1707",
       "productName": "产品名称",
       "inStock": true,
       "stockReason": "未发现售罄标识，推测有库存"
     }
   }
   ```

3. **在iOS应用中测试**
   - 打开设置页面
   - 点击"🔗 测试后端连接"按钮
   - 点击"🚀 测试简单API"按钮
   - 查看测试结果

4. **如果两个API都可用**
   应用会自动使用故障转移机制

### ❌ 问题2：Puppeteer API错误

**错误信息**: "error while loading shared libraries: libnss3.so"

**原因**: Vercel平台上Chromium的已知限制

**✅ 解决方案**:
- **自动处理**：应用会自动切换到简单API
- **简单API**：使用fetch+cheerio，不依赖Chromium
- **功能完整**：简单API提供完整的库存检查功能
- **无需干预**：用户无感知的自动切换

### ❌ 问题3：网络连接问题

**表现**：应用显示"无网络连接"

**✅ 解决方案**:
1. **检查设备网络**：确保WiFi或蜂窝数据正常
2. **验证后端URL**：确保URL格式正确
3. **测试连接**：使用应用内的连接测试功能
4. **重启应用**：如果问题持续，重启应用

### ❌ 问题4：构建错误

**错误信息**: 各种Xcode构建错误

**✅ 解决方案**:
1. **清理构建缓存**
   ```bash
   xcodebuild clean -project Popmart.xcodeproj -scheme Popmart
   ```

2. **检查依赖**
   - 确保所有文件都添加到项目中
   - 检查Swift版本兼容性

3. **重新构建**
   ```bash
   xcodebuild -project Popmart.xcodeproj -scheme Popmart -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build
   ```

## 🔍 调试技巧

### 1. 查看详细日志

**在Xcode中**：
- 运行应用并打开调试控制台
- 观察网络请求和响应日志
- 查看错误堆栈信息

**示例日志**：
```
开始检查产品: https://www.popmart.com/de/products/1707/...
主要API失败，尝试简单API...
页面内容获取成功，开始解析...
解析结果: {"productName": "...", "inStock": true}
```

### 2. 使用浏览器测试API

在浏览器中访问：
```
https://your-vercel-url.vercel.app/api/test
https://your-vercel-url.vercel.app/api/check-stock-simple?productId=1707
```

### 3. 使用Postman测试

创建GET请求到以下端点：
- `{{base_url}}/api/test`
- `{{base_url}}/api/check-stock-simple?productId=1707`
- `{{base_url}}/api/check-stock?productId=1707`

### 4. 检查Vercel部署日志

1. 登录 [Vercel控制台](https://vercel.com)
2. 选择你的项目
3. 查看"Functions"标签页
4. 点击具体的函数查看执行日志

## 📱 iOS应用功能详解

### 主界面功能
1. **快速检查**：输入产品ID进行库存检查
2. **URL检查**：输入完整产品URL进行检查
3. **状态显示**：实时显示网络状态和检查结果
4. **历史记录**：保存最近的检查结果

### 设置页面功能
- **🔧 后端服务配置**：
  - 自定义API服务器URL
  - 保存/恢复配置
  
- **🔗 测试后端连接**：
  - 验证服务器基本连接
  - 检查服务器状态
  
- **🚀 测试简单API**：
  - 测试备用API功能
  - 验证库存检查能力
  
- **📊 测试URL**：
  - 测试具体产品URL
  - 验证解析结果

### 智能提示系统

应用会根据不同情况显示相应提示：

**✅ 成功情况**：
- "✅ 后端API测试成功！"
- "✅ 简单API测试成功！"
- "🎉 简单API工作正常！这意味着应用可以使用备用方案检查库存。"

**❌ 错误情况**：
- "❌ 后端API测试失败" + 详细错误信息和解决建议
- "❌ 简单API测试失败" + 可能原因分析

## 🔄 更新和维护

### 更新后端服务
```bash
cd backend
# 修改代码后重新部署
vercel --prod
# 记录新的URL并更新iOS应用配置
```

### 更新iOS应用
1. 修改Swift代码
2. 测试功能
3. 构建新版本
4. 通过TestFlight或App Store分发

### 定期维护任务
- **每周检查**：API响应时间和错误率
- **每月检查**：依赖包更新
- **季度检查**：Vercel配额使用情况
- **及时响应**：用户反馈和bug报告

## 📈 性能监控

### 建议监控指标
- **API响应时间**：正常应小于10秒
- **成功率**：应保持在95%以上
- **故障转移频率**：监控主API vs 备用API使用比例
- **用户活跃度**：日活跃用户数

### 性能优化建议
1. **缓存结果**：对相同产品的重复查询进行缓存
2. **并发限制**：控制同时进行的检查数量
3. **超时设置**：合理设置网络请求超时时间
4. **错误处理**：优雅处理各种错误情况

## 🎉 部署完成检查清单

在完成部署后，请确认以下项目：

### 后端服务检查
- [ ] Vercel部署成功，获得生产URL
- [ ] `/api/test` 端点正常响应
- [ ] `/api/check-stock-simple` 端点正常工作
- [ ] API响应时间合理（<30秒）

### iOS应用检查
- [ ] 应用成功构建和运行
- [ ] 后端URL配置正确
- [ ] 网络状态显示正常
- [ ] 基本库存检查功能正常
- [ ] 故障转移机制工作正常

### 功能测试检查
- [ ] 设置页面所有测试按钮正常
- [ ] 可以成功检查已知产品
- [ ] 错误情况下显示合理提示
- [ ] 应用界面响应流畅

### 用户体验检查
- [ ] 界面文字清晰易懂
- [ ] 操作流程直观简单
- [ ] 错误提示有帮助性
- [ ] 无明显bug或崩溃

## 🆘 获取帮助

如果遇到问题：

1. **检查本指南**：首先查看故障排除部分
2. **查看日志**：检查Xcode控制台和Vercel日志
3. **测试API**：使用浏览器或Postman独立测试
4. **重新部署**：尝试重新部署后端服务
5. **联系支持**：如果问题持续，请联系技术支持

---

## 🎯 总结

恭喜！你已经成功部署了一个功能完整的Popmart库存监控系统：

✅ **稳定的后端服务**：部署在Vercel上，具有主备API方案  
✅ **智能的iOS应用**：自动故障转移，用户友好界面  
✅ **完整的测试工具**：全面的连接测试和调试功能  
✅ **可靠的故障处理**：自动切换机制，确保服务可用性  

该系统现在可以稳定运行，即使遇到Vercel平台的技术限制也能自动切换到备用方案，为用户提供持续可靠的库存监控服务！

享受你的新应用吧！ 🎉 