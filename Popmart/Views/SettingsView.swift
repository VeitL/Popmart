import SwiftUI

struct SettingsView: View {
    @ObservedObject var emailService: EmailService
    @ObservedObject var productMonitor: ProductMonitor
    @ObservedObject var hermesService: HermesService
    @StateObject private var stockCheckService = StockCheckService()
    @State private var testURL = "https://www.popmart.com/de/products/1707/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll"
    @State private var testResult = ""
    @State private var isTestingURL = false
    @State private var backendURL = "https://popmart-stock-checker-aiu9amdzm-nion119-gmailcoms-projects.vercel.app"
    
    var body: some View {
        NavigationView {
            Form {
                // 后端服务配置
                Section(header: Text("🔧 后端服务配置").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("后端服务URL:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("输入后端服务URL", text: $backendURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button("保存配置") {
                            // 更新服务配置
                            UserDefaults.standard.set(backendURL, forKey: "backendURL")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("🔗 测试后端连接") {
                            testBackendConnection()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(backendURL.isEmpty)
                        
                        Button("🚀 测试简单API") {
                            testSimpleAPI()
                        }
                        .buttonStyle(.bordered)
                        .disabled(backendURL.isEmpty)
                        
                        // 网络状态指示器
                        HStack {
                            Circle()
                                .fill(stockCheckService.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(stockCheckService.isConnected ? "网络已连接" : "网络未连接")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // URL测试区域
                Section(header: Text("🔍 URL解析测试").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("测试URL:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("输入要测试的URL", text: $testURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        HStack {
                            Button(action: {
                                testURL = "https://www.popmart.com/de/products/1707/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll"
                            }) {
                                Text("使用测试URL")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                        
                        VStack(spacing: 8) {
                            // 推荐的API测试按钮
                            Button("🚀 测试后端API (推荐)") {
                                testBackendAPI()
                            }
                            .disabled(isTestingURL || !stockCheckService.isConnected)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            
                            // 传统测试按钮
                            Button("📱 本地测试 (旧方法)") {
                                testLocalMethod()
                            }
                            .disabled(testURL.isEmpty || isTestingURL)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                        
                        // 加载状态指示器
                        if stockCheckService.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("正在检查库存...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 测试结果显示
                if !testResult.isEmpty {
                    Section(header: Text("📊 测试结果").font(.headline)) {
                        ScrollView {
                            Text(testResult)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        
                        Button("复制结果") {
                            UIPasteboard.general.string = testResult
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 最后检查结果
                if let lastResult = stockCheckService.lastCheckResult {
                    Section(header: Text("📈 最新检查结果").font(.headline)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("商品名称:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastResult.productName)
                                    .font(.caption)
                                    .bold()
                            }
                            
                            HStack {
                                Text("库存状态:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack {
                                    Circle()
                                        .fill(lastResult.inStock ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(lastResult.inStock ? "有货" : "缺货")
                                        .font(.caption)
                                        .foregroundColor(lastResult.inStock ? .green : .red)
                                        .bold()
                                }
                            }
                            
                            HStack {
                                Text("价格:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastResult.price)
                                    .font(.caption)
                                    .bold()
                            }
                            
                            HStack {
                                Text("检查时间:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatTimestamp(lastResult.timestamp))
                                    .font(.caption)
                            }
                            
                            Text("原因: \(lastResult.stockReason)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 错误信息显示
                if let errorMessage = stockCheckService.errorMessage {
                    Section(header: Text("⚠️ 错误信息").font(.headline)) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("邮件通知") {
                    Toggle("启用邮件通知", isOn: $emailService.emailSettings.isEnabled)
                    
                    TextField("收件邮箱", text: $emailService.emailSettings.recipientEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                }
                
                Section("监控统计") {
                    HStack {
                        Text("监控商品数量")
                        Spacer()
                        Text("\(productMonitor.products.count)")
                    }
                    
                    HStack {
                        Text("总日志条数")
                        Spacer()
                        Text("\(productMonitor.monitorLogs.count)")
                    }
                    
                    HStack {
                        Text("当前状态")
                        Spacer()
                        Text(productMonitor.isAnyMonitoring ? "监控中" : "已停止")
                            .foregroundColor(productMonitor.isAnyMonitoring ? .green : .gray)
                    }
                }
                
                Section("Hermes表格") {
                    HStack {
                        Text("表格状态")
                        Spacer()
                        Text(hermesService.formData.isEnabled ? "已启用" : "已禁用")
                            .foregroundColor(hermesService.formData.isEnabled ? .green : .gray)
                    }
                    
                    HStack {
                        Text("提交次数")
                        Spacer()
                        Text("\(hermesService.formData.submitCount)")
                    }
                    
                    HStack {
                        Text("最后提交")
                        Spacer()
                        if let lastSubmitted = hermesService.formData.lastSubmitted {
                            Text(DateFormatter.localizedString(from: lastSubmitted, dateStyle: .short, timeStyle: .short))
                        } else {
                            Text("从未提交")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("应用信息") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("3.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("开发者")
                        Spacer()
                        Text("Guanchenuous")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // 加载保存的后端URL
            if let savedURL = UserDefaults.standard.string(forKey: "backendURL") {
                backendURL = savedURL
            }
        }
    }
    
    // MARK: - 私有方法
    
    private func testBackendConnection() {
        guard !backendURL.isEmpty else { return }
        
        isTestingURL = true
        testResult = "正在测试后端连接..."
        
        guard let url = URL(string: "\(backendURL)/api/test") else {
            testResult = "❌ 无效的后端URL"
            isTestingURL = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isTestingURL = false
                
                if let error = error {
                    self.testResult = """
                    ❌ 后端连接测试失败
                    
                    错误信息: \(error.localizedDescription)
                    
                    💡 可能的原因：
                    • 后端服务URL不正确
                    • 网络连接问题
                    • 后端服务暂时不可用
                    
                    🔧 建议检查：
                    1. 验证后端服务URL是否正确
                    2. 检查网络连接状态
                    3. 稍后重试
                    """
                    return
                }
                
                guard let data = data else {
                    self.testResult = "❌ 没有收到响应数据"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool,
                       success {
                        let message = json["message"] as? String ?? "未知消息"
                        let timestamp = json["timestamp"] as? String ?? "未知时间"
                        
                        self.testResult = """
                        ✅ 后端连接测试成功！
                        
                        📡 服务状态：正常运行
                        💬 响应消息：\(message)
                        🕐 响应时间：\(self.formatTimestamp(timestamp))
                        
                        🎉 后端服务可以正常访问，但Puppeteer功能可能仍有问题。
                        """
                    } else {
                        self.testResult = "❌ 后端服务返回错误响应"
                    }
                } catch {
                    self.testResult = "❌ 解析响应数据失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func testBackendAPI() {
        guard !testURL.isEmpty else { return }
        
        isTestingURL = true
        testResult = "正在调用后端API..."
        
        // 直接使用简单API测试，避免Puppeteer问题
        guard let encodedURL = testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(backendURL)/api/check-stock-simple?url=\(encodedURL)") else {
            testResult = "❌ 无效的URL格式"
            isTestingURL = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isTestingURL = false
                
                if let error = error {
                    self.testResult = """
                    ❌ 后端API测试失败
                    
                    错误信息: \(error.localizedDescription)
                    
                    💡 可能的原因：
                    • 后端服务URL配置错误
                    • 网络连接问题
                    • 后端服务暂时不可用
                    • 产品URL格式不正确
                    
                    🔧 建议检查：
                    1. 验证后端服务URL是否正确
                    2. 检查网络连接状态
                    3. 尝试使用标准测试URL
                    """
                    return
                }
                
                guard let data = data else {
                    self.testResult = "❌ 没有收到响应数据"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let success = json["success"] as? Bool, success {
                            let stockData = json["data"] as? [String: Any] ?? [:]
                            let productId = stockData["productId"] as? String ?? "未知"
                            let productName = stockData["productName"] as? String ?? "未知"
                            let inStock = stockData["inStock"] as? Bool ?? false
                            let stockReason = stockData["stockReason"] as? String ?? "未知"
                            let price = stockData["price"] as? String ?? "未知"
                            let timestamp = stockData["timestamp"] as? String ?? "未知"
                            let debugInfo = stockData["debug"] as? [String: Any] ?? [:]
                            
                            self.testResult = """
                            ✅ 后端API测试成功！
                            
                            📦 商品信息：
                            • 商品ID: \(productId)
                            • 商品名称: \(productName)
                            • 库存状态: \(inStock ? "✅ 有货" : "❌ 缺货")
                            • 价格: \(price)
                            • 检查时间: \(self.formatTimestamp(timestamp))
                            
                            📋 详细信息：
                            • 状态原因: \(stockReason)
                            • 请求URL: \(self.testURL)
                            
                            🔍 调试信息：
                            \(debugInfo["hasAddToCartButton"] as? Bool == true ? "• 找到加入购物车按钮" : "• 未找到加入购物车按钮")
                            \(debugInfo["hasDisabledButton"] as? Bool == true ? "• 找到禁用按钮" : "• 未找到禁用按钮")
                            \(debugInfo["hasSoldOutText"] as? Bool == true ? "• 找到售罄文本" : "• 未找到售罄文本")
                            \((debugInfo["buttonText"] as? String)?.isEmpty == false ? "• 按钮文本: \(debugInfo["buttonText"] as? String ?? "")" : "• 无按钮文本")
                            
                            🎉 API工作正常，使用简单解析方案！
                            """
                        } else {
                            let errorMsg = json["error"] as? String ?? "未知错误"
                            self.testResult = """
                            ❌ 后端API返回错误
                            
                            错误信息: \(errorMsg)
                            
                            这可能是网站结构变化或反爬措施导致的。
                            """
                        }
                    } else {
                        self.testResult = "❌ 无法解析API响应"
                    }
                } catch {
                    self.testResult = "❌ 解析响应数据失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func testLocalMethod() {
        guard !testURL.isEmpty else { return }
        
        isTestingURL = true
        testResult = "正在调用iOS服务检查..."
        
        Task {
            do {
                let result = try await stockCheckService.checkStockForURL(testURL)
                
                await MainActor.run {
                    let statusIcon = result.inStock ? "✅" : "❌"
                    let stockStatus = result.inStock ? "有货" : "缺货"
                    
                    testResult = """
                    \(statusIcon) 测试成功！
                    
                    商品ID: \(result.productId)
                    商品名称: \(result.productName)
                    库存状态: \(stockStatus)
                    原因: \(result.stockReason)
                    价格: \(result.price)
                    时间: \(result.timestamp)
                    """
                    isTestingURL = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ 测试失败: \(error.localizedDescription)"
                    isTestingURL = false
                }
            }
        }
    }
    
    private func testSimpleAPI() {
        guard !backendURL.isEmpty else { return }
        
        isTestingURL = true
        testResult = "正在测试简单API..."
        
        guard let url = URL(string: "\(backendURL)/api/check-stock-simple?productId=1707") else {
            testResult = "❌ 无效的后端URL"
            isTestingURL = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isTestingURL = false
                
                if let error = error {
                    self.testResult = """
                    ❌ 简单API测试失败
                    
                    错误信息: \(error.localizedDescription)
                    
                    💡 这表明简单API也无法访问，可能是：
                    • 后端服务URL不正确
                    • 网络连接问题
                    • 后端服务完全不可用
                    """
                    return
                }
                
                guard let data = data else {
                    self.testResult = "❌ 没有收到响应数据"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let success = json["success"] as? Bool, success {
                            let data = json["data"] as? [String: Any] ?? [:]
                            let productName = data["productName"] as? String ?? "未知"
                            let inStock = data["inStock"] as? Bool ?? false
                            let stockReason = data["stockReason"] as? String ?? "未知"
                            let price = data["price"] as? String ?? "未知"
                            
                            self.testResult = """
                            ✅ 简单API测试成功！
                            
                            📦 商品信息：
                            • 商品名称: \(productName)
                            • 库存状态: \(inStock ? "✅ 有货" : "❌ 缺货")
                            • 价格: \(price)
                            • 状态原因: \(stockReason)
                            
                            🎉 简单API工作正常！
                            这意味着应用可以使用备用方案检查库存。
                            """
                        } else {
                            let errorMsg = json["error"] as? String ?? "未知错误"
                            self.testResult = """
                            ❌ 简单API返回错误
                            
                            错误信息: \(errorMsg)
                            
                            这可能是网站结构变化或反爬措施导致的。
                            """
                        }
                    } else {
                        self.testResult = "❌ 无法解析API响应"
                    }
                } catch {
                    self.testResult = "❌ 解析响应数据失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        }
        return timestamp
    }
} 