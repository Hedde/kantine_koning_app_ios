import Foundation
import os.log

/// Centralized logging system that respects debug/release build configurations
/// Provides structured debug output with visual separation for development
enum Logger {
    
    // MARK: - Log Levels
    enum Level: String, CaseIterable {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARNING"
        case error = "❌ ERROR"
        case success = "✅ SUCCESS"
        case network = "📡 NETWORK"
        case email = "📧 EMAIL"
        case volunteer = "👥 VOLUNTEER"
        case auth = "🔐 AUTH"
        case push = "🔔 PUSH"
        case leaderboard = "🏆 LEADERBOARD"
        case qr = "📱 QR"
        case enrollment = "📝 ENROLLMENT"
        case view = "🖼️ VIEW"
        case interaction = "👆 INTERACTION"
        case bootstrap = "🚀 BOOTSTRAP"
        case performance = "⚡ PERFORMANCE"
    }
    
    // MARK: - Configuration
    

    
    private static var isDebugEnabled: Bool {
        #if DEBUG
        return true
        #elseif ENABLE_LOGGING
        // Build flag for release builds with logging enabled
        return true
        #else
        return false
        #endif
    }
    
    private static var isProductionLoggingEnabled: Bool {
        #if DEBUG
        return true
        #elseif ENABLE_LOGGING
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Logging Methods
    
    /// Log a debug message (only in debug builds)
    static func debug(_ message: String, category: String = "App") {
        log(level: .debug, message: message, category: category, debugOnly: true)
    }
    
    /// Log an info message
    static func info(_ message: String, category: String = "App") {
        log(level: .info, message: message, category: category, debugOnly: false)
    }
    
    /// Log a warning message
    static func warning(_ message: String, category: String = "App") {
        log(level: .warning, message: message, category: category, debugOnly: false)
    }
    
    /// Log an error message (always logged)
    static func error(_ message: String, category: String = "App") {
        log(level: .error, message: message, category: category, debugOnly: false)
    }
    
    /// Log a success message (debug only)
    static func success(_ message: String, category: String = "App") {
        log(level: .success, message: message, category: category, debugOnly: true)
    }
    
    /// Log a network operation (debug only)
    static func network(_ message: String) {
        log(level: .network, message: message, category: "Network", debugOnly: true)
    }
    
    /// Log email operations (debug only)
    static func email(_ message: String) {
        log(level: .email, message: message, category: "Email", debugOnly: true)
    }
    
    /// Log volunteer operations (debug only)
    static func volunteer(_ message: String) {
        log(level: .volunteer, message: message, category: "Volunteer", debugOnly: true)
    }
    
    /// Log authentication operations (debug only)
    static func auth(_ message: String) {
        log(level: .auth, message: message, category: "Auth", debugOnly: true)
    }
    
    /// Log push notification operations (debug only)
    static func push(_ message: String) {
        log(level: .push, message: message, category: "Push", debugOnly: true)
    }
    
    /// Log leaderboard operations (debug only)
    static func leaderboard(_ message: String) {
        log(level: .leaderboard, message: message, category: "Leaderboard", debugOnly: true)
    }
    
    /// Log QR scanning operations (debug only)
    static func qr(_ message: String) {
        log(level: .qr, message: message, category: "QR", debugOnly: true)
    }
    
    /// Log enrollment operations (debug only)
    static func enrollment(_ message: String) {
        log(level: .enrollment, message: message, category: "Enrollment", debugOnly: true)
    }
    
    /// Log reconciliation operations (debug only, verbose)
    /// Used for detailed sync/reconciliation logging that should not appear in production
    static func reconcile(_ message: String) {
        #if DEBUG
        log(level: .info, message: message, category: "Reconcile", debugOnly: true)
        #endif
    }
    
    /// Log view lifecycle and UI operations (debug only)
    static func view(_ message: String) {
        log(level: .view, message: message, category: "View", debugOnly: true)
    }
    
    /// Log user interactions (debug only)
    static func interaction(_ message: String) {
        log(level: .interaction, message: message, category: "Interaction", debugOnly: true)
    }
    
    /// Log app bootstrap and initialization (debug only)
    static func bootstrap(_ message: String) {
        log(level: .bootstrap, message: message, category: "Bootstrap", debugOnly: true)
    }
    
    /// Log performance metrics (debug only)
    static func performance(_ message: String) {
        log(level: .performance, message: message, category: "Performance", debugOnly: true)
    }
    
    // MARK: - Core Logging Implementation
    
    private static func log(level: Level, message: String, category: String, debugOnly: Bool) {
        // Skip debug-only messages in production unless production logging is enabled
        if debugOnly && !isDebugEnabled && !isProductionLoggingEnabled {
            return
        }
        
        // Skip all logging in production unless it's an error or production logging is enabled
        if !isDebugEnabled && !isProductionLoggingEnabled && level != .error {
            return
        }
        
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(category)] \(level.rawValue) \(message)"
        
        #if DEBUG
        // In debug builds, use print for immediate console output
        print(logMessage)
        #else
        // In production builds, use os_log for system logging (if enabled)
        if isProductionLoggingEnabled || level == .error {
            let osLog = OSLog(subsystem: "com.kantinekoning.app", category: category)
            let osLogType: OSLogType = {
                switch level {
                case .error: return .error
                case .warning: return .default
                case .info: return .info
                default: return .debug
                }
            }()
            os_log("%{public}@", log: osLog, type: osLogType, logMessage)
        }
        #endif
    }
}

