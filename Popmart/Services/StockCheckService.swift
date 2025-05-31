import Foundation
import Network

// MARK: - Cloud Run API响应模型
struct CloudRunStockResponse: Codable {
    let success: Bool
    let productId: String?
    let productName: String?
    let price: String?
    let inStock: Bool?
    let stockStatus: String?
    let stockReason: String?
    let url: String?
    let currentUrl: String?
    let timestamp: String?
    let debug: CloudRunDebugInfo?
    let error: String?
    let message: String?
}

struct CloudRunDebugInfo: Codable {
    let buttonText: String?
    let isButtonDisabled: Bool?
}

// MARK: - 兼容旧格式的数据模型
struct StockCheckResponse: Codable {
    let success: Bool
    let data: StockData?
    let error: String?
}

struct StockData: Codable {
    let productId: String
    let productName: String
    let inStock: Bool
    let stockReason: String
    let price: String
    let url: String
    let timestamp: String
    let debug: DebugInfo?
}

struct DebugInfo: Codable {
    let hasAddToCartButton: Bool
    let hasDisabledButton: Bool
    let hasSoldOutText: Bool
    let buttonText: String
    let pageContentSample: String?
}

// MARK: - Data Models
struct APIResponse: Codable {
    let success: Bool
    let data: StockResult
    let error: String?
}

struct StockResult: Codable {
    let productId: String
    let productName: String
    let inStock: Bool
    let stockReason: String
    let price: String
    let url: String
    let timestamp: String
}

// MARK: - Error Types
enum StockCheckError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .serverError(let message):
            return "服务器错误: \(message)"
        case .parseError(let message):
            return "数据解析错误: \(message)"
        }
    }
}

class StockCheckService: ObservableObject {
    @Published var isLoading = false
    @Published var lastCheckResult: StockData?
    @Published var errorMessage: String?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = true
    
    // 更新为Google Cloud Run URL
    private var baseURL: String {
        return UserDefaults.standard.string(forKey: "backendURL") ?? "https://popmart-full-215643545724.asia-northeast1.run.app"
    }
    
    init() {
        startNetworkMonitoring()
    }
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    func checkStock(productId: String = "1707", completion: @escaping (Result<StockData, Error>) -> Void) {
        guard isConnected else {
            completion(.failure(NetworkError.noConnection))
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // 使用新的Google Cloud Run API
        checkStockWithCloudRun(productId: productId, completion: completion)
    }
    
    // 新的Cloud Run API调用方法
    private func checkStockWithCloudRun(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/check-stock?productId=\(productId)") else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "无效的URL"
            }
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60.0 // Cloud Run需要更长时间
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        print("🚀 正在调用Cloud Run API: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "网络请求失败: \(error.localizedDescription)"
                }
                print("❌ 网络错误: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "没有收到数据"
                }
                completion(.failure(NetworkError.noData))
                return
            }
            
            // 打印原始响应用于调试
            if let responseString = String(data: data, encoding: .utf8) {
                print("📦 API响应: \(responseString)")
            }
            
            do {
                // 尝试解析新的Cloud Run API响应格式
                let cloudRunResponse = try JSONDecoder().decode(CloudRunStockResponse.self, from: data)
                
                if cloudRunResponse.success {
                    // 转换为旧格式以保持兼容性
                    let stockData = StockData(
                        productId: cloudRunResponse.productId ?? productId,
                        productName: cloudRunResponse.productName ?? "未知产品",
                        inStock: cloudRunResponse.inStock ?? false,
                        stockReason: cloudRunResponse.stockReason ?? "无法确定库存状态",
                        price: cloudRunResponse.price ?? "价格未知",
                        url: cloudRunResponse.url ?? "",
                        timestamp: cloudRunResponse.timestamp ?? ISO8601DateFormatter().string(from: Date()),
                        debug: DebugInfo(
                            hasAddToCartButton: cloudRunResponse.debug?.buttonText?.contains("add") ?? false,
                            hasDisabledButton: cloudRunResponse.debug?.isButtonDisabled ?? false,
                            hasSoldOutText: cloudRunResponse.stockReason?.contains("缺货") ?? false,
                            buttonText: cloudRunResponse.debug?.buttonText ?? "",
                            pageContentSample: nil
                        )
                    )
                    
                    DispatchQueue.main.async {
                        self?.lastCheckResult = stockData
                        self?.errorMessage = nil
                    }
                    print("✅ 库存检查成功: \(stockData.productName) - \(stockData.inStock ? "有货" : "缺货")")
                    completion(.success(stockData))
                } else {
                    let errorMsg = cloudRunResponse.error ?? cloudRunResponse.message ?? "未知错误"
                    DispatchQueue.main.async {
                        self?.errorMessage = errorMsg
                    }
                    print("❌ API返回错误: \(errorMsg)")
                    completion(.failure(NetworkError.apiError(errorMsg)))
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "数据解析失败: \(error.localizedDescription)"
                }
                print("❌ 解析错误: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    // 保留旧方法以兼容现有代码
    private func checkStockWithPuppeteer(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
        // 重定向到新的Cloud Run方法
        checkStockWithCloudRun(productId: productId, completion: completion)
    }
    
    private func checkStockSimple(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
        // 重定向到新的Cloud Run方法
        checkStockWithCloudRun(productId: productId, completion: completion)
    }
    
    func checkStockForURL(_ urlString: String) async throws -> StockResult {
        guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw StockCheckError.invalidURL
        }
        
        return try await checkWithCloudRunAPI(encodedURL)
    }
    
    private func checkWithCloudRunAPI(_ encodedURL: String) async throws -> StockResult {
        guard let url = URL(string: "\(baseURL)/api/check-stock?url=\(encodedURL)") else {
            throw StockCheckError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        print("🚀 正在调用Cloud Run URL API: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StockCheckError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StockCheckError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let cloudRunResponse = try JSONDecoder().decode(CloudRunStockResponse.self, from: data)
        
        guard cloudRunResponse.success else {
            throw StockCheckError.serverError(cloudRunResponse.error ?? cloudRunResponse.message ?? "Unknown error")
        }
        
        // 转换为StockResult格式
        return StockResult(
            productId: cloudRunResponse.productId ?? "unknown",
            productName: cloudRunResponse.productName ?? "未知产品",
            inStock: cloudRunResponse.inStock ?? false,
            stockReason: cloudRunResponse.stockReason ?? "无法确定库存状态",
            price: cloudRunResponse.price ?? "价格未知",
            url: cloudRunResponse.url ?? "",
            timestamp: cloudRunResponse.timestamp ?? ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // 保留旧方法以兼容现有代码
    private func checkWithPuppeteerAPI(_ encodedURL: String) async throws -> StockResult {
        return try await checkWithCloudRunAPI(encodedURL)
    }
    
    private func checkWithSimpleAPI(_ encodedURL: String) async throws -> StockResult {
        return try await checkWithCloudRunAPI(encodedURL)
    }
    
    deinit {
        monitor.cancel()
    }
}

enum NetworkError: LocalizedError {
    case noConnection
    case invalidURL
    case noData
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "无网络连接"
        case .invalidURL:
            return "无效的URL"
        case .noData:
            return "没有收到数据"
        case .apiError(let message):
            return "API错误: \(message)"
        }
    }
} 