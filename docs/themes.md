# Themes

This document explains how the theming system in SuperMD works so future palettes can be added without having to reverse-engineer the propagation rules.

## TL;DR — adding a new theme

1. Add a new `case` to `ThemePalette` in `Sources/SuperMD/Theme.swift`.
2. Pick an emoji + title for it (used in the toolbar picker).
3. Decide whether it reads as **light** or **dark** — that controls `preferredColorScheme`, which sets the window chrome + the system color scheme inside the app.
4. Fill in the 14 colors in `var colors: PaletteColors`.
5. Run `swift run SuperMD`, open the toolbar theme picker, pick the new theme, and confirm it looks right.

Everything else — Theme.* lookups, AttributedString runs, mermaid diagrams, the file browser, the TOC — already pulls from the active palette.

## Why a single fixed palette per theme

We deliberately do **not** model themes as a (palette × {light, dark}) matrix. Each theme is one fixed look:

- 🌸 Rose is light-pink with a deep-rose accent.
- 🌹 Crimson is dark with a hot-pink accent.
- 🌙 Midnight is deep navy with a sky accent.
- etc.

That means there is **no** "light/dark switcher" in the UI. The user picks a theme; the brightness is implied. This keeps the picker flat and avoids the trap where every palette has to ship two versions and look good in both.

The macOS app icon is the one exception — it still flips with the system theme (Light/Dark in System Settings), independent of the in-app palette. See `SuperMDAppDelegate.applyIcon()`.

## Anatomy of a palette

`PaletteColors` (in `Theme.swift`) is a flat struct of 14 sRGB hex values. They group into four roles:

### Surfaces (4)

| field | where it shows up |
| --- | --- |
| `background` | Main markdown reading pane behind everything |
| `sidebar` | File browser column background |
| `surface` | TOC column background, mermaid cluster fills |
| `elevated` | Slightly-brighter card surface; mermaid notes & edge labels |

Rule of thumb: `background` is the darkest/lightest, then `sidebar`/`surface` are one step toward neutral, and `elevated` is the brightest "lifted" surface. On dark themes you invert this — `background` is the darkest, `elevated` is the brightest.

### Accent (1)

| field | where it shows up |
| --- | --- |
| `accent` | Folder icon, "Folders" label, links, inline-code text, code-block titles, mermaid lines/borders, TOC active highlight, app `.tint` |

`accentSoft` and `accentBorder` are derived automatically from `accent` (the alpha is 0.10/0.55 on light themes and 0.16/0.60 on dark themes; see `Theme.accentSoft` / `Theme.accentBorder`).

You only ever pick one accent color per palette. Pick something that contrasts strongly with `background` — it's used both as fill (very transparent) and as solid text.

### Text (3)

| field | where it shows up |
| --- | --- |
| `text` | Primary body text, headings, code-block code |
| `secondaryText` | List bullets, blockquote outer fill, code-block language label, image alt-text |
| `tertiaryText` | Disclosure chevrons in the sidebar, "Select a file" placeholder icon |

These are a three-step ramp from "fully readable" to "background-leaning". Aim for high contrast on `text` (WCAG AA against `background` is a safe floor) and progressively lower contrast for `secondaryText` and `tertiaryText`.

### Lines & subtle fills (4)

| field | where it shows up |
| --- | --- |
| `border` | Code block stroke, mermaid container stroke, cluster borders |
| `dividerSoft` | Sidebar header divider |
| `hover` | Sidebar row hover fill |
| `activeRow` | Sidebar selected-file fill |

`hover` and `activeRow` should be one and two steps darker (light theme) or brighter (dark theme) than `sidebar`, respectively — the selected row should clearly read above hover.

### Code (2)

| field | where it shows up |
| --- | --- |
| `codeBackground` | Code block container fill, mermaid webview background |
| `inlineCodeFill` | Inline `` `code` `` fill, code-block language-label strip, mermaid node fills |

`codeBackground` is usually one step toward `accent`'s hue from `background`. `inlineCodeFill` is a touch more saturated still — it's used as the fill behind inline-code runs and as the primary node fill in mermaid diagrams.

