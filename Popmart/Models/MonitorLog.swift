import Foundation

enum LogStatus: String, Codable, CaseIterable {
    case success = "成功"
    case error = "错误"
    case networkError = "网络错误"
    case antiBot = "反爬虫"
    case availabilityChanged = "状态变化"
    case instantCheck = "立即检查"
    
    var statusColor: String {
        switch self {
        case .success, .instantCheck:
            return "green"
        case .error, .networkError, .antiBot:
            return "red"
        case .availabilityChanged:
            return "blue"
        }
    }
    
    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error, .networkError:
            return "xmark.circle.fill"
        case .antiBot:
            return "shield.slash.fill"
        case .availabilityChanged:
            return "arrow.triangle.2.circlepath"
        case .instantCheck:
            return "bolt.fill"
        }
    }
}

struct MonitorLog: Identifiable, Codable {
    let id: UUID
    let productId: UUID
    let productName: String
    let status: LogStatus
    let message: String
    let timestamp: Date
    let responseTime: TimeInterval?
    let httpStatusCode: Int?
    
    init(productId: UUID,
         productName: String,
         status: LogStatus,
         message: String,
         responseTime: TimeInterval? = nil,
         httpStatusCode: Int? = nil) {
        self.id = UUID()
        self.productId = productId
        self.productName = productName
        self.status = status
        self.message = message
        self.timestamp = Date()
        self.responseTime = responseTime
        self.httpStatusCode = httpStatusCode
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    var statusColor: String {
        return status.statusColor
    }
} 