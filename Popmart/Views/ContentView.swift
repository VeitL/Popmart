//
//  ContentView.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import SwiftUI
import MessageUI

struct ContentView: View {
    @StateObject private var productMonitor = ProductMonitor()
    @StateObject private var emailService = EmailService()
    @StateObject private var hermesService = HermesService()
    @State private var showingSettings = false
    @State private var showingAddProduct = false
    @State private var showingLogs = false
    @State private var showingEmailComposer = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 商品监控页面
            ProductListView(productMonitor: productMonitor)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("商品监控")
                }
                .tag(0)
            
            // 日志页面
            LogsView(productMonitor: productMonitor)
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("监控日志")
                }
                .tag(1)
            
            // Hermes表格页面
            HermesFormView(hermesService: hermesService)
                .tabItem {
                    Image(systemName: "doc.richtext")
                    Text("Hermes表格")
                }
                .tag(2)
            
            // 设置页面 - 使用独立的SettingsView
            SettingsView(emailService: emailService, productMonitor: productMonitor, hermesService: hermesService)
                .tabItem {
                    Image(systemName: "gear")
                    Text("设置")
                }
                .tag(3)
        }
        .sheet(isPresented: $showingEmailComposer) {
            if MFMailComposeViewController.canSendMail() {
                MailComposer(
                    product: productMonitor.products.first(where: { $0.isAvailable }) ?? Product(url: "", name: ""),
                    recipientEmail: emailService.emailSettings.recipientEmail,
                    isPresented: $showingEmailComposer
                )
            } else {
                Text("邮件服务不可用")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            emailService.requestNotificationPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProductAvailable"))) { _ in
            if emailService.emailSettings.isEnabled && !emailService.emailSettings.recipientEmail.isEmpty {
                showingEmailComposer = true
            }
        }
    }
}

// MARK: - 商品列表页面
struct ProductListView: View {
    @ObservedObject var productMonitor: ProductMonitor
    @State private var showingAddProduct = false
    
    var body: some View {
        NavigationView {
            VStack {
                if productMonitor.products.isEmpty {
                    EmptyProductsView()
                } else {
                    List {
                        // 全局控制区域
                        Section {
                            GlobalControlCard(productMonitor: productMonitor)
                        }
                        
                        // 商品列表
                        Section("监控商品") {
                            ForEach(productMonitor.products) { product in
                                ProductRowView(product: product, productMonitor: productMonitor)
                            }
                            .onDelete(perform: deleteProducts)
                        }
                    }
                }
            }
            .navigationTitle("Popmart监控助手")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddProduct = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProduct) {
                AddProductView(productMonitor: productMonitor)
            }
        }
    }
    
    private func deleteProducts(at offsets: IndexSet) {
        for index in offsets {
            productMonitor.removeProduct(at: index)
        }
    }
}

// MARK: - 全局控制卡片
struct GlobalControlCard: View {
    @ObservedObject var productMonitor: ProductMonitor
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("全局控制")
                        .font(.headline)
                    
                    Text(productMonitor.isAnyMonitoring ? 
                         "正在监控 \(productMonitor.products.filter({ $0.isMonitoring }).count) 个商品" : 
                         "所有监控已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(productMonitor.isAnyMonitoring ? "运行中" : "已停止")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(productMonitor.isAnyMonitoring ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .foregroundColor(productMonitor.isAnyMonitoring ? .green : .gray)
                    .cornerRadius(8)
            }
            