## How a color reaches a pixel

There are three rendering paths, each with its own propagation rule.

### 1. SwiftUI views — `Theme.background`, `Theme.text`, etc.

Every Theme accessor is a **computed property**:

```swift
static var background: Color { color(palette.background) }
```

`palette` reads `ThemePalette.current` which reads `UserDefaults["themePalette"]` on each access. There is no cached `Color`. So as long as a view's `body` is re-evaluated after the user changes the theme, it picks up the new color.

The reactivity glue is `@AppStorage(ThemePalette.storageKey)` on every view that uses `Theme.*`. SwiftUI invalidates the view when the stored value changes, and `body` re-runs. Views that already have this observer:

- `ContentView` (root)
- `FileBrowserView`, `FileTreeRow`
- `MarkdownPaneView`, `BlockView`, `HeadingBlockView`, `CodeBlockView`, `BlockQuoteView`, `ListBlockView`
- `TableOfContentsView`
- `MermaidBlockView`

**If you add a new view that calls `Theme.*`, add the observer:**

```swift
@AppStorage(ThemePalette.storageKey) private var _palette: String = ThemePalette.rose.rawValue
```

The underscore makes it clear the property exists only to trigger re-evaluation.

### 2. AttributedString runs — `Theme.text`, `Theme.accent`, `Theme.inlineCodeFill`, `Theme.secondaryText`

Markdown inline rendering builds `AttributedString` values (see `attributedString(forInline:)` in `MarkdownView.swift`). Each text run gets `s.foregroundColor = Theme.text` (or `accent` for links/inline code, etc.) baked in **at build time**.

Two consequences:

1. **You must call the builder fresh on theme change.** Already-mounted `Text(attributedString)` views won't pick up new colors — the `AttributedString` is a value baked at construction. That's why `MarkdownPaneView`'s `LazyVStack` carries `.id(_palette)`: when the palette changes, the identity changes, SwiftUI tears down the mounted rows, and `BlockView`'s body rebuilds new `AttributedString`s with fresh colors. **Don't remove that `.id(_palette)`** unless you also change how inline rendering works.

2. **Every text run must set `foregroundColor` explicitly.** Plain `AttributedString(text.string)` without an explicit color falls through to SwiftUI's system `Color.primary`, which on a macOS Dark Mode host + a `.light` `preferredColorScheme` does not always resolve correctly and ends up rendering near-invisible. Look at the existing `attributedString(forInline:)` — every branch sets `s.foregroundColor`. Keep that invariant if you add new inline cases.

### 3. Mermaid (WebView) — hex strings

The mermaid HTML is built in `MermaidWebView.html()`. Its background, foreground, and Mermaid theme variables (`Theme.mermaidThemeVarsJSON`) are all derived from the current palette via the `*Hex` accessors on `Theme`.

The WebView reloads its HTML when **any** of `(code, colorScheme, palette)` changes (see `MermaidWebView.updateNSView`). If you add a new theme, mermaid will recolor on theme-switch for free.

If you add new mermaid theme keys, update `Theme.mermaidThemeVarsJSON` to emit them — don't introduce a hardcoded fallback string.

## The forgotten gotchas

Reading this section will save you 20 minutes when something looks "almost right".

- **`preferredColorScheme`.** Each palette declares whether it's `.light` or `.dark` via `var preferredColorScheme: ColorScheme`. This drives (a) the macOS window chrome (title bar appearance), (b) SwiftUI's environment color scheme, (c) any system-resolved colors like the toolbar's. If a palette looks readable in isolation but the title bar feels wrong, check this property is set correctly.

- **Never use `.foregroundStyle(.secondary)` / `.tertiary`** in this codebase. Those resolve from the system color hierarchy, which doesn't know about our palette. Use `Theme.secondaryText` / `Theme.tertiaryText`. There's an audit grep in the testing checklist below.

- **`accentSoft` and `accentBorder` alpha values are hard-coded** in `Theme.swift` (0.10/0.16 and 0.55/0.60). If your accent has very low saturation or is near-white/near-black, the soft variants may look invisible — bump the alpha just for that palette by switching to per-palette overrides, or pick a more saturated accent.

