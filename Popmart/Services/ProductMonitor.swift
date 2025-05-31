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
    private var variantTimers: [String: Timer] = [:]  // 新增：变体定时器，key格式为 "productId_variantId"
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
            
            // 添加您提到的问题URL
            addProduct(url: "https://www.popmart.com/de/products/1984/THE-MONSTERS-Big-into-Energy-Series-Phone-Case-for-iPhone",
                      name: "THE MONSTERS Big into Energy Series Phone Case for iPhone")
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
    
    // 新增：添加多变体产品
    func addMultiVariantProduct(baseURL: String, name: String, variants: [VariantDetail], imageURL: String? = nil, monitoringInterval: TimeInterval = 300, autoStart: Bool = false) {
        let product = Product(baseURL: baseURL, name: name, variants: variants, imageURL: imageURL, monitoringInterval: monitoringInterval, autoStart: autoStart)
        products.append(product)
        saveProducts()
        addLog(for: product, status: .success, message: "多变体商品已添加到监控列表 (\(variants.count)个变体)")
        
        if autoStart {
            startMonitoring(for: product.id)
        }
    }
    
    // 新增：添加单个变体到现有产品
    func addVariantToProduct(productId: UUID, variant: VariantDetail) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        
        products[index].addVariant(variant)
        saveProducts()
        addLog(for: products[index], status: .success, message: "已添加新变体: \(variant.name)")
    }
    
    // 新增：移除产品的特定变体
    func removeVariantFromProduct(productId: UUID, variantId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        
        let variantName = products[index].getVariant(by: variantId)?.name ?? "未知变体"
        products[index].removeVariant(id: variantId)
        saveProducts()
        addLog(for: products[index], status: .success, message: "已移除变体: \(variantName)")
    }
    
    // 新增：开始监控特定变体
    func startMonitoringVariant(productId: UUID, variantId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        guard var variant = products[index].getVariant(by: variantId) else { return }
        
        variant.isMonitoring = true
        products[index].updateVariant(variant)
        saveProducts()
        
        // 立即检查该变体
        checkVariantAvailability(product: products[index], variant: variant)
        
        // 为该变体设置独立定时器
        let timerKey = "\(productId.uuidString)_\(variantId.uuidString)"
        let timer = Timer.scheduledTimer(withTimeInterval: products[index].monitoringInterval, repeats: true) { _ in
            if let currentProduct = self.products.first(where: { $0.id == productId }),
               let currentVariant = currentProduct.getVariant(by: variantId) {
                self.checkVariantAvailability(product: currentProduct, variant: currentVariant)
            }
        }
        
        variantTimers[timerKey] = timer
        addLog(for: products[index], status: .success, message: "开始监控变体: \(variant.name)")
    }
    
    // 新增：停止监控特定变体
    func stopMonitoringVariant(productId: UUID, variantId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        guard var variant = products[index].getVariant(by: variantId) else { return }
        
        variant.isMonitoring = false
        products[index].updateVariant(variant)
        saveProducts()
        
        // 停止该变体的定时器
        let timerKey = "\(productId.uuidString)_\(variantId.uuidString)"
        variantTimers[timerKey]?.invalidate()
        variantTimers.removeValue(forKey: timerKey)
        
        addLog(for: products[index], status: .success, message: "停止监控变体: \(variant.name)")
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
        let product = products[index]
        
        guard !product.isMonitoring else { return }
        
        // 对于多变体产品，需要启动所有变体的监控
        if product.variants.count > 1 {
            for variant in product.variants {
                if !variant.isMonitoring {
                    startMonitoringVariant(productId: productId, variantId: variant.id)
                }
            }
        } else {
            // 对于单变体产品，启动第一个变体的监控
            if let firstVariant = product.variants.first, !firstVariant.isMonitoring {
                startMonitoringVariant(productId: productId, variantId: firstVariant.id)
            }
        }
        
        saveProducts()
        
        // 立即检查一次
        checkProductAvailability(product)
        
        // 设置该产品的独立定时器
        let timer = Timer.scheduledTimer(withTimeInterval: product.monitoringInterval, repeats: true) { _ in
            self.checkProductAvailability(self.products.first(where: { $0.id == productId }) ?? product)
        }
        
        productTimers[product.id] = timer
        addLog(for: product, status: .success, message: "开始监控，间隔 \(Int(product.monitoringInterval)) 秒")
    }
    
    func stopMonitoring(for productId: UUID) {
        guard let index = products.firstIndex(where: { $0.id == productId }) else { return }
        
        let product = products[index]
        
        // 停止所有变体的监控
        for variant in product.variants {
            if variant.isMonitoring {
                stopMonitoringVariant(productId: productId, variantId: variant.id)
            }
        }
        
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
                // 停止所有变体监控状态，然后重新启动
                for i in 0..<updatedProduct.variants.count {
                    updatedProduct.variants[i].isMonitoring = false
                }
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
    
    // 新增：检查特定变体的可用性
    private func checkVariantAvailability(product: Product, variant: VariantDetail) {
        guard let url = URL(string: variant.url) else {
            addLog(for: product, status: .error, message: "变体URL无效: \(variant.name)")
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
                        self.handleVariantNetworkError(for: product, variant: variant, error: error, responseTime: responseTime)
                    case .finished:
                        break
                    }
                },
                receiveValue: { htmlContent, statusCode in
                    let responseTime = Date().timeIntervalSince(startTime)
                    self.parseVariantStatus(from: htmlContent, for: product, variant: variant, responseTime: responseTime, statusCode: statusCode)
                }
            )
            .store(in: &cancellables)
    }
    
    private func handleVariantNetworkError(for product: Product, variant: VariantDetail, error: Error, responseTime: TimeInterval) {
        updateVariantStats(product: product, variantId: variant.id, incrementError: true)
        
        let errorMessage: String
        let logStatus: LogStatus
        
        switch error {
        case let urlError as URLError:
            switch urlError.code {
            case .timedOut:
                errorMessage = "[\(variant.name)] 请求超时 - 可能触发了反爬虫机制"
                logStatus = .antiBot
            case .notConnectedToInternet:
                errorMessage = "[\(variant.name)] 网络连接已断开"
                logStatus = .networkError
            default:
                errorMessage = "[\(variant.name)] 网络错误: \(urlError.localizedDescription)"
                logStatus = .networkError
            }
        default:
            errorMessage = "[\(variant.name)] 未知错误: \(error.localizedDescription)"
            logStatus = .error
        }
        
        addLog(for: product, status: logStatus, message: errorMessage, responseTime: responseTime)
        
        // 如果该变体错误次数过多，停止监控
        if let updatedVariant = getUpdatedVariant(product: product, variantId: variant.id),
           updatedVariant.errorCount >= product.maxRetries && updatedVariant.isMonitoring {
            stopMonitoringVariant(productId: product.id, variantId: variant.id)
            addLog(for: product, status: .error, message: "[\(variant.name)] 错误次数过多，已自动暂停监控")
        }
    }
    
    private func parseVariantStatus(from html: String, for product: Product, variant: VariantDetail, responseTime: TimeInterval, statusCode: Int) {
        updateVariantStats(product: product, variantId: variant.id, incrementError: false)
        
        // 检查是否被反爬虫检测
        if statusCode == 403 || statusCode == 429 || html.contains("Access Denied") || html.contains("Cloudflare") {
            addLog(for: product, status: .antiBot, message: "[\(variant.name)] 检测到反爬虫机制 (HTTP \(statusCode))", responseTime: responseTime, httpStatusCode: statusCode)
            return
        }
        
        // 使用与parseProductStatus相同的增强关键词检测
        let unavailableKeywords = [
            // 英语关键词
            "out of stock", "sold out", "temporarily unavailable",
            "sorry, this item is currently out of stock", "currently unavailable",
            "not available", "item not available", "no longer available",
            "discontinued", "out-of-stock", "soldout",
            
            // 德语关键词
            "ausverkauft", "nicht verfügbar", "vorübergehend nicht verfügbar",
            "leider ausverkauft", "derzeit nicht verfügbar", "nicht auf lager",
            "zur zeit nicht verfügbar", "vergriffen", "nicht lieferbar",
            "momentan nicht verfügbar", "aktuell nicht verfügbar",
            
            // Popmart特定关键词
            "coming soon", "bald verfügbar", "pre-order", "vorbestellung",
            "notify me", "benachrichtigen", "email me when available"
        ]
        
        let availableKeywords = [
            // 英语关键词
            "add to cart", "buy now", "purchase", "available",
            "in stock", "add to bag", "add to basket", "order now",
            "get it now", "shop now", "quick buy", "instant buy",
            
            // 德语关键词
            "in den warenkorb", "jetzt kaufen", "verfügbar", "kaufen",
            "sofort kaufen", "in den korb", "bestellen", "jetzt bestellen",
            "auf lager", "lieferbar", "sofort lieferbar", "verfügbarkeit",
            
            // Popmart特定关键词
            "add to wishlist", "zur wunschliste", "quick view",
            "select variant", "variante wählen"
        ]
        
        let priceIndicators = [
            "€", "EUR", "price", "preis", "cost", "kosten",
            "sale", "discount", "rabatt", "angebot"
        ]
        
        let htmlLowercase = html.lowercased()
        
        // 获取当前变体状态
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }),
              var currentVariant = products[productIndex].getVariant(by: variant.id) else { return }
        
        let wasAvailable = currentVariant.isAvailable
        
        // 使用相同的智能检测逻辑
        let hasUnavailableKeywords = unavailableKeywords.contains { keyword in
            htmlLowercase.contains(keyword.lowercased())
        }
        
        let hasAvailableKeywords = availableKeywords.contains { keyword in
            htmlLowercase.contains(keyword.lowercased())
        }
        
        let hasPriceIndicators = priceIndicators.contains { indicator in
            htmlLowercase.contains(indicator.lowercased())
        }
        
        let hasProductInfo = extractProductName(from: html, baseURL: product.url) != nil
        let hasProductImages = html.lowercased().contains("img") && 
                             (html.lowercased().contains("product") || 
                              html.lowercased().contains("image"))
        
        // 综合判断逻辑
        var newAvailabilityStatus: Bool
        
        if hasUnavailableKeywords {
            newAvailabilityStatus = false
        } else if hasAvailableKeywords || hasPriceIndicators {
            newAvailabilityStatus = true
        } else if hasProductInfo && hasProductImages {
            newAvailabilityStatus = true
        } else {
            newAvailabilityStatus = currentVariant.isAvailable
        }
        
        currentVariant.isAvailable = newAvailabilityStatus
        
        // 提取价格信息
        if let price = extractEnhancedPrice(from: html) {
            currentVariant = VariantDetail(
                variant: currentVariant.variant,
                name: currentVariant.name,
                price: price,
                isAvailable: currentVariant.isAvailable,
                url: currentVariant.url,
                imageURL: currentVariant.imageURL,
                sku: currentVariant.sku,
                stockLevel: currentVariant.stockLevel
            )
        }
        
        // 更新变体信息
        products[productIndex].updateVariant(currentVariant)
        saveProducts()
        
        // 记录详细日志
        let statusMessage = currentVariant.isAvailable ? "有库存 ✅" : "缺货 ❌"
        let priceInfo = currentVariant.price != nil ? " (价格: \(currentVariant.price!))" : ""
        let detectionInfo = """
        检测信息: 缺货词=\(hasUnavailableKeywords ? "是" : "否"), \
        购买词=\(hasAvailableKeywords ? "是" : "否"), \
        价格=\(hasPriceIndicators ? "是" : "否"), \
        商品信息=\(hasProductInfo ? "是" : "否")
        """
        
        if wasAvailable != currentVariant.isAvailable {
            let changeMessage = currentVariant.isAvailable ? "🎉 变体上架了！" : "⚠️ 变体已下架"
            addLog(for: products[productIndex], status: .availabilityChanged, 
                  message: "[\(variant.name)] \(changeMessage) - \(statusMessage)\(priceInfo)\n\(detectionInfo)", 
                  responseTime: responseTime, httpStatusCode: statusCode)
            
            // 如果变体从缺货变为有货，发送通知
            if !wasAvailable && currentVariant.isAvailable {
                NotificationCenter.default.post(
                    name: NSNotification.Name("VariantAvailable"),
                    object: ["product": products[productIndex], "variant": currentVariant]
                )
            }
        } else {
            addLog(for: products[productIndex], status: .success, 
                  message: "[\(variant.name)] 状态检查: \(statusMessage)\(priceInfo)\n\(detectionInfo)", 
                  responseTime: responseTime, httpStatusCode: statusCode)
        }
    }
    
    // 新增：更新变体统计信息
    private func updateVariantStats(product: Product, variantId: UUID, incrementError: Bool) {
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }),
              var variant = products[productIndex].getVariant(by: variantId) else { return }
        
        variant.incrementCheck()
        if incrementError {
            variant.incrementError()
        } else {
            variant.incrementSuccess()
        }
        
        products[productIndex].updateVariant(variant)
        saveProducts()
    }
    
    // 新增：获取更新后的变体
    private func getUpdatedVariant(product: Product, variantId: UUID) -> VariantDetail? {
        guard let currentProduct = products.first(where: { $0.id == product.id }) else { return nil }
        return currentProduct.getVariant(by: variantId)
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
    
    // MARK: - 解析商品页面并获取变体信息
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
    
    // 从HTML中提取商品信息 - 增强版
    private func extractProductPageInfo(from html: String, baseURL: String) -> ProductPageInfo? {
        print("🔍 [商品解析] 开始解析商品页面: \(baseURL)")
        print("📄 [商品解析] HTML内容长度: \(html.count) 字符")
        
        // 首先尝试Amazon解析
        if baseURL.contains("amazon") {
            print("🛒 [商品解析] 检测到Amazon网站，使用Amazon解析器")
            return extractAmazonProductInfo(from: html, baseURL: baseURL)
        }
        
        print("🏪 [商品解析] 使用通用解析器")
        
        // 尝试提取商品名称
        guard let name = extractProductName(from: html, baseURL: baseURL) else {
            print("❌ [商品解析] 无法提取商品名称")
            // 添加调试信息
            print("🔍 [调试] HTML前500字符:")
            let preview = String(html.prefix(500))
            print(preview)
            
            // 尝试备选解析方法
            if let fallbackName = extractFallbackProductName(from: html, url: baseURL) {
                print("🔄 [商品解析] 使用备选方法提取到名称: \(fallbackName)")
                return createProductInfoWithName(fallbackName, html: html, baseURL: baseURL)
            }
            
            return nil
        }
        
        print("📝 [商品解析] 商品名称: \(name)")
        
        return createProductInfoWithName(name, html: html, baseURL: baseURL)
    }
    
    // 创建产品信息
    private func createProductInfoWithName(_ name: String, html: String, baseURL: String) -> ProductPageInfo {
        // 基本信息
        let variants = extractShopifyVariants(from: html, baseURL: baseURL)
        let imageURL = extractImageURL(from: html)
        let description = extractProductDescription(from: html)
        let brand = extractProductBrand(from: html)
        
        print("🔧 [商品解析] 提取到 \(variants.count) 个变体")
        if let imageURL = imageURL {
            print("🖼️ [商品解析] 商品图片: \(imageURL)")
        }
        if let description = description {
            print("📄 [商品解析] 商品描述长度: \(description.count) 字符")
        }
        if let brand = brand {
            print("🏷️ [商品解析] 品牌: \(brand)")
        }
        
        let info = ProductPageInfo(
            name: name,
            availableVariants: variants,
            imageURL: imageURL,
            description: description,
            brand: brand,
            category: nil
        )
        
        print("✅ [商品解析] 通用解析完成")
        return info
    }
    
    // 备选商品名称提取方法
    private func extractFallbackProductName(from html: String, url: String) -> String? {
        print("🔄 [备选解析] 开始备选商品名称提取...")
        
        // 方法1: 从URL中提取商品名称
        if let urlName = extractNameFromURL(url) {
            print("✅ [备选解析] 从URL提取到名称: \(urlName)")
            return urlName
        }
        
        // 方法2: 查找任何h1-h6标签
        let headerPatterns = [
            #"<h[1-6][^>]*>(.*?)</h[1-6]>"#,
            #"<p[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)</p>"#,
            #"<div[^>]*class="[^"]*name[^"]*"[^>]*>(.*?)</div>"#
        ]
        
        for pattern in headerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                let matches = regex.matches(in: html, options: [], range: range)
                
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: html) {
                        let name = String(html[nameRange])
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if isValidProductName(name) {
                            print("✅ [备选解析] 从标题标签提取到名称: \(name)")
                            return name
                        }
                    }
                }
            }
        }
        
        // 方法3: 使用页面标题作为最后手段
        if let titleMatch = html.range(of: #"<title>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) {
            let title = String(html[titleMatch])
                .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 清理常见的网站后缀
            let cleanTitle = title
                .replacingOccurrences(of: " - Popmart", with: "")
                .replacingOccurrences(of: " | Popmart", with: "")
                .replacingOccurrences(of: " - Amazon", with: "")
                .replacingOccurrences(of: " | Amazon", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if isValidProductName(cleanTitle) {
                print("✅ [备选解析] 从页面标题提取到名称: \(cleanTitle)")
                return cleanTitle
            }
        }
        
        print("❌ [备选解析] 所有备选方法都失败了")
        return nil
    }
    
    // MARK: - Amazon商品解析
    private func extractAmazonProductInfo(from html: String, baseURL: String) -> ProductPageInfo? {
        print("🛒 [Amazon解析] 开始解析Amazon商品页面: \(baseURL)")
        
        guard let name = extractAmazonProductName(from: html) else {
            print("❌ [Amazon解析] 无法提取商品名称，解析失败")
            return nil
        }
        
        print("📝 [Amazon解析] 商品名称: \(name)")
        
        let variants = extractAmazonSizeVariants(from: html, baseURL: baseURL) ?? []
        print("🔧 [Amazon解析] 提取到 \(variants.count) 个变体")
        
        // 如果没有找到变体，创建默认变体
        let finalVariants: [ProductPageInfo.ProductVariantInfo]
        if variants.isEmpty {
            print("🔧 [Amazon解析] 创建默认变体")
            let price = extractAmazonPrice(from: html)
            let isAvailable = extractAmazonAvailability(from: html)
            let imageURL = extractAmazonImageURL(from: html)
            
            print("💰 [Amazon解析] 价格: \(price ?? "未找到")")
            print("📦 [Amazon解析] 库存状态: \(isAvailable ? "有库存" : "缺货")")
            
            let defaultVariant = ProductPageInfo.ProductVariantInfo(
                variant: .singleBox,
                price: price,
                isAvailable: isAvailable,
                url: baseURL,
                imageURL: imageURL,
                sku: nil,
                stockLevel: nil,
                variantName: "默认选项"
            )
            finalVariants = [defaultVariant]
        } else {
            finalVariants = variants
        }
        
        let imageURL = extractAmazonImageURL(from: html)
        if let imageURL = imageURL {
            print("🖼️ [Amazon解析] 商品图片: \(imageURL)")
        } else {
            print("⚠️ [Amazon解析] 未找到商品图片")
        }
        
        let description = extractAmazonDescription(from: html)
        if let description = description {
            print("📄 [Amazon解析] 商品描述长度: \(description.count) 字符")
        }
        
        let brand = extractAmazonBrand(from: html)
        if let brand = brand {
            print("🏷️ [Amazon解析] 品牌: \(brand)")
        }
        
        let productInfo = ProductPageInfo(
            name: name,
            availableVariants: finalVariants,
            imageURL: imageURL,
            description: description,
            brand: brand,
            category: nil
        )
        
        print("✅ [Amazon解析] 成功创建产品信息")
        return productInfo
    }
    
    private func extractAmazonProductName(from html: String) -> String? {
        let namePatterns = [
            // Amazon产品标题的各种可能格式
            #"<span[^>]*id="productTitle"[^>]*>\s*(.*?)\s*</span>"#,
            #"<h1[^>]*id="title"[^>]*>\s*(.*?)\s*</h1>"#,
            #"<h1[^>]*class="[^"]*title[^"]*"[^>]*>\s*(.*?)\s*</h1>"#,
            #"<meta[^>]*property="og:title"[^>]*content="([^"]+)""#,
            #"<meta[^>]*name="title"[^>]*content="([^"]+)""#,
            #"<title>\s*(.*?)\s*</title>"#,
            // Amazon特有的JSON数据中的标题
            #""title":\s*"([^"]+)""#,
            #""productTitle":\s*"([^"]+)""#
        ]
        
        print("🔍 [Amazon解析] 开始提取商品名称...")
        
        for (index, pattern) in namePatterns.enumerated() {
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
                            .replacingOccurrences(of: "&#39;", with: "'")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !name.isEmpty && !name.contains("Amazon.de") && !name.contains("Amazon") && name.count > 5 {
                            print("✅ [Amazon解析] 使用模式 \(index + 1) 成功提取商品名称: \(name)")
                            return name
                        } else {
                            print("⚠️ [Amazon解析] 模式 \(index + 1) 匹配但名称无效: \(name)")
                        }
                    }
                }
            }
        }
        
        print("❌ [Amazon解析] 无法提取商品名称")
        return nil
    }
    
    private func extractAmazonSizeVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo]? {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        print("🔧 [Amazon变体] 开始精确解析Amazon变体...")
        
        // 1. 专门查找Amazon的尺寸/样式选择器
        let amazonSelectPatterns = [
            // Amazon德国特有的尺寸选择器
            #"<select[^>]*(?:name|id)="dropdown_selected_(?:size_name|style_name|color_name)"[^>]*>(.*?)</select>"#,
            // Amazon的变体下拉菜单
            #"<select[^>]*class="[^"]*a-native-dropdown[^"]*"[^>]*name="[^"]*(?:size|style|color)[^"]*"[^>]*>(.*?)</select>"#,
            // 通用Amazon选择器
            #"<select[^>]*data-feature-name="[^"]*(?:size|style|color)[^"]*"[^>]*>(.*?)</select>"#
        ]
        
        for (index, pattern) in amazonSelectPatterns.enumerated() {
            print("🔍 [Amazon变体] 尝试Amazon模式 \(index + 1): \(pattern.prefix(50))...")
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let selectContent = Range(match.range(at: 1), in: html) {
                        let optionsHTML = String(html[selectContent])
                        print("📦 [Amazon变体] 找到选择器内容长度: \(optionsHTML.count)")
                        variants = parseAmazonSelectOptions(optionsHTML, baseURL: baseURL)
                        print("✅ [Amazon变体] 从模式 \(index + 1) 提取到 \(variants.count) 个变体")
                        if !variants.isEmpty {
                            break
                        }
                    }
                }
            }
        }
        
        // 2. 如果没有找到select，尝试查找按钮式选择器
        if variants.isEmpty {
            print("🔍 [Amazon变体] 未找到select，尝试按钮式选择器...")
            variants = extractAmazonButtonVariants(from: html, baseURL: baseURL)
        }
        
        // 3. 严格过滤变体 - 只保留明确的尺寸/样式选项
        let validVariants = variants.filter { variant in
            guard let name = variant.variantName else { 
                print("⚠️ [Amazon过滤] 跳过无名称变体")
                return false 
            }
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 更严格的过滤条件
            let invalidKeywords = [
                "select", "wählen", "choose", "option", "---", "please", "bitte", 
                "auswählen", "please select", "bitte wählen", "dropdown", "menu"
            ]
            
            // 检查是否包含无效关键词
            let hasInvalidKeyword = invalidKeywords.contains { cleanName.lowercased().contains($0) }
            
            // 检查是否是有效的尺寸/样式描述
            let validSizePatterns = [
                #"\d+\s*(?:cm|mm|inch|"|')"#,  // 尺寸信息
                #"\d+\s*(?:pack|piece|stück)"#,  // 数量信息
                #"(?:small|medium|large|klein|mittel|groß)"#,  // 尺寸描述
                #"\w+\s*-\s*\w+"#  // 带连字符的描述
            ]
            
            let hasValidPattern = validSizePatterns.contains { pattern in
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    return regex.firstMatch(in: cleanName, options: [], range: NSRange(location: 0, length: cleanName.count)) != nil
                }
                return false
            }
            
            let isValid = !cleanName.isEmpty && 
                         cleanName.count >= 3 && 
                         cleanName.count <= 100 && 
                         !hasInvalidKeyword &&
                         (hasValidPattern || cleanName.contains("-") || cleanName.contains("x"))
            
            print("🔍 [Amazon过滤] '\(cleanName)': 有效=\(isValid), 长度=\(cleanName.count), 无效关键词=\(hasInvalidKeyword), 有效模式=\(hasValidPattern)")
            
            return isValid
        }
        
        print("✅ [Amazon变体] 最终过滤后剩余 \(validVariants.count) 个有效变体")
        
        // 如果过滤后变体太少，放宽条件重新解析
        if validVariants.count < 2 && variants.count > validVariants.count {
            print("⚠️ [Amazon变体] 变体数量太少，尝试放宽过滤条件...")
            let relaxedVariants = variants.filter { variant in
                guard let name = variant.variantName else { return false }
                let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let strictInvalidKeywords = ["select", "wählen", "choose", "please", "bitte"]
                let hasStrictInvalid = strictInvalidKeywords.contains { cleanName.lowercased().contains($0) }
                
                return !cleanName.isEmpty && 
                       cleanName.count >= 2 && 
                       cleanName.count <= 150 && 
                       !hasStrictInvalid
            }
            
            print("🔧 [Amazon变体] 放宽条件后得到 \(relaxedVariants.count) 个变体")
            return relaxedVariants.isEmpty ? nil : relaxedVariants
        }
        
        return validVariants.isEmpty ? nil : validVariants
    }
    
    // 解析Amazon的select选项
    private func parseAmazonSelectOptions(_ html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        print("📋 [Amazon选项] 开始解析select选项...")
        
        let optionPattern = #"<option[^>]*value="([^"]*)"[^>]*>(.*?)</option>"#
        if let regex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: html.count)
            let matches = regex.matches(in: html, options: [], range: range)
            
            print("🔍 [Amazon选项] 找到 \(matches.count) 个option元素")
            
            for (index, match) in matches.enumerated() {
                if let valueRange = Range(match.range(at: 1), in: html),
                   let textRange = Range(match.range(at: 2), in: html) {
                    
                    let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = String(html[textRange])
                        .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("📝 [Amazon选项] \(index + 1): 值='\(value)', 文本='\(text)'")
                    
                    // 跳过无效选项
                    if value.isEmpty || value == "-1" || text.isEmpty {
                        print("⚠️ [Amazon选项] 跳过无效选项: 值='\(value)', 文本='\(text)'")
                        continue
                    }
                    
                    // 尝试从选项文本中提取价格
                    let extractedPrice = extractDetailedPrice(from: text)
                    print("💰 [Amazon选项] 从文本中提取的价格: \(extractedPrice ?? "无")")
                    
                    let variant = ProductPageInfo.ProductVariantInfo(
                        variant: determineVariantFromAmazonOption(text),
                        price: extractedPrice,
                        isAvailable: true,
                        url: constructAmazonVariantURL(baseURL: baseURL, value: value),
                        imageURL: nil,
                        sku: value,
                        stockLevel: nil,
                        variantName: text
                    )
                    variants.append(variant)
                }
            }
        }
        
        print("📦 [Amazon选项] 总共解析出 \(variants.count) 个变体")
        return variants
    }
    
    // 增强的价格提取方法
    private func extractDetailedPrice(from text: String) -> String? {
        print("💰 [价格提取] 分析文本: '\(text)'")
        
        let pricePatterns = [
            // 标准欧元格式
            #"€\s*(\d+[.,]\d{1,2})"#,
            #"(\d+[.,]\d{1,2})\s*€"#,
            #"EUR\s*(\d+[.,]\d{1,2})"#,
            #"(\d+[.,]\d{1,2})\s*EUR"#,
            // 美元格式
            #"\$\s*(\d+[.,]\d{1,2})"#,
            #"(\d+[.,]\d{1,2})\s*\$"#,
            #"USD\s*(\d+[.,]\d{1,2})"#,
            // 英镑格式
            #"£\s*(\d+[.,]\d{1,2})"#,
            #"(\d+[.,]\d{1,2})\s*£"#,
            // 带括号的价格
            #"\(\s*€?\s*(\d+[.,]\d{1,2})\s*€?\s*\)"#,
            #"\[\s*€?\s*(\d+[.,]\d{1,2})\s*€?\s*\]"#,
            // 更宽泛的数字格式
            #"(\d+[.,]\d{1,2})"#
        ]
        
        for (index, pattern) in pricePatterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: text.count)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    
                    // 尝试从不同的捕获组中获取价格
                    for i in 1..<match.numberOfRanges {
                        let rangeAtIndex = match.range(at: i)
                        if rangeAtIndex.location != NSNotFound,
                           let priceRange = Range(rangeAtIndex, in: text) {
                            let priceString = String(text[priceRange])
                                .replacingOccurrences(of: ",", with: ".")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            if let priceValue = Double(priceString), priceValue > 0 && priceValue < 10000 {
                                let formattedPrice = "€\(String(format: "%.2f", priceValue))"
                                print("✅ [价格提取] 模式\(index + 1)组\(i): 找到价格 '\(formattedPrice)'")
                                return formattedPrice
                            }
                        }
                    }
                    
                    // 如果没有捕获组，尝试整个匹配
                    if let fullRange = Range(match.range(at: 0), in: text) {
                        let fullMatch = String(text[fullRange])
                        print("💰 [价格提取] 模式\(index + 1): 完整匹配 '\(fullMatch)'")
                        
                        // 从完整匹配中提取数字
                        let numberPattern = #"(\d+[.,]\d{1,2})"#
                        if let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: []),
                           let numberMatch = numberRegex.firstMatch(in: fullMatch, options: [], range: NSRange(location: 0, length: fullMatch.count)),
                           let numberRange = Range(numberMatch.range(at: 1), in: fullMatch) {
                            let numberString = String(fullMatch[numberRange])
                                .replacingOccurrences(of: ",", with: ".")
                            
                            if let priceValue = Double(numberString), priceValue > 0 && priceValue < 10000 {
                                let formattedPrice = "€\(String(format: "%.2f", priceValue))"
                                print("✅ [价格提取] 从完整匹配提取: '\(formattedPrice)'")
                                return formattedPrice
                            }
                        }
                    }
                }
            }
        }
        
        print("❌ [价格提取] 未找到有效价格")
        return nil
    }
    
    // 根据选项文本确定变体类型
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
    
    // 从HTML中提取Amazon价格
    private func extractAmazonPrice(from html: String) -> String? {
        let pricePatterns = [
            // Amazon标准价格格式
            #"<span[^>]*class="[^"]*a-price-whole[^"]*"[^>]*>([^<]+)</span><span[^>]*class="[^"]*a-price-fraction[^"]*"[^>]*>([^<]+)</span>"#,
            #"<span[^>]*class="[^"]*a-price[^"]*amount[^"]*"[^>]*>([^<]+)</span>"#,
            #"<span[^>]*class="[^"]*a-price[^"]*"[^>]*>[^<]*<span[^>]*>([^<]*€[^<]*)</span>"#,
            // 通用价格格式
            #"€\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*€"#,
            #"EUR\s*(\d+[.,]\d{2})"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    let numberOfRanges = match.numberOfRanges
                    
                    if numberOfRanges >= 3 {
                        // 处理整数和小数部分分离的情况
                        if let wholeRange = Range(match.range(at: 1), in: html),
                           let fractionRange = Range(match.range(at: 2), in: html) {
                            let whole = String(html[wholeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let fraction = String(html[fractionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            return "€\(whole).\(fraction)"
                        }
                    } else if numberOfRanges >= 2 {
                        // 处理完整价格
                        if let priceRange = Range(match.range(at: 1), in: html) {
                            let price = String(html[priceRange])
                                .replacingOccurrences(of: ",", with: ".")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            if !price.contains("€") && !price.contains("$") && !price.contains("EUR") {
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
    
    // 检查Amazon商品可用性
    private func extractAmazonAvailability(from html: String) -> Bool {
        let htmlLowercase = html.lowercased()
        
        let unavailableKeywords = [
            "currently unavailable", "out of stock", "ausverkauft", "nicht verfügbar",
            "temporarily out of stock", "vorübergehend nicht verfügbar",
            "derzeit nicht verfügbar", "nicht auf lager"
        ]
        
        let availableKeywords = [
            "add to cart", "in den warenkorb", "buy now", "jetzt kaufen",
            "add to basket", "in den einkaufswagen", "in stock", "verfügbar",
            "auf lager", "sofort lieferbar"
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
    
    // MARK: - Shopify变体处理 - 增强版
    private func extractShopifyVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        print("🔧 [变体解析] 开始提取变体信息...")
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 方法1: 提取Shopify产品配置
        if let shopifyConfig = extractShopifyProductConfig(from: html) {
            print("✅ [变体解析] 找到Shopify配置")
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
        
        // 方法2: 通用变体选择器检测
        if variants.isEmpty {
            print("🔄 [变体解析] Shopify配置为空，尝试通用选择器...")
            variants = extractGenericVariants(from: html, baseURL: baseURL)
        }
        
        // 方法3: HTML表单选择器
        if variants.isEmpty {
            print("🔄 [变体解析] 通用选择器为空，尝试表单选择器...")
            variants = extractFormVariants(from: html, baseURL: baseURL)
        }
        
        // 方法4: 如果没有找到任何变体，创建默认变体
        if variants.isEmpty {
            print("🔄 [变体解析] 未找到变体，创建默认变体...")
            variants = createDefaultVariant(baseURL: baseURL, html: html)
        }
        
        print("📦 [变体解析] 最终提取到 \(variants.count) 个变体")
        return variants
    }
    
    // 从HTML中提取通用变体信息
    private func extractGenericVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        let variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 检测变体选择器的模式
        let variantPatterns = [
            // JSON数据中的变体
            #""variants":\s*\[(.*?)\]"#,
            // 选择器中的选项
            #"<select[^>]*name="[^"]*variant[^"]*"[^>]*>(.*?)</select>"#,
            #"<select[^>]*class="[^"]*variant[^"]*"[^>]*>(.*?)</select>"#,
            // 按钮式变体选择器
            #"<div[^>]*class="[^"]*variant[^"]*selector[^"]*"[^>]*>(.*?)</div>"#,
            // Radio按钮组
            #"<input[^>]*type="radio"[^>]*name="[^"]*variant[^"]*"[^>]*>"#
        ]
        
        for pattern in variantPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if regex.firstMatch(in: html, options: [], range: range) != nil {
                    print("✅ [变体解析] 匹配到变体模式")
                    // 这里可以进一步解析匹配到的内容
                    break
                }
            }
        }
        
        return variants
    }
    
    // 从表单元素中提取变体
    private func extractFormVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        // 查找option标签
        let optionPattern = #"<option[^>]*value="([^"]*)"[^>]*>(.*?)</option>"#
        
        if let regex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: html.count)
            let matches = regex.matches(in: html, options: [], range: range)
            
            for match in matches {
                if let valueRange = Range(match.range(at: 1), in: html),
                   let textRange = Range(match.range(at: 2), in: html) {
                    
                    let value = String(html[valueRange])
                    let text = String(html[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 跳过空值或默认选项
                    if !value.isEmpty && !text.isEmpty && 
                       !text.lowercased().contains("select") && 
                       !text.lowercased().contains("choose") {
                        
                        let variant = determineVariantType(from: text)
                        let variantInfo = ProductPageInfo.ProductVariantInfo(
                            variant: variant,
                            price: nil,
                            isAvailable: true,
                            url: constructVariantURL(baseURL: baseURL, sku: value),
                            imageURL: nil,
                            sku: value,
                            stockLevel: nil,
                            variantName: text
                        )
                        
                        variants.append(variantInfo)
                    }
                }
            }
        }
        
        return variants
    }
    
    // 创建默认变体
    private func createDefaultVariant(baseURL: String, html: String) -> [ProductPageInfo.ProductVariantInfo] {
        let isAvailable = checkAvailability(from: html)
        let price = extractEnhancedPrice(from: html)
        
        let defaultVariant = ProductPageInfo.ProductVariantInfo(
            variant: .singleBox,
            price: price,
            isAvailable: isAvailable,
            url: baseURL,
            imageURL: extractImageURL(from: html),
            sku: nil,
            stockLevel: nil,
            variantName: "默认选项"
        )
        
        print("📦 [变体解析] 创建默认变体: \(defaultVariant.variantName ?? "未知")")
        return [defaultVariant]
    }
    
    // 从Shopify网站提取变体信息 - 增强版
    private func extractShopifyProductConfig(from html: String) -> [String: Any]? {
        // 查找Shopify产品数据的各种模式
        let shopifyPatterns = [
            // 标准Shopify产品配置
            #"window\.ShopifyAnalytics\.meta\.product\s*=\s*(\{.*?\});"#,
            #"window\.ShopifyAnalytics\.meta\s*=\s*\{.*?product:\s*(\{.*?\})"#,
            // 产品JSON数据
            #"product:\s*(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})"#,
            // 变体数组
            #""variants":\s*(\[.*?\])"#,
            // 直接的product对象
            #"var\s+product\s*=\s*(\{.*?\});"#
        ]
        
        for pattern in shopifyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let jsonRange = Range(match.range(at: 1), in: html) {
                        let jsonString = String(html[jsonRange])
                        
                        // 尝试解析JSON
                        if let jsonData = jsonString.data(using: .utf8),
                           let productConfig = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            print("✅ [变体解析] 成功解析Shopify配置")
                            return productConfig
                        }
                    }
                }
            }
        }
        
        print("❌ [变体解析] 未找到Shopify配置")
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
        for timer in variantTimers.values {
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
    
    // 解析Amazon的按钮式变体选择器
    private func extractAmazonButtonVariants(from html: String, baseURL: String) -> [ProductPageInfo.ProductVariantInfo] {
        var variants: [ProductPageInfo.ProductVariantInfo] = []
        
        print("🔘 [Amazon按钮] 开始解析按钮式选择器...")
        
        let buttonPatterns = [
            // Amazon的ASIN按钮
            #"<li[^>]*data-defaultasin="([^"]*)"[^>]*data-dp-url="[^"]*"[^>]*>(.*?)</li>"#,
            // Amazon的变体按钮
            #"<span[^>]*data-asin="([^"]*)"[^>]*title="([^"]*)"[^>]*>"#,
            #"<button[^>]*data-value="([^"]*)"[^>]*>(.*?)</button>"#,
            // Amazon的颜色/尺寸按钮
            #"<div[^>]*class="[^"]*swatches[^"]*"[^>]*data-asin="([^"]*)"[^>]*>(.*?)</div>"#
        ]
        
        for (patternIndex, pattern) in buttonPatterns.enumerated() {
            print("🔍 [Amazon按钮] 尝试按钮模式 \(patternIndex + 1)...")
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                let matches = regex.matches(in: html, options: [], range: range)
                
                print("🔍 [Amazon按钮] 模式 \(patternIndex + 1) 找到 \(matches.count) 个匹配")
                
                for (matchIndex, match) in matches.enumerated() {
                    if let valueRange = Range(match.range(at: 1), in: html),
                       let textRange = Range(match.range(at: 2), in: html) {
                        
                        let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let text = String(html[textRange])
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        print("📝 [Amazon按钮] 匹配 \(matchIndex + 1): 值='\(value)', 文本='\(text)'")
                        
                        if !value.isEmpty && !text.isEmpty && text.count <= 100 {
                            let extractedPrice = extractDetailedPrice(from: text)
                            print("💰 [Amazon按钮] 从文本中提取的价格: \(extractedPrice ?? "无")")
                            
                            let variant = ProductPageInfo.ProductVariantInfo(
                                variant: determineVariantFromAmazonOption(text),
                                price: extractedPrice,
                                isAvailable: true,
                                url: constructAmazonVariantURL(baseURL: baseURL, value: value),
                                imageURL: nil,
                                sku: value,
                                stockLevel: nil,
                                variantName: text
                            )
                            variants.append(variant)
                        }
                    }
                }
                
                if !variants.isEmpty {
                    print("✅ [Amazon按钮] 从模式 \(patternIndex + 1) 获得 \(variants.count) 个变体")
                    break
                }
            }
        }
        
        print("📦 [Amazon按钮] 总共解析出 \(variants.count) 个按钮变体")
        return variants
    }
    
    // 构建Amazon变体URL
    private func constructAmazonVariantURL(baseURL: String, value: String) -> String {
        if value.count == 10 && value.allSatisfy({ $0.isLetter || $0.isNumber }) {
            // 如果是ASIN格式，构建新的商品页面URL
            if let baseComponents = URLComponents(string: baseURL) {
                return "https://\(baseComponents.host ?? "www.amazon.de")/dp/\(value)"
            }
        }
        
        // 否则作为参数添加到当前URL
        let separator = baseURL.contains("?") ? "&" : "?"
        return "\(baseURL)\(separator)th=1&psc=1&variant=\(value)"
    }
    
    // MARK: - 反检测请求创建
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
    
    // MARK: - 更新产品统计信息
    private func updateProductStats(_ product: Product, incrementError: Bool) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            // 更新第一个变体的统计信息
            if let firstVariantIndex = products[index].variants.indices.first {
                products[index].variants[firstVariantIndex].incrementCheck()
                if incrementError {
                    products[index].variants[firstVariantIndex].incrementError()
                } else {
                    products[index].variants[firstVariantIndex].incrementSuccess()
                }
            }
            saveProducts()
        }
    }
    
    // MARK: - 解析产品状态（增强版本）
    private func parseProductStatus(from html: String, for product: Product, responseTime: TimeInterval, statusCode: Int) {
        updateProductStats(product, incrementError: false)
        
        // 检查是否被反爬虫检测
        if statusCode == 403 || statusCode == 429 || html.contains("Access Denied") || html.contains("Cloudflare") {
            addLog(for: product, status: .antiBot, message: "检测到反爬虫机制 (HTTP \(statusCode))", responseTime: responseTime, httpStatusCode: statusCode)
            return
        }
        
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }) else { return }
        var currentProduct = products[productIndex]
        
        // 增强的商品信息解析
        let extractedName = extractProductName(from: html, baseURL: product.url)
        let extractedPrice = extractEnhancedPrice(from: html)
        let isAvailable = determineEnhancedAvailability(from: html)
        let imageURL = extractEnhancedImage(from: html, baseURL: product.url)
        
        // 记录调试信息
        if product.enableDebugLogging {
            var debugInfo: [String] = []
            debugInfo.append("解析结果:")
            debugInfo.append("- 商品名称: \(extractedName ?? "未找到")")
            debugInfo.append("- 价格: \(extractedPrice ?? "未找到")")
            debugInfo.append("- 可用性: \(isAvailable)")
            debugInfo.append("- 图片URL: \(imageURL ?? "未找到")")
            addLog(for: product, status: .success, message: debugInfo.joined(separator: "\n"))
        }
        
        // 更新产品信息
        if let name = extractedName, !name.isEmpty && name != currentProduct.name {
            currentProduct.name = name
        }
        
        // 更新第一个变体的信息
        if !currentProduct.variants.isEmpty {
            var firstVariant = currentProduct.variants[0]
            let previouslyAvailable = firstVariant.isAvailable
            
            if let price = extractedPrice {
                firstVariant.price = price
            }
            
            firstVariant.isAvailable = isAvailable
            firstVariant.lastChecked = Date()
            
            // 检查可用性变化
            if previouslyAvailable != isAvailable {
                let statusMessage = isAvailable ? "商品现在有货了！🎉" : "商品已缺货 😞"
                addLog(for: currentProduct, status: .availabilityChanged, message: "[\(firstVariant.name)] \(statusMessage)", responseTime: responseTime)
                
                // 添加到可用性历史
                let change = AvailabilityChange(
                    variantId: firstVariant.id,
                    variantName: firstVariant.name,
                    wasAvailable: previouslyAvailable,
                    isAvailable: isAvailable,
                    price: extractedPrice
                )
                currentProduct.availabilityHistory.append(change)
            } else {
                addLog(for: currentProduct, status: .success, message: "[\(firstVariant.name)] 检查完成 - 状态: \(isAvailable ? "有货" : "缺货")", responseTime: responseTime)
            }
            
            currentProduct.variants[0] = firstVariant
        }
        
        products[productIndex] = currentProduct
        saveProducts()
    }
    
    // MARK: - 增强的解析方法
    
    // 提取商品名称 - 优先主标题
    private func extractProductName(from html: String, baseURL: String) -> String? {
        // 优先匹配商品详情主标题
        let namePatterns = [
            #"<h1[^>]*>([^<]+)</h1>"#, // 最高优先级：主标题
            #"<h1[^>]*class=\"[^\"]*product[^\"]*title[^\"]*\"[^>]*>(.*?)</h1>"#,
            #"<h1[^>]*class=\"[^\"]*title[^\"]*\"[^>]*>(.*?)</h1>"#,
            #"<div[^>]*class=\"[^\"]*product[^\"]*name[^\"]*\"[^>]*>(.*?)</div>"#,
            #"<span[^>]*class=\"[^\"]*product[^\"]*title[^\"]*\"[^>]*>(.*?)</span>"#,
            // JSON-LD 结构化数据
            #""name"\s*:\s*"([^"]+)""#,
            #""@type"\s*:\s*"Product".*?"name"\s*:\s*"([^"]+)""#,
            // Open Graph 元标签
            #"<meta[^>]*property=\"og:title\"[^>]*content=\"([^"]+)\""#,
            #"<meta[^>]*name=\"twitter:title\"[^>]*content=\"([^"]+)\""#,
            // 标准HTML标签
            #"<h2[^>]*class=\"[^\"]*product[^\"]*\"[^>]*>(.*?)</h2>"#,
            // 通用元标签
            #"<meta[^>]*name=\"title\"[^>]*content=\"([^"]+)\""#,
            #"<meta[^>]*property=\"title\"[^>]*content=\"([^"]+)\""#,
            // 页面标题（最后备选）
            #"<title>(.*?)</title>"#
        ]
        print("🔍 [商品解析] 开始提取商品名称，使用 \(namePatterns.count) 种模式...")
        for (index, pattern) in namePatterns.enumerated() {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
                    if let nameRange = Range(captureRange, in: html) {
                        var cleanedName = String(html[nameRange])
                        cleanedName = cleanedName
                            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .replacingOccurrences(of: "&#39;", with: "'")
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "\t", with: " ")
                            .replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidProductName(cleanedName) {
                            print("✅ [商品解析] 使用模式 \(index + 1) 成功提取商品名称: \(cleanedName)")
                            return cleanedName
                        } else {
                            print("⚠️ [商品解析] 模式 \(index + 1) 匹配但名称无效: \(cleanedName)")
                        }
                    }
                }
            } catch {
                print("❌ [商品解析] 正则表达式模式 \(index + 1) 编译失败: \(error)")
                continue
            }
        }
        print("❌ [商品解析] 所有模式都无法提取有效的商品名称")
        if let urlBasedName = extractNameFromURL(baseURL) {
            print("🔄 [商品解析] 从URL中提取备选名称: \(urlBasedName)")
            return urlBasedName
        }
        return nil
    }

    // 增强价格提取 - 针对Popmart网站优化
    private func extractEnhancedPrice(from html: String) -> String? {
        print("💰 [价格提取] 开始提取价格信息...")
        print("📄 [价格提取] HTML片段预览: \(String(html.prefix(500)).replacingOccurrences(of: "\n", with: " "))")
        
        // 提取HTML中包含价格相关信息的行
        let priceRelatedLines = html.components(separatedBy: .newlines).filter { line in
            let lowercaseLine = line.lowercased()
            return lowercaseLine.contains("€") || 
                   lowercaseLine.contains("eur") || 
                   lowercaseLine.contains("price") || 
                   lowercaseLine.contains("preis") ||
                   lowercaseLine.contains("cost") ||
                   lowercaseLine.contains("amount")
        }
        
        print("💰 [价格提取] 找到 \(priceRelatedLines.count) 行包含价格相关信息")
        for (index, line) in priceRelatedLines.prefix(5).enumerated() {
            print("💰 [价格行 \(index + 1)] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        
        // Popmart网站专用价格模式 - 扩展版
        let popmartPricePatterns = [
            // 标准价格显示模式
            #"<span[^>]*class=\"[^\"]*price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"<div[^>]*class=\"[^\"]*price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"<span[^>]*class=\"[^\"]*product-price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"<span[^>]*class=\"[^\"]*current-price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"<span[^>]*class=\"[^\"]*selling-price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"<span[^>]*class=\"[^\"]*final-price[^\"]*\"[^>]*>\s*€\s*([0-9]+[.,][0-9]{1,2})"#,
            
            // HTML属性中的价格
            #"data-price=\"([0-9]+[.,][0-9]{1,2})\""#,
            #"data-value=\"([0-9]+[.,][0-9]{1,2})\""#,
            #"data-amount=\"([0-9]+[.,][0-9]{1,2})\""#,
            
            // JSON数据中的价格（多种变体）
            #"\"price\":\s*\"?€?\s*([0-9]+[.,][0-9]{1,2})"#,
            #"\"amount\":\s*\"?([0-9]+[.,][0-9]{1,2})"#,
            #"\"value\":\s*\"?([0-9]+[.,][0-9]{1,2})"#,
            #"\"cost\":\s*\"?([0-9]+[.,][0-9]{1,2})"#,
            #"\"retail_price\":\s*\"?([0-9]+[.,][0-9]{1,2})"#,
            #"\"selling_price\":\s*\"?([0-9]+[.,][0-9]{1,2})"#,
            
            // 内联样式和文本中的价格
            #"€\s*([0-9]+[.,][0-9]{1,2})\s*(?:EUR|€|</|\s|$)"#,
            #"([0-9]+[.,][0-9]{1,2})\s*€"#,
            #"EUR\s*([0-9]+[.,][0-9]{1,2})"#,
            #"([0-9]+[.,][0-9]{1,2})\s*EUR"#,
            
            // 特殊格式
            #"price[^>]*>.*?€\s*([0-9]+[.,][0-9]{1,2})"#,
            #"preis[^>]*>.*?€\s*([0-9]+[.,][0-9]{1,2})"#,
            
            // 更宽松的匹配（可能有额外的空格或标签）
            #"<[^>]*price[^>]*>.*?([0-9]+[.,][0-9]{1,2})"#,
            #">.*?€.*?([0-9]+[.,][0-9]{1,2})"#,
            #">.*?([0-9]+[.,][0-9]{1,2}).*?€"#
        ]
        
        for (index, pattern) in popmartPricePatterns.enumerated() {
            print("💰 [价格提取] 尝试模式 \(index + 1): \(pattern)")
            if let priceString = extractFirstMatch(pattern: pattern, from: html) {
                print("💰 [价格提取] 模式 \(index + 1) 匹配到原始价格: '\(priceString)'")
                let normalizedPrice = priceString.replacingOccurrences(of: ",", with: ".")
                if let priceValue = Double(normalizedPrice) {
                    let formattedPrice = "€\(normalizedPrice)"
                    print("✅ [价格提取] 使用模式 \(index + 1) 成功提取价格: \(formattedPrice) (数值: \(priceValue))")
                    return formattedPrice
                } else {
                    print("⚠️ [价格提取] 模式 \(index + 1) 匹配但无法转换为数字: '\(priceString)' -> '\(normalizedPrice)'")
                }
            } else {
                print("💰 [价格提取] 模式 \(index + 1) 无匹配")
            }
        }
        
        // 如果专用模式都不匹配，尝试更通用的模式
        print("💰 [价格提取] 专用模式未找到价格，尝试通用模式...")
        let generalPricePatterns = [
            #"([0-9]{1,3}[.,][0-9]{2})\s*€"#,
            #"€\s*([0-9]{1,3}[.,][0-9]{2})"#,
            #"([0-9]{1,3}[.,][0-9]{1,2})\s*EUR"#,
            #"EUR\s*([0-9]{1,3}[.,][0-9]{1,2})"#,
            #"([0-9]{1,3}[.,][0-9]{2})"#  // 纯数字模式（最后尝试）
        ]
        
        for (index, pattern) in generalPricePatterns.enumerated() {
            print("💰 [价格提取] 尝试通用模式 \(index + 1): \(pattern)")
            if let priceString = extractFirstMatch(pattern: pattern, from: html) {
                print("💰 [价格提取] 通用模式 \(index + 1) 匹配到: '\(priceString)'")
                let normalizedPrice = priceString.replacingOccurrences(of: ",", with: ".")
                if let priceValue = Double(normalizedPrice), priceValue > 0 && priceValue < 10000 { // 合理的价格范围
                    let formattedPrice = "€\(normalizedPrice)"
                    print("✅ [价格提取] 使用通用模式 \(index + 1) 提取到价格: \(formattedPrice)")
                    return formattedPrice
                } else {
                    print("⚠️ [价格提取] 通用模式 \(index + 1) 价格超出合理范围: '\(priceString)' -> \(normalizedPrice)")
                }
            }
        }
        
        print("❌ [价格提取] 所有模式都未能提取到价格信息")
        return nil
    }

    // 增强可用性判断 - 针对Popmart网站优化
    private func determineEnhancedAvailability(from html: String) -> Bool {
        print("🔍 [库存检测] 开始检测商品库存状态...")
        
        // Popmart网站专用检测逻辑
        if let stockStatus = checkPopmartSpecificStock(from: html) {
            print("✅ [库存检测] 使用Popmart专用检测: \(stockStatus ? "有货" : "缺货")")
            return stockStatus
        }
        
        // 通用缺货指示器
        let unavailableIndicators = [
            "ausverkauft", "nicht verfügbar", "out of stock", "sold out",
            "nicht auf lager", "vergriffen", "nicht lieferbar",
            "add-to-cart.*disabled", "btn.*disabled", "button.*disabled",
            "not-available", "out-of-stock", "sold-out",
            "缺货", "售完", "无库存", "已售完"
        ]
        
        for indicator in unavailableIndicators {
            let regex = try? NSRegularExpression(pattern: indicator, options: [.caseInsensitive])
            if regex?.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.count)) != nil {
                print("❌ [库存检测] 发现缺货指示器: \(indicator)")
                return false
            }
        }
        
        // 通用有货指示器
        let availableIndicators = [
            "add to cart", "buy now", "in stock", "verfügbar", "auf lager",
            "in den warenkorb", "jetzt kaufen", "zum warenkorb hinzufügen",
            "加入购物车", "立即购买", "现货", "有库存"
        ]
        
        for indicator in availableIndicators {
            let regex = try? NSRegularExpression(pattern: indicator, options: [.caseInsensitive])
            if regex?.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.count)) != nil {
                print("✅ [库存检测] 发现有货指示器: \(indicator)")
                return true
            }
        }
        
        // 检查按钮状态
        if html.contains("add-to-cart") && !html.contains("disabled") {
            print("✅ [库存检测] 发现可用的添加到购物车按钮")
            return true
        }
        
        // 如果找不到明确指示器，检查是否有价格且有add to cart（单变体商品）
        if extractEnhancedPrice(from: html) != nil && html.lowercased().contains("add to cart") {
            print("✅ [库存检测] 检测到价格和购买按钮，判断为有货")
            return true
        }
        
        print("❓ [库存检测] 无法确定库存状态，默认假设无货")
        return false
    }
    
    // MARK: - Popmart网站专用库存检测 - 改进版
    private func checkPopmartSpecificStock(from html: String) -> Bool? {
        print("🏪 [Popmart检测] 开始Popmart专用库存检测...")
        print("📄 [Popmart检测] HTML长度: \(html.count) 字符")
        
        // 先检查是否确实是Popmart网站
        if !html.lowercased().contains("popmart") {
            print("❓ [Popmart检测] 不是Popmart网站，跳过专用检测")
            return nil
        }
        
        // 方法1: 检测明确的缺货状态
        let outOfStockIndicators = [
            "ausverkauft",
            "sold out", 
            "nicht verfügbar",
            "nicht auf lager",
            "vergriffen",
            "out of stock"
        ]
        
        for indicator in outOfStockIndicators {
            if html.lowercased().contains(indicator) {
                print("❌ [Popmart检测] 发现缺货指示词: \(indicator)")
                return false
            }
        }
        
        // 方法2: 检测disabled按钮
        let disabledButtonPatterns = [
            #"<button[^>]*disabled[^>]*>"#,
            #"<button[^>]*class=\"[^\"]*disabled[^\"]*\""#,
            #"<button[^>]*class=\"[^\"]*btn[^\"]*disabled[^\"]*\""#
        ]
        
        for pattern in disabledButtonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: html.count)
                if regex.firstMatch(in: html, options: [], range: range) != nil {
                    print("❌ [Popmart检测] 发现disabled按钮")
                    return false
                }
            }
        }
        
        // 方法3: 检测有货按钮和文本
        let inStockIndicators = [
            "in den warenkorb",
            "add to cart",
            "zum warenkorb hinzufügen",
            "jetzt kaufen",
            "buy now",
            "in den warenkorb legen"
        ]
        
        var foundAddToCartButton = false
        for indicator in inStockIndicators {
            if html.lowercased().contains(indicator) {
                print("✅ [Popmart检测] 发现有货指示词: \(indicator)")
                foundAddToCartButton = true
                break
            }
        }
        
        // 方法4: 检测按钮状态
        let activeButtonPatterns = [
            #"<button[^>]*class=\"[^\"]*btn[^\"]*primary[^\"]*\"[^>]*>.*?(warenkorb|cart)"#,
            #"<button[^>]*class=\"[^\"]*btn[^\"]*add[^\"]*\"[^>]*>"#,
            #"<button[^>]*class=\"[^\"]*add[^\"]*to[^\"]*cart[^\"]*\"[^>]*>"#,
            #"<button[^>]*id=\"[^\"]*add[^\"]*cart[^\"]*\"[^>]*>"#
        ]
        
        var foundActiveButton = false
        for pattern in activeButtonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: html.count)
                if regex.firstMatch(in: html, options: [], range: range) != nil {
                    print("✅ [Popmart检测] 发现有效的购买按钮")
                    foundActiveButton = true
                    break
                }
            }
        }
        
        // 方法5: 检查价格信息
        let hasPrice = extractEnhancedPrice(from: html) != nil
        print("💰 [Popmart检测] 是否有价格信息: \(hasPrice)")
        
        // 综合判断
        if foundAddToCartButton || foundActiveButton {
            if hasPrice {
                print("✅ [Popmart检测] 综合判断: 有货 (有购买按钮且有价格)")
                return true
            } else {
                print("⚠️ [Popmart检测] 有购买按钮但无价格信息，判断为有货")
                return true
            }
        }
        
        // 如果没有找到明确的有货指示器，但有价格，可能是有货的
        if hasPrice {
            print("⚠️ [Popmart检测] 有价格但无明确购买按钮，需要进一步检查")
            
            // 检查是否有表单提交相关的元素
            if html.contains("form") && (html.contains("submit") || html.contains("button")) {
                print("✅ [Popmart检测] 发现表单和按钮，判断为有货")
                return true
            }
        }
        
        print("❓ [Popmart检测] 无法确定库存状态，返回nil让通用检测接管")
        return nil
    }
    
    // MARK: - JavaScript注入式库存检测（备用方案）
    private func generateStockCheckJavaScript() -> String {
        return """
        (function() {
            // 检查有货按钮
            let inStockButton = document.querySelector('button.btn.btn--primary');
            let hasAddToCart = inStockButton && 
                              (inStockButton.innerText.includes('In den Warenkorb') || 
                               inStockButton.innerText.includes('Add to Cart') ||
                               inStockButton.innerText.includes('zum Warenkorb'));
            
            // 检查缺货状态
            let soldOutButton = document.querySelector('button.btn.disabled');
            let soldOutStatus = document.querySelector('.product-action__status');
            let isSoldOut = (soldOutButton && soldOutButton.innerText.includes('Ausverkauft')) ||
                           (soldOutStatus && soldOutStatus.innerText.includes('Ausverkauft')) ||
                           (soldOutStatus && soldOutStatus.innerText.includes('Sold Out'));
            
            return {
                inStock: hasAddToCart && !isSoldOut,
                soldOut: isSoldOut,
                buttonText: inStockButton ? inStockButton.innerText : '',
                statusText: soldOutStatus ? soldOutStatus.innerText : ''
            };
        })();
        """
    }
    
    // MARK: - 调试和测试方法
    
    // 测试特定URL的解析能力
    func testURL(_ urlString: String, completion: @escaping (String) -> Void) {
        var resultLog = ""
        
        resultLog += "🔍 [URL测试] 开始测试URL: \(urlString)\n"
        resultLog += "⏰ [URL测试] 时间: \(Date())\n\n"
        
        guard let url = URL(string: urlString) else {
            resultLog += "❌ [URL测试] 无效的URL格式\n"
            completion(resultLog)
            return
        }
        
        var request = URLRequest(url: url)
        // 设置完整的浏览器请求头
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("https://www.popmart.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30.0
        
        resultLog += "📤 [请求详情] 设置完整的浏览器请求头\n"
        resultLog += "🌐 [请求详情] User-Agent: Chrome/120 (macOS)\n"
        resultLog += "🇩🇪 [请求详情] Accept-Language: de-DE,de;q=0.9\n\n"
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                resultLog += "❌ [URL测试] 网络错误: \(error.localizedDescription)\n"
                completion(resultLog)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultLog += "❌ [URL测试] 无效的HTTP响应\n"
                completion(resultLog)
                return
            }
            
            resultLog += "📡 [URL测试] HTTP状态码: \(httpResponse.statusCode)\n"
            
            // 检查响应URL是否发生了重定向
            if let responseURL = httpResponse.url?.absoluteString, responseURL != urlString {
                resultLog += "🔄 [重定向检测] 原始URL: \(urlString)\n"
                resultLog += "🔄 [重定向检测] 最终URL: \(responseURL)\n"
                resultLog += "⚠️ [重定向检测] 检测到URL重定向，可能影响解析结果\n"
            }
            
            if httpResponse.statusCode != 200 {
                resultLog += "⚠️ [URL测试] 非200状态码，可能有问题\n"
                if httpResponse.statusCode == 404 {
                    resultLog += "❌ [URL测试] 404错误：页面不存在\n"
                } else if httpResponse.statusCode >= 300 && httpResponse.statusCode < 400 {
                    resultLog += "🔄 [URL测试] 重定向状态码：\(httpResponse.statusCode)\n"
                }
            } else {
                resultLog += "✅ [URL测试] HTTP请求成功\n"
            }
            
            guard let data = data else {
                resultLog += "❌ [URL测试] 响应无数据\n"
                completion(resultLog)
                return
            }
            
            resultLog += "📊 [URL测试] 数据大小: \(data.count) 字节\n"
            
            // 检查响应头中的内容类型
            if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
                resultLog += "📄 [响应类型] Content-Type: \(contentType)\n"
                if !contentType.contains("text/html") {
                    resultLog += "⚠️ [响应类型] 不是HTML内容，可能影响解析\n"
                }
            }
            
            guard let htmlString = String(data: data, encoding: .utf8) else {
                resultLog += "❌ [URL测试] 无法将数据解析为UTF-8字符串\n"
                completion(resultLog)
                return
            }
            
            resultLog += "✅ [URL测试] 成功解析HTML字符串，长度: \(htmlString.count) 字符\n\n"
            
            // 检查HTML内容是否为商品页面
            resultLog += "🔍 [页面分析] 检查页面类型...\n"
            if htmlString.contains("1707") {
                resultLog += "✅ [页面分析] 包含商品ID (1707)\n"
            } else {
                resultLog += "❌ [页面分析] 未找到商品ID (1707)，可能不是商品页面\n"
            }
            
            if htmlString.lowercased().contains("the-monsters") {
                resultLog += "✅ [页面分析] 包含商品名称 (THE-MONSTERS)\n"
            } else {
                resultLog += "❌ [页面分析] 未找到商品名称 (THE-MONSTERS)\n"
            }
            
            if htmlString.lowercased().contains("checkmate") {
                resultLog += "✅ [页面分析] 包含系列名称 (Checkmate)\n"
            } else {
                resultLog += "❌ [页面分析] 未找到系列名称 (Checkmate)\n"
            }
            
            resultLog += "\n"
            
            // 使用增强的解析功能
            if let productInfo = self?.extractProductPageInfo(from: htmlString, baseURL: urlString) {
                resultLog += "🎉 [解析成功] 商品信息解析结果:\n"
                resultLog += "   📛 商品名称: \(productInfo.name)\n"
                resultLog += "   📝 商品描述: \(productInfo.description ?? "无描述")\n"
                
                // 从变体中获取价格信息
                let priceInfo = productInfo.availableVariants.first?.price ?? "无价格"
                resultLog += "   💰 价格: \(priceInfo)\n"
                
                // 检查整体库存状态
                let isInStock = productInfo.availableVariants.contains { $0.isAvailable }
                resultLog += "   📦 库存状态: \(isInStock ? "有货 ✅" : "缺货 ❌")\n"
                resultLog += "   🔢 变体数量: \(productInfo.availableVariants.count)\n\n"
                
                // 详细变体信息
                for (index, variant) in productInfo.availableVariants.enumerated() {
                    resultLog += "   变体 \(index + 1):\n"
                    resultLog += "     - 名称: \(variant.variantName ?? "未知")\n"
                    resultLog += "     - 价格: \(variant.price ?? "无价格")\n"
                    resultLog += "     - 状态: \(variant.isAvailable ? "有货" : "缺货")\n"
                    if let sku = variant.sku {
                        resultLog += "     - SKU: \(sku)\n"
                    }
                }
            } else {
                resultLog += "❌ [解析失败] 无法解析商品信息\n"
            }
            
            // 添加HTML片段预览以便调试
            resultLog += "\n🔍 [调试信息] HTML片段预览:\n"
            let htmlPreview = String(htmlString.prefix(1000))
            resultLog += "前1000字符: \(htmlPreview)\n"
            
            // 搜索页面标题
            if let titleMatch = htmlString.range(of: #"<title>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) {
                let title = String(htmlString[titleMatch])
                resultLog += "\n📋 [页面标题] \(title)\n"
            }
            
            if htmlString.contains("€") {
                resultLog += "\n💰 [价格调试] 发现欧元符号，搜索价格相关片段:\n"
                // 搜索包含€的行
                let lines = htmlString.components(separatedBy: "\n")
                var priceLines: [String] = []
                for line in lines {
                    if line.contains("€") && priceLines.count < 10 {
                        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanLine.isEmpty && cleanLine.count < 200 {
                            priceLines.append(cleanLine)
                        }
                    }
                }
                resultLog += priceLines.joined(separator: "\n")
            }
            
            if htmlString.lowercased().contains("warenkorb") || htmlString.lowercased().contains("cart") {
                resultLog += "\n🛒 [按钮调试] 发现购物车相关内容，搜索按钮片段:\n"
                let lines = htmlString.components(separatedBy: "\n")
                var buttonLines: [String] = []
                for line in lines {
                    let lowercaseLine = line.lowercased()
                    if (lowercaseLine.contains("warenkorb") || lowercaseLine.contains("cart") || lowercaseLine.contains("button")) && buttonLines.count < 10 {
                        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanLine.isEmpty && cleanLine.count < 200 {
                            buttonLines.append(cleanLine)
                        }
                    }
                }
                resultLog += buttonLines.joined(separator: "\n")
            }
            
            completion(resultLog)
        }
        
        task.resume()
    }
    
    // 增强的图片提取
    private func extractEnhancedImage(from html: String, baseURL: String) -> String? {
        let patterns = [
            // Open Graph图片
            #"<meta\s+property=[\"']og:image[\"']\s+content=[\"']([^\"']+)[\"']"#,
            // JSON-LD图片
            #""image\"\s*:\s*\"([^\"]+)\""#,
            // 主产品图片
            #"<img[^>]*class=[\"'][^\"']*product[^\"']*image[^\"']*[\"'][^>]*src=[\"']([^\"']+)[\"']"#,
            #"<img[^>]*src=[\"']([^\"']+)[\"'][^>]*class=[\"'][^\"']*product[^\"']*image[^\"']*[\"']"#,
            // 通用图片选择器
            #"<img[^>]*src=[\"']([^\"']+\.(?:jpg|jpeg|png|webp))[\"']"#
        ]
        
        for pattern in patterns {
            if let imageURL = extractFirstMatch(pattern: pattern, from: html) {
                // 将相对URL转换为绝对URL
                if imageURL.hasPrefix("http") {
                    return imageURL
                } else if imageURL.hasPrefix("//") {
                    return "https:" + imageURL
                } else if imageURL.hasPrefix("/") {
                    if let url = URL(string: baseURL),
                       let host = url.host {
                        return "https://\(host)\(imageURL)"
                    }
                }
            }
        }
        
        return nil
    }
    
    // 辅助方法：提取第一个匹配项
    private func extractFirstMatch(pattern: String, from html: String) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsString = html as NSString
        if let match = regex?.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) {
            if match.numberOfRanges >= 2 {
                return nsString.substring(with: match.range(at: 1))
            }
        }
        return nil
    }
    
    // 测试特定URL的解析能力 - 增强版浏览器模拟
    func testURLAdvanced(_ urlString: String, completion: @escaping (String) -> Void) {
        var resultLog = ""
        resultLog += "🔍 [URL测试] 开始测试URL: \(urlString)\n"
        resultLog += "⏰ [URL测试] 时间: \(Date())\n\n"
        
        guard let url = URL(string: urlString) else {
            resultLog += "❌ [URL测试] 无效的URL格式\n"
            completion(resultLog)
            return
        }
        
        // 创建增强的URLSessionConfiguration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // 设置Cookie存储
        let cookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieStorage = cookieStorage
        
        let session = URLSession(configuration: configuration)
        
        var request = URLRequest(url: url)
        
        // 设置完整的Chrome浏览器Headers
        let headers = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
            "Accept-Encoding": "gzip, deflate, br",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-User": "?1",
            "sec-ch-ua": "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"macOS\"",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "DNT": "1"
        ]
        
        // 添加Referer header模拟从搜索或主页进入
        if urlString.contains("popmart.com") {
            request.setValue("https://www.popmart.com/de/", forHTTPHeaderField: "Referer")
        }
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 预设德国本地化Cookies
        let germanCookies = [
            "locale=de",
            "region=DE", 
            "currency=EUR",
            "country=DE",
            "language=de",
            "timezone=Europe/Berlin",
            "visited=true",
            "consent=accepted"
        ]
        
        if let cookieURL = URL(string: "https://www.popmart.com") {
            for cookieString in germanCookies {
                let parts = cookieString.split(separator: "=")
                if parts.count == 2 {
                    let cookie = HTTPCookie(properties: [
                        .domain: ".popmart.com",
                        .path: "/",
                        .name: String(parts[0]),
                        .value: String(parts[1])
                    ])
                    if let cookie = cookie {
                        cookieStorage.setCookie(cookie)
                    }
                }
            }
        }
        
        resultLog += "📤 [请求详情] 设置增强的浏览器模拟\n"
        resultLog += "🌐 [请求详情] User-Agent: Chrome/120 (macOS)\n"
        resultLog += "🇩🇪 [请求详情] Accept-Language: de-DE,de;q=0.9\n"
        resultLog += "🍪 [请求详情] Cookies: locale=de; region=DE; currency=EUR\n"
        resultLog += "🔒 [请求详情] Sec-CH-UA Headers: 已设置\n"
        resultLog += "🔄 [请求详情] Referer: https://www.popmart.com/de/\n\n"
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                resultLog += "❌ [URL测试] 请求失败: \(error.localizedDescription)\n"
                completion(resultLog)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultLog += "❌ [URL测试] 无效的HTTP响应\n"
                completion(resultLog)
                return
            }
            
            resultLog += "📡 [URL测试] HTTP状态码: \(httpResponse.statusCode)\n"
            
            // 检查重定向
            if let finalURL = httpResponse.url?.absoluteString, finalURL != urlString {
                resultLog += "🔄 [重定向检测] 重定向到: \(finalURL)\n"
            } else {
                resultLog += "✅ [重定向检测] 未发生重定向，URL正确\n"
            }
            
            // 检查Set-Cookie
            if let cookies = httpResponse.allHeaderFields["Set-Cookie"] as? String {
                resultLog += "🍪 [响应Cookies] \(cookies)\n"
            }
            
            guard let data = data else {
                resultLog += "❌ [URL测试] 未收到数据\n"
                completion(resultLog)
                return
            }
            
            resultLog += "✅ [URL测试] HTTP请求成功\n"
            resultLog += "📊 [URL测试] 数据大小: \(data.count) 字节\n"
            
            if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
                resultLog += "📄 [响应类型] Content-Type: \(contentType)\n"
            }
            
            guard let htmlString = String(data: data, encoding: .utf8) else {
                resultLog += "❌ [URL测试] 无法解析HTML字符串\n"
                completion(resultLog)
                return
            }
            
            resultLog += "✅ [URL测试] 成功解析HTML字符串，长度: \(htmlString.count) 字符\n\n"
            
            // 页面内容分析
            resultLog += "🔍 [页面分析] 详细检查页面内容...\n"
            
            // 检查特定商品标识
            let productId = "1707"
            let productName = "THE-MONSTERS"
            let seriesName = "Checkmate"
            
            if htmlString.contains(productId) {
                resultLog += "✅ [页面分析] 找到商品ID (\(productId))\n"
            } else {
                resultLog += "❌ [页面分析] HTML中未找到商品ID (\(productId))\n"
            }
            
            if htmlString.lowercased().contains(productName.lowercased()) {
                resultLog += "✅ [页面分析] 找到商品名称 (\(productName))\n"
            } else {
                resultLog += "❌ [页面分析] HTML中未找到商品名称 (\(productName))\n"
            }
            
            if htmlString.lowercased().contains(seriesName.lowercased()) {
                resultLog += "✅ [页面分析] 找到系列名称 (\(seriesName))\n"
            } else {
                resultLog += "❌ [页面分析] HTML中未找到系列名称 (\(seriesName))\n"
            }
            
            // 检查页面特征
            let pageIndicators = [
                "product-details", "add-to-cart", "warenkorb", 
                "ausverkauft", "price", "variant", "sku",
                "product-info", "buy-button", "cart"
            ]
            
            var foundIndicators: [String] = []
            for indicator in pageIndicators {
                if htmlString.lowercased().contains(indicator) {
                    foundIndicators.append(indicator)
                }
            }
            
            if !foundIndicators.isEmpty {
                resultLog += "🛍️ [商品页面特征] 找到商品页面指标: \(foundIndicators.joined(separator: ", "))\n"
            } else {
                resultLog += "❌ [商品页面特征] 未找到商品页面特征，可能是主页或其他页面\n"
            }
            
            // 检查JavaScript内容
            let jsPattern = #"<script[^>]*>.*?</script>"#
            let jsMatches = htmlString.matches(of: try! Regex(jsPattern))
            resultLog += "📜 [JavaScript检测] 找到 \(jsMatches.count) 个脚本标签\n"
            
            if htmlString.contains("window.__INITIAL_STATE__") || htmlString.contains("__NEXT_DATA__") {
                resultLog += "⚙️ [JavaScript检测] 检测到SPA应用，内容可能需要JavaScript渲染\n"
            }
            
            // 搜索可能的API端点
            let apiPatterns = [
                #"/api/products/\d+"#,
                #"/api/v\d+/products"#,
                #"product-api"#,
                #"graphql"#,
                #"/api/catalog"#
            ]
            
            var foundApis: [String] = []
            for pattern in apiPatterns {
                let matches = htmlString.matches(of: try! Regex(pattern))
                if !matches.isEmpty {
                    for match in matches.prefix(3) {
                        foundApis.append(String(match.0))
                    }
                }
            }
            
            if !foundApis.isEmpty {
                resultLog += "🔍 [API发现] 发现可能的API端点: \(foundApis.joined(separator: ", "))\n"
            }
            
            resultLog += "\n"
            
            // 使用增强的解析功能
            if let productInfo = self?.extractProductPageInfo(from: htmlString, baseURL: urlString) {
                resultLog += "🎉 [解析结果] 商品信息解析结果:\n"
                resultLog += "   📛 商品名称: \(productInfo.name)\n"
                resultLog += "   📝 商品描述: \(productInfo.description ?? "无描述")\n"
                
                // 从变体中获取价格信息
                let priceInfo = productInfo.availableVariants.first?.price ?? "无价格"
                resultLog += "   💰 价格: \(priceInfo)\n"
                
                // 检查整体库存状态
                let isInStock = productInfo.availableVariants.contains { $0.isAvailable }
                resultLog += "   📦 库存状态: \(isInStock ? "有货 ✅" : "缺货 ❌")\n"
                resultLog += "   🔢 变体数量: \(productInfo.availableVariants.count)\n\n"
                
                // 详细变体信息
                for (index, variant) in productInfo.availableVariants.enumerated() {
                    resultLog += "   变体 \(index + 1):\n"
                    resultLog += "     - 名称: \(variant.variantName ?? "未知")\n"
                    resultLog += "     - 价格: \(variant.price ?? "无价格")\n"
                    resultLog += "     - 状态: \(variant.isAvailable ? "有货" : "缺货")\n"
                    if let sku = variant.sku {
                        resultLog += "     - SKU: \(sku)\n"
                    }
                }
            } else {
                resultLog += "❌ [解析失败] 无法解析商品信息\n"
                resultLog += "💡 [建议] 可能需要使用WebView来渲染JavaScript内容\n"
            }
            
            // 添加关键HTML片段分析
            resultLog += "\n🔍 [关键内容分析]\n"
            
            // 查找JSON数据
            if htmlString.contains("__NEXT_DATA__") {
                resultLog += "🔍 [Next.js数据] 检测到Next.js应用数据\n"
                if let jsonStart = htmlString.range(of: "__NEXT_DATA__\" type=\"application/json\">")?.upperBound,
                   let jsonEnd = htmlString[jsonStart...].range(of: "</script>")?.lowerBound {
                    let jsonString = String(htmlString[jsonStart..<jsonEnd])
                    resultLog += "📄 [JSON数据] 尝试解析Next.js数据...\n"
                    
                    // 尝试解析JSON数据
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                resultLog += "✅ [JSON解析] 成功解析Next.js数据\n"
                                
                                // 查找产品信息
                                if let props = jsonObject["props"] as? [String: Any],
                                   let pageProps = props["pageProps"] as? [String: Any] {
                                    resultLog += "🔍 [产品搜索] 在pageProps中搜索产品数据...\n"
                                    
                                    // 递归搜索产品相关数据
                                    let productData = self?.searchForProductData(in: pageProps, path: "pageProps")
                                    if let productInfo = productData, !productInfo.isEmpty {
                                        resultLog += "🎉 [产品发现] 找到产品数据:\n\(productInfo)\n"
                                    } else {
                                        resultLog += "⚠️ [产品搜索] pageProps为空，可能需要客户端渲染\n"
                                        
                                        // 尝试从更深层次搜索
                                        let allData = self?.searchForProductData(in: jsonObject, path: "root")
                                        if let allInfo = allData, !allInfo.isEmpty {
                                            resultLog += "🔍 [深度搜索] 在完整JSON中找到相关数据:\n\(allInfo)\n"
                                        }
                                    }
                                }
                                
                                // 查找query参数
                                if let query = jsonObject["query"] as? [String: Any] {
                                    if query.isEmpty {
                                        resultLog += "⚠️ [路由问题] Query参数为空，URL路由可能未正确解析\n"
                                    } else {
                                        resultLog += "🔍 [路由信息] Query参数: \(query)\n"
                                    }
                                }
                                
                                // 查找buildId和page信息
                                if let page = jsonObject["page"] as? String {
                                    resultLog += "📍 [路由信息] 页面路径: \(page)\n"
                                    if page.contains("[...queryParams]") {
                                        resultLog += "💡 [路由分析] 使用动态路由，需要正确的URL参数解析\n"
                                    }
                                }
                                
                                if let buildId = jsonObject["buildId"] as? String {
                                    resultLog += "🏗️ [构建信息] Build ID: \(buildId)\n"
                                }
                                
                                // 检查是否有额外的数据源
                                if let runtimeConfig = jsonObject["runtimeConfig"] as? [String: Any] {
                                    resultLog += "⚙️ [运行时配置] 发现运行时配置数据\n"
                                    if let countries = runtimeConfig["COUNTRYS"] as? [String] {
                                        if countries.contains("de") {
                                            resultLog += "✅ [地区支持] 确认支持德国(de)地区\n"
                                        }
                                    }
                                }
                            }
                        } catch {
                            resultLog += "❌ [JSON解析] 解析失败: \(error.localizedDescription)\n"
                        }
                    }
                    
                    let jsonSnippet = String(jsonString.prefix(500))
                    resultLog += "📄 [JSON片段] \(jsonSnippet)...\n"
                } else {
                    if let jsonStart = htmlString.range(of: "__NEXT_DATA__")?.upperBound,
                       let jsonEnd = htmlString[jsonStart...].range(of: "</script>")?.lowerBound {
                        let jsonSnippet = String(htmlString[jsonStart..<jsonEnd]).prefix(500)
                        resultLog += "📄 [JSON片段] \(jsonSnippet)...\n"
                    }
                }
            }
            
            // 查找产品相关的DOM结构
            let domPatterns = [
                #"class="[^"]*product[^"]*""#,
                #"id="[^"]*product[^"]*""#,
                #"data-[^=]*product[^=]*="[^"]*""#
            ]
            
            for pattern in domPatterns {
                let matches = htmlString.matches(of: try! Regex(pattern))
                if !matches.isEmpty {
                    resultLog += "🏗️ [DOM结构] 找到产品相关元素: \(matches.count) 个\n"
                    break
                }
            }
            
            // 搜索价格信息
            if htmlString.contains("€") {
                resultLog += "\n💰 [价格调试] 欧元符号相关内容:\n"
                let lines = htmlString.components(separatedBy: "\n")
                var priceLines: [String] = []
                for line in lines {
                    if line.contains("€") && priceLines.count < 5 {
                        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanLine.isEmpty && cleanLine.count < 300 && !cleanLine.hasPrefix("<script") {
                            priceLines.append(cleanLine)
                        }
                    }
                }
                resultLog += priceLines.joined(separator: "\n")
            }
            
            completion(resultLog)
        }
        
        task.resume()
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