// MARK: - Helper Extensions

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Legacy Support (for gradual migration)

/// Legacy logging functions for backward compatibility
/// These will be deprecated once migration is complete
extension Logger {
    
    /// Legacy print replacement - will be removed after migration
    @available(*, deprecated, message: "Use Logger.debug() instead")
    static func legacyPrint(_ message: String) {
        debug(message)
    }
}

// MARK: - Build Information

extension Logger {
    /// Check if logging is currently enabled
    static var isLoggingEnabled: Bool {
        return isDebugEnabled
    }
    
    /// Get current build configuration info
    static var buildInfo: String {
        #if DEBUG
        return "Debug Build"
        #elseif ENABLE_LOGGING
        return "Release Build (Logging Enabled)"
        #else
        return "Production Build"
        #endif
    }
}

// MARK: - Structured Debug Logging

extension Logger {
    
    /// Log a major section separator for visual clarity
    static func section(_ title: String) {
        #if DEBUG
        let separator = String(repeating: "═", count: 60)
        let paddedTitle = " \(title) "
        let totalPadding = max(0, separator.count - paddedTitle.count)
        let leftPadding = totalPadding / 2
        let rightPadding = totalPadding - leftPadding
        
        print("\n\(String(repeating: "═", count: leftPadding))\(paddedTitle)\(String(repeating: "═", count: rightPadding))")
        #endif
    }
    
    /// Log a subsection for grouping related operations
    static func subsection(_ title: String) {
        #if DEBUG
        print("\n┌─ \(title) " + String(repeating: "─", count: max(0, 50 - title.count)))
        #endif
    }
    
    /// Log the end of a subsection
    static func endSubsection() {
        #if DEBUG
        print("└" + String(repeating: "─", count: 55))
        #endif
    }
    
    /// Log an HTTP request with full details
    static func httpRequest(method: String, url: String, headers: [String: String]? = nil, body: Data? = nil) {
        #if DEBUG
        subsection("HTTP REQUEST")
        print("│ \(method) \(url)")
        
        if let headers = headers, !headers.isEmpty {
            print("│ Headers:")
            for (key, value) in headers {
                let displayValue = key.lowercased().contains("auth") ? "\(value.prefix(20))..." : value
                print("│   \(key): \(displayValue)")
            }
        }
        
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            print("│ Body: \(bodyString.prefix(200))\(bodyString.count > 200 ? "..." : "")")
        }
        endSubsection()
        #endif
    }
    
    /// Log an HTTP response with full details
    static func httpResponse(statusCode: Int, url: String, responseTime: TimeInterval? = nil, body: Data? = nil) {
        #if DEBUG
        let statusEmoji = statusCode < 300 ? "✅" : (statusCode < 400 ? "⚠️" : "❌")
        subsection("HTTP RESPONSE")
        print("│ \(statusEmoji) \(statusCode) \(url)")
        
        if let responseTime = responseTime {
            print("│ ⏱️ Response time: \(String(format: "%.0fms", responseTime * 1000))")
        }
        
        if let body = body {
            if let jsonObject = try? JSONSerialization.jsonObject(with: body),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                let lines = prettyString.components(separatedBy: .newlines).prefix(20)
                for line in lines {
                    print("│ \(line)")
                }
                if prettyString.components(separatedBy: .newlines).count > 20 {
                    print("│ ... (truncated)")
                }
            } else if let bodyString = String(data: body, encoding: .utf8) {
                print("│ \(bodyString.prefix(500))\(bodyString.count > 500 ? "..." : "")")
            }
        }
        endSubsection()
        #endif
    }
    
    /// Log view lifecycle events
    static func viewLifecycle(_ viewName: String, event: String, details: String? = nil) {
        #if DEBUG
        let message = details != nil ? "\(event) - \(details!)" : event
        view("[\(viewName)] \(message)")
        #endif
    }
    
    /// Log user interactions with context
    static func userInteraction(_ action: String, target: String, context: [String: Any]? = nil) {
        #if DEBUG
        var message = "\(action) → \(target)"
        if let context = context, !context.isEmpty {
            let contextString = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            message += " (\(contextString))"
        }
        interaction(message)
        #endif
    }
    
    /// Log performance measurements
    static func performanceMeasure(_ operation: String, duration: TimeInterval, additionalInfo: String? = nil) {
        #if DEBUG
        let durationString = String(format: "%.2fms", duration * 1000)
        let message = additionalInfo != nil ? 
            "\(operation): \(durationString) - \(additionalInfo!)" : 
            "\(operation): \(durationString)"
        performance(message)
        #endif
    }
}


