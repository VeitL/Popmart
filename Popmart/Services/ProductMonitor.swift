//
//  ProductMonitor.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import Foundation
import Combine
import SwiftUI
import WebKit
import OSLog

class ProductMonitor: ObservableObject {
    @Published var products: [Product] = []
    @Published var monitorLogs: [MonitorLog] = []
    @Published var lastError: String?
    
    private var productTimers: [UUID: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // 反爬虫用户代理池
    private let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ]
    
    // 请求头池
    private let acceptLanguages = [
        "zh-CN,zh;q=0.9,en;q=0.8",
        "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7",
        "de-DE,de;q=0.9,en;q=0.8",
        "ja-JP,ja;q=0.9,en;q=0.8"
    ]
    
    // 计算属性：是否有任何产品在监控中
    var isAnyMonitoring: Bool {
        products.contains { $0.isMonitoring }
    }
    
    // 添加日志记录器
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.popmart", category: "ProductMonitor")
    
    init() {
        loadProducts()
        loadLogs()
        // 添加默认商品
        if products.isEmpty {
            addProduct(url: "https://www.popmart.com/de/products/1991/THE-MONSTERS-Big-into-Energy-Series-Vinyl-Plush-Pendant-Blind-Box", 
                      name: "THE MONSTERS Big into Energy Series Vinyl Plush Pendant Blind Box")
        }
        // 恢复监控状态
        restoreMonitoringStates()
    }
    
    // MARK: - 商品管理
    func addProduct(url: String, name: String, variant: ProductVariant = .singleBox, imageURL: String? = nil, monitoringInterval: TimeInterval = 300, autoStart: Bool = false) {
        let product = Product(url: url, name: name, variant: variant, imageURL: imageURL, monitoringInterval: monitoringInterval, autoStart: autoStart)
        products.append(product)
        saveProducts()
        addLog(for: product, status: .success, message: "商品已添加到监控列表")
        
        if autoStart {
            startMonitoring(for: product.id)
        }
    }
    
    func removeProduct(at index: Int) {
        guard index < products.count else { return }
        let product = products[index]
        
        // 停止该商品的监控
        if product.isMonitoring {
            stopMonitoring(for: product.id)
        }
        
        products.remove(at: index)
        saveProducts()
        addLog(for: product, status: .success, message: "商品已从监控列表移除")
    }
    