// 提取商品名称 - 增强版
private func extractProductName(from html: String, baseURL: String) -> String? {
    // 扩展的商品名称匹配模式，针对不同网站结构
    let namePatterns = [
        // Popmart 网站特有模式
        #"<h1[^>]*class="[^"]*product[^"]*title[^"]*"[^>]*>(.*?)</h1>"#,
        #"<h1[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)</h1>"#,
        #"<div[^>]*class="[^"]*product[^"]*name[^"]*"[^>]*>(.*?)</div>"#,
        #"<span[^>]*class="[^"]*product[^"]*title[^"]*"[^>]*>(.*?)</span>"#,
        
        // JSON-LD 结构化数据
        #""name"\s*:\s*"([^"]+)""#,
        #""@type"\s*:\s*"Product".*?"name"\s*:\s*"([^"]+)""#,
        
        // Open Graph 元标签
        #"<meta[^>]*property="og:title"[^>]*content="([^"]+)""#,
        #"<meta[^>]*name="twitter:title"[^>]*content="([^"]+)""#,
        
        // 标准HTML标签
        #"<h1[^>]*>(.*?)</h1>"#,
        #"<h2[^>]*class="[^"]*product[^"]*"[^>]*>(.*?)</h2>"#,
        
        // 通用元标签
        #"<meta[^>]*name="title"[^>]*content="([^"]+)""#,
        #"<meta[^>]*property="title"[^>]*content="([^"]+)""#,
        
        // 页面标题（最后备选）
        #"<title>(.*?)</title>"#
    ]
    
    print("🔍 [商品解析] 开始提取商品名称，使用 \(namePatterns.count) 种模式...")
    
    for (index, pattern) in namePatterns.enumerated() {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: html.count)
            
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
                
                if let nameRange = Range(captureRange, in: html) {
                    var cleanedName = String(html[nameRange])
                    
                    // 清理HTML标签和特殊字符
                    cleanedName = cleanedName
                        .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\t", with: " ")
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 验证商品名称的有效性
                    if isValidProductName(cleanedName) {
                        print("✅ [商品解析] 使用模式 \(index + 1) 成功提取商品名称: \(cleanedName)")
                        return cleanedName
                    } else {
                        print("⚠️ [商品解析] 模式 \(index + 1) 匹配但名称无效: \(cleanedName)")
                    }
                }
            }
        } catch {
            print("❌ [商品解析] 正则表达式模式 \(index + 1) 编译失败: \(error)")
            continue
        }
    }
    
    print("❌ [商品解析] 所有模式都无法提取有效的商品名称")
    
    // 尝试从URL中提取可能的商品名称作为备选方案
    if let urlBasedName = extractNameFromURL(baseURL) {
        print("🔄 [商品解析] 从URL中提取备选名称: \(urlBasedName)")
        return urlBasedName
    }
    
    return nil
}

