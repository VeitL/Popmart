import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var monitor: ProductMonitor
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("全局操作")) {
                    Button(action: {
                        monitor.startAllMonitoring()
                    }) {
                        Label("开始所有监控", systemImage: "play.fill")
                    }
                    .foregroundColor(.green)
                    
                    Button(action: {
                        monitor.stopAllMonitoring()
                    }) {
                        Label("停止所有监控", systemImage: "stop.fill")
                    }
                    .foregroundColor(.red)
                    
                    Button(action: {
                        monitor.instantCheckAll()
                    }) {
                        Label("立即检查所有商品", systemImage: "arrow.clockwise")
                    }
                    .foregroundColor(.blue)
                }
                
                Section(header: Text("日志管理")) {
                    Button(action: {
                        monitor.clearLogs()
                    }) {
                        Label("清除所有日志", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("关于"), footer: Text("版本 1.0.0")) {
                    LabeledContent("开发者", value: "Guanchenuous")
                    Link("访问Popmart德国官网",
                         destination: URL(string: "https://www.popmart.com/de")!)
                }
            }
            .navigationTitle("设置")
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

#Preview {
    SettingsView(monitor: ProductMonitor())
} 