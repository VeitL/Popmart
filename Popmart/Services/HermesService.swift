//
//  HermesService.swift
//  Popmart
//
//  Created by Guanchenuous on 29.05.25.
//

import Foundation
import Combine
import WebKit
import UIKit

class HermesService: NSObject, ObservableObject {
    @Published var formData = HermesFormData()
    @Published var submissionLogs: [HermesSubmissionLog] = []
    @Published var isSubmitting = false
    @Published var isDailySubmissionEnabled = false
    @Published var lastSubmissionDate: Date?
    @Published var lastScreenshot: UIImage?
    @Published var showingScreenshot = false
    @Published var submitInterval: Int = 15 // 默认15分钟
    
    // 计算属性
    var successfulSubmissions: Int {
        return submissionLogs.filter { $0.status == .success }.count
    }
    
    var canSubmit: Bool {
        return validateFormData() && !isSubmitting
    }
    
    // 可用门店列表
    let availableStores = ["全部", "巴黎香榭丽舍大街", "巴黎圣日耳曼", "巴黎玛黑区", "巴黎蒙田大道"]
    
    // 可用国家列表
    let availableCountries = ["France", "Germany", "Italy", "Spain", "United Kingdom", "China", "Japan", "United States"]
    
    private var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()
    private var submissionTimer: Timer?
    private var timeoutTimer: Timer?
    
    private let hermesURL = "https://rendezvousparis.hermes.com/client/register"
    private let requestTimeout: TimeInterval = 60
    
    override init() {
        super.init()
        loadFormData()
        loadSubmissionLogs()
        setupDailySubmission()
        setupWebView()
    }
    
    deinit {
        submissionTimer?.invalidate()
        timeoutTimer?.invalidate()
    }
    
    // MARK: - WebView Setup
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        
        // 设置更好的用户代理
        config.applicationNameForUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        
        // 添加JavaScript消息处理
        config.userContentController.add(self, name: "submissionResult")
        config.userContentController.add(self, name: "pageReady")
        
