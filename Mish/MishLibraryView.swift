import SwiftUI
import PhotosUI

// MARK: - Shared bits

private func mishMuted(_ special: Bool) -> Color {
    special ? Color.black.opacity(0.58) : Color.mishDim
}

private func mishSongCount(_ count: Int) -> String {
    count == 1 ? "1 song" : "\(count) songs"
}

/// Square artwork with a tidy placeholder. Pass `size: nil` to fill the width it is given.
struct MishArtTile: View {
    let image: UIImage?
    var symbol: String? = nil
    var size: CGFloat? = nil
    var corner: CGFloat = 6

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { artContent }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .frame(width: size)
    }

    @ViewBuilder
    private var artContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholderColors: [Color] {
        [Color(hex: 0x353639), Color(hex: 0x252629)]
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: placeholderColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: (size ?? 120) * 0.38))
                    .foregroundStyle(Color(hex: 0xC9C9CD))
            } else {
                Text("m")
                    .font(.custom("delagothicone-regular", size: (size ?? 120) * 0.5))
                    .foregroundStyle(Color(hex: 0xC9C9CD))
            }
        }
    }
}

/// A playlist's cover: its custom picture, else the first song's art, else a placeholder.
struct MishPlaylistArt: View {
    @EnvironmentObject private var player: PlayerModel

    let playlist: MishPlaylist
    var size: CGFloat? = nil
    var corner: CGFloat = 6

    private var image: UIImage? {
        if let custom = player.playlistCover(for: playlist) {
            return custom
        }

        for path in playlist.trackPaths.prefix(8) {
            let match = player.tracks.first {
                $0.url.standardizedFileURL.absoluteString == path
            }
            if let art = match?.artwork {
                return art
            }
        }
        return nil
    }

    var body: some View {
        MishArtTile(image: image, symbol: "music.note.list", size: size, corner: corner)
    }
}

// MARK: - Albums

struct MishAlbumGroup: Identifiable {
    let id: String
    let title: String
    let artist: String
    let artwork: UIImage?
    let tracks: [Track]

    var subtitle: String { "Album · \(artist)" }

    private struct Builder {
        var title: String
        var artist: String
        var artwork: UIImage?
        var tracks: [Track]
    }

    /// Groups songs into albums, keeping the order albums first appear in the library.
    static func groups(from tracks: [Track]) -> [MishAlbumGroup] {
        var order: [String] = []
        var builders: [String: Builder] = [:]

        for track in tracks {
            let albumName = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let artistName = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)

            let title = albumName.isEmpty ? "Unknown Album" : albumName
            let artist = artistName.isEmpty ? "Unknown Artist" : artistName
            let key = "\(artist)\u{1F}\(title)"

            if var builder = builders[key] {
                if builder.artwork == nil {
                    builder.artwork = track.artwork
                }
                builder.tracks.append(track)
                builders[key] = builder
            } else {
                order.append(key)
                builders[key] = Builder(
                    title: title,
                    artist: artist,
                    artwork: track.artwork,
                    tracks: [track]
                )
            }
        }

        var result: [MishAlbumGroup] = []
        for key in order {
            guard let builder = builders[key] else { continue }
            result.append(
                MishAlbumGroup(
                    id: key,
                    title: builder.title,
                    artist: builder.artist,
                    artwork: builder.artwork,
                    tracks: builder.tracks
                )
            )
        }
        return result
    }
}

// MARK: - Library (root)

enum MishLibrarySection: String, CaseIterable, Identifiable {
    case albums, playlists, songs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: return "Albums"
        case .playlists: return "Playlists"
        case .songs: return "Songs"
        }
    }
}

private enum MishLibraryDestination: Hashable {
    case album(String)
    case playlist(UUID)
}

