import SwiftUI

/// How to Play: the full web rulebook (`Rulebook.sections`). Chips jump between sections; on
/// wide layouts a sidebar table of contents sits beside the text.
struct RulesView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var app
    @State private var current: String? = Rulebook.sections[0].id

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    tableOfContents
                        .frame(width: 260)
                        .padding(.vertical, 16)
                    Divider().overlay(Theme.hairline)
                    content
                }
            } else {
                content
            }
        }
        .appBackground()
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let section = app.pendingRulesSection else { return }
            app.pendingRulesSection = nil
            // Let the lazy list lay out before asking it to scroll.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.35)) { current = section }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if sizeClass != .regular { chips }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Rulebook.sections) { section in
                        RulebookSectionView(section: section)
                            .id(section.id)
                    }
                }
                .scrollTargetLayout()
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $current, anchor: .top)
        }
    }

    private var chips: some View {
        ScrollViewReader { strip in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Rulebook.sections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { current = section.id }
                    } label: {
                        Text(section.navLabel)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(current == section.id ? .white : Color(hex: "#C8C8D6"))
                            .background(
                                Capsule().fill(current == section.id ? Color(hex: section.theme.hex).opacity(0.28) : Theme.surfaceRaised)
                            )
                            .overlay(Capsule().strokeBorder(current == section.id ? Color(hex: section.theme.hex) : Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .id("chip-" + section.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onChange(of: current) { _, id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.3)) { strip.scrollTo("chip-" + id, anchor: .center) }
        }
        }
    }

    private var tableOfContents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Contents").padding(.horizontal, 16).padding(.bottom, 6)
                ForEach(Rulebook.sections) { section in
                    Button { withAnimation(.easeInOut(duration: 0.35)) { current = section.id } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.navLabel).font(.subheadline.weight(.semibold))
                            Text(section.navDescription).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(current == section.id ? Color(hex: section.theme.hex).opacity(0.18) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

struct RulebookSectionView: View {
    let section: Rulebook.Section

    var body: some View {
        let tint = Color(hex: section.theme.hex)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow = section.eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                }
                Text(section.title).font(Theme.display(24)).minimumScaleFactor(0.8).lineLimit(2)
                if let intro = section.intro {
                    Text(intro).foregroundStyle(.white.opacity(0.85))
                }
            }
            ForEach(section.blocks) { block in
                RulebookBlockView(block: block, tint: tint)
            }
            ForEach(section.subsections) { sub in
                VStack(alignment: .leading, spacing: 12) {
                    Text(sub.title).font(.title3.bold()).padding(.top, 6)
                    ForEach(sub.blocks) { block in
                        RulebookBlockView(block: block, tint: tint)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 18)
        }
    }
}

struct RulebookBlockView: View {
    let block: Rulebook.Block
    let tint: Color

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text).foregroundStyle(.white.opacity(0.85))

        case .subtitle(let text):
            Text(text).font(.headline).padding(.top, 4)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tint)
                            .frame(width: 18, alignment: .trailing)
                        Text(item).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }

        case .table(let caption, let columns, let rows):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(columns.0)
                    Spacer()
                    Text(columns.1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 6)
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(row.1).bold().monospacedDigit().foregroundStyle(tint)
                    }
                    .frame(minHeight: 32)
                    Divider().overlay(Theme.hairline)
                }
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 8)
                }
            }
            .padding(14)
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .demo(let demo, let caption):
            VStack(alignment: .leading, spacing: 6) {
                DemoBoardView(demo: demo)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }

        case .callout(let kind, let title, let text):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.symbol).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    if let title { Text(title).font(.subheadline.weight(.bold)) }
                    Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.4)))

        case .formula(let lines, let caption):
            VStack(spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                }
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
