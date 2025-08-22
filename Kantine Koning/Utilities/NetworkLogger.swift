import Foundation

/// Network request/response logging with performance monitoring
final class NetworkLogger {
    
    // MARK: - Request Tracking
    private static var requestStartTimes: [String: Date] = [:]
    private static let queue = DispatchQueue(label: "com.kantinekoning.network-logger", attributes: .concurrent)
    
    /// Log the start of a network request
    static func logRequest(_ request: URLRequest, requestId: String = UUID().uuidString) -> String {
        let startTime = Date()
        
        queue.async(flags: .barrier) {
            requestStartTimes[requestId] = startTime
        }
        
        #if DEBUG
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "Unknown URL"
        
        var headers: [String: String] = [:]
        if let allHeaders = request.allHTTPHeaderFields {
            headers = allHeaders
        }
        
        Logger.httpRequest(
            method: method,
            url: url,
            headers: headers,
            body: request.httpBody
        )
        #endif
        
        return requestId
    }
    
    /// Log the completion of a network request
    static func logResponse(
        _ response: URLResponse?,
        data: Data?,
        error: Error?,
        requestId: String
    ) {
        var responseTime: TimeInterval?
        
        queue.sync {
            if let startTime = requestStartTimes[requestId] {
                responseTime = Date().timeIntervalSince(startTime)
                requestStartTimes.removeValue(forKey: requestId)
            }
        }
        
        let url = response?.url?.absoluteString ?? "Unknown URL"
        
        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        
        if let error = error {
            Logger.httpResponse(
                statusCode: -1,
                url: url,
                responseTime: responseTime,
                body: error.localizedDescription.data(using: .utf8)
            )
            Logger.error("Network request failed: \(error.localizedDescription)")
        } else {
            Logger.httpResponse(
                statusCode: statusCode,
                url: url,
                responseTime: responseTime,
                body: data
            )
            
            if let responseTime = responseTime {
                let performanceLevel = responseTime < 0.5 ? "Fast" : (responseTime < 2.0 ? "Moderate" : "Slow")
                Logger.performanceMeasure(
                    "Network Request",
                    duration: responseTime,
                    additionalInfo: "\(performanceLevel) - \(url)"
                )
            }
        }
        #endif
        
        // Handle errors using global error handler
        if let error = error {
            error.handle(context: "Network request to \(url)", showToUser: false)
        }
    }
    
    /// Create a logged URLSessionDataTask
    static func createLoggedDataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let requestId = logRequest(request)
        
        return URLSession.shared.dataTask(with: request) { data, response, error in
            logResponse(response, data: data, error: error, requestId: requestId)
            completionHandler(data, response, error)
        }
    }
}