struct MishLibraryView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var profile: MishProfile
    @AppStorage("mishLibraryGrid") private var gridLayout = false
    @State private var greeting = ""
    @State private var showProfile = false

    @State private var section: MishLibrarySection = .albums
    @State private var destination: MishLibraryDestination?
    @State private var showCreate = false

    private var muted: Color { mishMuted(player.isUnderscoresMode) }

    var body: some View {
        ZStack {
            if let destination {
                detailView(for: destination)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                rootView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: destination)
        .onAppear {
            greeting = MishGreeting.text(for: profile.firstName)
        }
        .sheet(isPresented: $showProfile) {
            MishIDEditSheet()
                .environmentObject(profile)
        }
        .sheet(isPresented: $showCreate) {
            MishPlaylistEditorSheet(mode: .create) { newID in
                section = .playlists
                destination = .playlist(newID)
            }
            .environmentObject(player)
        }
    }

    // MARK: Detail routing

    @ViewBuilder
    private func detailView(for destination: MishLibraryDestination) -> some View {
        switch destination {
        case .album(let id):
            MishAlbumDetailView(albumID: id, onBack: goBack)
        case .playlist(let id):
            MishPlaylistDetailView(playlistID: id, onBack: goBack)
        }
    }

    private func goBack() {
        destination = nil
    }

    // MARK: Root

    private var rootView: some View {
        VStack(spacing: 0) {
            headerRow
            chipRow
            sectionContent
        }
    }

    private var headerRow: some View {
        HStack {
            Text(greeting.isEmpty ? "Your Library" : greeting)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                showProfile = true
            } label: {
                MishAvatar(size: 32)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit mishID")

            Button {
                showCreate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New playlist")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(MishLibrarySection.allCases) { item in
                MishChip(title: item.title, selected: item == section) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        section = item
                    }
                }
            }

            Spacer(minLength: 0)

            if section == .albums {
                Button {
                    gridLayout.toggle()
                } label: {
                    Image(systemName: gridLayout ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(gridLayout ? "Show as list" : "Show as grid")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .albums:
            albumsContent
        case .playlists:
            playlistsContent
        case .songs:
            songsContent
        }
    }

    // MARK: Albums

    @ViewBuilder
    private var albumsContent: some View {
        let items = MishAlbumGroup.groups(from: player.tracks)

        if items.isEmpty {
            MishLibraryEmpty(
                symbol: "square.stack",
                title: "No albums yet",
                message: "Add some music to start your collection."
            )
        } else if gridLayout {
            albumGrid(items)
        } else {
            albumList(items)
        }
    }

    private func albumList(_ items: [MishAlbumGroup]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(items) { album in
                    Button {
                        destination = .album(album.id)
                    } label: {
                        MishAlbumRow(album: album, muted: muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func albumGrid(_ items: [MishAlbumGroup]) -> some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]

        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { album in
                    Button {
                        destination = .album(album.id)
                    } label: {
                        MishAlbumCell(album: album, muted: muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: Playlists

    private var playlistsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                Button {
                    showCreate = true
                } label: {
                    MishNewPlaylistRow()
                }
                .buttonStyle(.plain)

                ForEach(player.playlists) { playlist in
                    Button {
                        destination = .playlist(playlist.id)
                    } label: {
                        MishPlaylistRow(playlist: playlist, muted: muted)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            player.deletePlaylist(id: playlist.id)
                        } label: {
                            Label("Delete playlist", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: Songs

    private var songsContent: some View {
        TrackList(
            tracks: player.tracks,
            onSelect: { track in
                if let index = player.tracks.firstIndex(of: track) {
                    player.play(index: index)
                }
            },
            onRemove: player.removeFromLibrary,
            allowsPlaylistAdd: true
        )
    }
}

// MARK: - Root rows

private struct MishChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundColor(selected ? Color(hex: 0x121812) : nil)
                .background(Capsule().fill(fillColor))
        }
        .buttonStyle(.plain)
    }

    private var fillColor: Color {
        selected ? Color.mishGreen : Color.white.opacity(0.14)
    }
}

private struct MishAlbumRow: View {
    let album: MishAlbumGroup
    let muted: Color

    var body: some View {
        HStack(spacing: 12) {
            MishArtTile(image: album.artwork, size: 56, corner: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(album.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct MishAlbumCell: View {
    let album: MishAlbumGroup
    let muted: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MishArtTile(image: album.artwork, corner: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 12))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MishPlaylistRow: View {
    let playlist: MishPlaylist
    let muted: Color

    var body: some View {
        HStack(spacing: 12) {
            MishPlaylistArt(playlist: playlist, size: 56, corner: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("Playlist · \(mishSongCount(playlist.trackCount))")
                    .font(.system(size: 12))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct MishNewPlaylistRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
            }
            .frame(width: 56, height: 56)

            Text("New playlist")
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct MishLibraryEmpty: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundColor(.mishDim)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.mishDim)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail pieces

private struct MishBackButton: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                Text("Library")
                    .font(.system(size: 15, weight: .medium))
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to library")
    }
}

private struct MishPlayShuffleRow: View {
    let canPlay: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            pill(title: "Play", symbol: "play.fill", filled: true, action: onPlay)
            pill(title: "Shuffle", symbol: "shuffle", filled: false, action: onShuffle)
        }
        .disabled(!canPlay)
        .opacity(canPlay ? 1 : 0.45)
    }

    private func pill(
        title: String,
        symbol: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let fill: Color = filled ? Color.mishGreen : Color.white.opacity(0.14)

        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .foregroundColor(filled ? Color(hex: 0x121812) : nil)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album detail

private struct MishAlbumDetailView: View {
    @EnvironmentObject private var player: PlayerModel

    let albumID: String
    let onBack: () -> Void

    private var album: MishAlbumGroup? {
        MishAlbumGroup.groups(from: player.tracks).first { $0.id == albumID }
    }

    private var muted: Color { mishMuted(player.isUnderscoresMode) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MishBackButton(onBack: onBack)
                Spacer()
            }
            .padding(.horizontal, 16)

            if let album {
                content(album)
            } else {
                MishLibraryEmpty(
                    symbol: "square.stack",
                    title: "Album not found",
                    message: "It may have been removed from your library."
                )
            }
        }
    }

    private func content(_ album: MishAlbumGroup) -> some View {
        VStack(spacing: 14) {
            header(album)

            MishPlayShuffleRow(
                canPlay: !album.tracks.isEmpty,
                onPlay: { player.playTracks(album.tracks) },
                onShuffle: {
                    player.shuffleOn = true
                    player.playTracks(album.tracks, startingAt: album.tracks.randomElement())
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            TrackList(
                tracks: album.tracks,
                onSelect: { track in
                    player.playTracks(album.tracks, startingAt: track)
                },
                onRemove: player.removeFromLibrary,
                allowsPlaylistAdd: true
            )
        }
    }

    private func header(_ album: MishAlbumGroup) -> some View {
        HStack(spacing: 14) {
            MishArtTile(image: album.artwork, size: 112, corner: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 14))
                    .foregroundColor(muted)
                    .lineLimit(1)
                Text("Album · \(mishSongCount(album.tracks.count))")
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Playlist detail

private struct MishPlaylistDetailView: View {
    @EnvironmentObject private var player: PlayerModel

    let playlistID: UUID
    let onBack: () -> Void

    @State private var editMode: EditMode = .inactive
    @State private var showEditor = false
    @State private var showAddSongs = false
    @State private var confirmDelete = false

    init(playlistID: UUID, onBack: @escaping () -> Void) {
        self.playlistID = playlistID
        self.onBack = onBack
    }

    private var playlist: MishPlaylist? {
        player.playlists.first { $0.id == playlistID }
    }

    private var muted: Color { mishMuted(player.isUnderscoresMode) }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let playlist {
                content(playlist)
            } else {
                MishLibraryEmpty(
                    symbol: "music.note.list",
                    title: "Playlist not found",
                    message: "This playlist may have been deleted."
                )
            }
        }
        .sheet(isPresented: $showEditor) {
            MishPlaylistEditorSheet(mode: .edit(playlistID))
                .environmentObject(player)
        }
        .sheet(isPresented: $showAddSongs) {
            MishAddSongsSheet(playlistID: playlistID)
                .environmentObject(player)
        }
        .confirmationDialog(
            "Delete this playlist?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                player.deletePlaylist(id: playlistID)
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your songs stay in your library.")
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            MishBackButton(onBack: onBack)
            Spacer()

            Menu {
                Button {
                    showAddSongs = true
                } label: {
                    Label("Add songs", systemImage: "plus")
                }

                Button {
                    showEditor = true
                } label: {
                    Label("Edit name & cover", systemImage: "photo")
                }

                Button {
                    toggleReorder()
                } label: {
                    Label(
                        editMode.isEditing ? "Done reordering" : "Reorder songs",
                        systemImage: "arrow.up.arrow.down"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete playlist", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playlist options")
        }
        .padding(.horizontal, 16)
    }

    private func content(_ playlist: MishPlaylist) -> some View {
        VStack(spacing: 14) {
            header(playlist)
            actionRow(playlist)
            trackList(playlist)
        }
    }

    private func header(_ playlist: MishPlaylist) -> some View {
        HStack(spacing: 14) {
            MishPlaylistArt(playlist: playlist, size: 112, corner: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                Text("Playlist · \(mishSongCount(playlist.trackCount))")
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func actionRow(_ playlist: MishPlaylist) -> some View {
        HStack(spacing: 10) {
            MishPlayShuffleRow(
                canPlay: !playlist.trackPaths.isEmpty,
                onPlay: { player.playPlaylist(id: playlistID) },
                onShuffle: {
                    player.shuffleOn = true
                    player.playPlaylist(
                        id: playlistID,
                        startingAt: playlist.trackPaths.randomElement()
                    )
                }
            )

            Spacer(minLength: 0)

            Button {
                showAddSongs = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color.mishGreen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add songs")
        }
        .padding(.horizontal, 20)
    }

    private func trackList(_ playlist: MishPlaylist) -> some View {
        List {
            if playlist.trackPaths.isEmpty {
                emptyHint
            }

            ForEach(Array(playlist.trackPaths.enumerated()), id: \.offset) { _, path in
                MishPlaylistTrackRow(path: path) {
                    player.playPlaylist(id: playlistID, startingAt: path)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            }
            .onMove { source, destination in
                player.reorderPlaylist(id: playlistID, from: source, to: destination)
            }
            .onDelete { offsets in
                removeRows(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
    }

    private var emptyHint: some View {
        Text("This playlist is empty. Tap + to add songs from your library.")
            .font(.system(size: 13))
            .foregroundColor(muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: Actions

    private func toggleReorder() {
        withAnimation {
            editMode = editMode.isEditing ? .inactive : .active
        }
    }

    private func removeRows(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            player.removeFromPlaylist(id: playlistID, at: index)
        }
    }
}

private struct MishPlaylistTrackRow: View {
    @EnvironmentObject private var player: PlayerModel

    let path: String
    let onPlay: () -> Void

    private var track: Track? {
        player.tracks.first { $0.url.standardizedFileURL.absoluteString == path }
    }

    var body: some View {
        if let track {
            Button(action: onPlay) {
                TrackRow(
                    track: track,
                    badge: "",
                    highlighted: track == player.currentTrack
                )
            }
            .buttonStyle(.plain)
        } else {
            missingRow
        }
    }

    private var missingRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle")
                .frame(width: 39, height: 39)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(string: path)?.lastPathComponent ?? path)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("File unavailable in library")
                    .font(.system(size: 10))
                    .foregroundColor(.mishDim)
            }

            Spacer(minLength: 0)
        }
        .opacity(0.7)
    }
}

// MARK: - Create / edit sheet (name + cover picture)

struct MishPlaylistEditorSheet: View {
    enum Mode {
        case create
        case edit(UUID)
    }

    let mode: Mode
    let onCreated: ((UUID) -> Void)?

    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var newCoverData: Data?
    @State private var previewImage: UIImage?
    @State private var removeCover = false
    @State private var didLoad = false

    init(mode: Mode, onCreated: ((UUID) -> Void)? = nil) {
        self.mode = mode
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                coverSection

                Section("Name") {
                    TextField("Playlist name", text: $name)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { loadExisting() }
            .onChange(of: pickerItem) { _, item in
                Task { await loadPicked(item) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    private var coverSection: some View {
        Section {
            VStack(spacing: 12) {
                MishArtTile(
                    image: displayedCover,
                    symbol: "music.note.list",
                    size: 160,
                    corner: 12
                )

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(
                        displayedCover == nil ? "Choose cover" : "Change cover",
                        systemImage: "photo"
                    )
                }

                if displayedCover != nil {
                    Button("Remove cover", role: .destructive) {
                        clearCover()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } footer: {
            Text("Pick any picture from your photos. Without one, the playlist shows its first song's art.")
        }
    }

    // MARK: State helpers

    private var screenTitle: String {
        switch mode {
        case .create: return "New Playlist"
        case .edit: return "Edit Playlist"
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var existingPlaylist: MishPlaylist? {
        switch mode {
        case .create:
            return nil
        case .edit(let id):
            return player.playlists.first { $0.id == id }
        }
    }

    private var displayedCover: UIImage? {
        if let previewImage { return previewImage }
        if removeCover { return nil }
        guard let existing = existingPlaylist else { return nil }
        return player.playlistCover(for: existing)
    }

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .create:
            name = "My Playlist \(player.playlists.count + 1)"
        case .edit:
            name = existingPlaylist?.name ?? ""
        }
    }

    private func clearCover() {
        newCoverData = nil
        previewImage = nil
        removeCover = true
    }

    @MainActor
    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { pickerItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        newCoverData = data
        previewImage = image.mishScaledToFit(maxDimension: 800)
        removeCover = false
    }

    private func save() {
        switch mode {
        case .create:
            if let id = player.createPlaylist(name: trimmedName, coverData: newCoverData) {
                onCreated?(id)
            }

        case .edit(let id):
            player.renamePlaylist(id: id, name: trimmedName)

            if let data = newCoverData {
                player.setPlaylistCover(id: id, data: data)
            } else if removeCover {
                player.clearPlaylistCover(id: id)
            }
        }

        dismiss()
    }
}

// MARK: - Add songs sheet

private struct MishAddSongsSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    @State private var query = ""

    init(playlistID: UUID) {
        self.playlistID = playlistID
    }

    private var playlist: MishPlaylist? {
        player.playlists.first { $0.id == playlistID }
    }

    private var filtered: [Track] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return player.tracks }

        return player.tracks.filter { track in
            track.title.lowercased().contains(needle)
                || track.artist.lowercased().contains(needle)
        }
    }

    private func isAdded(_ track: Track) -> Bool {
        let path = track.url.standardizedFileURL.absoluteString
        return playlist?.trackPaths.contains(path) ?? false
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { track in
                    MishAddSongRow(track: track, added: isAdded(track)) {
                        player.addToPlaylist(id: playlistID, track: track)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search your library")
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MishAddSongRow: View {
    let track: Track
    let added: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MishArtTile(image: track.artwork, size: 44, corner: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? Color.green : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(added)
    }
}
