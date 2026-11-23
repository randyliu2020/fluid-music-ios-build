import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    var importFiles: () -> Void
    var importFolder: () -> Void
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FLUID MUSIC").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(.mint)
                    Text("音乐，回到纯粹。").font(.largeTitle.weight(.bold))
                    Text("\(library.songs.count) 首珍藏 · 纯本地聆听").font(.subheadline).foregroundStyle(.secondary)
                    if !library.songs.isEmpty {
                        HStack(spacing: 12) {
                            Button("播放全部", systemImage: "play.fill") { if let song = library.songs.first { player.play(song, in: library.songs) } }
                                .buttonStyle(.glassProminent)
                            Button("随机", systemImage: "shuffle") {
                                if !player.shuffled { player.toggleShuffle() }
                                if let song = library.songs.randomElement() { player.play(song, in: library.songs) }
                            }.buttonStyle(.glass)
                        }.padding(.top, 8)
                    }
                }.padding(.vertical, 14)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if library.songs.isEmpty {
                EmptyMusicView(action: importFiles).listRowBackground(Color.clear)
            } else {
                Section("浏览音乐") {
                    NavigationLink { SongListView(title: "全部歌曲", songs: library.songs, showIndex: true) } label: { category("歌曲", icon: "music.note", count: library.songs.count) }
                        .accessibilityIdentifier("browseSongs")
                    NavigationLink { CollectionsView(kind: .album) } label: { category("专辑", icon: "square.stack", count: Set(library.songs.map(\.album)).count) }
                    NavigationLink { CollectionsView(kind: .artist) } label: { category("艺术家", icon: "person.2", count: Set(library.songs.map(\.artist)).count) }
                    NavigationLink { CollectionsView(kind: .folder) } label: { category("文件夹", icon: "folder", count: library.allFolders.count) }
                }
                Section("最近添加") {
                    ForEach(Array(library.data.songs.filter { !library.data.excludedFolders.contains($0.folder) }.sorted { $0.addedAt > $1.addedAt }.prefix(8))) { song in
                        SongRow(song: song, context: library.songs)
                    }
                }
            }
        }
        .musicBackground().navigationTitle("音乐库").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("导入歌曲与歌词", systemImage: "doc.badge.plus", action: importFiles)
                    Button("导入文件夹", systemImage: "folder.badge.plus", action: importFolder)
                    Button("重新扫描", systemImage: "arrow.clockwise") { Task { await library.rescan() } }
                } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                    .disabled(library.isImporting).accessibilityLabel("导入音乐")
            }
        }
    }
    private func category(_ name: String, icon: String, count: Int) -> some View {
        HStack { Label(name, systemImage: icon).labelStyle(.titleAndIcon); Spacer(); Text("\(count)").foregroundStyle(.secondary).font(.subheadline) }.padding(.vertical, 5)
    }
}

struct SongListView: View {
    var title: String
    var songs: [Song]
    var playlistID: UUID? = nil
    var showIndex = false
    var emptyMessage = "这里还没有歌曲。请从音乐库导入，或将歌曲添加到这里。"
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @State private var query = ""
    private var filtered: [Song] { query.isEmpty ? songs : songs.filter { $0.searchText.localizedCaseInsensitiveContains(query) || Song.sortKey($0.searchText).contains(Song.sortKey(query)) } }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !filtered.isEmpty {
                    Section {
                        Button { player.play(filtered[0], in: filtered) } label: {
                            Label("播放全部 · \(filtered.count) 首", systemImage: "play.fill").padding(.vertical, 6)
                        }
                    }
                    ForEach(filtered) { song in SongRow(song: song, context: filtered, playlistID: playlistID).id(song.id) }
                }
            }
            .overlay {
                if filtered.isEmpty { EmptyMusicView(title: query.isEmpty ? "还没有歌曲" : "没有找到这首歌", message: query.isEmpty ? emptyMessage : "试试其他歌名、艺术家或专辑。") }
            }
            .overlay(alignment: .trailing) {
                if showIndex && library.sort == .title && !filtered.isEmpty {
                    AlphabetIndex(songs: filtered) { letter in
                        if let song = filtered.first(where: { $0.indexLetter == letter }) { proxy.scrollTo(song.id, anchor: .top) }
                    }.padding(.trailing, 2)
                }
            }
            .safeAreaPadding(.trailing, showIndex && library.sort == .title ? 14 : 0)
            .musicBackground().navigationTitle(title)
            .searchable(text: $query, prompt: "歌曲、艺术家或专辑")
            .toolbar {
                if showIndex {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu { Picker("排序", selection: $library.sort) { ForEach(SongSort.allCases) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("排序方式")
                    }
                }
            }
            .onChange(of: library.sort) { _, _ in library.persist() }
        }
    }
}

