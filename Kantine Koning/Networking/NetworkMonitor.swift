import Foundation
import Network
import Combine

/// Network connectivity monitor for detecting online/offline state
/// Disables backend-dependent UI controls when offline
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kantinekoning.network-monitor")
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
                Logger.network("Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
                
                if let type = self?.connectionType {
                    Logger.debug("Connection type: \(type)")
                }
            }
        }
        
        monitor.start(queue: queue)
        Logger.bootstrap("NetworkMonitor started")
    }
    
    private func stopMonitoring() {
        monitor.cancel()
        Logger.debug("NetworkMonitor stopped")
    }
    
    /// Check if network is available for backend operations
    var canPerformBackendOperations: Bool {
        return isConnected
    }
    
    /// Get user-friendly network status description
    var statusDescription: String {
        if isConnected {
            switch connectionType {
            case .wifi:
                return "Verbonden via WiFi"
            case .cellular:
                return "Verbonden via mobiel netwerk"
            case .wiredEthernet:
                return "Verbonden via ethernet"
            default:
                return "Verbonden"
            }
        } else {
            return "Geen internetverbinding"
        }
    }
    
    /// Show network status indicator emoji
    var statusEmoji: String {
        if isConnected {
            switch connectionType {
            case .wifi:
                return "📶"
            case .cellular:
                return "📱"
            default:
                return "🌐"
            }
        } else {
            return "❌"
        }
    }
}
