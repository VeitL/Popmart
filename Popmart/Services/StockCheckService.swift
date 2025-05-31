import Foundation
import Network

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
    
    // 动态获取后端URL
    private var baseURL: String {
        return UserDefaults.standard.string(forKey: "backendURL") ?? "https://popmart-stock-checker-aiu9amdzm-nion119-gmailcoms-projects.vercel.app"
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
    
    private func checkStockWithPuppeteer(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/check-stock?productId=\(productId)") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(StockCheckResponse.self, from: data)
                
                if response.success, let stockData = response.data {
                    DispatchQueue.main.async {
                        self?.lastCheckResult = stockData
                        self?.errorMessage = nil
                        self?.isLoading = false
                    }
                    completion(.success(stockData))
                } else {
                    let errorMsg = response.error ?? "未知错误"
                    completion(.failure(NetworkError.apiError(errorMsg)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func checkStockSimple(productId: String, completion: @escaping (Result<StockData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/check-stock-simple?productId=\(productId)") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "网络请求失败: \(error.localizedDescription)"
                }
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NetworkError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(StockCheckResponse.self, from: data)
                
                if response.success, let stockData = response.data {
                    DispatchQueue.main.async {
                        self?.lastCheckResult = stockData
                        self?.errorMessage = nil
                    }
                    completion(.success(stockData))
                } else {
                    let errorMsg = response.error ?? "未知错误"
                    DispatchQueue.main.async {
                        self?.errorMessage = errorMsg
                    }
                    completion(.failure(NetworkError.apiError(errorMsg)))
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "数据解析失败: \(error.localizedDescription)"
                }
                completion(.failure(error))
            }
        }.resume()
    }
    
    func checkStockForURL(_ urlString: String) async throws -> StockResult {
        guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw StockCheckError.invalidURL
        }
        
        // 优先尝试Puppeteer API（支持JavaScript）
        do {
            let puppeteerResult = try await checkWithPuppeteerAPI(encodedURL)
            print("✅ Puppeteer API成功获取库存信息")
            return puppeteerResult
        } catch {
            print("⚠️ Puppeteer API失败: \(error.localizedDescription)")
            print("🔄 回退到简单API...")
            
            // 如果Puppeteer失败，使用简单API作为后备
            return try await checkWithSimpleAPI(encodedURL)
        }
    }
    
    private func checkWithPuppeteerAPI(_ encodedURL: String) async throws -> StockResult {
        guard let url = URL(string: "\(baseURL)/api/check-stock-puppeteer?url=\(encodedURL)") else {
            throw StockCheckError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45.0 // Puppeteer需要更长时间
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StockCheckError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StockCheckError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard apiResponse.success else {
            throw StockCheckError.serverError(apiResponse.error ?? "Unknown error")
        }
        
        return apiResponse.data
    }
    
    private func checkWithSimpleAPI(_ encodedURL: String) async throws -> StockResult {
        guard let url = URL(string: "\(baseURL)/api/check-stock-simple?url=\(encodedURL)") else {
            throw StockCheckError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StockCheckError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StockCheckError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard apiResponse.success else {
            throw StockCheckError.serverError(apiResponse.error ?? "Unknown error")
        }
        
        return apiResponse.data
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