// 验证商品名称的有效性
private func isValidProductName(_ name: String) -> Bool {
    // 检查基本条件
    guard !name.isEmpty else { return false }
    guard name.count >= 3 else { return false }  // 名称至少3个字符
    guard name.count <= 200 else { return false } // 名称不超过200个字符
    
    // 排除常见的无效名称
    let invalidNames = [
        "popmart", "amazon", "shop", "store", "product", "item",
        "loading", "error", "404", "not found", "页面", "网站",
        "home", "首页", "商城", "购物", "title", "untitled"
    ]
    
    let lowerName = name.lowercased()
    for invalid in invalidNames {
        if lowerName == invalid || lowerName.contains("- \(invalid)") || lowerName.contains("\(invalid) -") {
            return false
        }
    }
    
    // 检查是否只包含特殊字符或数字
    let alphanumericCount = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
    if alphanumericCount < 2 {
        return false
    }
    
    return true
}

// 从URL中提取可能的商品名称
private func extractNameFromURL(_ url: String) -> String? {
    guard let urlComponents = URLComponents(string: url) else { return nil }
    
    let pathComponents = urlComponents.path.components(separatedBy: "/").filter { !$0.isEmpty }
    
    // 查找可能的商品名称部分
    for component in pathComponents.reversed() {
        // 跳过常见的非商品名称部分
        if ["products", "product", "p", "items", "item", "de", "en", "www", "shop"].contains(component.lowercased()) {
            continue
        }
        
        // 跳过纯数字的部分（通常是ID）
        if component.allSatisfy({ $0.isNumber }) {
            continue
        }
        
        // 清理URL编码和特殊字符
        var cleanedName = component
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "%20", with: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .removingPercentEncoding ?? component
        
        // 首字母大写处理
        cleanedName = cleanedName.capitalized
        
        if isValidProductName(cleanedName) {
            return cleanedName
        }
    }
    
    return nil
}

