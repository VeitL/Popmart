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
        
        let hasProductInfo = extractProductName(from: html) != nil
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
    
    private func parseProductStatus(from html: String, for product: Product, responseTime: TimeInterval, statusCode: Int) {
        updateProductStats(product, incrementError: false)
        
        // 检查是否被反爬虫检测
        if statusCode == 403 || statusCode == 429 || html.contains("Access Denied") || html.contains("Cloudflare") {
            addLog(for: product, status: .antiBot, message: "检测到反爬虫机制 (HTTP \(statusCode))", responseTime: responseTime, httpStatusCode: statusCode)
            return
        }
        
        // 增强的缺货关键词检测 - 德语网站专用
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
        
        // 增强的有货关键词检测
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
        
        // 价格存在指标（通常表示商品可购买）
        let priceIndicators = [
            "€", "EUR", "price", "preis", "cost", "kosten",
            "sale", "discount", "rabatt", "angebot"
        ]
        
        let htmlLowercase = html.lowercased()
        
        // 获取当前商品状态
        guard let productIndex = products.firstIndex(where: { $0.id == product.id }) else { return }
        var currentProduct = products[productIndex]
        
        // 对于单变体产品，更新第一个变体的状态
        if let firstVariantIndex = currentProduct.variants.indices.first {
            let wasAvailable = currentProduct.variants[firstVariantIndex].isAvailable
            
            // 更智能的库存检测逻辑
            let hasUnavailableKeywords = unavailableKeywords.contains { keyword in
                htmlLowercase.contains(keyword.lowercased())
            }
            
            let hasAvailableKeywords = availableKeywords.contains { keyword in
                htmlLowercase.contains(keyword.lowercased())
            }
            
            let hasPriceIndicators = priceIndicators.contains { indicator in
                htmlLowercase.contains(indicator.lowercased())
            }
            
            // 检查是否有具体的产品信息（标题、描述等）
            let hasProductInfo = extractProductName(from: html) != nil
            
            // 检查是否有图片（通常表示商品存在）
            let hasProductImages = html.lowercased().contains("img") && 
                                 (html.lowercased().contains("product") || 
                                  html.lowercased().contains("image"))
            
            // 检查特殊商品类型
            let (isSpecialType, specialTypeInfo) = analyzeSpecialProductTypes(html: html, url: product.url)
            
            // 综合判断逻辑：
            // 1. 如果明确显示缺货关键词，则判定为缺货
            // 2. 如果有购买按钮或价格信息，且没有缺货关键词，则判定为有货
            // 3. 如果有产品信息和图片，且没有明确的缺货信息，则倾向于判定为有货
            // 4. 特殊商品类型（如手机壳）有额外的检测逻辑
            var newAvailabilityStatus: Bool
            
            if hasUnavailableKeywords {
                // 明确的缺货指示
                newAvailabilityStatus = false
            } else if hasAvailableKeywords || hasPriceIndicators {
                // 有购买按钮或价格信息
                newAvailabilityStatus = true
            } else if hasProductInfo && hasProductImages {
                // 有产品信息和图片，但没有明确的可用性指示
                // 在这种情况下，我们倾向于认为是可用的，除非明确说明不可用
                newAvailabilityStatus = true
            } else if isSpecialType {
                // 特殊商品类型，如果能解析到特殊信息，通常表示页面正常
                newAvailabilityStatus = true
            } else {
                // 无法确定状态，保持之前的状态
                newAvailabilityStatus = currentProduct.variants[firstVariantIndex].isAvailable
            }
            
            currentProduct.variants[firstVariantIndex].isAvailable = newAvailabilityStatus
            
            // 提取价格信息（增强版）
            if let price = extractEnhancedPrice(from: html) {
                currentProduct.variants[firstVariantIndex] = VariantDetail(
                    variant: currentProduct.variants[firstVariantIndex].variant,
                    name: currentProduct.variants[firstVariantIndex].name,
                    price: price,
                    isAvailable: currentProduct.variants[firstVariantIndex].isAvailable,
                    url: currentProduct.variants[firstVariantIndex].url,
                    imageURL: currentProduct.variants[firstVariantIndex].imageURL,
                    sku: currentProduct.variants[firstVariantIndex].sku,
                    stockLevel: currentProduct.variants[firstVariantIndex].stockLevel
                )
            }
            
            // 更新产品信息
            products[productIndex] = currentProduct
            saveProducts()
            
            // 记录详细日志
            let statusMessage = currentProduct.variants[firstVariantIndex].isAvailable ? "有库存 ✅" : "缺货 ❌"
            let priceInfo = currentProduct.variants[firstVariantIndex].price != nil ? " (价格: \(currentProduct.variants[firstVariantIndex].price!))" : ""
            let specialTypeMsg = isSpecialType ? "\n特殊类型: \(specialTypeInfo ?? "已识别")" : ""
            let detectionInfo = """
            检测信息: 缺货词=\(hasUnavailableKeywords ? "是" : "否"), \
            购买词=\(hasAvailableKeywords ? "是" : "否"), \
            价格=\(hasPriceIndicators ? "是" : "否"), \
            商品信息=\(hasProductInfo ? "是" : "否")\(specialTypeMsg)
            """
            
            if wasAvailable != currentProduct.variants[firstVariantIndex].isAvailable {
                let changeMessage = currentProduct.variants[firstVariantIndex].isAvailable ? "🎉 商品上架了！" : "⚠️ 商品已下架"
                addLog(for: currentProduct, status: .availabilityChanged, 
                      message: "\(changeMessage) - \(statusMessage)\(priceInfo)\n\(detectionInfo)", 
                      responseTime: responseTime, httpStatusCode: statusCode)
                
                // 如果商品从缺货变为有货，发送通知
                if !wasAvailable && currentProduct.variants[firstVariantIndex].isAvailable {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ProductAvailable"),
                        object: currentProduct
                    )
                }
            } else {
                addLog(for: currentProduct, status: .success, 
                      message: "状态检查: \(statusMessage)\(priceInfo)\n\(detectionInfo)", 
                      responseTime: responseTime, httpStatusCode: statusCode)
            }
        }
    }
    
    // 增强的价格提取方法
    private func extractEnhancedPrice(from html: String) -> String? {
        // 更全面的价格提取正则表达式
        let pricePatterns = [
            // 欧元符号在前
            #"€\s*(\d+[.,]\d{1,2})"#,
            #"EUR\s*(\d+[.,]\d{1,2})"#,
            
            // 欧元符号在后
            #"(\d+[.,]\d{1,2})\s*€"#,
            #"(\d+[.,]\d{1,2})\s*EUR"#,
            
            // JSON格式的价格
            #""price":\s*"([^"]+)""#,
            #""amount":\s*"([^"]+)""#,
            #""value":\s*"?(\d+[.,]?\d*)"?"#,
            
            // HTML元素中的价格
            #"<span[^>]*class="[^"]*price[^"]*"[^>]*>.*?€?\s*(\d+[.,]\d{1,2})"#,
            #"<div[^>]*class="[^"]*price[^"]*"[^>]*>.*?€?\s*(\d+[.,]\d{1,2})"#,
            #"<p[^>]*class="[^"]*price[^"]*"[^>]*>.*?€?\s*(\d+[.,]\d{1,2})"#,
            
            // data属性中的价格
            #"data-price="(\d+[.,]?\d*)\""#,
            #"data-amount="(\d+[.,]?\d*)\""#,
            
            // Schema.org微数据
            #"itemprop="price"[^>]*content="([^"]+)""#,
            #"itemprop="lowPrice"[^>]*content="([^"]+)""#,
            
            // 特殊格式
            #"preis[:\s]*€?\s*(\d+[.,]\d{1,2})"#,
            #"kosten[:\s]*€?\s*(\d+[.,]\d{1,2})"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let priceRange = Range(match.range(at: 1), in: html) {
                        let priceString = String(html[priceRange])
                            .replacingOccurrences(of: ",", with: ".")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // 验证价格格式
                        if let _ = Double(priceString), !priceString.isEmpty {
                            return "€\(priceString)"
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 提取价格的辅助函数
    private func extractPrice(from html: String) -> String? {
        // 提取价格的正则表达式模式
        let pricePatterns = [
            #"€\s*(\d+[,.]?\d*)"#,
            #"(\d+[,.]?\d*)\s*€"#,
            #""price":\s*"([^"]+)""#,
            #"<span[^>]*class="[^"]*price[^"]*"[^>]*>([^<]*)</span>"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: html.count)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let priceRange = Range(match.range(at: 1), in: html) {
                        let priceString = String(html[priceRange])
                        // 清理价格字符串
                        let cleanedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanedPrice.isEmpty {
                            return "€\(cleanedPrice)"
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 移除旧的extractPrice方法
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
    
    // 从HTML中提取商品信息
    private func extractProductPageInfo(from html: String, baseURL: String) -> ProductPageInfo? {
        print("🔍 [商品解析] 开始解析商品页面: \(baseURL)")
        
        // 首先尝试Amazon解析
        if baseURL.contains("amazon") {
            print("🛒 [商品解析] 检测到Amazon网站，使用Amazon解析器")
            return extractAmazonProductInfo(from: html, baseURL: baseURL)
        }
        
        print("🏪 [商品解析] 使用通用解析器")
        
        // 然后尝试Popmart解析
        guard let name = extractProductName(from: html) else {
            print("❌ [商品解析] 无法提取商品名称")
            return nil
        }
        
        print("📝 [商品解析] 商品名称: \(name)")
        
        // 基本信息
        let info = ProductPageInfo(
            name: name,
            availableVariants: extractShopifyVariants(from: html, baseURL: baseURL),
            imageURL: extractImageURL(from: html),
            description: nil,
            brand: nil,
            category: nil
        )
        
        print("✅ [商品解析] 通用解析完成")
        return info
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