struct AlphabetIndex: View {
    var songs: [Song]
    var select: (String) -> Void
    @State private var active: String?
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]
    var body: some View {
        GeometryReader { geometry in
            let rowHeight = min(16.0, max(10, geometry.size.height / 28))
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter).font(.system(size: 9, weight: .semibold)).foregroundStyle(.mint)
                        .frame(width: 20, height: rowHeight).accessibilityAddTraits(.isButton)
                        .onTapGesture { select(letter) }
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let start = (geometry.size.height - rowHeight * Double(letters.count)) / 2
                let index = max(0, min(letters.count - 1, Int((value.location.y - start) / rowHeight)))
                let letter = letters[index]
                if active != letter { active = letter; select(letter); UISelectionFeedbackGenerator().selectionChanged() }
            }.onEnded { _ in active = nil })
            .overlay(alignment: .leading) {
                if let active { Text(active).font(.largeTitle.bold()).frame(width: 64, height: 64).glassEffect(in: .rect(cornerRadius: 16)).offset(x: -90) }
            }
        }.frame(width: 20).accessibilityLabel("字母索引")
    }
}

enum CollectionKind {
    case album, artist, folder
    var title: String { self == .album ? "专辑" : self == .artist ? "艺术家" : "文件夹" }
    func key(_ song: Song) -> String { self == .album ? song.album + "\u{001F}" + song.artist : self == .artist ? song.artist : song.folder }
    func label(_ key: String) -> String { key.components(separatedBy: "\u{001F}").first ?? key }
}
struct CollectionsView: View {
    var kind: CollectionKind
    @EnvironmentObject private var library: LibraryStore
    private var groups: [String: [Song]] { Dictionary(grouping: library.songs, by: kind.key) }
    var body: some View {
        List {
            ForEach(groups.keys.sorted { Song.sortKey($0) < Song.sortKey($1) }, id: \.self) { key in
                let songs = groups[key] ?? []
                NavigationLink {
                    SongListView(title: kind.label(key), songs: songs.sorted { $0.trackNumber < $1.trackNumber })
                } label: {
                    HStack(spacing: 14) {
                        Artwork(song: songs.first, corner: kind == .artist ? 28 : 12).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind.label(key)).font(.headline).lineLimit(2)
                            Text("\(songs.count) 首" + (kind == .album ? " · \(songs.first?.artist ?? "")" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.musicBackground().navigationTitle(kind.title)
    }
}

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    private var results: [Song] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return library.songs.filter { $0.searchText.localizedCaseInsensitiveContains(query) || Song.sortKey($0.searchText).contains(Song.sortKey(query)) }
    }
    var body: some View {
        List { ForEach(results) { SongRow(song: $0, context: results) } }
            .overlay { if results.isEmpty { ContentUnavailableView(query.isEmpty ? "寻找你的音乐" : "没有搜索结果", systemImage: "magnifyingglass", description: Text("搜索歌名、艺术家、专辑，也支持拼音。")) } }
            .searchable(text: $query, prompt: "歌曲、艺术家或专辑")
            .musicBackground().navigationTitle("搜索")
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showName = false
    @State private var name = ""
    @State private var renaming: UUID?
    @State private var deleting: Playlist?
    var body: some View {
        List {
            ForEach(library.data.playlists) { playlist in
                NavigationLink { PlaylistDetailView(id: playlist.id) } label: {
                    HStack(spacing: 14) {
                        Artwork(song: library.playlistSongs(playlist.id).first).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(playlist.name).font(.headline)
                            Text("\(playlist.songIDs.count) 首").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }
                .contextMenu {
                    Button("重命名", systemImage: "pencil") { renaming = playlist.id; name = playlist.name; showName = true }
                    Button("删除歌单", systemImage: "trash", role: .destructive) { deleting = playlist }
                }
                .swipeActions { Button(role: .destructive) { deleting = playlist } label: { Label("删除", systemImage: "trash") } }
            }
        }
        .overlay {
            if library.data.playlists.isEmpty {
                ContentUnavailableView { Label("为每一种心情建个歌单", systemImage: "music.note.list") }
                description: { Text("收藏通勤、夜晚和独处时想听的音乐。") }
                actions: { Button("新建歌单") { renaming = nil; name = ""; showName = true }.buttonStyle(.glassProminent) }
            }
        }
        .musicBackground().navigationTitle("歌单")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("新建歌单", systemImage: "plus") { renaming = nil; name = ""; showName = true } } }
        .alert(renaming == nil ? "新建歌单" : "重命名歌单", isPresented: $showName) {
            TextField("歌单名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let renaming { library.renamePlaylist(renaming, name: name) } else { library.createPlaylist(name) }
            }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .confirmationDialog("删除歌单？歌曲文件会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) { if let deleting { library.deletePlaylist(deleting.id) }; deleting = nil }
        }
    }
}
struct PlaylistDetailView: View {
    let id: UUID
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        SongListView(title: library.data.playlists.first { $0.id == id }?.name ?? "歌单", songs: library.playlistSongs(id), playlistID: id)
    }
}
struct AddToPlaylistView: View {
    let song: Song
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            List {
                Section("新建歌单") {
                    TextField("歌单名称", text: $newName)
                    Button("创建并添加") {
                        library.createPlaylist(newName)
                        if let id = library.data.playlists.last?.id { library.add(song, to: id) }
                        dismiss()
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("选择歌单") {
                    ForEach(library.data.playlists) { playlist in
                        Button { library.add(song, to: playlist.id); dismiss() } label: {
                            HStack { Text(playlist.name); Spacer(); if playlist.songIDs.contains(song.id) { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }.navigationTitle("添加到歌单").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
