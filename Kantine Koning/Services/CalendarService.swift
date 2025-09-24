import Foundation
import EventKit

enum CalendarError: LocalizedError {
    case permissionDenied
    case eventStoreUnavailable
    case eventCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Toegang tot agenda geweigerd. Ga naar Instellingen > Privacy & Beveiliging > Agenda om toegang toe te staan."
        case .eventStoreUnavailable:
            return "Agenda niet beschikbaar op dit apparaat."
        case .eventCreationFailed:
            return "Kon gebeurtenis niet aanmaken in agenda."
        }
    }
}

/// Service for adding diensten to the user's calendar
final class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()
    
    /// Add a dienst to the user's calendar
    func addDienstToCalendar(_ dienst: Dienst, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.userInteraction("Calendar Add Request", target: "CalendarService", context: [
            "dienst_id": dienst.id,
            "team": dienst.teamName ?? "unknown"
        ])
        
        // Log current calendar status for debugging
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        Logger.debug("Calendar authorization status: \(currentStatus.rawValue)")
        
        switch currentStatus {
        case .notDetermined:
            Logger.debug("Calendar status: Not determined - will request permission")
        case .denied:
            Logger.debug("Calendar status: Denied")
        case .authorized:
            Logger.debug("Calendar status: Authorized (legacy)")
        case .fullAccess:
            Logger.debug("Calendar status: Full access")
        case .writeOnly:
            Logger.debug("Calendar status: Write only")
        case .restricted:
            Logger.debug("Calendar status: Restricted")
        @unknown default:
            Logger.debug("Calendar status: Unknown")
        }
        
        // Check if EventKit is available
        guard currentStatus != .restricted else {
            Logger.error("Calendar access restricted")
            completion(.failure(CalendarError.eventStoreUnavailable))
            return
        }
        
        // Request permission if needed
        if currentStatus == .notDetermined {
            Logger.debug("Requesting calendar permission")
            
            // Use modern API for iOS 17+, fallback for older versions
            if #available(iOS 17.0, *) {
                eventStore.requestWriteOnlyAccessToEvents { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            Logger.error("Calendar permission error: \(error)")
                            completion(.failure(error))
                            return
                        }
                        
                        if granted {
                            Logger.success("Calendar write permission granted")
                            self?.createCalendarEvent(for: dienst, completion: completion)
                        } else {
                            Logger.warning("Calendar permission denied by user")
                            completion(.failure(CalendarError.permissionDenied))
                        }
                    }
                }
            } else {
                // Fallback for iOS 16
                eventStore.requestAccess(to: .event) { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            Logger.error("Calendar permission error: \(error)")
                            completion(.failure(error))
                            return
                        }
                        
                        if granted {
                            Logger.success("Calendar permission granted")
                            self?.createCalendarEvent(for: dienst, completion: completion)
                        } else {
                            Logger.warning("Calendar permission denied by user")
                            completion(.failure(CalendarError.permissionDenied))
                        }
                    }
                }
            }
        } else if hasWriteAccess(status: currentStatus) {
            Logger.debug("Calendar already has write access - creating event")
            createCalendarEvent(for: dienst, completion: completion)
        } else {
            Logger.warning("Calendar permission previously denied")
            completion(.failure(CalendarError.permissionDenied))
        }
    }
    
    private func createCalendarEvent(for dienst: Dienst, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.debug("Creating calendar event for dienst \(dienst.id)")
        
        let event = EKEvent(eventStore: eventStore)
        
        // Event title with team name
        if let teamName = dienst.teamName {
            event.title = "Kantinedienst - \(teamName)"
        } else {
            event.title = "Kantinedienst"
        }
        
        // Time and location
        event.startDate = dienst.startTime
        event.endDate = dienst.endTime
        event.location = dienst.locationName ?? "Kantine"
        
        // Build detailed notes
        event.notes = buildEventNotes(for: dienst)
        
        // Use default calendar
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        // Create alert 30 minutes before
        let alarm = EKAlarm(relativeOffset: -30 * 60) // 30 minutes before
        event.addAlarm(alarm)
        
        do {
            try eventStore.save(event, span: .thisEvent)
            Logger.success("Calendar event created successfully")
            Logger.userInteraction("Calendar Add Success", target: "CalendarService", context: [
                "dienst_id": dienst.id,
                "event_title": event.title ?? "Kantinedienst"
            ])
            completion(.success(()))
        } catch {
            Logger.error("Failed to save calendar event: \(error)")
            completion(.failure(CalendarError.eventCreationFailed))
        }
    }
    
    private func buildEventNotes(for dienst: Dienst) -> String {
        var notes = "Vrijwilligersdienst voor het team"
        
        if let teamName = dienst.teamName {
            notes += " \(teamName)"
        }
        notes += "."
        
        // Add minimum staffing info
        notes += "\n\nMinimale bemanning: \(dienst.minimumBemanning) vrijwilliger(s)"
        
        // Add volunteers if any
        if let volunteers = dienst.volunteers, !volunteers.isEmpty {
            notes += "\n\nAangemelde vrijwilligers (\(volunteers.count)):"
            for volunteer in volunteers {
                notes += "\n• \(volunteer)"
            }
        } else {
            notes += "\n\nNog geen vrijwilligers aangemeld."
        }
        
        // Add helpful text
        notes += "\n\nGegenereerd door Kantine Koning app"
        
        return notes
    }
    
    /// Helper to check if we have write access to calendar
    private func hasWriteAccess(status: EKAuthorizationStatus) -> Bool {
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
    }
    
    /// Check if calendar access is available without requesting permission
    var isCalendarAvailable: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return hasWriteAccess(status: status) || status == .notDetermined
    }
    
    /// Get current authorization status for UI decisions
    var authorizationStatus: EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }
}
