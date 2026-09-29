import SwiftUI

/// Figma: "Invite Friends". Contacts list with per-row invite.
struct InviteFriendsView: View {
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}
    @Environment(\.dwell) private var t
    @State private var search = ""
    @State private var invited: Set<String> = []

    private struct Contact: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let avatar: Int
    }

    private let contacts: [Contact] = [
        .init(name: "Daniel Osei", avatar: 1),
        .init(name: "Priya Sharma", avatar: 2),
        .init(name: "Jordan Reyes", avatar: 3),
        .init(name: "Will Saleh", avatar: 4),
        .init(name: "Madison Austin", avatar: 5),
        .init(name: "Gabi Fjellman", avatar: 6)
    ]

    private var filtered: [Contact] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 260, fadeFrom: 0.2)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeader(progress: 0.84, onBack: onBack)

                Text("Invite friends")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
                    .padding(.top, Space.lg)

                selectedRow

                searchField.padding(.top, Space.lg)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { contact in
                            row(contact)
                            if contact.id != filtered.last?.id {
                                Rectangle().fill(t.border).frame(height: 1)
                            }
                        }
                    }
                    .padding(.top, Space.sm)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                PrimaryButton(title: invited.isEmpty ? "Skip for now" : "Continue", action: onNext)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
    }

    @ViewBuilder
    private var selectedRow: some View {
        if !invited.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: Space.md) {
                    ForEach(contacts.filter { invited.contains($0.name) }) { contact in
                        VStack(spacing: 6) {
                            PhotoAvatar(name: contact.name, index: contact.avatar, size: 52)
                            Text(contact.name.split(separator: " ").first.map(String.init) ?? "")
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                        }
                    }
                }
                .padding(.vertical, Space.md)
            }
            .scrollIndicators(.hidden)
            .transition(.opacity)
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(t.textSecondary)
            TextField("Search", text: $search)
                .font(.dwellBody)
                .textFieldStyle(.plain)
                .foregroundStyle(t.textPrimary)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 14)
        .background(t.surfaceRaised)
        .clipShape(Capsule())
    }

    private func row(_ contact: Contact) -> some View {
        let isInvited = invited.contains(contact.name)
        return HStack(spacing: Space.md) {
            PhotoAvatar(name: contact.name, index: contact.avatar, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name)
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                Text("From your contacts")
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer()
            Button {
                Haptics.select()
                withAnimation(.easeOut(duration: 0.2)) {
                    if isInvited { invited.remove(contact.name) } else { invited.insert(contact.name) }
                }
            } label: {
                Text(isInvited ? "Invited" : "Invite")
                    .font(.dwellCaptionMd)
                    .foregroundStyle(isInvited ? t.onInk : t.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(isInvited ? t.ink : .clear)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(isInvited ? .clear : t.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(PressScale())
        }
        .padding(.vertical, Space.md)
    }
}

#Preview { InviteFriendsView() }
