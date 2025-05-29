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
            
            // 设置页面
            AppSettingsView(emailService: emailService, productMonitor: productMonitor, hermesService: hermesService)
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
                        // 商品名称和变体
                        HStack {
                            Text(product.name)
                                .font(.headline)
                                .lineLimit(2)
                            
                            Spacer()
                            
                            // 变体标签
                            HStack(spacing: 4) {
                                Image(systemName: product.variant.icon)
                                    .foregroundColor(.purple)
                                Text(product.variant.displayName)
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                        }
                        
                        if let price = product.price {
                            Text(price)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        
                        HStack {
                            StatusBadge(isAvailable: product.isAvailable)
                            
                            if product.isMonitoring {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                    Text("监控中")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    // 信息按钮
                    Button {
                        showingDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle()) // 防止与父容器的点击事件冲突
                }
                
                // 监控设置信息
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("间隔: \(formatInterval(product.monitoringInterval))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("重试: \(product.maxRetries)次")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("成功率: \(product.checkCount > 0 ? String(format: "%.1f%%", Double(product.successCount) / Double(product.checkCount) * 100) : "0%")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("最后检查: \(DateFormatter.timeFormatter.string(from: product.lastChecked))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .contentShape(Rectangle()) // 定义点击区域
            .onTapGesture {
                showingDetail = true
            }
            
            // 控制按钮区域 - 完全独立
            VStack(spacing: 8) {
                Divider()
                
                HStack(spacing: 8) {
                    // 开始/停止按钮
                    Button {
                        withAnimation {
                            if product.isMonitoring {
                                productMonitor.stopMonitoring(for: product.id)
                            } else {
                                productMonitor.startMonitoring(for: product.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: product.isMonitoring ? "stop.fill" : "play.fill")
                            Text(product.isMonitoring ? "停止" : "开始")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(product.isMonitoring ? Color.red : Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 立即检查按钮
                    Button {
                        productMonitor.instantCheck(for: product.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text("立即检查")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 设置按钮
                    Button {
                        showingSettings = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gear")
                            Text("设置")
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
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
    }
    
    // 格式化时间间隔显示
    private func formatInterval(_ seconds: TimeInterval) -> String {
        let interval = Int(seconds)
        if interval < 60 {
            return "\(interval)秒"
        } else if interval < 3600 {
            return "\(interval / 60)分钟"
        } else if interval < 86400 {
            return "\(interval / 3600)小时"
        } else {
            return "\(interval / 86400)天"
        }
    }
}

// MARK: - 异步图片加载视图
struct AsyncImageView: View {
    let url: String?
    @State private var imageData: Data?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "cube.box")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let urlString = url, let imageURL = URL(string: urlString) else { return }
        
        isLoading = true
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data {
                    imageData = data
                }
            }
        }.resume()
    }
}

// MARK: - 商品设置页面
struct ProductSettingsView: View {
    let product: Product
    @ObservedObject var productMonitor: ProductMonitor
    @Environment(\.dismiss) private var dismiss
    
    @State private var monitoringInterval: Double
    @State private var autoStart: Bool
    @State private var customUserAgent: String
    @State private var maxRetries: Double
    
    // 新增：时间单位选择
    @State private var timeUnit: TimeUnit = .seconds
    @State private var timeValue: Double = 60
    
    enum TimeUnit: String, CaseIterable {
        case seconds = "秒"
        case minutes = "分钟"
        case hours = "小时"
        case days = "天"
        case weeks = "周"
        case months = "月"
        
        var maxValue: Double {
            switch self {
            case .seconds: return 60
            case .minutes: return 60
            case .hours: return 24
            case .days: return 31
            case .weeks: return 4
            case .months: return 12
            }
        }
        
        var minValue: Double {
            return 1
        }
        
        var step: Double {
            return 1
        }
        
        func toSeconds(_ value: Double) -> Double {
            switch self {
            case .seconds: return value
            case .minutes: return value * 60
            case .hours: return value * 3600
            case .days: return value * 86400
            case .weeks: return value * 604800
            case .months: return value * 2592000 // 30天
            }
        }
        
        func fromSeconds(_ seconds: Double) -> Double {
            switch self {
            case .seconds: return seconds
            case .minutes: return seconds / 60
            case .hours: return seconds / 3600
            case .days: return seconds / 86400
            case .weeks: return seconds / 604800
            case .months: return seconds / 2592000
            }
        }
    }
    
    init(product: Product, productMonitor: ProductMonitor) {
        self.product = product
        self.productMonitor = productMonitor
        self._monitoringInterval = State(initialValue: product.monitoringInterval)
        self._autoStart = State(initialValue: product.autoStart)
        self._customUserAgent = State(initialValue: product.customUserAgent ?? "")
        self._maxRetries = State(initialValue: Double(product.maxRetries))
        
        // 初始化时间单位和值
        let seconds = product.monitoringInterval
        if seconds < 60 {
            self._timeUnit = State(initialValue: .seconds)
            self._timeValue = State(initialValue: seconds)
        } else if seconds < 3600 {
            self._timeUnit = State(initialValue: .minutes)
            self._timeValue = State(initialValue: seconds / 60)
        } else if seconds < 86400 {
            self._timeUnit = State(initialValue: .hours)
            self._timeValue = State(initialValue: seconds / 3600)
        } else if seconds < 604800 {
            self._timeUnit = State(initialValue: .days)
            self._timeValue = State(initialValue: seconds / 86400)
        } else if seconds < 2592000 {
            self._timeUnit = State(initialValue: .weeks)
            self._timeValue = State(initialValue: seconds / 604800)
        } else {
            self._timeUnit = State(initialValue: .months)
            self._timeValue = State(initialValue: seconds / 2592000)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("监控设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("检查间隔")
                            .font(.headline)
                        
                        // 时间单位选择器
                        Picker("时间单位", selection: $timeUnit) {
                            ForEach(TimeUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: timeUnit) { _, newUnit in
                            // 当单位改变时，调整数值到合理范围
                            let currentSeconds = timeUnit.toSeconds(timeValue)
                            timeValue = min(max(newUnit.fromSeconds(currentSeconds), newUnit.minValue), newUnit.maxValue)
                            updateMonitoringInterval()
                        }
                        
                        // 时间数值滑块
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("数值: \(Int(timeValue)) \(timeUnit.rawValue)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("总计: \(formatTotalTime())")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(
                                value: $timeValue,
                                in: timeUnit.minValue...timeUnit.maxValue,
                                step: timeUnit.step
                            ) {
                                Text("数值")
                            }
                            .onChange(of: timeValue) { _, _ in
                                updateMonitoringInterval()
                            }
                            
                            HStack {
                                Text("\(Int(timeUnit.minValue))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(timeUnit.maxValue))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Toggle("自动开始监控", isOn: $autoStart)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最大重试次数: \(Int(maxRetries))")
                            .font(.headline)
                        Slider(value: $maxRetries, in: 1...10, step: 1) {
                            Text("重试次数")
                        }
                    }
                }
                
                Section("反爬虫设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义用户代理")
                            .font(.headline)
                        
                        TextField("留空使用随机用户代理", text: $customUserAgent, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    
                    Text("留空时将使用内置的随机用户代理池来避免检测")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("快捷设置") {
                    Button("快速设置（1分钟）") {
                        setQuickInterval(.minutes, value: 1)
                    }
                    
                    Button("保守设置（5分钟）") {
                        setQuickInterval(.minutes, value: 5)
                    }
                    
                    Button("积极设置（30秒）") {
                        setQuickInterval(.seconds, value: 30)
                    }
                    
                    Button("每小时检查") {
                        setQuickInterval(.hours, value: 1)
                    }
                    
                    Button("每天检查") {
                        setQuickInterval(.days, value: 1)
                    }
                }
            }
            .navigationTitle("监控设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
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
                        if let index = productMonitor.products.firstIndex(where: { $0.id == product.id }) {
                            productMonitor.products[index].maxRetries = Int(maxRetries)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateMonitoringInterval() {
        monitoringInterval = timeUnit.toSeconds(timeValue)
    }
    
    private func formatTotalTime() -> String {
        let seconds = Int(monitoringInterval)
        if seconds < 60 {
            return "\(seconds)秒"
        } else if seconds < 3600 {
            return "\(seconds / 60)分钟"
        } else if seconds < 86400 {
            return "\(seconds / 3600)小时"
        } else {
            return "\(seconds / 86400)天"
        }
    }
    
    private func setQuickInterval(_ unit: TimeUnit, value: Double) {
        timeUnit = unit
        timeValue = value
        updateMonitoringInterval()
        autoStart = true
        maxRetries = 3
        customUserAgent = ""
    }
}

// MARK: - 其他视图组件
struct EmptyProductsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.box")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("还没有监控的商品")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("点击右上角的 + 号添加要监控的商品")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct StatusBadge: View {
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isAvailable ? "有库存" : "缺货")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - 简化的日志页面
struct LogsView: View {
    @ObservedObject var productMonitor: ProductMonitor
    @State private var selectedLogType: LogStatus? = nil
    @State private var selectedProductId: UUID? = nil
    
    var filteredLogs: [MonitorLog] {
        var logs = productMonitor.monitorLogs
        
        if let logType = selectedLogType {
            logs = logs.filter { $0.status == logType }
        }
        
        if let productId = selectedProductId {
            logs = logs.filter { $0.productId == productId }
        }
        
        return logs
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if productMonitor.monitorLogs.isEmpty {
                    EmptyLogsView()
                } else {
                    List {
                        // 过滤器
                        Section("筛选") {
                            FilterRow(
                                title: "日志类型",
                                selection: $selectedLogType,
                                options: LogStatus.allCases,
                                displayName: { $0?.rawValue ?? "全部" }
                            )
                            
                            FilterRow(
                                title: "商品",
                                selection: $selectedProductId,
                                options: [nil] + productMonitor.products.map { $0.id },
                                displayName: { id in
                                    if let id = id {
                                        return productMonitor.products.first(where: { $0.id == id })?.name ?? "未知商品"
                                    } else {
                                        return "全部商品"
                                    }
                                }
                            )
                        }
                        
                        // 日志列表
                        Section("监控日志 (\(filteredLogs.count))") {
                            ForEach(filteredLogs) { log in
                                LogRowView(log: log)
                            }
                        }
                    }
                }
            }
            .navigationTitle("监控日志")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("清空所有日志") {
                            productMonitor.clearLogs()
                        }
                        
                        if let productId = selectedProductId {
                            Button("清空当前商品日志") {
                                productMonitor.clearLogsForProduct(productId)
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
}

// MARK: - 简化的设置页面
struct AppSettingsView: View {
    @ObservedObject var emailService: EmailService
    @ObservedObject var productMonitor: ProductMonitor
    @ObservedObject var hermesService: HermesService
    
    var body: some View {
        NavigationView {
            Form {
                Section("邮件通知") {
                    Toggle("启用邮件通知", isOn: $emailService.emailSettings.isEnabled)
                    
                    TextField("收件邮箱", text: $emailService.emailSettings.recipientEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                }
                
                Section("监控统计") {
                    HStack {
                        Text("监控商品数量")
                        Spacer()
                        Text("\(productMonitor.products.count)")
                    }
                    
                    HStack {
                        Text("总日志条数")
                        Spacer()
                        Text("\(productMonitor.monitorLogs.count)")
                    }
                    
                    HStack {
                        Text("当前状态")
                        Spacer()
                        Text(productMonitor.isAnyMonitoring ? "监控中" : "已停止")
                            .foregroundColor(productMonitor.isAnyMonitoring ? .green : .gray)
                    }
                }
                
                Section("Hermes表格") {
                    HStack {
                        Text("表格状态")
                        Spacer()
                        Text(hermesService.formData.isEnabled ? "已启用" : "已禁用")
                            .foregroundColor(hermesService.formData.isEnabled ? .green : .gray)
                    }
                    
                    HStack {
                        Text("提交次数")
                        Spacer()
                        Text("\(hermesService.formData.submitCount)")
                    }
                    
                    HStack {
                        Text("最后提交")
                        Spacer()
                        if let lastSubmitted = hermesService.formData.lastSubmitted {
                            Text(DateFormatter.localizedString(from: lastSubmitted, dateStyle: .short, timeStyle: .short))
                        } else {
                            Text("从未提交")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("应用信息") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("3.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("开发者")
                        Spacer()
                        Text("Guanchenuous")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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