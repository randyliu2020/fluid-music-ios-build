import SwiftUI
import AVKit
import MediaPlayer
import UniformTypeIdentifiers

enum ArtworkCache {
    static let cache = NSCache<NSString, UIImage>()
    static func image(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let image = cache.object(forKey: url.path as NSString) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.countLimit = 80; cache.totalCostLimit = 60_000_000
        cache.setObject(image, forKey: url.path as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}
struct Artwork: View {
    var song: Song?
    var corner: CGFloat = 10
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = ArtworkCache.image(song?.artworkURL) { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.16, green: 0.39, blue: 0.42), Color(red: 0.08, green: 0.12, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: max(16, geometry.size.width * 0.36), weight: .light)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipShape(.rect(cornerRadius: corner)).accessibilityHidden(true)
    }
}

struct MusicBackdrop: View {
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if !reduceTransparency {
                if let image = ArtworkCache.image(player.song?.artworkURL) {
                    Image(uiImage: image).resizable().scaledToFill().blur(radius: 90).opacity(scheme == .dark ? 0.3 : 0.13)
                } else {
                    LinearGradient(colors: [.mint.opacity(0.13), .clear, .indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
struct MusicBackground: ViewModifier {
    func body(content: Content) -> some View { content.scrollContentBackground(.hidden).background { MusicBackdrop() } }
}
extension View { func musicBackground() -> some View { modifier(MusicBackground()) } }

struct SongRow: View {
    let song: Song
    let context: [Song]
    var playlistID: UUID? = nil
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @State private var addToPlaylist = false
    @State private var importLyrics = false
    @State private var confirmDelete = false
    var body: some View {
        HStack(spacing: 12) {
            Button { player.play(song, in: context) } label: {
                HStack(spacing: 12) {
                    Artwork(song: song).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song.title).font(.body.weight(player.song?.id == song.id ? .semibold : .regular))
                            .foregroundStyle(player.song?.id == song.id ? Color.mint : Color.primary).lineLimit(1)
                        Text(song.artist + " · " + song.album).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    if player.song?.id == song.id { Image(systemName: player.isPlaying ? "waveform" : "pause.fill").foregroundStyle(.mint).font(.caption) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("song-" + song.title)
            Menu {
                Button(library.data.favorites.contains(song.id) ? "取消喜欢" : "喜欢", systemImage: library.data.favorites.contains(song.id) ? "heart.slash" : "heart") { library.favorite(song) }
                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(song, next: true) }
                Button("加入队列", systemImage: "text.badge.plus") { player.enqueue(song, next: false) }
                Button("添加到歌单", systemImage: "music.note.list") { addToPlaylist = true }
                Button("导入歌词", systemImage: "text.bubble") { importLyrics = true }
                ShareLink(item: song.fileURL) { Label("分享音频", systemImage: "square.and.arrow.up") }
                if let playlistID { Button("从歌单移除", systemImage: "minus.circle", role: .destructive) { library.remove(song, from: playlistID) } }
                Button("删除导入的音频", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("\(song.title)的更多操作")
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading) {
            Button { library.favorite(song) } label: { Label("喜欢", systemImage: "heart.fill") }.tint(.pink)
        }
        .swipeActions(edge: .trailing) {
            if let playlistID { Button(role: .destructive) { library.remove(song, from: playlistID) } label: { Label("移除", systemImage: "minus.circle") } }
            else { Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") } }
        }
        .sheet(isPresented: $addToPlaylist) { AddToPlaylistView(song: song) }
        .fileImporter(isPresented: $importLyrics, allowedContentTypes: [.data, .plainText]) { result in
            if case .success(let url) = result { Task { await library.importLyrics(url, song: song) } }
            else if case .failure(let error) = result { library.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("删除“\(song.title)”？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除导入的音频", role: .destructive) { library.delete(song) }
        } message: { Text("将删除 App 内的音频副本，并从歌单和队列移除。原始导入位置的文件不受影响。") }
    }
}

struct MiniPlayer: View {
    var open: () -> Void
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 10) {
                        Artwork(song: player.song, corner: 8).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.song?.title ?? "流体音乐").font(.subheadline.weight(.medium)).lineLimit(1)
                            if placement != .inline { Text(player.song?.artist ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开正在播放").accessibilityIdentifier("openPlayer")
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(player.isPlaying ? "暂停" : "播放").accessibilityIdentifier("miniPlayPause")
                if placement != .inline {
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title3).frame(width: 36, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("下一首")
                }
            }.padding(.horizontal, 12).padding(.top, 5)
            if placement != .inline { SeekBar(compact: true).padding(.horizontal, 16).frame(height: 18) }
        }
    }
}

struct SeekBar: View {
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    @State private var dragging = false
    @State private var preview: Double = 0
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let fraction = max(0, min(1, (dragging ? preview : player.position) / max(1, player.duration)))
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule().fill(.primary.opacity(0.8)).frame(width: max(0, width * fraction))
                if let chorus = player.lyrics.chorus, player.duration > 0 {
                    Circle().fill(.mint).frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                        .offset(x: max(0, min(width - 7, width * chorus / player.duration - 3)))
                }
            }
            .frame(height: dragging ? (compact ? 6 : 10) : (compact ? 2 : 5))
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true; preview = max(0, min(1, value.location.x / width)) * player.duration
                }.onEnded { value in
                    let destination = max(0, min(1, value.location.x / width)) * player.duration
                    player.seek(to: destination); dragging = false
                })
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            .accessibilityElement().accessibilityLabel("播放进度")
            .accessibilityValue("\(timeText(player.position))，共 \(timeText(player.duration))")
            .accessibilityAdjustableAction { direction in
                player.seek(to: player.position + (direction == .increment ? 10 : -10))
            }
        }
        .frame(height: compact ? 18 : 44)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.tintColor = .label; view.activeTintColor = .systemMint
        view.prioritizesVideoDevices = false; return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { MPVolumeView(frame: .zero) }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct EmptyMusicView: View {
    var title = "把喜欢的音乐带进来"
    var message = "导入歌曲或整个文件夹。歌词与封面，一起留在本地。"
    var action: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "opticaldisc")
        } description: { Text(message) } actions: {
            if let action { Button("导入音乐", action: action).buttonStyle(.glassProminent).accessibilityIdentifier("importMusic") }
        }
    }
}
