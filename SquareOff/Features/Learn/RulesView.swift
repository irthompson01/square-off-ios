import SwiftUI

/// How to Play (web `/instructions`): one accordion with a numbered row per section (intro open
/// by default, several may be open), a contents sheet on phones and a sticky contents sidebar on
/// wide layouts. Demo boards play only while their section is open and on screen.
struct RulesView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var expanded: Set<String> = ["section-intro"]
    @State private var current: String? = "section-intro"
    @State private var scrollTarget: String?
    @State private var isContentsPresented = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    RulebookContents(current: current, onSelect: jump)
                        .frame(width: 256)
                        .padding(.vertical, 16)
                    Theme.border.frame(width: 1)
                    content
                }
            } else {
                content
            }
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isContentsPresented) {
            NavigationStack {
                RulebookContents(current: current) { id in
                    isContentsPresented = false
                    // Let the sheet go before scrolling (web waits 450 ms after closing its drawer).
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        jump(to: id)
                    }
                }
                .navigationTitle("On this page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isContentsPresented = false } } }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.overlay)
        }
        .task {
            guard let section = app.pendingRulesSection else { return }
            app.pendingRulesSection = nil
            try? await Task.sleep(for: .milliseconds(150))
            jump(to: section)
        }
    }

    private var content: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeading(title: "How to Play", description: "Rules, scoring, multipliers, and strategies — open a section to see it in action.")
                    if sizeClass != .regular {
                        Button { isContentsPresented = true } label: { Label("Contents", systemImage: "list.bullet.indent") }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                    }
                    accordion
                }
                .padding(16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $current, anchor: .top)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                Task {
                    // The section body mounts first; then scroll (web: 260 ms after expanding).
                    try? await Task.sleep(for: .milliseconds(260))
                    withAnimation(.easeInOut(duration: 0.35)) { reader.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
    }

    private var accordion: some View {
        VStack(spacing: 0) {
            ForEach(Array(Rulebook.sections.enumerated()), id: \.element.id) { index, section in
                RulebookSectionView(
                    section: section,
                    number: index + 1,
                    isExpanded: expanded.contains(section.id),
                    onToggle: { toggle(section.id) }
                )
                .id(section.id)
                if index < Rulebook.sections.count - 1 {
                    Theme.separator.frame(height: 1).padding(.horizontal, 16)
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border))
        .scrollTargetLayout()
    }

    private func toggle(_ id: String) {
        withAnimation(.easeOutQuad(0.2)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    /// Expands the owning section, then scrolls to the section or subsection.
    private func jump(to id: String) {
        let owner = Rulebook.sections.first { $0.id == id || $0.subsections.contains { $0.id == id } }?.id ?? id
        withAnimation(.easeOutQuad(0.2)) { expanded.insert(owner) }
        current = owner
        scrollTarget = id
    }
}

/// Section list for the sidebar and the phone sheet (web `RulebookToc`): sections at depth 0,
/// strategy subsections at depth 1; the current entry is highlighted.
struct RulebookContents: View {
    let current: String?
    let onSelect: (String) -> Void

    private struct Entry: Identifiable {
        let id: String
        let label: String
        let depth: Int
    }

    private var entries: [Entry] {
        Rulebook.sections.flatMap { section in
            [Entry(id: section.id, label: section.title, depth: 0)]
                + section.subsections.map { Entry(id: $0.id, label: $0.title, depth: 1) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("On this page").padding(.horizontal, 16).padding(.bottom, 8)
                ForEach(entries) { entry in
                    let active = current == entry.id
                    Button { onSelect(entry.id) } label: {
                        Text(entry.label)
                            .font(entry.depth == 0 ? .subheadline.weight(.medium) : .footnote)
                            .foregroundStyle(active ? Theme.foreground : Theme.muted)
                            .padding(.leading, entry.depth == 0 ? 8 : 24)
                            .padding(.trailing, 8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(active ? Theme.controlFill : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// One accordion row: number badge, title + eyebrow, chevron; the body mounts on first expand.
struct RulebookSectionView: View {
    let section: Rulebook.Section
    let number: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var mounted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Text("\(number)")
                        .font(Theme.display(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 32, height: 32)
                        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title).font(Theme.display(17, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                        if let eyebrow = section.eyebrow {
                            Text(eyebrow.uppercased()).font(.system(size: 11, weight: .medium)).tracking(1.3).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeOut(duration: 0.25), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded || mounted {
                body(expanded: isExpanded)
                    .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(isExpanded ? 1 : 0)
                    .accessibilityHidden(!isExpanded)
            }
        }
        .onChange(of: isExpanded, initial: true) { _, expanded in
            if expanded { mounted = true }
        }
    }

    private func body(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let intro = section.intro {
                Text(intro).font(.system(size: 15)).lineSpacing(4).foregroundStyle(Theme.foregroundSecondary)
            }
            ForEach(section.blocks) { block in
                RulebookBlockView(block: block, demosEnabled: expanded)
            }
            if !section.subsections.isEmpty {
                Theme.separator.frame(height: 1).padding(.top, 8)
                ForEach(section.subsections) { sub in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(sub.title).font(Theme.display(17, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(sub.blocks) { block in
                            RulebookBlockView(block: block, demosEnabled: expanded)
                        }
                    }
                    .id(sub.id)
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}

struct RulebookBlockView: View {
    let block: Rulebook.Block
    var demosEnabled = true

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text).font(.system(size: 15)).lineSpacing(4).foregroundStyle(Theme.foregroundSecondary)

        case .subtitle(let text):
            Text(text).font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground).padding(.top, 8)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 18, alignment: .trailing)
                        Text(item).font(.system(size: 15)).lineSpacing(3).foregroundStyle(Theme.foregroundSecondary)
                    }
                }
            }

        case .table(let caption, let columns, let rows):
            VStack(alignment: .leading, spacing: 8) {
                if let caption { SectionLabel(caption) }
                VStack(spacing: 0) {
                    HStack {
                        Text(columns.0)
                        Spacer()
                        Text(columns.1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceTertiary)
                    ForEach(rows, id: \.0) { row in
                        HStack {
                            Text(row.0).foregroundStyle(Theme.foregroundSecondary)
                            Spacer()
                            Text(row.1).font(Theme.display(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.foreground)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        Theme.separator.frame(height: 1)
                    }
                }
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

        case .demo(let demo, let caption):
            VStack(spacing: 8) {
                DemoBoardView(demo: demo, enabled: demosEnabled)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))

        case .callout(let kind, let title, let text):
            AlertBox(kind == .tip ? .success : kind == .note ? .accent : .default, title: title, message: text)

        case .formula(let lines, let caption):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceTertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        }
    }
}
