import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var preferred: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceMenu: View {
    @Binding var raw: String

    private var current: AppearanceMode {
        AppearanceMode(rawValue: raw) ?? .system
    }

    var body: some View {
        Menu {
            Picker("Appearance", selection: $raw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: current.symbol)
        }
        .help("Appearance: \(current.title)")
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