            // 控制按钮组
            HStack(spacing: 12) {
                Button(action: {
                    productMonitor.startAllMonitoring()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("全部开始")
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    productMonitor.stopAllMonitoring()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("全部停止")
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    productMonitor.instantCheckAll()
                }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("立即检查")
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 商品行视图
struct ProductRowView: View {
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    @State private var showingDetail = false
    @State private var showingSettings = false
    @State private var showingVariants = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 商品基本信息区域 - 独立的可点击区域
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // 商品图片
                    AsyncImageView(url: product.imageURL)
                        .frame(width: 60, height: 60)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // 商品名称和变体信息
                        HStack {
                            Text(product.name)
                                .font(.headline)
                                .lineLimit(2)
                            
                            Spacer()
                            
                            // 变体数量显示
                            if product.variants.count > 1 {
                                Button {
                                    showingVariants = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "cube.box.fill")
                                            .foregroundColor(.purple)
                                        Text("\(product.variants.count)个变体")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // 商品URL显示
                        Text(product.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        // 状态指示器
                        HStack(spacing: 8) {
                            // 库存状态
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(product.isAvailable ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(product.isAvailable ? "有货" : "缺货")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(product.isAvailable ? .green : .red)
                            }
                            
                            Spacer()
                            
                            // 监控状态
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(product.isMonitoring ? Color.blue : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(product.isMonitoring ? "监控中" : "已暂停")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(product.isMonitoring ? .blue : .gray)
                            }
                        }
                        
                        // 最后检查时间
                        Text("最后检查: \(DateFormatter.timeFormatter.string(from: product.lastChecked))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onTapGesture {
                showingDetail = true
            }
            
            Divider()
            
            // 控制按钮区域
            HStack(spacing: 16) {
                // 监控开关按钮
                Button {
                    if product.isMonitoring {
                        productMonitor.stopMonitoring(for: product.id)
                    } else {
                        productMonitor.startMonitoring(for: product.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: product.isMonitoring ? "pause.fill" : "play.fill")
                        Text(product.isMonitoring ? "暂停" : "开始")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(product.isMonitoring ? Color.orange : Color.green)
                    .cornerRadius(6)
                }
                
                // 立即检查按钮
                Button {
                    productMonitor.instantCheck(for: product.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("立即检查")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // 设置按钮
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showingDetail) {
            ProductDetailView(product: product, productMonitor: productMonitor)
        }
        .sheet(isPresented: $showingSettings) {
            ProductSettingsView(product: product, productMonitor: productMonitor)
        }
        .sheet(isPresented: $showingVariants) {
            ProductVariantsView(product: product, productMonitor: productMonitor)
        }
    }
}

// MARK: - 空状态视图
struct EmptyProductsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("还没有添加任何商品")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("点击右上角的 + 号开始添加你要监控的Popmart商品")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 异步图片视图
struct AsyncImageView: View {
    let url: String?
    
    var body: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
        } else {
            Image(systemName: "photo")
                .foregroundColor(.gray)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 添加商品视图
struct AddProductView: View {
    @ObservedObject var productMonitor: ProductMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var isAdding = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var testResult = ""
    @State private var isTestingURL = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("商品信息") {
                    TextField("输入Popmart商品链接", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("商品名称（自动解析）", text: $name)
                        .textContentType(.name)
                    
                    HStack {
                        Button("使用测试URL") {
                            url = "https://www.popmart.com/de/products/1707/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll"
                            name = "THE-MONSTERS Let's Checkmate Series"
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("测试解析") {
                            testURLParsing()
                        }
                        .buttonStyle(.bordered)
                        .disabled(url.isEmpty || isTestingURL)
                    }
                }
                
                if !testResult.isEmpty {
                    Section("测试结果") {
                        ScrollView {
                            Text(testResult)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                
                Section {
                    Button(action: addProduct) {
                        if isAdding {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("正在添加...")
                            }
                        } else {
                            Text("添加商品")
                        }
                    }
                    .disabled(url.isEmpty || name.isEmpty || isAdding)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("添加新商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("错误", isPresented: $showingError) {
                Button("确定") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func testURLParsing() {
        guard !url.isEmpty else { return }
        
        isTestingURL = true
        testResult = "正在测试URL解析..."
        
        productMonitor.testURLAdvanced(url) { result in
            DispatchQueue.main.async {
                self.testResult = result
                self.isTestingURL = false
            }
        }
    }
    
    private func addProduct() {
        guard !url.isEmpty, !name.isEmpty else { return }
        
        isAdding = true
        
        productMonitor.addProduct(url: url, name: name)
        
        DispatchQueue.main.async {
            isAdding = false
            dismiss()
        }
    }
}

// MARK: - 商品详情视图
struct ProductDetailView: View {
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 商品图片
                    AsyncImageView(url: product.imageURL)
                        .frame(height: 300)
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(product.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("变体: \(product.variant.displayName)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        if let price = product.price {
                            Text("价格: \(price)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Text("库存状态:")
                            Spacer()
                            Text(product.isAvailable ? "有货" : "缺货")
                                .fontWeight(.medium)
                                .foregroundColor(product.isAvailable ? .green : .red)
                        }
                        
                        HStack {
                            Text("监控状态:")
                            Spacer()
                            Text(product.isMonitoring ? "监控中" : "已暂停")
                                .fontWeight(.medium)
                                .foregroundColor(product.isMonitoring ? .blue : .gray)
                        }
                        
                        HStack {
                            Text("最后检查:")
                            Spacer()
                            Text(DateFormatter.timeFormatter.string(from: product.lastChecked))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("商品链接:")
                                .font(.headline)
                            
                            Link(destination: URL(string: product.url)!) {
                                Text(product.url)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("商品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 商品设置视图
struct ProductSettingsView: View {
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var monitoringInterval: Double
    @State private var maxRetries: Double
    
    init(product: Product, productMonitor: ProductMonitor) {
        self.product = product
        self.productMonitor = productMonitor
        _monitoringInterval = State(initialValue: product.monitoringInterval / 60.0) // 转换为分钟
        _maxRetries = State(initialValue: Double(product.maxRetries))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("监控设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("检查间隔")
                            Spacer()
                            Text("\(Int(monitoringInterval))分钟")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $monitoringInterval, in: 1...60, step: 1)
                            .accentColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("最大重试次数")
                            Spacer()
                            Text("\(Int(maxRetries))次")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $maxRetries, in: 1...10, step: 1)
                            .accentColor(.blue)
                    }
                }
                
                Section("危险操作") {
                    Button("删除此商品") {
                        if let index = productMonitor.products.firstIndex(where: { $0.id == product.id }) {
                            productMonitor.removeProduct(at: index)
                        }
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("商品设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveSettings() {
        productMonitor.updateProductSettings(
            product.id,
            interval: monitoringInterval * 60.0, // 转换回秒
            autoStart: product.autoStart,
            customUserAgent: product.customUserAgent
        )
        // 更新最大重试次数
        if let index = productMonitor.products.firstIndex(where: { $0.id == product.id }) {
            productMonitor.products[index].maxRetries = Int(maxRetries)
        }
    }
}

// MARK: - 商品变体视图
struct ProductVariantsView: View {
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(product.variants, id: \.id) { variant in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(variant.name)
                                .font(.headline)
                            
                            if let price = variant.price {
                                Text(price)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if variant.isAvailable {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("商品变体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 日志视图
struct LogsView: View {
    @ObservedObject var productMonitor: ProductMonitor
    @State private var selectedStatus: LogStatus?
    @State private var selectedProductName: String?
    @State private var searchText = ""
    
    var filteredLogs: [MonitorLog] {
        var logs = productMonitor.monitorLogs
        
        if let status = selectedStatus {
            logs = logs.filter { $0.status == status }
        }
        
        if let productName = selectedProductName {
            logs = logs.filter { $0.productName == productName }
        }
        
        if !searchText.isEmpty {
            logs = logs.filter { log in
                log.productName.localizedCaseInsensitiveContains(searchText) ||
                log.message.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return logs.sorted { $0.timestamp > $1.timestamp }
    }
    
    var uniqueProductNames: [String?] {
        let names = Set(productMonitor.monitorLogs.map { $0.productName })
        return [nil] + Array(names).sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if productMonitor.monitorLogs.isEmpty {
                    EmptyLogsView()
                } else {
                    List {
                        // 筛选器部分
                        Section("筛选器") {
                            FilterRow(
                                title: "状态",
                                selection: $selectedStatus,
                                options: [nil] + LogStatus.allCases,
                                displayName: { status in
                                    status?.rawValue ?? "全部"
                                }
                            )
                            
                            FilterRow(
                                title: "商品",
                                selection: $selectedProductName,
                                options: uniqueProductNames,
                                displayName: { name in
                                    name ?? "全部商品"
                                }
                            )
                        }
                        
                        // 日志列表
                        Section("监控日志") {
                            ForEach(filteredLogs) { log in
                                LogRowView(log: log)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "搜索日志...")
                }
            }
            .navigationTitle("监控日志")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("清除所有日志") {
                            productMonitor.clearLogs()
                        }
                        
                        Button("导出日志") {
                            // TODO: 实现日志导出功能
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

// MARK: - 缺失的视图组件
struct EmptyLogsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("还没有监控日志")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("开始监控商品后，日志将会显示在这里")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct FilterRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T?
    let options: [T?]
    let displayName: (T?) -> String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(displayName(option)) {
                        selection = option
                    }
                }
            } label: {
                Text(displayName(selection))
                    .foregroundColor(.blue)
            }
        }
    }
}

struct LogRowView: View {
    let log: MonitorLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(log.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(log.status.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(log.statusColor).opacity(0.2))
                    .foregroundColor(Color(log.statusColor))
                    .cornerRadius(4)
            }
            
            Text(log.message)
                .font(.body)
            
            if let responseTime = log.responseTime {
                Text(String(format: "响应时间: %.2f秒", responseTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 邮件编辑器
struct MailComposer: UIViewControllerRepresentable {
    let product: Product
    let recipientEmail: String
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipientEmail])
        composer.setSubject("🎉 Popmart商品有货通知 - \(product.name)")
        
        let body = """
        好消息！您监控的商品现在有库存了：
        
        商品名称：\(product.name)
        商品类型：\(product.variant.displayName)
        商品链接：\(product.url)
        
        赶快去抢购吧！
        
        ---
        Popmart监控助手
        """
        
        composer.setMessageBody(body, isHTML: false)
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposer
        
        init(_ parent: MailComposer) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isPresented = false
        }
    }
}

#Preview {
    ContentView()
} 