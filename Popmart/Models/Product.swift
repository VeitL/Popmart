//
//  Product.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import Foundation

// MARK: - 商品变体枚举
enum ProductVariant: String, Codable, CaseIterable {
    case singleBox = "单盒"
    case wholeSet = "整套"
    case random = "随机"
    case limited = "限定"
    case specific = "指定款"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .singleBox:
            return "cube.box"
        case .wholeSet:
            return "cube.box.fill"
        case .random:
            return "dice"
        case .specific:
            return "star"
        case .limited:
            return "crown"
        }
    }
}

// 改进：变体详细信息结构体，包含独立的监控状态
struct VariantDetail: Codable, Identifiable {
    let id: UUID
    let variant: ProductVariant
    let name: String
    let price: String?
    var isAvailable: Bool
    let url: String
    let imageURL: String?
    let sku: String?
    let stockLevel: Int?
    
    // 添加变体级别的监控状态
    var isMonitoring: Bool
    var lastChecked: Date
    var totalChecks: Int
    var successfulChecks: Int
    var errorCount: Int
    
    init(variant: ProductVariant, name: String, price: String? = nil, isAvailable: Bool = false, 
         url: String, imageURL: String? = nil, sku: String? = nil, stockLevel: Int? = nil) {
        self.id = UUID()
        self.variant = variant
        self.name = name
        self.price = price
        self.isAvailable = isAvailable
        self.url = url
        self.imageURL = imageURL
        self.sku = sku
        self.stockLevel = stockLevel
        self.isMonitoring = false
        self.lastChecked = Date()
        self.totalChecks = 0
        self.successfulChecks = 0
        self.errorCount = 0
    }
    
    mutating func incrementCheck() {
        totalChecks += 1
        lastChecked = Date()
    }
    
    mutating func incrementSuccess() {
        successfulChecks += 1
        errorCount = 0
    }
    
    mutating func incrementError() {
        errorCount += 1
    }
}

// 改进：产品结构体支持多个变体
struct Product: Identifiable, Codable {
    let id: UUID
    let baseURL: String  // 产品的基础URL
    var name: String
    var imageURL: String?
    var monitoringInterval: TimeInterval
    var autoStart: Bool
    var customUserAgent: String?
    var maxRetries: Int
    
    // 支持多个变体
    var variants: [VariantDetail]
    
    // 向后兼容的属性
    var url: String { baseURL }
    var variant: ProductVariant { variants.first?.variant ?? .singleBox }
    var price: String? { variants.first?.price }
    var isAvailable: Bool { variants.contains { $0.isAvailable } }
    var isMonitoring: Bool { variants.contains { $0.isMonitoring } }
    var lastChecked: Date { variants.map { $0.lastChecked }.max() ?? Date() }
    var totalChecks: Int { variants.reduce(0) { $0 + $1.totalChecks } }
    var successfulChecks: Int { variants.reduce(0) { $0 + $1.successfulChecks } }
    var errorCount: Int { variants.reduce(0) { $0 + $1.errorCount } }
    
    // 兼容旧版本的属性
    var checkCount: Int { totalChecks }
    var successCount: Int { successfulChecks }
    
    // 单变体产品初始化器（向后兼容）
    init(url: String, 
         name: String, 
         variant: ProductVariant = .singleBox,
         imageURL: String? = nil,
         monitoringInterval: TimeInterval = 300,
         autoStart: Bool = false) {
        self.id = UUID()
        self.baseURL = url
        self.name = name
        self.imageURL = imageURL
        self.monitoringInterval = monitoringInterval
        self.autoStart = autoStart
        self.maxRetries = 3
        
        // 创建单个变体
        let variantDetail = VariantDetail(
            variant: variant,
            name: name,
            url: url,
            imageURL: imageURL
        )
        self.variants = [variantDetail]
    }
    
    // 多变体产品初始化器
    init(baseURL: String,
         name: String,
         variants: [VariantDetail],
         imageURL: String? = nil,
         monitoringInterval: TimeInterval = 300,
         autoStart: Bool = false) {
        self.id = UUID()
        self.baseURL = baseURL
        self.name = name
        self.imageURL = imageURL
        self.monitoringInterval = monitoringInterval
        self.autoStart = autoStart
        self.maxRetries = 3
        self.variants = variants
    }
    
    // 获取特定变体
    func getVariant(by id: UUID) -> VariantDetail? {
        return variants.first { $0.id == id }
    }
    
    // 更新特定变体
    mutating func updateVariant(_ variant: VariantDetail) {
        if let index = variants.firstIndex(where: { $0.id == variant.id }) {
            variants[index] = variant
        }
    }
    
    // 添加新变体
    mutating func addVariant(_ variant: VariantDetail) {
        // 检查是否已存在相同URL的变体
        if !variants.contains(where: { $0.url == variant.url }) {
            variants.append(variant)
        }
    }
    
    // 移除变体
    mutating func removeVariant(id: UUID) {
        variants.removeAll { $0.id == id }
    }
    
    // 获取可用的变体
    var availableVariants: [VariantDetail] {
        return variants.filter { $0.isAvailable }
    }
    
    // 获取正在监控的变体
    var monitoringVariants: [VariantDetail] {
        return variants.filter { $0.isMonitoring }
    }
    
    var fullDisplayName: String {
        if variants.count == 1 {
            return "\(name) (\(variants[0].variant.displayName))"
        } else {
            return "\(name) (\(variants.count)个变体)"
        }
    }
}

// MARK: - 商品页面解析结果
struct ProductPageInfo: Codable {
    let name: String
    let availableVariants: [ProductVariantInfo]
    let imageURL: String?
    let description: String?
    let brand: String?
    let category: String?
    
    struct ProductVariantInfo: Codable {
        let variant: ProductVariant
        let price: String?
        let isAvailable: Bool
        let url: String
        let imageURL: String?
        let sku: String?
        let stockLevel: Int?
        let variantName: String?
    }
}

enum ProductStatus {
    case available
    case outOfStock
    case error
    case unknown
}

// Hermes表格数据模型
struct HermesFormData: Codable, Identifiable {
    var id = UUID()
    var lastName: String
    var firstName: String
    var email: String
    var phone: String
    var passport: String
    var preferredStore: String
    var country: String
    var acceptTerms: Bool
    var consentDataProcessing: Bool
    var isEnabled: Bool
    var lastSubmitted: Date?
    var submitCount: Int
    
    init() {
        self.lastName = ""
        self.firstName = ""
        self.email = ""
        self.phone = ""
        self.passport = ""
        self.preferredStore = "全部"
        self.country = "Germany"
        self.acceptTerms = false
        self.consentDataProcessing = false
        self.isEnabled = true
        self.lastSubmitted = nil
        self.submitCount = 0
    }
}

struct HermesSubmissionLog: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let status: HermesSubmissionStatus
    let message: String
    let responseTime: TimeInterval?
    
    init(status: HermesSubmissionStatus, message: String, responseTime: TimeInterval? = nil) {
        self.timestamp = Date()
        self.status = status
        self.message = message
        self.responseTime = responseTime
    }
}

enum HermesSubmissionStatus: String, Codable, CaseIterable {
    case success = "成功提交"
    case failed = "提交失败"
    case networkError = "网络错误"
    case formError = "表格错误"
    case blocked = "被阻止"
    
    var color: String {
        switch self {
        case .success:
            return "green"
        case .failed, .formError, .blocked:
            return "red"
        case .networkError:
            return "orange"
        }
    }
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failed, .formError:
            return "xmark.circle.fill"
        case .networkError:
            return "wifi.slash"
        case .blocked:
            return "shield.slash.fill"
        }
    }
} 