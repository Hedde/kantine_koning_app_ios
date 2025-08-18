//
//  BrandAssets.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI
import UIKit

enum BrandAssets {
	static func logoImage() -> Image {
		if let ui = UIImage(named: "AppIcon") ?? UIImage(named: "BrandLogo") {
			return Image(uiImage: ui)
		}
		return Image(systemName: "crown.fill")
	}
}
