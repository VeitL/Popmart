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

// 新增：变体详细信息结构体
struct VariantDetail: Codable, Identifiable {
    let id: UUID
    let variant: ProductVariant
    let name: String
    let price: String?
    let isAvailable: Bool
    let url: String
    let imageURL: String?
    let sku: String?
    let stockLevel: Int?
    
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
    }
}

struct Product: Identifiable, Codable {
    let id: UUID
    let url: String
    var name: String
    var variant: ProductVariant
    var imageURL: String?
    var price: String?
    var isAvailable: Bool
    var isMonitoring: Bool
    var monitoringInterval: TimeInterval
    var autoStart: Bool
    var customUserAgent: String?
    var maxRetries: Int
    var lastChecked: Date
    
    private(set) var totalChecks: Int
    private(set) var successfulChecks: Int
    private(set) var errorCount: Int
    
    // 兼容旧版本的属性
    var checkCount: Int { totalChecks }
    var successCount: Int { successfulChecks }
    
    init(url: String, 
         name: String, 
         variant: ProductVariant = .singleBox,
         imageURL: String? = nil,
         monitoringInterval: TimeInterval = 300,
         autoStart: Bool = false) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.variant = variant
        self.imageURL = imageURL
        self.isAvailable = false
        self.isMonitoring = false
        self.monitoringInterval = monitoringInterval
        self.autoStart = autoStart
        self.maxRetries = 3
        self.totalChecks = 0
        self.successfulChecks = 0
        self.errorCount = 0
        self.lastChecked = Date()
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
    
    var fullDisplayName: String {
        return "\(name) (\(variant.displayName))"
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