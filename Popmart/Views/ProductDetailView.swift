import SwiftUI

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    
    @State private var showingLogs = false
    @State private var monitoringInterval: TimeInterval
    @State private var autoStart: Bool
    @State private var customUserAgent: String
    
    private let intervals = [
        60.0: "1分钟",
        180.0: "3分钟",
        300.0: "5分钟",
        600.0: "10分钟",
        900.0: "15分钟",
        1800.0: "30分钟",
        3600.0: "1小时"
    ]
    
    init(product: Product, productMonitor: ProductMonitor) {
        self.product = product
        self.productMonitor = productMonitor
        _monitoringInterval = State(initialValue: product.monitoringInterval)
        _autoStart = State(initialValue: product.autoStart)
        _customUserAgent = State(initialValue: product.customUserAgent ?? "")
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("商品信息")) {
                    if let imageURL = product.imageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxHeight: 200)
                    }
                    
                    LabeledContent("名称", value: product.name)
                    LabeledContent("类型", value: product.variant.rawValue)
                    if let price = product.price {
                        LabeledContent("价格", value: price)
                    }
                    Link("查看商品", destination: URL(string: product.url)!)
                }
                
                Section(header: Text("监控设置")) {
                    Picker("检查间隔", selection: $monitoringInterval) {
                        ForEach(Array(intervals.keys.sorted()), id: \.self) { interval in
                            Text(intervals[interval] ?? "").tag(interval)
                        }
                    }
                    
                    Toggle("自动开始监控", isOn: $autoStart)
                    
                    TextField("自定义User-Agent", text: $customUserAgent)
                        .font(.caption)
                }
                
                Section(header: Text("监控状态")) {
                    LabeledContent("当前状态", value: product.isAvailable ? "有库存" : "缺货")
                    LabeledContent("总检查次数", value: "\(product.totalChecks)")
                    LabeledContent("成功次数", value: "\(product.successfulChecks)")
                    LabeledContent("错误次数", value: "\(product.errorCount)")
                }
                
                Section {
                    Button("查看监控日志") {
                        showingLogs = true
                    }
                    
                    Button("清除此商品日志") {
                        productMonitor.clearLogsForProduct(product.id)
                    }
                    .foregroundColor(.orange)
                }
                
                Section {
                    Button("删除商品") {
                        if let index = productMonitor.products.firstIndex(where: { $0.id == product.id }) {
                            productMonitor.removeProduct(at: index)
                            dismiss()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("商品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        productMonitor.updateProductSettings(
                            product.id,
                            interval: monitoringInterval,
                            autoStart: autoStart,
                            customUserAgent: customUserAgent.isEmpty ? nil : customUserAgent
                        )
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingLogs) {
                ProductLogsView(productMonitor: productMonitor, productId: product.id)
            }
        }
    }
}

struct ProductLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var productMonitor: ProductMonitor
    let productId: UUID
    
    private var filteredLogs: [MonitorLog] {
        productMonitor.monitorLogs.filter { $0.productId == productId }
    }
    
    var body: some View {
        NavigationView {
            List(filteredLogs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(log.status.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(log.statusColor).opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text(log.message)
                        .font(.body)
                    
                    if let responseTime = log.responseTime {
                        Text(String(format: "响应时间: %.2f秒", responseTime))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if let statusCode = log.httpStatusCode {
                        Text("HTTP状态码: \(statusCode)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("监控日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ProductDetailView(
        product: Product(
            url: "https://example.com",
            name: "测试商品",
            variant: .singleBox
        ),
        productMonitor: ProductMonitor()
    )
} 