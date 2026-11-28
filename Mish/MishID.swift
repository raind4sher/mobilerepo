import SwiftUI
import PhotosUI
import UIKit

// MARK: - Profile (stored on the device only)

final class MishProfile: ObservableObject {
    private enum Key {
        static let first = "mishID.firstName"
        static let user = "mishID.username"
    }

    private let defaults = UserDefaults.standard

    @Published var firstName: String {
        didSet { defaults.set(firstName, forKey: Key.first) }
    }

    @Published var username: String {
        didSet { defaults.set(username, forKey: Key.user) }
    }

    @Published var avatar: UIImage? {
        didSet { persistAvatar() }
    }

    var isSignedUp: Bool {
        !firstName.isEmpty && !username.isEmpty
    }

    init() {
        let d = UserDefaults.standard
        firstName = d.string(forKey: Key.first) ?? ""
        username = d.string(forKey: Key.user) ?? ""
        avatar = UIImage(contentsOfFile: Self.avatarURL.path)
    }

    /// Handy while developing: shows the mishID sign-up again.
    func signOut() {
        firstName = ""
        username = ""
        avatar = nil
    }

    // MARK: Avatar storage

    private static var avatarURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mishID-avatar.jpg")
    }

    private func persistAvatar() {
        let url = Self.avatarURL

        if let avatar, let data = avatar.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Keeps the saved picture small.
    static func downscaled(_ image: UIImage, maxSide: CGFloat = 600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }

        let scale = maxSide / longest
        let size = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Lowercase letters, numbers, dots and underscores only.
    static func cleanUsername(_ text: String) -> String {
        String(
            text.lowercased().filter {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_")
            }
        )
    }
}

// MARK: - Greeting

enum MishGreeting {
    /// "Hi(o)(u)" is a nod to underscores. Edit the spellings to taste.
    private static let hiVariants = ["Hi", "Hio", "Hiu", "Hiou"]

    static func text(for name: String, at date: Date = Date()) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)

        // About 1 in 4 launches gets the wildcard hello.
        if Int.random(in: 0..<4) == 0 {
            return "\(hiVariants.randomElement() ?? "Hi"), \(name)."
        }

        switch Calendar.current.component(.hour, from: date) {
        case 0..<5, 23: return "Up late, \(name)?"
        case 5..<12:    return "Morning, \(name)."
        case 12..<17:   return "Good afternoon, \(name)."
        default:        return "Evening, \(name)."
        }
    }
}

// MARK: - Avatar

struct MishAvatar: View {
    @EnvironmentObject private var profile: MishProfile
    var size: CGFloat

    var body: some View {
        Group {
            if let image = profile.avatar {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Shared form (photo + first name + username)

private struct MishIDForm: View {
    @EnvironmentObject private var profile: MishProfile

    @Binding var first: String
    @Binding var user: String

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 18) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    MishAvatar(size: 112)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 30, height: 30)
                        .background(Color.mishGreen, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose profile picture")
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }

                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        profile.avatar = MishProfile.downscaled(image)
                    }
                }
            }

            field("First name", text: $first)
                .textContentType(.givenName)

            field("Username", text: $user)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: user) { _, newValue in
                    let cleaned = MishProfile.cleanUsername(newValue)
                    if cleaned != newValue { user = cleaned }
                }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

// MARK: - Sign-up (shown once, right after setup)

struct MishIDSignUpView: View {
    @EnvironmentObject private var profile: MishProfile
    @EnvironmentObject private var settings: MishSettings

    let onContinue: () -> Void

    @State private var first = ""
    @State private var user = ""

    private var cleanFirst: String {
        first.trimmingCharacters(in: .whitespaces)
    }

    private var canContinue: Bool {
        !cleanFirst.isEmpty && !user.isEmpty
    }

    var body: some View {
        ZStack {
            MishBackdrop(theme: settings.baseTheme)

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Text("create your mishID")
                        .font(.custom("delagothicone-regular", size: 30))
                        .foregroundStyle(Color.white)

                    Text("Just for this device. Nothing gets uploaded.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                MishIDForm(first: $first, user: $user)

                Button {
                    MishHaptics.tap()
                    profile.firstName = cleanFirst
                    profile.username = user
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.mishGreen, in: Capsule())
                        .opacity(canContinue ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Edit profile (opens from the avatar in Library)

struct MishIDEditSheet: View {
    @EnvironmentObject private var profile: MishProfile
    @Environment(\.dismiss) private var dismiss

    @State private var first = ""
    @State private var user = ""

    private var cleanFirst: String {
        first.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !cleanFirst.isEmpty && !user.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                MishIDForm(first: $first, user: $user)
                    .padding(24)
            }
            .navigationTitle("Your mishID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.firstName = cleanFirst
                        profile.username = user
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                first = profile.firstName
                user = profile.username
            }
        }
        .preferredColorScheme(.dark)
    }
}
