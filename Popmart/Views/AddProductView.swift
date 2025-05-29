import SwiftUI

struct AddProductView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var productMonitor: ProductMonitor
    
    @State private var url = ""
    @State private var name = ""
    @State private var selectedVariant: ProductVariant = .singleBox
    @State private var monitoringInterval: TimeInterval = 300
    @State private var autoStart = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let intervals = [
        60.0: "1分钟",
        180.0: "3分钟",
        300.0: "5分钟",
        600.0: "10分钟",
        900.0: "15分钟",
        1800.0: "30分钟",
        3600.0: "1小时"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("商品信息")) {
                    TextField("商品URL", text: $url)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if !url.isEmpty {
                        Button("自动获取信息") {
                            fetchProductInfo()
                        }
                        .disabled(isLoading)
                    }
                    
                    TextField("商品名称", text: $name)
                    
                    Picker("商品类型", selection: $selectedVariant) {
                        ForEach(ProductVariant.allCases, id: \.self) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }
                }
                
                Section(header: Text("监控设置")) {
                    Picker("检查间隔", selection: $monitoringInterval) {
                        ForEach(Array(intervals.keys.sorted()), id: \.self) { interval in
                            Text(intervals[interval] ?? "").tag(interval)
                        }
                    }
                    
                    Toggle("添加后立即开始监控", isOn: $autoStart)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("添加商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加") {
                        addProduct()
                    }
                    .disabled(url.isEmpty || name.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("加载中...")
                        .progressViewStyle(.circular)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private func fetchProductInfo() {
        isLoading = true
        errorMessage = nil
        
        productMonitor.parseProductPage(url: url) { result in
            isLoading = false
            
            switch result {
            case .success(let info):
                name = info.name
                if let firstVariant = info.availableVariants.first {
                    selectedVariant = firstVariant.variant
                }
            case .failure(let error):
                errorMessage = "获取商品信息失败: \(error.localizedDescription)"
            }
        }
    }
    
    private func addProduct() {
        productMonitor.addProduct(
            url: url,
            name: name,
            variant: selectedVariant,
            imageURL: nil,
            monitoringInterval: monitoringInterval,
            autoStart: autoStart
        )
        dismiss()
    }
}

#Preview {
    AddProductView(productMonitor: ProductMonitor())
} 