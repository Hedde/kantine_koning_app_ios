import Foundation
import UIKit

/// Global error handling system following iOS best practices
/// Handles uncaught exceptions, network errors, and provides user-friendly error messages
final class ErrorHandler {
    static let shared = ErrorHandler()
    
    // MARK: - Error Categories
    enum ErrorCategory {
        case network
        case authentication  
        case validation
        case system
        case unknown
    }
    
    // MARK: - User-Facing Error Messages
    private let errorMessages: [ErrorCategory: String] = [
        .network: "Er is een probleem met de internetverbinding. Probeer het later opnieuw.",
        .authentication: "Er is een probleem met je aanmelding. Log opnieuw in.",
        .validation: "De ingevoerde gegevens zijn niet correct. Controleer je invoer.",
        .system: "Er is een technisch probleem opgetreden. Probeer de app opnieuw te starten.",
        .unknown: "Er is een onbekend probleem opgetreden. Neem contact op met support."
    ]
    
    // MARK: - Initialization
    private init() {
        setupGlobalExceptionHandler()
        Logger.bootstrap("ErrorHandler initialized with global exception handling")
    }
    
    // MARK: - Global Exception Handler Setup
    private func setupGlobalExceptionHandler() {
        // Handle NSExceptions (Objective-C exceptions)
        NSSetUncaughtExceptionHandler { exception in
            ErrorHandler.shared.handleUncaughtException(exception)
        }
        
        // Handle Unix signals (crashes)
        signal(SIGABRT) { signal in
            ErrorHandler.shared.handleSignal(signal, name: "SIGABRT")
        }
        signal(SIGILL) { signal in
            ErrorHandler.shared.handleSignal(signal, name: "SIGILL")
        }
        signal(SIGSEGV) { signal in
            ErrorHandler.shared.handleSignal(signal, name: "SIGSEGV")
        }
        signal(SIGFPE) { signal in
            ErrorHandler.shared.handleSignal(signal, name: "SIGFPE")
        }
        signal(SIGBUS) { signal in
            ErrorHandler.shared.handleSignal(signal, name: "SIGBUS")
        }
    }
    
    // MARK: - Exception Handling
    private func handleUncaughtException(_ exception: NSException) {
        let crashInfo = """
        🚨 UNCAUGHT EXCEPTION 🚨
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        Stack: \(exception.callStackSymbols.joined(separator: "\n"))
        """
        
        Logger.error("Uncaught exception: \(crashInfo)")
        
        #if DEBUG
        Logger.section("CRASH REPORT")
        print(crashInfo)
        Logger.endSubsection()
        #endif
        
        // In production, log to crash reporting service
        logCrashToService(type: "NSException", details: crashInfo)
    }
    
    private func handleSignal(_ signal: Int32, name: String) {
        let crashInfo = """
        🚨 SIGNAL CRASH 🚨
        Signal: \(name) (\(signal))
        Thread: \(Thread.current)
        """
        
        Logger.error("Signal crash: \(crashInfo)")
        
        #if DEBUG
        Logger.section("SIGNAL CRASH")
        print(crashInfo)
        Logger.endSubsection()
        #endif
        
        logCrashToService(type: "Signal", details: crashInfo)
        exit(signal)
    }
    
    // MARK: - Error Categorization
    func categorizeError(_ error: Error) -> ErrorCategory {
        // Network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return .network
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return .authentication
            default:
                return .network
            }
        }
        
        // Custom app errors
        if let appError = error as? AppError {
            return appError.category
        }
        
        // Validation errors
        if error.localizedDescription.lowercased().contains("validation") ||
           error.localizedDescription.lowercased().contains("invalid") {
            return .validation
        }
        
        // System errors
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return .system
        case "com.kantinekoning.auth":
            return .authentication
        default:
            return .unknown
        }
    }
    
    // MARK: - User-Friendly Error Handling
    func handleError(_ error: Error, context: String? = nil, showToUser: Bool = true) {
        let category = categorizeError(error)
        
        // Log the error with full details
        Logger.error("Error in \(context ?? "unknown context"): \(error.localizedDescription)")
        
        #if DEBUG
        Logger.subsection("ERROR DETAILS")
        print("│ Category: \(category)")
        print("│ Error: \(error)")
        print("│ Description: \(error.localizedDescription)")
        let nsError = error as NSError
        print("│ Domain: \(nsError.domain)")
        print("│ Code: \(nsError.code)")
        print("│ User Info: \(nsError.userInfo)")
        Logger.endSubsection()
        #endif
        
        // Show user-friendly message if requested
        if showToUser {
            showErrorToUser(category: category, originalError: error, context: context)
        }
        
        // Log to analytics/crash reporting in production
        logErrorToService(error: error, category: category, context: context)
    }
    
    private func showErrorToUser(category: ErrorCategory, originalError: Error, context: String?) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                Logger.warning("Could not find window to show error alert")
                return
            }
            
            let message = self.errorMessages[category] ?? self.errorMessages[.unknown]!
            let alert = UIAlertController(
                title: "Oeps!",
                message: message,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            #if DEBUG
            // Add debug info in development
            alert.addAction(UIAlertAction(title: "Debug Info", style: .destructive) { _ in
                let debugAlert = UIAlertController(
                    title: "Debug Information",
                    message: "Error: \(originalError.localizedDescription)\nContext: \(context ?? "None")",
                    preferredStyle: .alert
                )
                debugAlert.addAction(UIAlertAction(title: "OK", style: .default))
                window.rootViewController?.present(debugAlert, animated: true)
            })
            #endif
            
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    // MARK: - Crash and Error Reporting
    private func logCrashToService(type: String, details: String) {
        #if !DEBUG
        // In production, integrate with crash reporting service like:
        // - Firebase Crashlytics
        // - Sentry
        // - Bugsnag
        // For now, just log locally
        Logger.error("CRASH: \(type) - \(details)")
        #endif
    }
    
    private func logErrorToService(error: Error, category: ErrorCategory, context: String?) {
        #if !DEBUG
        // In production, log to analytics service
        Logger.error("Handled error: \(category) - \(error.localizedDescription)")
        #endif
    }
}

// MARK: - Custom App Errors

enum AppError: LocalizedError {
    case networkUnavailable
    case invalidCredentials
    case dataCorrupted
    case unauthorized
    case serverError(Int)
    case validationFailed(String)
    case cacheError
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Geen internetverbinding beschikbaar"
        case .invalidCredentials:
            return "Ongeldige inloggegevens"
        case .dataCorrupted:
            return "Data is beschadigd"
        case .unauthorized:
            return "Geen toegang"
        case .serverError(let code):
            return "Server error (\(code))"
        case .validationFailed(let message):
            return "Validatie mislukt: \(message)"
        case .cacheError:
            return "Cache fout"
        }
    }
    
    var category: ErrorHandler.ErrorCategory {
        switch self {
        case .networkUnavailable, .serverError:
            return .network
        case .invalidCredentials, .unauthorized:
            return .authentication
        case .validationFailed:
            return .validation
        case .dataCorrupted, .cacheError:
            return .system
        }
    }
}

// MARK: - Error Handling Extensions

extension Error {
    /// Handle this error using the global error handler
    func handle(context: String? = nil, showToUser: Bool = true) {
        ErrorHandler.shared.handleError(self, context: context, showToUser: showToUser)
    }
    
    /// Get the error category
    var category: ErrorHandler.ErrorCategory {
        return ErrorHandler.shared.categorizeError(self)
    }
}
