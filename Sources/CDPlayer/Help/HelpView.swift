import SwiftUI

/// Which topic the help window shows. Shared so the snapshot mode can walk
/// every topic (Snapshot.swift).
@Observable
final class HelpNavigation {
    static let shared = HelpNavigation()
    var topic: HelpTopic.ID? = HelpTopic.all.first?.id
}

/// Ayuda > Ayuda de CDPlayer (⌘?): the guide to every unit, inside and out.
/// The text lives in HelpContent.swift.
struct HelpView: View {
    static let windowID = "help"
    @Bindable private var navigation = HelpNavigation.shared

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.all, selection: $navigation.topic) { topic in
                Label(topic.title, systemImage: topic.symbol)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            if let topic = HelpTopic.all.first(where: { $0.id == navigation.topic }) {
                HelpTopicPage(topic: topic)
                    .id(topic.id)
            } else {
                ContentUnavailableView("Elige un tema", systemImage: "questionmark.circle")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .noInitialFocus()
    }
}

/// One topic: its title, a line on what it covers, and its sections.
private struct HelpTopicPage: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(topic.title)
                        .font(.largeTitle.bold())
                    Text(topic.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .gridProbe("help-title", area: "help")

                ForEach(Array(topic.sections.enumerated()), id: \.offset) { index, section in
                    HelpSectionView(section: section)
                        .gridProbe("help-section-\(index)", area: "help")
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("help")
        }
        .navigationTitle(topic.title)
    }
}

private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(section.title)
                .font(.title2.bold())
            ForEach(section.text, id: \.self) { paragraph in
                Text(Self.markdown(paragraph))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(Space.xs / 2)
            }
            if !section.controls.isEmpty {
                GroupBox {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                        ForEach(Array(section.controls.enumerated()), id: \.offset) { index, control in
                            if index > 0 { Divider() }
                            GridRow {
                                Text(control.name)
                                    .bold()
                                    .frame(minWidth: 160, alignment: .leading)
                                Text(control.key)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                Text(Self.markdown(control.text))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(Space.xs)
                }
            }
        }
        .textSelection(.enabled)
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