    func updateProduct(_ product: Product) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
            saveProducts()
        }
    }
    
    func updateProductSettings(_ productId: UUID, interval: TimeInterval, autoStart: Bool, customUserAgent: String?) {
        if let index = products.firstIndex(where: { $0.id == productId }) {
            let wasMonitoring = products[index].isMonitoring
            
            products[index].monitoringInterval = interval
            products[index].autoStart = autoStart
            products[index].customUserAgent = customUserAgent
            
            // 如果正在监控且间隔改变，重启监控
            if wasMonitoring {
                stopMonitoring(for: productId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startMonitoring(for: productId)
                }
            }
            
            saveProducts()
            addLog(for: products[index], status: .success, message: "监控设置已更新 - 间隔: \(Int(interval))秒")
        }
    }
    
    // MARK: - 独立监控控制
    func startMonitoring(for productId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        
        var product = products[index]
        guard !product.isMonitoring else { return }
        
        product.isMonitoring = true
        products[index] = product
        saveProducts()
        
        // 立即检查一次
        checkProductAvailability(product)
        
        // 设置该产品的独立定时器
        let timer = Timer.scheduledTimer(withTimeInterval: product.monitoringInterval, repeats: true) { _ in
            self.checkProductAvailability(self.products.first(where: { $0.id == productId }) ?? product)
        }
        
        productTimers[productId] = timer
        addLog(for: product, status: .success, message: "开始监控，间隔 \(Int(product.monitoringInterval)) 秒")
    }
    
    func stopMonitoring(for productId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        
        var product = products[index]
        product.isMonitoring = false
        products[index] = product
        saveProducts()
        
        // 停止该产品的定时器
        productTimers[productId]?.invalidate()
        productTimers.removeValue(forKey: productId)
        
        addLog(for: product, status: .success, message: "停止监控")
    }
    
    func startAllMonitoring() {
        for product in products {
            if product.autoStart || !product.isMonitoring {
                startMonitoring(for: product.id)
            }
        }
    }
    
    func stopAllMonitoring() {
        for product in products {
            if product.isMonitoring {
                stopMonitoring(for: product.id)
            }
        }
    }
    
    func restoreMonitoringStates() {
        // 恢复应用关闭前的监控状态
        for product in products {
            if product.isMonitoring {
                // 重新开始监控
                var updatedProduct = product
                updatedProduct.isMonitoring = false
                if let index = products.firstIndex(where: { $0.id == product.id }) {
                    products[index] = updatedProduct
                }
                startMonitoring(for: product.id)
            }
        }
    }
    
    // MARK: - 立即检查功能
    func instantCheck(for productId: UUID) {
        guard let product = products.first(where: { $0.id == productId }) else { return }
        
        addLog(for: product, status: .instantCheck, message: "执行立即检查...")
        checkProductAvailability(product)
    }
    
    func instantCheckAll() {
        for product in products {
            addLog(for: product, status: .instantCheck, message: "执行立即检查...")
            // 添加小延迟避免同时发送太多请求
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
                self.checkProductAvailability(product)
            }
        }
    }
    
    // MARK: - 商品检查
    private func checkProductAvailability(_ product: Product) {
        guard let url = URL(string: product.url) else {
            addLog(for: product, status: .error, message: "无效的URL")
            return
        }
        
        let startTime = Date()
        let request = createAntiDetectionRequest(for: url, with: product)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response -> (String, Int) in
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                return (String(data: data, encoding: .utf8) ?? "", statusCode)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    let responseTime = Date().timeIntervalSince(startTime)
                    switch completion {
                    case .failure(let error):
                        self.handleNetworkError(for: product, error: error, responseTime: responseTime)
                    case .finished:
                        break
                    }
                },
                receiveValue: { htmlContent, statusCode in
                    let responseTime = Date().timeIntervalSince(startTime)
                    self.parseProductStatus(from: htmlContent, for: product, responseTime: responseTime, statusCode: statusCode)
                }
            )
            .store(in: &cancellables)
    }
    
    private func createAntiDetectionRequest(for url: URL, with product: Product) -> URLRequest {
        var request = URLRequest(url: url)
        
        // 使用自定义用户代理或随机选择
        if let customUA = product.customUserAgent, !customUA.isEmpty {
            request.setValue(customUA, forHTTPHeaderField: "User-Agent")
        } else {
            request.setValue(userAgents.randomElement(), forHTTPHeaderField: "User-Agent")
        }
        
        // 随机选择Accept-Language
        request.setValue(acceptLanguages.randomElement(), forHTTPHeaderField: "Accept-Language")
        
        // 添加其他反检测头
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("upgrade-insecure-requests", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        
        // 设置超时和连接属性
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // 添加随机延迟（1-3秒）
        let delay = Double.random(in: 1.0...3.0)
        Thread.sleep(forTimeInterval: delay)
        
        return request
    }
    
    private func handleNetworkError(for product: Product, error: Error, responseTime: TimeInterval) {
        updateProductStats(product, incrementError: true)
        
        let errorMessage: String
        let logStatus: LogStatus
        
        switch error {
        case let urlError as URLError:
            switch urlError.code {
            case .timedOut:
                errorMessage = "请求超时 - 可能触发了反爬虫机制"
                logStatus = .antiBot
            case .notConnectedToInternet:
                errorMessage = "网络连接已断开"
                logStatus = .networkError
            default:
                errorMessage = "网络错误: \(urlError.localizedDescription)"
                logStatus = .networkError
            }
        case let nsError as NSError:
            if nsError.domain == NSURLErrorDomain && (nsError.code == 403 || nsError.code == 429) {
                errorMessage = "访问被拒绝 - 触发反爬虫检测"
                logStatus = .antiBot
            } else {
                errorMessage = "错误: \(nsError.localizedDescription)"
                logStatus = .error
            }
        default:
            errorMessage = "未知错误: \(error.localizedDescription)"
            logStatus = .error
        }
        
        addLog(for: product, status: logStatus, message: errorMessage, responseTime: responseTime)
        
        if product.errorCount >= product.maxRetries && product.isMonitoring {
            stopMonitoring(for: product.id)
            addLog(for: product, status: .error, message: "错误次数过多，已自动暂停监控")
        }
    }
    
    private func parseProductStatus(from html: String, for product: Product, responseTime: TimeInterval, statusCode: Int) {
        updateProductStats(product, incrementError: false)
        
        // 检查是否被反爬虫检测
        if statusCode == 403 || statusCode == 429 || html.contains("Access Denied") || html.contains("Cloudflare") {
            addLog(for: product, status: .antiBot, message: "检测到反爬虫机制 (HTTP \(statusCode))", responseTime: responseTime, httpStatusCode: statusCode)
            return
        }
        
        // 检测关键词来判断商品状态
        let unavailableKeywords = [
            "out of stock", "sold out", "ausverkauft", "nicht verfügbar",
            "temporarily unavailable", "vorübergehend nicht verfügbar",
            "sorry, this item is currently out of stock", "leider ausverkauft"
        ]
        
        let availableKeywords = [
            "add to cart", "in den warenkorb", "buy now", "jetzt kaufen",
            "verfügbar", "available", "add to bag", "in stock"
        ]
        
        let htmlLowercase = html.lowercased()
        
        // 获取当前商品状态
        var currentProduct = product
        let wasAvailable = currentProduct.isAvailable
        
        // 首先检查是否缺货
        let isOutOfStock = unavailableKeywords.contains { keyword in
            htmlLowercase.contains(keyword)
        }
        
        // 然后检查是否有库存
        let hasStock = availableKeywords.contains { keyword in
            htmlLowercase.contains(keyword)
        }
        
        if hasStock && !isOutOfStock {
            currentProduct.isAvailable = true
        } else {
            currentProduct.isAvailable = false
        }
        
        // 提取价格信息
        extractPrice(from: html, for: &currentProduct)
        
        // 更新产品信息
        updateProduct(currentProduct)
        
        // 记录日志
        let statusMessage = currentProduct.isAvailable ? "有库存" : "缺货"
        let priceInfo = currentProduct.price != nil ? " (价格: \(currentProduct.price!))" : ""
        
        if wasAvailable != currentProduct.isAvailable {
            let changeMessage = currentProduct.isAvailable ? "🎉 商品上架了！" : "商品已下架"
            addLog(for: currentProduct, status: .availabilityChanged, 
                  message: "\(changeMessage) - \(statusMessage)\(priceInfo)", 
                  responseTime: responseTime, httpStatusCode: statusCode)
            
            // 如果商品从缺货变为有货，发送通知
            if !wasAvailable && currentProduct.isAvailable {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ProductAvailable"),
                    object: currentProduct
                )
            }
        } else {
            addLog(for: currentProduct, status: .success, 
                  message: "状态检查: \(statusMessage)\(priceInfo)", 
                  responseTime: responseTime, httpStatusCode: statusCode)
        }
    }
    
    private func extractPrice(from html: String, for product: inout Product) {
        // 使用全局函数而不是实例方法
        if let price = Popmart.extractPrice(from: html) {
            product.price = price
        }
    }
    
    private func updateProductStats(_ product: Product, incrementError: Bool) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index].incrementCheck()
            if incrementError {
                products[index].incrementError()
            } else {
                products[index].incrementSuccess()
            }
            saveProducts()
        }
    }
    
    // MARK: - 日志管理
    private func addLog(for product: Product, status: LogStatus, message: String, responseTime: TimeInterval? = nil, httpStatusCode: Int? = nil) {
        let log = MonitorLog(
            productId: product.id,
            productName: product.name,
            status: status,
            message: message,
            responseTime: responseTime,
            httpStatusCode: httpStatusCode
        )
        
        monitorLogs.insert(log, at: 0)
        
        if monitorLogs.count > 500 {
            monitorLogs = Array(monitorLogs.prefix(500))
        }
        
        saveLogs()
        logger.info("📝 [\(product.name)] \(message)")
    }
    
    func clearLogs() {
        monitorLogs.removeAll()
        saveLogs()
    }
    
    func clearLogsForProduct(_ productId: UUID) {
        monitorLogs.removeAll { $0.productId == productId }
        saveLogs()
    }
    
    // MARK: - 数据持久化
    private func saveProducts() {
        if let data = try? JSONEncoder().encode(products) {
            UserDefaults.standard.set(data, forKey: "SavedProducts")
        }
    }
    
    private func loadProducts() {
        if let data = UserDefaults.standard.data(forKey: "SavedProducts"),
           let savedProducts = try? JSONDecoder().decode([Product].self, from: data) {
            products = savedProducts
        }
    }
    
    private func saveLogs() {
        if let data = try? JSONEncoder().encode(monitorLogs) {
            UserDefaults.standard.set(data, forKey: "MonitorLogs")
        }
    }
    
    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: "MonitorLogs"),
           let savedLogs = try? JSONDecoder().decode([MonitorLog].self, from: data) {
            monitorLogs = savedLogs
        }
    }
    
    // 新增：解析商品页面并获取变体信息
    func parseProductPage(url: String, completion: @escaping (Result<ProductPageInfo, Error>) -> Void) {
        guard let pageURL = URL(string: url) else {
            completion(.failure(NSError(domain: "InvalidURL", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])))
            return
        }
        
        var request = URLRequest(url: pageURL)
        request.setValue(userAgents.randomElement(), forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguages.randomElement(), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ParseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析页面内容"])))
                }
                return
            }
            
            let pageInfo = self.extractProductPageInfo(from: html, baseURL: url)
            DispatchQueue.main.async {
                if let pageInfo = pageInfo {
                    completion(.success(pageInfo))
                } else {
                    completion(.failure(NSError(domain: "ParseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析商品信息"])))
                }
            }
        }.resume()
    }
    
    // 从HTML中提取商品信息
    private func extractProductPageInfo(from html: String, baseURL: String) -> ProductPageInfo? {
        // 首先尝试Amazon解析
        if baseURL.contains("amazon") {
            return extractAmazonProductInfo(from: html, baseURL: baseURL)
        }
        
        // 然后尝试Popmart解析
        guard let name = extractProductName(from: html) else {
            return nil
        }
        
        // 基本信息
        let info = ProductPageInfo(
            name: name,
            availableVariants: extractShopifyVariants(from: html, baseURL: baseURL),
            imageURL: extractImageURL(from: html),
            description: nil,
            brand: nil,
            category: nil
        )
        
        return info
    }
    
    // MARK: - Amazon商品解析
    private func extractAmazonProductInfo(from html: String, baseURL: String) -> ProductPageInfo? {
        guard let name = extractAmazonProductName(from: html) else {
            return nil
        }
        
        let variants = extractAmazonVariants(from: html, baseURL: baseURL)
        let imageURL = extractAmazonImageURL(from: html)
        let description = extractAmazonDescription(from: html)
        let brand = extractAmazonBrand(from: html)
        
        return ProductPageInfo(
            name: name,
            availableVariants: variants,
            imageURL: imageURL,
            description: description,
            brand: brand,
            category: nil
        )
    }
    
    private func extractAmazonProductName(from html: String) -> String? {
        let namePatterns = [
            #"<span[^>]*id="productTitle"[^>]*>(.*?)</span>"#,
            #"<h1[^>]*id="title"[^>]*>(.*?)</h1>"#,
            #"<meta[^>]*property="og:title"[^>]*content="([^"]+)""#,
            #"<title>(.*?)</title>"#
        ]
        
        for pattern in namePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let nameRange = Range(match.range(at: 1), in: html) {
                        let name = String(html[nameRange])
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !name.isEmpty && !name.contains("Amazon") {
                            return name
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractAmazonVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 尝试从size选择器中提取变体
        if let sizeVariants = extractAmazonSizeVariants(from: html, baseURL: baseURL) {
            variants.append(contentsOf: sizeVariants)
        }
        
        // 如果没有找到变体，创建一个默认变体
        if variants.isEmpty {
            if let price = extractAmazonPrice(from: html) {
                let defaultVariant = ProductPageInfo.ProductVariantInfo(
                    variant: .singleBox,
                    price: price,
                    isAvailable: extractAmazonAvailability(from: html),
                    url: baseURL,
                    imageURL: extractAmazonImageURL(from: html),
                    sku: nil,
                    stockLevel: nil,
                    variantName: "默认"
                )
                variants.append(defaultVariant)
            }
        }
        
        return variants
    }
    
    private func extractAmazonSizeVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo]? {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 查找size选择区域 - 扩展更多Amazon特有的模式
        let sizePatterns = [
            // Amazon的尺寸选择器
            #"<ul[^>]*id="[^"]*size[^"]*"[^>]*>(.*?)</ul>"#,
            #"<div[^>]*class="[^"]*size[^"]*"[^>]*>(.*?)</div>"#,
            #"Size:\s*<select[^>]*>(.*?)</select>"#,
            // Amazon的变体选择器模式
            #"<div[^>]*id="[^"]*variation[^"]*"[^>]*>(.*?)</div>"#,
            #"<ul[^>]*class="[^"]*a-unordered-list[^"]*"[^>]*>(.*?)</ul>"#,
            #"<div[^>]*data-asin[^>]*>(.*?)</div>"#,
            // 查找包含价格和选项的区域
            #"<span[^>]*class="[^"]*dropdown[^"]*"[^>]*>(.*?)</span>"#
        ]
        
        for pattern in sizePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                let matches = regex.matches(in: html, options: [], range: range)
                
                for match in matches {
                    if let sectionRange = Range(match.range(at: 1), in: html) {
                        let sectionHTML = String(html[sectionRange])
                        
                        // 提取每个选项 - 支持多种Amazon格式
                        let optionPatterns = [
                            // 标准列表项
                            #"<li[^>]*>(.*?)</li>"#,
                            #"<option[^>]*>(.*?)</option>"#,
                            // Amazon特有的span元素
                            #"<span[^>]*data-csa-c-type="element"[^>]*data-csa-c-content="([^"]*)"[^>]*>(.*?)</span>"#,
                            #"<span[^>]*class="[^"]*selection[^"]*"[^>]*>(.*?)</span>"#,
                            // 按钮式选择器
                            #"<button[^>]*class="[^"]*size[^"]*"[^>]*>(.*?)</button>"#,
                            #"<div[^>]*class="[^"]*option[^"]*"[^>]*>(.*?)</div>"#
                        ]
                        
                        for optionPattern in optionPatterns {
                            if let optionRegex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                                let optionRange = NSRange(location: 0, length: sectionHTML.count)
                                let optionMatches = optionRegex.matches(in: sectionHTML, options: [], range: optionRange)
                                
                                for optionMatch in optionMatches {
                                    var optionText = ""
                                    
                                    // 安全地检查哪个捕获组有内容
                                    for i in 1..<optionMatch.numberOfRanges {
                                        let rangeAtIndex = optionMatch.range(at: i)
                                        if rangeAtIndex.location != NSNotFound,
                                           let range = Range(rangeAtIndex, in: sectionHTML) {
                                            let text = String(sectionHTML[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !text.isEmpty {
                                                optionText = text
                                                break
                                            }
                                        }
                                    }
                                    
                                    if !optionText.isEmpty {
                                        let cleanedText = optionText
                                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        
                                        if !cleanedText.isEmpty && cleanedText.count < 100 && !cleanedText.lowercased().contains("select") {
                                            let variant = determineVariantFromAmazonOption(cleanedText)
                                            let variantInfo = ProductPageInfo.ProductVariantInfo(
                                                variant: variant,
                                                price: extractPriceFromOptionText(cleanedText),
                                                isAvailable: true,
                                                url: baseURL,
                                                imageURL: nil,
                                                sku: nil,
                                                stockLevel: nil,
                                                variantName: cleanedText
                                            )
                                            variants.append(variantInfo)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 如果仍然没有找到变体，尝试从页面标题或描述中提取
        if variants.isEmpty {
            variants = extractVariantsFromTitle(html: html, baseURL: baseURL)
        }
        
        return variants.isEmpty ? nil : variants
    }
    
    private func determineVariantFromAmazonOption(_ optionText: String) -> ProductVariant {
        let lowercaseText = optionText.lowercased()
        
        switch true {
        case lowercaseText.contains("pack") || lowercaseText.contains("set"):
            return .wholeSet
        case lowercaseText.contains("size"):
            return .specific
        case lowercaseText.contains("random"):
            return .random
        case lowercaseText.contains("limited") || lowercaseText.contains("special"):
            return .limited
        default:
            return .singleBox
        }
    }
    
    private func extractPriceFromOptionText(_ text: String) -> String? {
        let pricePatterns = [
            #"€\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*€"#,
            #"\$\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*\$"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.count)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let priceRange = Range(match.range(at: 0), in: text) {
                        return String(text[priceRange])
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractAmazonPrice(from html: String) -> String? {
        let pricePatterns = [
            #"<span[^>]*class="[^"]*price[^"]*"[^>]*><span[^>]*class="[^"]*currency[^"]*"[^>]*>([^<]+)</span><span[^>]*class="[^"]*whole[^"]*"[^>]*>([^<]+)</span><span[^>]*class="[^"]*fraction[^"]*"[^>]*>([^<]+)</span>"#,
            #"<span[^>]*class="[^"]*a-price-whole[^"]*"[^>]*>([^<]+)</span><span[^>]*class="[^"]*a-price-fraction[^"]*"[^>]*>([^<]+)</span>"#,
            #"<span[^>]*class="[^"]*a-price[^"]*"[^>]*>.*?€\s*(\d+[.,]\d{2})"#,
            #"€\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*€"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    let numberOfRanges = match.numberOfRanges
                    
                    if numberOfRanges >= 4 {
                        // 处理分离的货币符号、整数和小数部分 (3个捕获组)
                        if let currencyRange = Range(match.range(at: 1), in: html),
                           let wholeRange = Range(match.range(at: 2), in: html),
                           let fractionRange = Range(match.range(at: 3), in: html) {
                            let currency = String(html[currencyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let whole = String(html[wholeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let fraction = String(html[fractionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            return "\(currency)\(whole).\(fraction)"
                        }
                    } else if numberOfRanges >= 3 {
                        // 处理整数和小数部分 (2个捕获组)
                        if let wholeRange = Range(match.range(at: 1), in: html),
                           let fractionRange = Range(match.range(at: 2), in: html) {
                            let whole = String(html[wholeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let fraction = String(html[fractionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            return "€\(whole).\(fraction)"
                        }
                    } else if numberOfRanges >= 2 {
                        // 处理完整价格 (1个捕获组)
                        if let priceRange = Range(match.range(at: 1), in: html) {
                            let price = String(html[priceRange])
                                .replacingOccurrences(of: ",", with: ".")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // 如果价格不包含货币符号，添加€
                            if !price.contains("€") && !price.contains("$") {
                                return "€\(price)"
                            } else {
                                return price
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractAmazonAvailability(from html: String) -> Bool {
        let htmlLowercase = html.lowercased()
        
        let unavailableKeywords = [
            "currently unavailable", "out of stock", "ausverkauft", "nicht verfügbar",
            "temporarily out of stock", "vorübergehend nicht verfügbar"
        ]
        
        let availableKeywords = [
            "add to cart", "in den warenkorb", "buy now", "jetzt kaufen",
            "add to basket", "in den einkaufswagen", "in stock", "verfügbar"
        ]
        
        let isOutOfStock = unavailableKeywords.contains { htmlLowercase.contains($0) }
        let hasStock = availableKeywords.contains { htmlLowercase.contains($0) }
        
        return hasStock && !isOutOfStock
    }
    
    private func extractAmazonImageURL(from html: String) -> String? {
        let imagePatterns = [
            #"<img[^>]*id="[^"]*product[^"]*Image[^"]*"[^>]*src="([^"]+)""#,
            #"<img[^>]*data-old-hires="([^"]+)""#,
            #"<img[^>]*data-a-dynamic-image="[^"]*([^"]*\.jpg)"#,
            #"<meta[^>]*property="og:image"[^>]*content="([^"]+)""#
        ]
        
        for pattern in imagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let urlRange = Range(match.range(at: 1), in: html) {
                        let imageURL = String(html[urlRange])
                        if imageURL.hasPrefix("http") {
                            return imageURL
                        } else if imageURL.hasPrefix("//") {
                            return "https:" + imageURL
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractAmazonDescription(from html: String) -> String? {
        let descPatterns = [
            #"<div[^>]*id="[^"]*feature[^"]*bullets[^"]*"[^>]*>(.*?)</div>"#,
            #"<div[^>]*class="[^"]*product[^"]*description[^"]*"[^>]*>(.*?)</div>"#
        ]
        
        for pattern in descPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let descRange = Range(match.range(at: 1), in: html) {
                        let description = String(html[descRange])
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !description.isEmpty {
                            return description
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractAmazonBrand(from html: String) -> String? {
        let brandPatterns = [
            #"<a[^>]*id="[^"]*byline[^"]*"[^>]*>(.*?)</a>"#,
            #"<span[^>]*class="[^"]*brand[^"]*"[^>]*>(.*?)</span>"#
        ]
        
        for pattern in brandPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let brandRange = Range(match.range(at: 1), in: html) {
                        let brand = String(html[brandRange])
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !brand.isEmpty {
                            return brand
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Shopify变体处理
    private func extractShopifyVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 提取Shopify产品配置
        if let shopifyConfig = extractShopifyProductConfig(from: html) {
            if let variations = shopifyConfig["variants"] as? [[String: Any]] {
                for variation in variations {
                    // 安全地访问字典值
                    guard let available = variation["available"] as? Bool,
                          let sku = variation["sku"] as? String,
                          let title = variation["title"] as? String else {
                        continue
                    }
                    
                    let variant = mapSkuToVariant(sku: sku, title: title)
                    
                    var imageURL: String?
                    if let imageDict = variation["image"] as? [String: Any],
                       let url = imageDict["url"] as? String {
                        imageURL = url
                    }
                    
                    let variantInfo = ProductPageInfo.ProductVariantInfo(
                        variant: variant,
                        price: variation["price"] as? String,
                        isAvailable: available,
                        url: constructVariantURL(baseURL: baseURL, sku: sku),
                        imageURL: imageURL,
                        sku: sku,
                        stockLevel: nil,
                        variantName: title
                    )
                    
                    variants.append(variantInfo)
                }
            }
        }
        
        return variants
    }
    
    // 从Shopify网站提取变体信息
    private func extractShopifyProductConfig(from html: String) -> [String: Any]? {
        // 实现从HTML中提取Shopify产品配置的逻辑
        // 这里需要根据实际情况实现
        return nil
    }
    
    // 根据变体标题确定变体类型
    private func determineVariantType(from title: String) -> ProductVariant {
        let lowercaseTitle = title.lowercased()
        
        switch true {
        case lowercaseTitle.contains("set") || lowercaseTitle.contains("complete"):
            return .wholeSet
        case lowercaseTitle.contains("random"):
            return .random
        case lowercaseTitle.contains("limited") || lowercaseTitle.contains("special"):
            return .limited
        case lowercaseTitle.contains("specific") || lowercaseTitle.contains("style"):
            return .specific
        default:
            return .singleBox
        }
    }
    
    // 构建变体特定的URL
    private func constructVariantURL(baseURL: String, sku: String) -> String {
        // 如果base URL已经包含参数，使用&连接，否则使用?
        let separator = baseURL.contains("?") ? "&" : "?"
        return "\(baseURL)\(separator)variant=\(sku)"
    }
    
    // 格式化价格
    private func formatPrice(_ price: Double) -> String {
        return String(format: "€%.2f", price)
    }
    
    // 提取商品图片URL
    private func extractImageURL(from html: String) -> String? {
        // Pop Mart 图片选择器模式
        let imagePatterns = [
            #"<img[^>]*class="[^"]*product[^"]*"[^>]*src="([^"]+)""#,
            #"<img[^>]*src="([^"]*product[^"]*\.(?:jpg|jpeg|png|webp))"#,
            #""image":\s*"([^"]+)""#,
            #"<meta[^>]*property="og:image"[^>]*content="([^"]+)""#,
            #"<img[^>]*data-src="([^"]+)""#
        ]
        
        for pattern in imagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let urlRange = Range(match.range(at: 1), in: html) {
                        let imageURL = String(html[urlRange])
                        // 确保URL是完整的
                        if imageURL.hasPrefix("http") {
                            return imageURL
                        } else if imageURL.hasPrefix("//") {
                            return "https:" + imageURL
                        } else if imageURL.hasPrefix("/") {
                            return "https://www.popmart.com" + imageURL
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 通用可用性检查方法
    private func checkAvailability(from html: String) -> Bool {
        let htmlLowercase = html.lowercased()
        
        let unavailableKeywords = [
            "out of stock", "sold out", "ausverkauft", "nicht verfügbar",
            "temporarily unavailable", "vorübergehend nicht verfügbar",
            "sorry, this item is currently out of stock", "leider ausverkauft"
        ]
        
        let availableKeywords = [
            "add to cart", "in den warenkorb", "buy now", "jetzt kaufen",
            "verfügbar", "available", "add to bag", "in stock"
        ]
        
        let isOutOfStock = unavailableKeywords.contains { htmlLowercase.contains($0) }
        let hasStock = availableKeywords.contains { htmlLowercase.contains($0) }
        
        return hasStock && !isOutOfStock
    }
    
    deinit {
        // 清理所有定时器
        for timer in productTimers.values {
            timer.invalidate()
        }
    }
    
    // 从页面标题中提取变体信息的备用方法
    private func extractVariantsFromTitle(html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 查找包含选项信息的文本
        let titlePattern = #"<title>(.*?)</title>"#
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: html.count)
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                if let titleRange = Range(match.range(at: 1), in: html) {
                    let title = String(html[titleRange])
                    
                    // 检查标题中是否包含变体信息（如尺寸、数量等）
                    let variationKeywords = ["pack", "set", "size", "piece", "count"]
                    for keyword in variationKeywords {
                        if title.lowercased().contains(keyword) {
                            // 创建基于标题的默认变体
                            let variant = ProductPageInfo.ProductVariantInfo(
                                variant: .singleBox,
                                price: extractAmazonPrice(from: html),
                                isAvailable: extractAmazonAvailability(from: html),
                                url: baseURL,
                                imageURL: extractAmazonImageURL(from: html),
                                sku: nil,
                                stockLevel: nil,
                                variantName: "默认选项"
                            )
                            variants.append(variant)
                            break
                        }
                    }
                }
            }
        }
        
        return variants
    }
}

// 通用价格提取方法
private func extractPrice(from html: String) -> String? {
    let pricePatterns = [
        #"€\s*(\d+[.,]\d{2})"#,
        #"EUR\s*(\d+[.,]\d{2})"#,
        #"(\d+[.,]\d{2})\s*€"#,
        #"(\d+[.,]\d{2})\s*EUR"#,
        #"price[^>]*>.*?€\s*(\d+[.,]\d{2})"#,
        #"class="[^"]*price[^"]*"[^>]*>.*?(\d+[.,]\d{2})"#
    ]
    
    for pattern in pricePatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: html.count)
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                if let priceRange = Range(match.range(at: 1), in: html) {
                    let priceString = String(html[priceRange])
                        .replacingOccurrences(of: ",", with: ".")
                    return "€\(priceString)"
                }
            }
        }
    }
    
    return nil
}

// 提取商品名称
private func extractProductName(from html: String) -> String? {
    let namePatterns = [
        #"<h1[^>]*class="[^"]*product[^"]*title[^"]*"[^>]*>(.*?)</h1>"#,
        #"<h1[^>]*>(.*?)</h1>"#,
        #"<meta[^>]*property="og:title"[^>]*content="([^"]+)""#,
        #"<title>(.*?)</title>"#
    ]
    
    for pattern in namePatterns {
        if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(html[range])
            let cleanedName = match.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                .replacingOccurrences(of: #"content="|""#, with: "", options: [.regularExpression])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanedName.isEmpty {
                return cleanedName
            }
        }
    }
    
    return nil
}

// 将SKU映射到变体类型
private func mapSkuToVariant(sku: String, title: String) -> ProductVariant {
    let lowercaseSku = sku.lowercased()
    let lowercaseTitle = title.lowercased()
    
    if lowercaseSku.contains("set") || lowercaseTitle.contains("整套") || lowercaseTitle.contains("set") {
        return .wholeSet
    } else if lowercaseSku.contains("random") || lowercaseTitle.contains("随机") || lowercaseTitle.contains("random") {
        return .random
    } else if lowercaseSku.contains("limited") || lowercaseTitle.contains("限定") || lowercaseTitle.contains("limited") {
        return .limited
    } else if lowercaseSku.contains("specific") || lowercaseTitle.contains("指定") || lowercaseTitle.contains("specific") {
        return .specific
    } else {
        return .singleBox
    }
} 