        // 创建一个较大的WebView以确保截图质量
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 414, height: 896), configuration: config)
        webView?.navigationDelegate = self
        
        // 确保WebView可见（这对截图很重要）
        webView?.isHidden = false
        webView?.alpha = 1.0
        
        // 添加到一个隐藏的容器中（这样可以截图但不显示给用户）
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            webView?.frame = CGRect(x: -500, y: -500, width: 414, height: 896) // 移到屏幕外
            window.addSubview(webView!)
        }
    }
    
    // MARK: - 截图功能
    func takeScreenshot() -> UIImage? {
        guard let webView = webView else { 
            print("📸 [截图] WebView不存在")
            return nil 
        }
        
        print("📸 [截图] 开始截图，WebView大小: \(webView.bounds)")
        
        // 确保在主线程执行
        var screenshot: UIImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.main.async {
            // 使用WKWebView的内置截图方法
            webView.takeSnapshot(with: nil) { image, error in
                if let error = error {
                    print("📸 [截图] 截图失败: \(error.localizedDescription)")
                } else if let image = image {
                    print("📸 [截图] 截图成功，图片大小: \(image.size)")
                    screenshot = image
                } else {
                    print("📸 [截图] 截图返回nil")
                }
                semaphore.signal()
            }
        }
        
        // 等待截图完成（最多3秒）
        _ = semaphore.wait(timeout: .now() + 3)
        return screenshot
    }
    
    private func captureAndShowScreenshot() {
        print("📸 [截图] 准备截图...")
        
        // 等待一下让页面稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let screenshot = self.takeScreenshot() {
                self.lastScreenshot = screenshot
                self.showingScreenshot = true
                
                self.addSubmissionLog(
                    status: .success,
                    message: "表格已填写完成，已生成截图供确认",
                    responseTime: nil
                )
            } else {
                // 如果截图失败，仍然显示确认对话框，但没有图片
                self.lastScreenshot = nil
                self.showingScreenshot = true
                
                self.addSubmissionLog(
                    status: .success,
                    message: "表格已填写完成，但截图生成失败",
                    responseTime: nil
                )
            }
        }
    }
    
    // 用户确认截图后继续提交
    func confirmAndSubmit() {
        showingScreenshot = false
        finalizeSubmission()
    }
    
    // 用户取消提交
    func cancelSubmission() {
        showingScreenshot = false
        isSubmitting = false
        addSubmissionLog(status: .failed, message: "用户取消提交")
    }
    
    // MARK: - 表格数据管理
    func updateFormData(_ newData: HermesFormData) {
        formData = newData
        saveFormData()
    }
    
    func validateFormData() -> Bool {
        return !formData.lastName.isEmpty &&
               !formData.firstName.isEmpty &&
               !formData.email.isEmpty &&
               formData.email.contains("@") &&
               !formData.phone.isEmpty &&
               !formData.passport.isEmpty &&
               formData.acceptTerms &&
               formData.consentDataProcessing
    }
    
    // MARK: - 手动提交
    func submitForm() {
        guard validateFormData() else {
            addSubmissionLog(status: .formError, message: "表格数据不完整，请检查所有必填字段")
            return
        }
        
        isSubmitting = true
        performFormSubmission()
    }
    
    // MARK: - 每日自动提交
    func enableDailySubmission(_ enabled: Bool) {
        isDailySubmissionEnabled = enabled
        if enabled {
            setupDailySubmission()
        } else {
            submissionTimer?.invalidate()
            submissionTimer = nil
        }
        UserDefaults.standard.set(enabled, forKey: "HermesDailySubmissionEnabled")
    }
    
    private func setupDailySubmission() {
        guard isDailySubmissionEnabled else { return }
        
        submissionTimer?.invalidate()
        
        submissionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            self.checkDailySubmission()
        }
        
        checkDailySubmission()
    }
    
    private func checkDailySubmission() {
        let calendar = Calendar.current
        let now = Date()
        
        if let lastSubmission = lastSubmissionDate,
           calendar.isDate(lastSubmission, inSameDayAs: now) {
            return
        }
        
        let components = calendar.dateComponents([.hour], from: now)
        if components.hour == 10 && formData.isEnabled {
            submitForm()
        }
    }
    
    // MARK: - 表格提交逻辑
    private func performFormSubmission() {
        guard let webView = webView else {
            addSubmissionLog(status: .failed, message: "WebView未初始化")
            isSubmitting = false
            return
        }
        
        let startTime = Date()
        
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: requestTimeout, repeats: false) { _ in
            if self.isSubmitting {
                self.addSubmissionLog(
                    status: .networkError,
                    message: "网络请求超时(\(self.requestTimeout)秒)，请检查网络连接或稍后重试",
                    responseTime: Date().timeIntervalSince(startTime)
                )
                self.isSubmitting = false
            }
        }
        
        guard let url = URL(string: hermesURL) else {
            addSubmissionLog(status: .failed, message: "无效的URL地址")
            isSubmitting = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.timeoutInterval = requestTimeout
        
        addSubmissionLog(status: .success, message: "开始加载Hermes注册页面...")
        webView.load(request)
    }
    
    private func fillAndSubmitForm() {
        guard let webView = webView else { return }
        
        addSubmissionLog(status: .success, message: "页面加载完成，开始填写表格...")
        
        let jsCode = """
        (function() {
            try {
                window.webkit.messageHandlers.pageReady.postMessage({
                    status: 'ready',
                    message: '页面已准备就绪'
                });
                
                var attempts = 0;
                var maxAttempts = 15;
                
                function findElementByMultipleSelectors(selectors) {
                    for (var i = 0; i < selectors.length; i++) {
                        var element = document.querySelector(selectors[i]);
                        if (element) return element;
                    }
                    return null;
                }
                
                function fillForm() {
                    attempts++;
                    console.log('尝试填写表格，第 ' + attempts + ' 次');
                    
                    var lastNameField = findElementByMultipleSelectors([
                        'input[name*="lastname"]', 'input[id*="lastname"]', 'input[name*="nom"]',
                        'input[placeholder*="姓氏"]', 'input[placeholder*="Last"]', 'input[placeholder*="Nom"]'
                    ]);
                    
                    var firstNameField = findElementByMultipleSelectors([
                        'input[name*="firstname"]', 'input[id*="firstname"]', 'input[name*="prenom"]',
                        'input[placeholder*="名字"]', 'input[placeholder*="First"]', 'input[placeholder*="Prénom"]'
                    ]);
                    
                    var emailField = findElementByMultipleSelectors([
                        'input[name*="email"]', 'input[id*="email"]', 'input[type="email"]'
                    ]);
                    
                    var phoneField = findElementByMultipleSelectors([
                        'input[name*="phone"]', 'input[id*="phone"]', 'input[type="tel"]',
                        'input[name*="telephone"]', 'input[placeholder*="电话"]'
                    ]);
                    
                    var passportField = findElementByMultipleSelectors([
                        'input[name*="passport"]', 'input[id*="passport"]', 'input[name*="document"]',
                        'input[placeholder*="passport"]', 'input[placeholder*="护照"]'
                    ]);
                    
                    var countryField = findElementByMultipleSelectors([
                        'select[name*="country"]', 'select[id*="country"]', 'select[name*="pays"]'
                    ]);
                    
                    var storeField = findElementByMultipleSelectors([
                        'select[name*="store"]', 'select[id*="store"]', 'select[name*="boutique"]',
                        'select[name*="location"]', 'select[name*="magasin"]'
                    ]);
                    
                    var termsCheckbox = findElementByMultipleSelectors([
                        'input[name*="terms"]', 'input[id*="terms"]', 'input[name*="conditions"]',
                        'input[type="checkbox"][name*="accept"]', 'input[type="checkbox"][id*="accept"]'
                    ]);
                    
                    var dataCheckbox = findElementByMultipleSelectors([
                        'input[name*="data"]', 'input[id*="data"]', 'input[name*="donnees"]',
                        'input[type="checkbox"][name*="consent"]', 'input[type="checkbox"][id*="consent"]',
                        'input[type="checkbox"][name*="processing"]'
                    ]);
                    
                    if (!lastNameField || !firstNameField || !emailField) {
                        if (attempts < maxAttempts) {
                            console.log('关键字段未找到，2秒后重试...');
                            setTimeout(fillForm, 2000);
                            return;
                        } else {
                            window.webkit.messageHandlers.submissionResult.postMessage({
                                status: 'error',
                                message: '无法找到表格字段，可能页面结构已改变'
                            });
                            return;
                        }
                    }
                    
                    console.log('找到表格字段，开始填写...');
                    
                    if (lastNameField) {
                        lastNameField.value = '\(formData.lastName)';
                        lastNameField.dispatchEvent(new Event('input', { bubbles: true }));
                        lastNameField.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (firstNameField) {
                        firstNameField.value = '\(formData.firstName)';
                        firstNameField.dispatchEvent(new Event('input', { bubbles: true }));
                        firstNameField.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (emailField) {
                        emailField.value = '\(formData.email)';
                        emailField.dispatchEvent(new Event('input', { bubbles: true }));
                        emailField.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (phoneField) {
                        phoneField.value = '\(formData.phone)';
                        phoneField.dispatchEvent(new Event('input', { bubbles: true }));
                        phoneField.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (passportField) {
                        passportField.value = '\(formData.passport)';
                        passportField.dispatchEvent(new Event('input', { bubbles: true }));
                        passportField.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (countryField) {
                        for (var i = 0; i < countryField.options.length; i++) {
                            var option = countryField.options[i];
                            if (option.text.includes('Germany') || option.text.includes('德国') || 
                                option.text.includes('Allemagne') || option.value.includes('DE')) {
                                countryField.selectedIndex = i;
                                countryField.dispatchEvent(new Event('change', { bubbles: true }));
                                break;
                            }
                        }
                    }
                    
                    if (storeField) {
                        if ('\(formData.preferredStore)' === '全部') {
                            for (var i = 0; i < storeField.options.length; i++) {
                                var option = storeField.options[i];
                                if (option.text.includes('All') || option.text.includes('全部') || 
                                    option.text.includes('Tous') || option.value === '' || i === 0) {
                                    storeField.selectedIndex = i;
                                    storeField.dispatchEvent(new Event('change', { bubbles: true }));
                                    break;
                                }
                            }
                        } else {
                            for (var i = 0; i < storeField.options.length; i++) {
                                var option = storeField.options[i];
                                if (option.text.includes('\(formData.preferredStore)')) {
                                    storeField.selectedIndex = i;
                                    storeField.dispatchEvent(new Event('change', { bubbles: true }));
                                    break;
                                }
                            }
                        }
                    }
                    
                    if (termsCheckbox && \(formData.acceptTerms)) {
                        termsCheckbox.checked = true;
                        termsCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    if (dataCheckbox && \(formData.consentDataProcessing)) {
                        dataCheckbox.checked = true;
                        dataCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    
                    console.log('表格填写完成');
                    
                    setTimeout(function() {
                        window.webkit.messageHandlers.submissionResult.postMessage({
                            status: 'filled',
                            message: '表格填写完成，等待用户确认'
                        });
                    }, 1000);
                }
                
                fillForm();
                
            } catch (error) {
                console.error('填表脚本错误:', error);
                window.webkit.messageHandlers.submissionResult.postMessage({
                    status: 'error',
                    message: '脚本执行错误: ' + error.message
                });
            }
        })();
        """
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                self.addSubmissionLog(
                    status: .failed,
                    message: "JavaScript执行失败: \(error.localizedDescription)"
                )
                self.isSubmitting = false
            }
        }
    }
    
    private func finalizeSubmission() {
        guard let webView = webView else { return }
        
        let submitJS = """
        (function() {
            try {
                var submitButton = document.querySelector('button[type="submit"], input[type="submit"]') ||
                                 document.querySelector('button[class*="validation"], button[id*="validation"]') ||
                                 document.querySelector('button[class*="submit"], button[id*="submit"]') ||
                                 document.querySelector('button:contains("validation"), button:contains("Validation")') ||
                                 document.querySelector('button:contains("Submit"), button:contains("提交")');
                
                if (!submitButton) {
                    var buttons = document.querySelectorAll('button');
                    for (var i = 0; i < buttons.length; i++) {
                        var button = buttons[i];
                        var text = button.textContent.toLowerCase();
                        if (text.includes('validation') || text.includes('submit') || 
                            text.includes('confirmer') || text.includes('envoyer')) {
                            submitButton = button;
                            break;
                        }
                    }
                }
                
                if (submitButton) {
                    console.log('找到提交按钮，点击提交...');
                    submitButton.click();
                    
                    setTimeout(function() {
                        window.webkit.messageHandlers.submissionResult.postMessage({
                            status: 'submitted',
                            message: '表格已提交'
                        });
                    }, 2000);
                } else {
                    window.webkit.messageHandlers.submissionResult.postMessage({
                        status: 'error',
                        message: '未找到提交按钮，请手动确认提交'
                    });
                }
            } catch (error) {
                window.webkit.messageHandlers.submissionResult.postMessage({
                    status: 'error',
                    message: '提交过程中发生错误: ' + error.message
                });
            }
        })();
        """
        
        webView.evaluateJavaScript(submitJS) { result, error in
            if let error = error {
                self.addSubmissionLog(
                    status: .failed,
                    message: "提交失败: \(error.localizedDescription)"
                )
            }
            self.isSubmitting = false
        }
    }
    
    // MARK: - 日志管理
    func clearLogs() {
        submissionLogs.removeAll()
        saveSubmissionLogs()
    }
    
    func addSubmissionLog(status: HermesSubmissionStatus, message: String, responseTime: TimeInterval? = nil) {
        let log = HermesSubmissionLog(status: status, message: message, responseTime: responseTime)
        submissionLogs.insert(log, at: 0)
        
        // 限制日志数量
        if submissionLogs.count > 100 {
            submissionLogs = Array(submissionLogs.prefix(100))
        }
        
        if status == .success {
            lastSubmissionDate = Date()
            formData.submitCount += 1
            formData.lastSubmitted = Date()
            saveFormData()
        }
        
        saveSubmissionLogs()
        print("📧 [Hermes提交] \(status.rawValue): \(message)")
    }
    
    // MARK: - 数据持久化
    private func saveFormData() {
        if let data = try? JSONEncoder().encode(formData) {
            UserDefaults.standard.set(data, forKey: "HermesFormData")
        }
    }
    
    private func loadFormData() {
        if let data = UserDefaults.standard.data(forKey: "HermesFormData"),
           let savedData = try? JSONDecoder().decode(HermesFormData.self, from: data) {
            formData = savedData
        }
        
        isDailySubmissionEnabled = UserDefaults.standard.bool(forKey: "HermesDailySubmissionEnabled")
    }
    
    private func loadSubmissionLogs() {
        if let data = UserDefaults.standard.data(forKey: "HermesSubmissionLogs"),
           let savedLogs = try? JSONDecoder().decode([HermesSubmissionLog].self, from: data) {
            submissionLogs = savedLogs
        }
    }
    
    private func saveSubmissionLogs() {
        if let data = try? JSONEncoder().encode(submissionLogs) {
            UserDefaults.standard.set(data, forKey: "HermesSubmissionLogs")
        }
    }
    
    // MARK: - 设置管理
    func resetSettings() {
        formData = HermesFormData()
        submitInterval = 15
        clearLogs()
        saveFormData()
    }
}

