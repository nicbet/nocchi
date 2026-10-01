import NocchiCore
import SwiftUI

/// Expanded: a focus card for the primary agent (face + step carousel) and chips for the others.
struct OverviewView: View {
    let model: NotchModel

    var body: some View {
        let body = model.bodySize(for: .expanded)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            HStack(spacing: 10) {
                FocusCard(store: model.store)
                    .frame(width: (body.width - 36 - 10) * 0.52)
                ChipsCard(store: model.store)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 16, trailing: 18))
        }
        .frame(width: body.width, height: body.height)
        .environment(\.colorScheme, .dark)
    }
}

/// The primary agent: big face with a glow in its mood color, and what it's doing.
private struct FocusCard: View {
    let store: AgentStore

    var body: some View {
        let primary = store.primary
        let mood = primary.map(store.mood(of:)) ?? store.emptyMood
        HStack(spacing: 14) {
            FaceView(mood: mood, size: 64, seed: primary?.faceSeed ?? 0.37)
                .frame(width: 92, height: 92)
                .background {
                    RadialGradient(colors: [mood.tint.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 70)
                        .frame(width: 150, height: 150)
                        .animation(.easeInOut(duration: 0.4), value: mood)
                }
            if let primary {
                StepCarousel(entry: primary, mood: mood)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No agents running").font(.system(size: 14, weight: .semibold))
                    Text(mood == .sleep ? "Waiting for an agent source…" : "Start an agent and it shows up here.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
    }
}

/// Previous step (dim), current step (bright), and the agent's name and state (dim).
/// New steps slide up from below.
private struct StepCarousel: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            line(entry.previousStep, symbol: "checkmark", size: 12, opacity: 0.4)
            line(entry.currentStep ?? mood.label, symbol: mood.symbol, size: 15, opacity: 1, weight: .semibold)
            line("\(entry.info.displayName) · \(mood.label)", symbol: "person.crop.circle", size: 12, opacity: 0.4)
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: entry.steps)
        .animation(.spring(duration: 0.4, bounce: 0.15), value: mood)
    }

    @ViewBuilder
    private func line(_ text: String?, symbol: String, size: CGFloat, opacity: Double, weight: Font.Weight = .regular) -> some View {
        ZStack(alignment: .leading) {
            if let text {
                Label {
                    Text(text).lineLimit(1).truncationMode(.tail)
                } icon: {
                    Image(systemName: symbol).frame(width: size + 4)
                }
                .font(.system(size: size, weight: weight))
                .foregroundStyle(.white.opacity(opacity))
                .id(text)
                .transition(.asymmetric(
                    insertion: .push(from: .bottom).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
        }
        .frame(height: size + 6, alignment: .leading)
        .clipped()
    }
}

/// One chip per other agent, two columns, tinted by state.
private struct ChipsCard: View {
    let store: AgentStore
    static let maxChips = 4

    var body: some View {
        let others = store.others
        let visible = others.count > Self.maxChips ? Array(others.prefix(Self.maxChips - 1)) : others
        let overflow = others.count - visible.count
        Group {
            if others.isEmpty {
                Text("No other agents").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                let index = row * 2 + column
                                if index < visible.count {
                                    AgentChip(entry: visible[index], mood: store.mood(of: visible[index]))
                                } else if index == visible.count, overflow > 0 {
                                    OverflowChip(count: overflow)
                                } else {
                                    Color.clear.frame(height: 34)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
        .animation(.spring(duration: 0.4, bounce: 0.15), value: others.map(\.ref))
    }
}

private struct AgentChip: View {
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        HStack(spacing: 7) {
            FaceView(mood: mood, size: 20, seed: entry.faceSeed)
                .frame(width: 22, height: 22)
            Text(entry.currentStep ?? entry.info.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(mood.tint)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(mood.tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(mood.tint.opacity(0.35), lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: mood)
        .help("\(entry.info.displayName): \(mood.label)")
    }
}

private struct OverflowChip: View {
    let count: Int

    var body: some View {
        Text("+\(count) more")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.white.opacity(0.06)))
    }
}