- **App icon ≠ theme.** The Dock/About icon swap reads the system appearance (`UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"`), **not** the active palette. This is intentional — your in-app palette of choice shouldn't drag the Dock icon's brightness with it. See `applyIcon()` in `SuperMDApp.swift`.

- **The LazyVStack `.id(_palette)` resets scroll position on theme switch.** If you want to preserve scroll, capture the scroll offset before the change and restore it after — but the simple approach is fine for a user-initiated theme swap.

## Adding a theme — full example

Adding a "Sunset" theme (warm orange-red light theme):

```swift
// 1. Add the case
enum ThemePalette: String, CaseIterable, Identifiable {
    case rose, crimson, paper, graphite, solar, ocean, midnight, forest, sunset
    // ...
}

// 2. Emoji + title
var emoji: String {
    switch self {
    // ...
    case .sunset:   return "🌇"
    }
}

var title: String {
    switch self {
    // ...
    case .sunset:   return "Sunset"
    }
}

// 3. Color scheme — sunset reads as light
var preferredColorScheme: ColorScheme {
    switch self {
    case .crimson, .graphite, .midnight: return .dark
    default: return .light  // sunset falls here
    }
}

// 4. The palette colors
var colors: PaletteColors {
    switch self {
    // ...
    case .sunset:
        return PaletteColors(
            background:     0xFFF4ED,
            sidebar:        0xFCE5D2,
            surface:        0xFDEADD,
            elevated:       0xFFF9F4,
            accent:         0xC2410C,  // burnt orange
            text:           0x2C1810,
            secondaryText:  0x744A2A,
            tertiaryText:   0x9B704C,
            border:         0xEED1B8,
            dividerSoft:    0xF3D9C0,
            hover:          0xF6DDC2,
            activeRow:      0xEFC9A5,
            codeBackground: 0xF7DEC2,
            inlineCodeFill: 0xEED1B8
        )
    }
}
```

That's it. The toolbar picker, palette propagation, file browser, markdown body, TOC, and mermaid diagrams all pick it up automatically.

## Testing checklist for a new theme

Before declaring a new theme done:

- [ ] Toolbar picker shows the emoji + title.
- [ ] Selecting the theme repaints the markdown pane immediately (no scroll required).
- [ ] Headings, paragraphs, links, **inline code**, code blocks, blockquotes, lists, and the image-alt label are all readable.
- [ ] File browser: folder labels, file labels, **selected** row, hovered row, and the chevron are all readable.
- [ ] TOC: heading levels (H1/H2 should look more prominent than H3+), active item highlight, hover state.
- [ ] Mermaid: render a flowchart and a sequence diagram. Node fills, borders, edge labels, and lines should all match the theme.
- [ ] Title bar appearance matches the theme brightness (light theme → light title bar).
- [ ] Run `grep -nE "\.secondary\b|\.tertiary\b|Color\.primary" Sources/SuperMD/*.swift` — should return zero hits inside view bodies.

## Reference: file map

| file | role |
| --- | --- |
| `Sources/SuperMD/Theme.swift` | `PaletteColors` struct, `ThemePalette` enum, `Theme.*` accessors, mermaid JSON builder |
| `Sources/SuperMD/Appearance.swift` | `ThemeMenu` toolbar picker, `ContentWidth` |
| `Sources/SuperMD/ContentView.swift` | Wires `themeRaw` AppStorage to `preferredColorScheme` and the toolbar |
| `Sources/SuperMD/MarkdownView.swift` | Block views, inline AttributedString builder — bakes `Theme.text` into every run |
| `Sources/SuperMD/MermaidView.swift` | WebView; reloads HTML when palette changes |
| `Sources/SuperMD/FileBrowser.swift` | Sidebar tree with hover/active palette colors |
| `Sources/SuperMD/TableOfContents.swift` | TOC column, accent-driven active indicator |
| `Sources/SuperMD/SuperMDApp.swift` | App icon swap based on **macOS** system theme (not palette) |
