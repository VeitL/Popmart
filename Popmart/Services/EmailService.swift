//
//  EmailService.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import Foundation
import MessageUI
import SwiftUI
import UserNotifications

class EmailService: NSObject, ObservableObject {
    @Published var isEmailComposerPresented = false
    @Published var emailSettings = EmailSettings()
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(productAvailable(_:)),
            name: NSNotification.Name("ProductAvailable"),
            object: nil
        )
    }
    
    @objc private func productAvailable(_ notification: Notification) {
        guard let product = notification.object as? Product else { return }
        sendEmailNotification(for: product)
    }
    
    func sendEmailNotification(for product: Product) {
        // 如果用户设置了邮件，尝试发送
        if emailSettings.isEnabled && !emailSettings.recipientEmail.isEmpty {
            // 由于iOS限制，我们需要通过用户确认来发送邮件
            DispatchQueue.main.async {
                self.isEmailComposerPresented = true
            }
        }
        
        // 发送本地通知
        sendLocalNotification(for: product)
    }
    
    private func sendLocalNotification(for product: Product) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 商品上架通知"
        content.body = "\(product.name) 现在有库存了！快去抢购吧！"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "product-available-\(product.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("发送通知失败: \(error)")
            } else {
                print("本地通知已发送")
            }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("通知权限已授予")
                } else {
                    print("通知权限被拒绝")
                }
                
                if let error = error {
                    print("请求通知权限错误: \(error)")
                }
            }
        }
    }
}

struct EmailSettings: Codable {
    var isEnabled: Bool = true
    var recipientEmail: String = ""
    var smtpServer: String = ""
    var smtpPort: Int = 587
    var username: String = ""
    var password: String = ""
} 