import SwiftUI
import UIKit

enum BrandAssets {
    static func logoImage() -> Image {
        if let ui = UIImage(named: "AppIcon") ?? UIImage(named: "BrandLogo") { return Image(uiImage: ui) }
        return Image(systemName: "crown.fill")
    }
}


