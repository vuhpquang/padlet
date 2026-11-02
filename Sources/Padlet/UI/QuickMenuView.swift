// UI/QuickMenuView.swift
// The top of the right-click menu: app header with the master switch, then one switch
// per gesture family — flip things without opening the panel. Hosted in an NSMenuItem.

import SwiftUI

struct QuickMenuView: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var granted = PermissionsManager.isAccessibilityGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: padletIcon)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Padlet").font(.system(size: 13.5, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(statusText).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                SwitchToggle(isOn: $prefs.flags.masterEnabled)
            }
            .padding(.bottom, 10)

            VStack(spacing: 7) {
                QuickToggle(icon: "rectangle.portrait.lefthalf.inset.filled", title: "Edge Controls",
                            isOn: $prefs.flags.edgeControls)
                ForEach(GestureFamily.allCases, id: \.self) { family in
                    QuickToggle(icon: Theme.symbol(for: family), title: Theme.title(for: family),
                                isOn: binding(family))
                }
                QuickToggle(icon: "square.stack.3d.up.fill", title: "App Profiles", isOn: $prefs.flags.appProfiles)
            }
            .disabled(!prefs.flags.masterEnabled)
            .opacity(prefs.flags.masterEnabled ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(width: 272)
        .tint(Theme.accent)
        .onAppear { granted = PermissionsManager.isAccessibilityGranted() }
    }

    private var statusColor: Color {
        !granted ? .orange : (prefs.flags.masterEnabled ? .green : .secondary)
    }

    private var statusText: String {
        !granted ? "Needs Accessibility" : (prefs.flags.masterEnabled ? "Ready" : "All gestures off")
    }

    private func binding(_ family: GestureFamily) -> Binding<Bool> {
        switch family {
        case .threeFinger: return $prefs.flags.threeFinger
        case .fourFinger: return $prefs.flags.fourFinger
        case .cornerForceClick: return $prefs.flags.cornerForceClick
        case .topEdge: return $prefs.flags.topEdge
        case .twoFingerEdgeSwipe: return $prefs.flags.twoFingerEdgeSwipe
        case .threeFingerEdgeSwipe: return $prefs.flags.threeFingerEdgeSwipe
        }
    }
}

private struct QuickToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Theme.accent : Color.primary.opacity(0.09))
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(isOn ? .white : .primary.opacity(0.7))
            }
            .frame(width: 22, height: 22)
            Text(title).font(.system(size: 12.5))
            Spacer()
            SwitchToggle(isOn: $isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
