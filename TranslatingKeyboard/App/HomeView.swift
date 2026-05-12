import SwiftUI

struct HomeView: View {
    /// Switch to a sibling tab. Set by `ContentView`.
    var onOpenEditor: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(spacing: 12) {
                    ActionCard(
                        title: "Try the editor",
                        subtitle: "Type shorthand and watch it expand right inside the app — no setup needed.",
                        systemImage: "wand.and.stars",
                        action: onOpenEditor
                    )
                    ActionCard(
                        title: "Set up the iOS keyboard",
                        subtitle: "Install Translating Keyboard system-wide so shorthand works in every app.",
                        systemImage: "keyboard",
                        action: onOpenSettings
                    )
                }

                howItWorks
                examples
            }
            .padding(20)
        }
        .navigationTitle("Translating Keyboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type less, write more.")
                .font(.title2.weight(.semibold))
            Text("Type the first 1–2 letters of each word with no spaces, end with “.”, and the app expands it into a full sentence.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How shorthand works")
                .font(.headline)
            BulletRow("Letters with no spaces → shorthand mode.")
            BulletRow("A period “.” at the end triggers expansion.")
            BulletRow("“i” and “a” count as single-letter words.")
            BulletRow("Normal sentences with spaces or known words pass through untouched.")
            BulletRow("Edit the expanded sentence — the app remembers your corrections.")
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.headline)
            ExampleRow(input: "thdoraho.", output: "the dog ran home.")
            ExampleRow(input: "iwatoma.", output: "i want to make.")
            ExampleRow(input: "iwatomaaprmare.", output: "i want to make a prediction market research.")
            ExampleRow(input: "hello there.", output: "hello there.  (unchanged)")
        }
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(.tint).frame(width: 5, height: 5).padding(.top, 7)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

private struct ExampleRow: View {
    let input: String
    let output: String
    var body: some View {
        HStack(spacing: 8) {
            Text(input)
                .font(.callout.monospaced())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(output)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}