// 提取商品描述
private func extractProductDescription(from html: String) -> String? {
    let descriptionPatterns = [
        #"<div[^>]*class="[^"]*description[^"]*"[^>]*>(.*?)</div>"#,
        #"<div[^>]*class="[^"]*product[^"]*description[^"]*"[^>]*>(.*?)</div>"#,
        #"<meta[^>]*name="description"[^>]*content="([^"]+)""#,
        #"<meta[^>]*property="og:description"[^>]*content="([^"]+)""#
    ]
    
    for pattern in descriptionPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: html.count)
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                if let descRange = Range(match.range(at: 1), in: html) {
                    let description = String(html[descRange])
                        .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: [.regularExpression])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !description.isEmpty && description.count > 10 {
                        return description
                    }
                }
            }
        }
    }
    
    return nil
}

// 提取商品品牌
private func extractProductBrand(from html: String) -> String? {
    let brandPatterns = [
        #"<span[^>]*class="[^"]*brand[^"]*"[^>]*>(.*?)</span>"#,
        #"<div[^>]*class="[^"]*brand[^"]*"[^>]*>(.*?)</div>"#,
        #"<meta[^>]*property="product:brand"[^>]*content="([^"]+)""#,
        #""brand"\s*:\s*"([^"]+)""#
    ]
    
    for pattern in brandPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
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

// 专门处理特殊商品类型的解析方法
extension ProductMonitor {
    // 特殊商品类型检测和处理
    private func analyzeSpecialProductTypes(html: String, url: String) -> (isSpecialType: Bool, productInfo: String?) {
        let urlLowercase = url.lowercased()
        let htmlLowercase = html.lowercased()
        
        // 检测手机壳类商品
        if urlLowercase.contains("phone-case") || urlLowercase.contains("case") || 
           htmlLowercase.contains("phone case") || htmlLowercase.contains("iphone") {
            
            let phoneInfo = extractPhoneCaseInfo(from: html)
            return (true, phoneInfo)
        }
        
        // 检测服装类商品
        if urlLowercase.contains("clothing") || urlLowercase.contains("shirt") || 
           urlLowercase.contains("hoodie") || htmlLowercase.contains("apparel") {
            
            let clothingInfo = extractClothingInfo(from: html)
            return (true, clothingInfo)
        }
        
        // 检测限定版商品
        if urlLowercase.contains("limited") || urlLowercase.contains("exclusive") ||
           htmlLowercase.contains("limited edition") || htmlLowercase.contains("exklusiv") {
            
            let limitedInfo = extractLimitedEditionInfo(from: html)
            return (true, limitedInfo)
        }
        
        return (false, nil)
    }
    
    // 提取手机壳商品信息
    private func extractPhoneCaseInfo(from html: String) -> String? {
        // 手机壳特有的关键信息
        let phoneCaseIndicators = [
            "iphone", "samsung", "huawei", "compatible", "kompatibel",
            "protective case", "schutzhülle", "cover", "abdeckung",
            "wireless charging", "drahtlos laden", "magsafe"
        ]
        
        let htmlLowercase = html.lowercased()
        var foundIndicators: [String] = []
        
        for indicator in phoneCaseIndicators {
            if htmlLowercase.contains(indicator) {
                foundIndicators.append(indicator)
            }
        }
        
        if !foundIndicators.isEmpty {
            return "手机壳类商品 - 检测到: \(foundIndicators.joined(separator: ", "))"
        }
        
        return nil
    }
    
    // 提取服装商品信息
    private func extractClothingInfo(from html: String) -> String? {
        let clothingIndicators = [
            "size", "größe", "small", "medium", "large", "xl",
            "cotton", "baumwolle", "material", "fabric",
            "wash", "waschen", "care instructions"
        ]
        
        let htmlLowercase = html.lowercased()
        var foundIndicators: [String] = []
        
        for indicator in clothingIndicators {
            if htmlLowercase.contains(indicator) {
                foundIndicators.append(indicator)
            }
        }
        
        if !foundIndicators.isEmpty {
            return "服装类商品 - 检测到: \(foundIndicators.joined(separator: ", "))"
        }
        
        return nil
    }
    
    // 提取限定版商品信息
    private func extractLimitedEditionInfo(from html: String) -> String? {
        let limitedIndicators = [
            "limited edition", "begrenzte auflage", "exclusive",
            "numbered", "nummeriert", "collector", "sammler",
            "rare", "selten", "special edition"
        ]
        
        let htmlLowercase = html.lowercased()
        var foundIndicators: [String] = []
        
        for indicator in limitedIndicators {
            if htmlLowercase.contains(indicator) {
                foundIndicators.append(indicator)
            }
        }
        
        if !foundIndicators.isEmpty {
            return "限定版商品 - 检测到: \(foundIndicators.joined(separator: ", "))"
        }
        
        return nil
    }
    
    // 增强的产品信息提取
    private func extractEnhancedProductInfo(from html: String, url: String) -> String {
        var productInfo = ["基本信息已解析"]
        
        // 检查特殊类型
        let (isSpecial, specialInfo) = analyzeSpecialProductTypes(html: html, url: url)
        if isSpecial, let info = specialInfo {
            productInfo.append(info)
        }
        
        // 检查是否有产品描述
        if html.lowercased().contains("description") || html.lowercased().contains("beschreibung") {
            productInfo.append("包含产品描述")
        }
        
        // 检查是否有产品图片
        let imageCount = html.components(separatedBy: "img").count - 1
        if imageCount > 0 {
            productInfo.append("检测到 \(imageCount) 张图片")
        }
        
        // 检查是否有评论
        if html.lowercased().contains("review") || html.lowercased().contains("bewertung") {
            productInfo.append("包含用户评论")
        }
        
        return productInfo.joined(separator: " | ")
    }
}

// MARK: - Next.js数据解析辅助方法
extension ProductMonitor {
    // 递归搜索产品相关数据
    private func searchForProductData(in data: Any, path: String) -> String? {
        var result: [String] = []
        
        if let dict = data as? [String: Any] {
            for (key, value) in dict {
                let currentPath = "\(path).\(key)"
                
                // 检查是否是产品相关的key
                if isProductRelatedKey(key) {
                    if let stringValue = value as? String {
                        result.append("\(currentPath): \(stringValue)")
                    } else if let numberValue = value as? NSNumber {
                        result.append("\(currentPath): \(numberValue)")
                    } else if let boolValue = value as? Bool {
                        result.append("\(currentPath): \(boolValue)")
                    }
                }
                
                // 递归搜索（限制深度避免无限递归）
                if path.components(separatedBy: ".").count < 5 {
                    if let subResult = searchForProductData(in: value, path: currentPath) {
                        result.append(subResult)
                    }
                }
            }
        } else if let array = data as? [Any] {
            for (index, item) in array.enumerated() {
                let currentPath = "\(path)[\(index)]"
                if let subResult = searchForProductData(in: item, path: currentPath) {
                    result.append(subResult)
                }
            }
        }
        
        return result.isEmpty ? nil : result.joined(separator: "\n")
    }
    
    // 检查是否是产品相关的key
    private func isProductRelatedKey(_ key: String) -> Bool {
        let productKeys = [
            "name", "title", "product", "item",
            "price", "cost", "amount", "value",
            "stock", "available", "inventory", "quantity",
            "sku", "id", "productId", "itemId",
            "description", "summary", "details",
            "brand", "manufacturer", "seller",
            "image", "thumbnail", "photo", "picture",
            "category", "type", "variant", "option",
            "status", "state", "condition",
            "url", "link", "permalink"
        ]
        
        let lowerKey = key.lowercased()
        return productKeys.contains { lowerKey.contains($0) }
    }
}

// MARK: - 直接API调用方法
extension ProductMonitor {
    
    // 尝试直接调用Popmart API获取产品信息
    func testDirectAPI(_ productId: String, completion: @escaping (String) -> Void) {
        var resultLog = ""
        resultLog += "🚀 [API测试] 开始直接API调用测试\n"
        resultLog += "🎯 [API测试] 产品ID: \(productId)\n"
        resultLog += "⏰ [API测试] 时间: \(Date())\n\n"
        
        // 可能的API端点
        let apiEndpoints = [
            "https://www.popmart.com/api/v1/products/\(productId)",
            "https://www.popmart.com/api/products/\(productId)",
            "https://api.popmart.com/v1/products/\(productId)",
            "https://www.popmart.com/de/api/products/\(productId)",
            "https://www.popmart.com/_next/data/20250528201128/de/products/\(productId).json",
            "https://cdn-global-eude.popmart.com/global-web/eude-prod/20250528201128/_next/static/chunks/pages/products/[...queryParams].js"
        ]
        
        var completedRequests = 0
        let totalRequests = apiEndpoints.count
        
        for (index, endpoint) in apiEndpoints.enumerated() {
            resultLog += "🔍 [API测试 \(index + 1)] 测试端点: \(endpoint)\n"
            
            guard let url = URL(string: endpoint) else {
                resultLog += "❌ [API测试 \(index + 1)] 无效URL\n"
                completedRequests += 1
                if completedRequests == totalRequests {
                    completion(resultLog)
                }
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://www.popmart.com/de/", forHTTPHeaderField: "Referer")
            request.setValue("locale=de; region=DE; currency=EUR", forHTTPHeaderField: "Cookie")
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer {
                    completedRequests += 1
                    if completedRequests == totalRequests {
                        DispatchQueue.main.async {
                            completion(resultLog)
                        }
                    }
                }
                
                if let error = error {
                    resultLog += "❌ [API测试 \(index + 1)] 请求失败: \(error.localizedDescription)\n"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    resultLog += "❌ [API测试 \(index + 1)] 无效响应\n"
                    return
                }
                
                resultLog += "📡 [API测试 \(index + 1)] 状态码: \(httpResponse.statusCode)\n"
                
                if httpResponse.statusCode == 200 {
                    if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                        resultLog += "✅ [API测试 \(index + 1)] 成功！数据长度: \(data.count) 字节\n"
                        
                        // 尝试解析JSON
                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
                                resultLog += "📊 [API测试 \(index + 1)] JSON解析成功\n"
                                
                                // 查找产品相关信息
                                if let productData = self.searchForProductData(in: jsonObject, path: "api_response") {
                                    resultLog += "🎉 [API测试 \(index + 1)] 找到产品数据:\n\(productData)\n"
                                }
                            } catch {
                                resultLog += "⚠️ [API测试 \(index + 1)] JSON解析失败，可能是HTML或其他格式\n"
                            }
                        }
                        
                        let preview = String(jsonString.prefix(200))
                        resultLog += "📄 [API测试 \(index + 1)] 内容预览: \(preview)...\n"
                    }
                } else if httpResponse.statusCode == 404 {
                    resultLog += "❌ [API测试 \(index + 1)] 404 - 端点不存在\n"
                } else if httpResponse.statusCode == 403 {
                    resultLog += "🔒 [API测试 \(index + 1)] 403 - 访问被拒绝\n"
                } else {
                    resultLog += "⚠️ [API测试 \(index + 1)] 状态码: \(httpResponse.statusCode)\n"
                }
                
                resultLog += "\n"
            }
            
            task.resume()
        }
    }
}