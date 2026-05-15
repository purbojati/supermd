import SwiftUI

enum Typography {
    static let bodySize: CGFloat = 16
    static let bodyLineSpacing: CGFloat = 7
    static let bodyDesign: Font.Design = .serif

    static let contentMaxWidth: CGFloat = 740
    static let contentHorizontalPadding: CGFloat = 56
    static let contentVerticalPadding: CGFloat = 40
    static let blockSpacing: CGFloat = 20

    static var body: Font { .system(size: bodySize, design: bodyDesign) }
    static var bodyEmphasized: Font { .system(size: bodySize, design: bodyDesign).italic() }
    static var caption: Font { .system(size: 12, design: .default) }

    static func heading(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 34, weight: .bold, design: bodyDesign)
        case 2: return .system(size: 26, weight: .semibold, design: bodyDesign)
        case 3: return .system(size: 21, weight: .semibold, design: bodyDesign)
        case 4: return .system(size: 18, weight: .semibold, design: bodyDesign)
        case 5: return .system(size: 16, weight: .semibold, design: bodyDesign)
        default: return .system(size: 14, weight: .semibold, design: bodyDesign)
        }
    }

    static func headingTopPadding(level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 18
        case 3: return 14
        default: return 8
        }
    }

    static func headingBottomPadding(level: Int) -> CGFloat {
        switch level {
        case 1, 2: return 6
        default: return 2
        }
    }
}
