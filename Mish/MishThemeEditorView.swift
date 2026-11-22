import SwiftUI
import PhotosUI

// MARK: - Theme list

struct MishThemeEditorView: View {
    @EnvironmentObject private var themeStore: MishThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingTheme: MishTheme?
    @State private var showDeleteConfirmation = false
    @State private var themePendingDeletion: UUID?

    var body: some View {
        NavigationStack {
            List {
                themesSection
                createSection
            }
            .navigationTitle("Theme Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingTheme) { theme in
                MishThemeDetailEditor(theme: theme)
                    .environmentObject(themeStore)
            }
            .confirmationDialog(
                "Delete this theme?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Theme", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    themePendingDeletion = nil
                }
            } message: {
                Text("This removes the theme and its saved background image.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var themesSection: some View {
        Section {
            ForEach(themeStore.themes) { theme in
                themeButton(theme)
            }
        } header: {
            Text("Your themes")
        } footer: {
            Text("Choose a theme to make it active, then customize its colors, background, blur, and motion.")
        }
    }

    private var createSection: some View {
        Section {
            Button {
                createTheme()
            } label: {
                Label("Create a theme", systemImage: "plus.circle.fill")
                    .foregroundStyle(themeStore.activeTheme.accentColor)
            }
        }
    }

    private func themeButton(_ theme: MishTheme) -> some View {
        let isActive = themeStore.activeThemeID == theme.id

        return Button {
            themeStore.select(theme.id)
            editingTheme = theme
        } label: {
            MishThemeRow(theme: theme, isActive: isActive)
        }
        .buttonStyle(.plain)
        .swipeActions {
            if themeStore.themes.count > 1 {
                Button(role: .destructive) {
                    themePendingDeletion = theme.id
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Actions

    private func createTheme() {
        let id = themeStore.createTheme()
        editingTheme = themeStore.themes.first { $0.id == id }
    }

    private func confirmDelete() {
        if let id = themePendingDeletion {
            themeStore.delete(id)
        }
        themePendingDeletion = nil
    }
}

private struct MishThemeRow: View {
    let theme: MishTheme
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            MishThemeSwatches(theme: theme)

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(theme.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accentColor)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct MishThemeSwatches: View {
    let theme: MishTheme

    var body: some View {
        HStack(spacing: 0) {
            theme.backgroundColor
            theme.accentColor
            theme.mainColor
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}

// MARK: - Detail editor

private struct MishThemeDetailEditor: View {
    @EnvironmentObject private var themeStore: MishThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var theme: MishTheme
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSavingPhoto = false

    init(theme: MishTheme) {
        _theme = State(initialValue: theme)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                colorsSection
                pictureSection
                blurSection
                tintSection
                motionSection
                previewSection
            }
            .navigationTitle("Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // One autosave for every control (MishTheme is Equatable).
            .onChange(of: theme) { _, newValue in
                themeStore.update(newValue)
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await importPhoto(item) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var nameSection: some View {
        Section("Theme name") {
            TextField("Give your theme a name", text: $theme.name)
        }
    }

    private var colorsSection: some View {
        Section {
            MishColorRow(title: "Accent color", hex: $theme.accentHex)
            MishColorRow(title: "Main color", hex: $theme.mainHex)
            MishColorRow(title: "Background color", hex: $theme.backgroundHex)
        } header: {
            Text("Colors")
        } footer: {
            Text("Accent is used for highlights and selected states. Main is the primary text and control color.")
        }
    }

    private var pictureSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(pictureButtonTitle, systemImage: "photo.on.rectangle.angled")
            }
            .disabled(isSavingPhoto)

            if isSavingPhoto {
                ProgressView("Saving picture…")
            }

            if theme.backgroundImageFilename != nil {
                Button(role: .destructive) {
                    removePicture()
                } label: {
                    Label("Remove background picture", systemImage: "trash")
                }
            }
        } header: {
            Text("Background picture")
        } footer: {
            Text("Your selected image is copied into Mish's private app storage, so it remains available offline.")
        }
    }

    private var blurSection: some View {
        Section {
            Toggle("Enable theme blur", isOn: $theme.blurEnabled)

            MishSliderRow(
                title: "Blur amount",
                valueText: blurText,
                value: $theme.blurRadius,
                range: 0...100,
                step: 1
            )
            .disabled(!theme.blurEnabled)

            Toggle("Override album-art blur", isOn: $theme.overridesAlbumArtBlur)
        } header: {
            Text("Blur")
        } footer: {
            Text("When override is enabled, this theme's blur amount replaces the normal album-art background blur setting.")
        }
    }

    private var tintSection: some View {
        Section("Background tint") {
            MishSliderRow(
                title: "Tint strength",
                valueText: tintText,
                value: $theme.overlayOpacity,
                range: 0...0.9,
                step: 0.01
            )
        }
    }

    private var motionSection: some View {
        Section("Animation") {
            Picker("Background motion", selection: $theme.motion) {
                ForEach(MishTheme.BackgroundMotion.allCases) { motion in
                    Text(motion.title).tag(motion)
                }
            }

            Text(theme.motion.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Section {
            MishThemePreviewCard(theme: theme)
                .listRowInsets(EdgeInsets())
        } header: {
            Text("Preview")
        }
    }

    // MARK: Display strings

    private var pictureButtonTitle: String {
        theme.backgroundImageFilename == nil ? "Choose a picture" : "Replace picture"
    }

    private var blurText: String {
        String(Int(theme.blurRadius))
    }

    private var tintText: String {
        let percent = Int(theme.overlayOpacity * 100)
        return "\(percent)%"
    }

    // MARK: Actions

    private func removePicture() {
        themeStore.clearBackgroundImage(for: theme.id)
        theme.backgroundImageFilename = nil
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isSavingPhoto = true
        defer {
            isSavingPhoto = false
            selectedPhoto = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard themeStore.setBackgroundImage(data, for: theme.id) else { return }

        // The store picked a new filename; pull it into our local copy.
        let updated = themeStore.themes.first { $0.id == theme.id }
        theme.backgroundImageFilename = updated?.backgroundImageFilename
    }
}

// MARK: - Small reusable rows

private struct MishColorRow: View {
    let title: String
    @Binding var hex: UInt32

    private var colorBinding: Binding<Color> {
        Binding<Color>(
            get: { Color(mishHex: hex) },
            set: { newColor in hex = newColor.mishHex }
        )
    }

    var body: some View {
        ColorPicker(title, selection: colorBinding, supportsOpacity: false)
    }
}

private struct MishSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct MishThemePreviewCard: View {
    let theme: MishTheme

    private var gradientColors: [Color] {
        [theme.backgroundColor, theme.backgroundColor.opacity(0.68)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Text("mish")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.mainColor)

                Text("NOW PLAYING")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(theme.accentColor)

                Capsule()
                    .fill(theme.accentColor)
                    .frame(width: 90, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
    }
}
