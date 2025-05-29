//
//  ProductVariantView.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import SwiftUI

struct ProductVariantView: View {
    @ObservedObject var productMonitor: ProductMonitor
    let product: Product
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // 产品基础信息
                Section(header: Text("产品信息")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(product.name)
                            .font(.headline)
                        
                        if let imageURL = product.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Rectangle()
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            .frame(height: 120)
                            .cornerRadius(8)
                        }
                        
                        Text("基础URL: \(product.baseURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 变体列表
                Section(header: Text("变体列表 (\(product.variants.count)个)")) {
                    ForEach(product.variants) { variant in
                        VariantRow(
                            variant: variant,
                            product: product,
                            productMonitor: productMonitor
                        )
                    }
                    .onDelete(perform: deleteVariants)
                }
                
                // 产品统计
                Section(header: Text("监控统计")) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("总检查次数")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(product.totalChecks)")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("成功次数")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(product.successfulChecks)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("错误次数")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(product.errorCount)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("变体管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("开始所有变体监控") {
                            startAllVariants()
                        }
                        
                        Button("停止所有变体监控") {
                            stopAllVariants()
                        }
                        
                        Divider()
                        
                        Button("立即检查所有变体") {
                            checkAllVariants()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private func deleteVariants(at offsets: IndexSet) {
        for index in offsets {
            let variantId = product.variants[index].id
            productMonitor.removeVariantFromProduct(productId: product.id, variantId: variantId)
        }
    }
    
    private func startAllVariants() {
        for variant in product.variants {
            if !variant.isMonitoring {
                productMonitor.startMonitoringVariant(productId: product.id, variantId: variant.id)
            }
        }
    }
    
    private func stopAllVariants() {
        for variant in product.variants {
            if variant.isMonitoring {
                productMonitor.stopMonitoringVariant(productId: product.id, variantId: variant.id)
            }
        }
    }
    
    private func checkAllVariants() {
        for _ in product.variants {
            // 立即检查所有变体
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2)) {
                productMonitor.instantCheck(for: product.id)
            }
        }
    }
}

// MARK: - 变体行视图
struct VariantRow: View {
    let variant: VariantDetail
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 变体图标和类型
                Image(systemName: variant.variant.icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(variant.variant.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 监控状态切换
                Toggle("", isOn: Binding(
                    get: { variant.isMonitoring },
                    set: { isOn in
                        if isOn {
                            productMonitor.startMonitoringVariant(productId: product.id, variantId: variant.id)
                        } else {
                            productMonitor.stopMonitoringVariant(productId: product.id, variantId: variant.id)
                        }
                    }
                ))
                .labelsHidden()
            }
            
            // 变体详细信息
            HStack {
                // 库存状态
                HStack(spacing: 4) {
                    Circle()
                        .fill(variant.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(variant.isAvailable ? "有库存" : "缺货")
                        .font(.caption)
                        .foregroundColor(variant.isAvailable ? .green : .red)
                }
                
                Spacer()
                
                // 价格
                if let price = variant.price {
                    Text(price)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            
            // 统计信息
            HStack {
                Text("检查: \(variant.totalChecks)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("成功: \(variant.successfulChecks)")
                    .font(.caption2)
                    .foregroundColor(.green)
                
                Spacer()
                
                Text("错误: \(variant.errorCount)")
                    .font(.caption2)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text(formatDate(variant.lastChecked))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // URL显示（可折叠）
            if variant.url != product.baseURL {
                Text("URL: \(variant.url)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("立即检查") {
                // 立即检查这个变体
                productMonitor.instantCheck(for: product.id)
            }
            
            Button("复制URL") {
                UIPasteboard.general.string = variant.url
            }
            
            Divider()
            
            Button("删除变体", role: .destructive) {
                productMonitor.removeVariantFromProduct(productId: product.id, variantId: variant.id)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    let monitor = ProductMonitor()
    let sampleVariants = [
        VariantDetail(variant: .singleBox, name: "单盒装", price: "€19.99", isAvailable: true, url: "https://example.com/single"),
        VariantDetail(variant: .wholeSet, name: "整套装", price: "€99.99", isAvailable: false, url: "https://example.com/set")
    ]
    let sampleProduct = Product(baseURL: "https://example.com", name: "示例产品", variants: sampleVariants)
    
    return ProductVariantView(productMonitor: monitor, product: sampleProduct)
} 