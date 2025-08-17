//
//  KeyboardHelpers.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import SwiftUI

// MARK: - Keyboard Management Extension
extension View {
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
