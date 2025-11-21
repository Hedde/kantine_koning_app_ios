import Foundation

enum ErrorTranslations {
    static func translate(_ error: Error) -> String {
        let errorString = error.localizedDescription
        
        // Try to parse JSON error responses
        if let data = errorString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorCode = json["error"] as? String {
            return translateErrorCode(errorCode)
        }
        
        // Check if the error description contains JSON
        if errorString.contains("{") && errorString.contains("}") {
            if let range = errorString.range(of: #"\{"error":\s*"([^"]+)""#, options: .regularExpression) {
                let errorCode = String(errorString[range]).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "{error:", with: "").replacingOccurrences(of: "}", with: "")
                return translateErrorCode(errorCode)
            }
        }
        
        // Fallback to generic translation
        return translateGenericError(errorString)
    }
    
    private static func translateErrorCode(_ code: String) -> String {
        switch code {
        case "team_manager_not_found":
            return "Dit e-mailadres is niet bekend als teammanager bij deze club."
        case "invalid_team_codes":
            return "Een of meer geselecteerde teams zijn niet geldig."
        case "enrollment_limit_exceeded":
            return "Je kunt maximaal 5 teams volgen. Verwijder eerst een team."
        case "tenant_not_found":
            return "Deze vereniging werd niet gevonden."
        case "invalid_email":
            return "Voer een geldig e-mailadres in."
        case "enrollment_expired":
            return "Deze aanmeldingslink is verlopen. Vraag een nieuwe aan."
        case "device_already_enrolled":
            return "Dit apparaat is al aangemeld voor deze teams."
        case "team_access_denied":
            return "Je bent niet gemachtigd om vrijwilligers te beheren voor dit team."
        case "invalid_or_expired_token":
            return "Deze koppellink is verlopen. Vraag een nieuwe link aan."
        case "team_conflict":
            return "Dit team is al gekoppeld met een andere rol."
        case "enrollment_failed":
            return "De koppeling kon niet worden voltooid. Probeer het opnieuw."
        default:
            return "Er is een onbekende fout opgetreden. Probeer het opnieuw."
        }
    }
    
    private static func translateGenericError(_ error: String) -> String {
        if error.lowercased().contains("network") || error.lowercased().contains("connection") {
            return "Geen internetverbinding. Controleer je netwerk en probeer opnieuw."
        }
        if error.lowercased().contains("timeout") {
            return "De server reageert niet. Probeer het later opnieuw."
        }
        if error.lowercased().contains("401") || error.lowercased().contains("unauthorized") {
            return "Je bent niet geautoriseerd. Log opnieuw in."
        }
        if error.lowercased().contains("403") || error.lowercased().contains("forbidden") {
            return "Je hebt geen toegang tot deze functie."
        }
        if error.lowercased().contains("404") || error.lowercased().contains("not found") {
            return "De gevraagde informatie werd niet gevonden."
        }
        if error.lowercased().contains("500") || error.lowercased().contains("server") {
            return "Er is een serverfout opgetreden. Probeer het later opnieuw."
        }
        
        return "Er is een fout opgetreden. Probeer het opnieuw."
    }
}
