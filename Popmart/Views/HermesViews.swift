//
//  HermesViews.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import SwiftUI

// MARK: - Hermes表格视图
struct HermesFormView: View {
    @ObservedObject var hermesService: HermesService
    @State private var showingLogs = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            List {
                // 表格状态卡片
                Section {
                    HermesStatusCard(hermesService: hermesService)
                }
                
                // 表格信息填写
                Section("个人信息") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("姓", text: $hermesService.formData.lastName)
                                    .textContentType(.familyName)
                                
                                TextField("名", text: $hermesService.formData.firstName)
                                    .textContentType(.givenName)
                                
                                TextField("邮箱", text: $hermesService.formData.email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                
                                TextField("电话", text: $hermesService.formData.phone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                                
                                TextField("护照号码", text: $hermesService.formData.passport)
                                    .textContentType(.creditCardNumber)
                            }
                        }
                    }
                }
                
                // 选择器
                Section("门店和国家") {
                    Picker("首选门店", selection: $hermesService.formData.preferredStore) {
                        ForEach(hermesService.availableStores, id: \.self) { store in
                            Text(store).tag(store)
                        }
                    }
                    
                    Picker("国家", selection: $hermesService.formData.country) {
                        ForEach(hermesService.availableCountries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    }
                }
                
                // 同意条款
                Section("用户协议") {
                    Toggle("同意条款和条件", isOn: $hermesService.formData.acceptTerms)
                    Toggle("同意数据处理", isOn: $hermesService.formData.consentDataProcessing)
                }
                
                // 提交设置
                Section("提交设置") {
                    Toggle("启用自动提交", isOn: $hermesService.formData.isEnabled)
                    
                    if hermesService.formData.isEnabled {
                        HStack {
                            Text("提交频率")
                            Spacer()
                            Text("每\(hermesService.submitInterval)分钟")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // 手动提交按钮
                Section {
                    Button(action: {
                        hermesService.submitForm()
                    }) {
                        HStack {
                            Spacer()
                            if hermesService.isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("提交中...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("立即提交")
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(hermesService.canSubmit ? Color.blue : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!hermesService.canSubmit || hermesService.isSubmitting)
                }
            }
            .navigationTitle("Hermes表格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingLogs = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingLogs) {
                HermesLogsView(hermesService: hermesService)
            }
            .sheet(isPresented: $showingSettings) {
                HermesSettingsView(hermesService: hermesService)
            }
        }
    }
}

// MARK: - Hermes状态卡片
struct HermesStatusCard: View {
    @ObservedObject var hermesService: HermesService
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hermes表格状态")
                        .font(.headline)
                    
                    Text(hermesService.formData.isEnabled ? 
                         "自动提交已启用" : 
                         "自动提交已禁用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(hermesService.formData.isEnabled ? "运行中" : "已停止")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hermesService.formData.isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .foregroundColor(hermesService.formData.isEnabled ? .green : .gray)
                    .cornerRadius(8)
            }
            
            // 统计信息
            HStack(spacing: 20) {
                VStack {
                    Text("\(hermesService.formData.submitCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("提交次数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text(hermesService.successfulSubmissions > 0 ? 
                         String(format: "%.1f%%", Double(hermesService.successfulSubmissions) / Double(hermesService.formData.submitCount) * 100) : 
                         "0%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("成功率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    if let lastSubmitted = hermesService.formData.lastSubmitted {
                        Text(DateFormatter.localizedString(from: lastSubmitted, dateStyle: .none, timeStyle: .medium))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else {
                        Text("—")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                    }
                    Text("最后提交")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Hermes日志视图
struct HermesLogsView: View {
    @ObservedObject var hermesService: HermesService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: HermesSubmissionStatus?
    
    var filteredLogs: [HermesSubmissionLog] {
        if let selectedStatus = selectedStatus {
            return hermesService.submissionLogs.filter { $0.status == selectedStatus }
        }
        return hermesService.submissionLogs
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if hermesService.submissionLogs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("还没有提交日志")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("提交表格后，这里会显示详细的记录")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // 过滤器
                        Section {
                            HStack {
                                Text("状态过滤")
                                Spacer()
                                Menu {
                                    Button("全部") {
                                        selectedStatus = nil
                                    }
                                    ForEach(HermesSubmissionStatus.allCases, id: \.self) { status in
                                        Button(status.rawValue) {
                                            selectedStatus = status
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedStatus?.rawValue ?? "全部")
                                            .foregroundColor(.blue)
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        
                        // 日志列表
                        Section("提交记录") {
                            ForEach(filteredLogs.sorted(by: { $0.timestamp > $1.timestamp })) { log in
                                HermesLogRowView(log: log)
                            }
                        }
                    }
                }
            }
            .navigationTitle("提交日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                if !hermesService.submissionLogs.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("清空") {
                            hermesService.clearLogs()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

// MARK: - Hermes设置视图
struct HermesSettingsView: View {
    @ObservedObject var hermesService: HermesService
    @Environment(\.dismiss) private var dismiss
    @State private var tempSubmitInterval: Double
    
    init(hermesService: HermesService) {
        self.hermesService = hermesService
        self._tempSubmitInterval = State(initialValue: Double(hermesService.submitInterval))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("提交频率") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("提交间隔: \(Int(tempSubmitInterval)) 分钟")
                            .font(.headline)
                        
                        Slider(value: $tempSubmitInterval, in: 1...60, step: 1) {
                            Text("间隔")
                        }
                        
                        HStack {
                            Text("1分钟")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("60分钟")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("快捷设置") {
                    Button("积极模式（1分钟）") {
                        tempSubmitInterval = 1
                    }
                    
                    Button("保守模式（15分钟）") {
                        tempSubmitInterval = 15
                    }
                    
                    Button("每半小时") {
                        tempSubmitInterval = 30
                    }
                    
                    Button("每小时") {
                        tempSubmitInterval = 60
                    }
                }
                
                Section("高级设置") {
                    Toggle("自动重试失败的提交", isOn: .constant(true))
                        .disabled(true)
                    
                    Toggle("智能频率调整", isOn: .constant(false))
                        .disabled(true)
                }
            }
            .navigationTitle("Hermes设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        hermesService.submitInterval = Int(tempSubmitInterval)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Hermes日志行视图
struct HermesLogRowView: View {
    let log: HermesSubmissionLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: log.status.icon)
                    .foregroundColor(colorForStatus(log.status.color))
                
                Text(log.status.rawValue)
                    .font(.headline)
                    .foregroundColor(colorForStatus(log.status.color))
                
                Spacer()
                
                Text(DateFormatter.localizedString(from: log.timestamp, dateStyle: .none, timeStyle: .medium))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(log.message)
                .font(.body)
                .foregroundColor(.primary)
            
            if let responseTime = log.responseTime {
                Text("响应时间: \(String(format: "%.2f", responseTime))秒")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func colorForStatus(_ colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .primary
        }
    }
} 