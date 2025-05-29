import SwiftUI

struct AddProductView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var productMonitor: ProductMonitor
    
    @State private var url = ""
    @State private var name = ""
    @State private var selectedVariant: ProductVariant = .singleBox
    @State private var selectedVariantInfo: ProductPageInfo.ProductVariantInfo?
    @State private var availableVariants: [ProductPageInfo.ProductVariantInfo] = []
    @State private var productPageInfo: ProductPageInfo?
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
                    
                    // 显示品牌信息（如果有）
                    if let brand = productPageInfo?.brand {
                        HStack {
                            Text("品牌:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(brand)
                        }
                    }
                    
                    // 显示商品图片（如果有）
                    if let imageURL = productPageInfo?.imageURL,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(height: 100)
                    }
                    
                    // 显示变体选择（如果有可用变体）
                    if !availableVariants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("选择变体:")
                                .font(.headline)
                            
                            ForEach(Array(availableVariants.enumerated()), id: \.offset) { index, variant in
                                VariantSelectionRow(
                                    variant: variant,
                                    isSelected: selectedVariantInfo?.variantName == variant.variantName,
                                    onTap: {
                                        selectedVariantInfo = variant
                                        selectedVariant = variant.variant
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        // 如果没有从网站获取到变体，显示默认的商品类型选择器
                        Picker("商品类型", selection: $selectedVariant) {
                            ForEach(ProductVariant.allCases, id: \.self) { variant in
                                Text(variant.rawValue).tag(variant)
                            }
                        }
                    }
                }
                
                // 显示商品描述（如果有）
                if let description = productPageInfo?.description, !description.isEmpty {
                    Section(header: Text("商品描述")) {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    ProgressView("获取商品信息中...")
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
        availableVariants = []
        productPageInfo = nil
        
        productMonitor.parseProductPage(url: url) { result in
            isLoading = false
            
            switch result {
            case .success(let info):
                productPageInfo = info
                name = info.name
                availableVariants = info.availableVariants
                
                // 如果有变体，选择第一个
                if let firstVariant = info.availableVariants.first {
                    selectedVariantInfo = firstVariant
                    selectedVariant = firstVariant.variant
                }
                
                errorMessage = nil
                
            case .failure(let error):
                errorMessage = "获取商品信息失败: \(error.localizedDescription)"
            }
        }
    }
    
    private func addProduct() {
        // 检查是否有多个变体被选择
        let selectedVariants = availableVariants.filter { variant in
            // 这里可以添加选择逻辑，现在先简单处理
            return selectedVariantInfo?.variantName == variant.variantName
        }
        
        if availableVariants.count > 1 {
            // 多变体情况：创建VariantDetail数组
            var variants: [VariantDetail] = []
            
            if selectedVariants.isEmpty {
                // 如果没有特定选择，添加所有可用变体
                for variantInfo in availableVariants {
                    let variant = VariantDetail(
                        variant: mapVariantInfoToProductVariant(variantInfo),
                        name: variantInfo.variantName ?? "未知变体",
                        price: variantInfo.price,
                        isAvailable: variantInfo.isAvailable,
                        url: variantInfo.url,
                        imageURL: variantInfo.imageURL,
                        sku: variantInfo.sku,
                        stockLevel: variantInfo.stockLevel
                    )
                    variants.append(variant)
                }
                
                // 添加多变体产品
                productMonitor.addMultiVariantProduct(
                    baseURL: url,
                    name: name,
                    variants: variants,
                    imageURL: productPageInfo?.imageURL,
                    monitoringInterval: monitoringInterval,
                    autoStart: autoStart
                )
            } else {
                // 只添加选中的变体作为单独的产品
                let productURL = selectedVariantInfo?.url ?? url
                let variantName = selectedVariantInfo?.variantName
                let price = selectedVariantInfo?.price
                let imageURL = selectedVariantInfo?.imageURL ?? productPageInfo?.imageURL
                
                let fullName = variantName != nil ? "\(name) - \(variantName!)" : name
                
                productMonitor.addProduct(
                    url: productURL,
                    name: fullName,
                    variant: selectedVariant,
                    imageURL: imageURL,
                    monitoringInterval: monitoringInterval,
                    autoStart: autoStart
                )
                
                // 更新价格信息
                if let price = price, let product = productMonitor.products.last {
                    // 更新第一个变体的价格
                    var updatedProduct = product
                    if !updatedProduct.variants.isEmpty {
                        updatedProduct.variants[0] = VariantDetail(
                            variant: updatedProduct.variants[0].variant,
                            name: updatedProduct.variants[0].name,
                            price: price,
                            isAvailable: updatedProduct.variants[0].isAvailable,
                            url: updatedProduct.variants[0].url,
                            imageURL: updatedProduct.variants[0].imageURL,
                            sku: updatedProduct.variants[0].sku,
                            stockLevel: updatedProduct.variants[0].stockLevel
                        )
                        productMonitor.updateProduct(updatedProduct)
                    }
                }
            }
        } else {
            // 单变体情况：使用原有逻辑
            let productURL = selectedVariantInfo?.url ?? url
            let variantName = selectedVariantInfo?.variantName
            let price = selectedVariantInfo?.price
            let imageURL = selectedVariantInfo?.imageURL ?? productPageInfo?.imageURL
            
            let fullName = variantName != nil ? "\(name) - \(variantName!)" : name
            
            productMonitor.addProduct(
                url: productURL,
                name: fullName,
                variant: selectedVariant,
                imageURL: imageURL,
                monitoringInterval: monitoringInterval,
                autoStart: autoStart
            )
            
            // 更新价格信息
            if let price = price, let product = productMonitor.products.last {
                // 更新第一个变体的价格
                var updatedProduct = product
                if !updatedProduct.variants.isEmpty {
                    updatedProduct.variants[0] = VariantDetail(
                        variant: updatedProduct.variants[0].variant,
                        name: updatedProduct.variants[0].name,
                        price: price,
                        isAvailable: updatedProduct.variants[0].isAvailable,
                        url: updatedProduct.variants[0].url,
                        imageURL: updatedProduct.variants[0].imageURL,
                        sku: updatedProduct.variants[0].sku,
                        stockLevel: updatedProduct.variants[0].stockLevel
                    )
                    productMonitor.updateProduct(updatedProduct)
                }
            }
        }
        
        dismiss()
    }
    
    // 新增：将ProductVariantInfo映射到ProductVariant
    private func mapVariantInfoToProductVariant(_ variantInfo: ProductPageInfo.ProductVariantInfo) -> ProductVariant {
        return variantInfo.variant
    }
}

// MARK: - 变体选择行视图
struct VariantSelectionRow: View {
    let variant: ProductPageInfo.ProductVariantInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(variant.variantName ?? "未知变体")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if let price = variant.price {
                        Text("价格: \(price)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: variant.variant.icon)
                            .font(.caption)
                        Text(variant.variant.displayName)
                            .font(.caption)
                        
                        Spacer()
                        
                        if variant.isAvailable {
                            Text("有库存")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("缺货")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AddProductView(productMonitor: ProductMonitor())
} 