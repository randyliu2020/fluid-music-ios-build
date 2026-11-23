import SwiftUI
import UniformTypeIdentifiers

@main struct FluidMusicApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlaybackController.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "深色"
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(player)
                .preferredColorScheme(appearance == "跟随系统" ? nil : appearance == "浅色" ? .light : .dark)
                .tint(.mint)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing") { await UITestSeed.prepare() }
                    #endif
                }
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { player.save(); library.persist() }
        }
    }
}

enum MainTab: Hashable { case library, favorites, playlists, search, settings }

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @State private var tab = MainTab.library
    @State private var showPlayer = false
    @State private var importing = false
    @State private var importFolder = false
    var body: some View {
        TabView(selection: $tab) {
            Tab("音乐库", systemImage: "music.note.house", value: .library) {
                NavigationStack { LibraryView(importFiles: { importing = true }, importFolder: { importFolder = true }) }
            }
            Tab("喜欢", systemImage: "heart", value: .favorites) {
                NavigationStack { SongListView(title: "我喜欢", songs: library.songs.filter { library.data.favorites.contains($0.id) }, emptyMessage: "轻点歌曲旁的爱心，将喜欢的音乐留在这里。") }
            }
            Tab("歌单", systemImage: "music.note.list", value: .playlists) {
                NavigationStack { PlaylistsView() }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack { SearchView() }
            }
            Tab("设置", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView(importFiles: { importing = true }, importFolder: { importFolder = true }) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory(isEnabled: player.song != nil) {
            MiniPlayer(open: { showPlayer = true })
        }
        .sheet(isPresented: $showPlayer) { NowPlayingView().presentationDragIndicator(.visible) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .data], allowsMultipleSelection: true) { result in handleImport(result) }
        .fileImporter(isPresented: $importFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in handleImport(result) }
        .alert("导入完成", isPresented: Binding(get: { library.importMessage != nil }, set: { if !$0 { library.importMessage = nil } })) {
            Button("好") { library.importMessage = nil }
        } message: { Text(library.importMessage ?? "") }
        .alert("需要处理", isPresented: Binding(get: { library.errorMessage != nil || player.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil; player.errorMessage = nil } })) {
            Button("好") { library.errorMessage = nil; player.errorMessage = nil }
        } message: { Text(library.errorMessage ?? player.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if library.isImporting {
                HStack(spacing: 12) { ProgressView(); Text("正在导入音乐…").font(.subheadline) }
                    .padding().glassEffect(in: .capsule).padding(.top, 8).accessibilityIdentifier("importProgress")
            }
        }
        .onOpenURL { url in
            if url.isFileURL { Task { await library.importURLs([url]) } }
            else if url.scheme == "fluidmusic" { showPlayer = true }
        }
    }
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls): Task { await library.importURLs(urls) }
        case .failure(let error): library.errorMessage = error.localizedDescription
        }
    }
}