// MARK: - WKNavigationDelegate
extension HermesService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.fillAndSubmitForm()
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        addSubmissionLog(status: .networkError, message: "页面加载失败: \(error.localizedDescription)")
        isSubmitting = false
    }
}

// MARK: - WKScriptMessageHandler
extension HermesService: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let result = message.body as? [String: String],
              let status = result["status"],
              let msg = result["message"] else { return }
        
        switch message.name {
        case "pageReady":
            addSubmissionLog(status: .success, message: msg)
            
        case "submissionResult":
            switch status {
            case "filled":
                // 表格填写完成，截图并等待用户确认
                addSubmissionLog(status: .success, message: msg)
                captureAndShowScreenshot()
                
            case "submitted":
                // 表格已提交
                let submissionStatus: HermesSubmissionStatus = .success
                addSubmissionLog(status: submissionStatus, message: msg)
                isSubmitting = false
                
            case "success":
                let submissionStatus: HermesSubmissionStatus = .success
                addSubmissionLog(status: submissionStatus, message: msg)
                isSubmitting = false
                
            case "error":
                let submissionStatus: HermesSubmissionStatus = .failed
                addSubmissionLog(status: submissionStatus, message: msg)
                isSubmitting = false
                
            default:
                addSubmissionLog(status: .failed, message: "未知状态: \(status) - \(msg)")
                isSubmitting = false
            }
            
        default:
            break
        }
    }
} 