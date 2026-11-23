import SwiftUI
import WidgetKit
import AppIntents

struct MusicEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}
struct MusicProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry { MusicEntry(date: Date(), snapshot: WidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) { completion(MusicEntry(date: Date(), snapshot: WidgetStorage.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        completion(Timeline(entries: [MusicEntry(date: Date(), snapshot: WidgetStorage.load())], policy: .never))
    }
}
struct MusicWidgetView: View {
    let entry: MusicEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let url = WidgetStorage.container?.appendingPathComponent("cover.jpg"), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 12))
                } else {
                    Image(systemName: "opticaldisc.fill").font(.system(size: 42)).foregroundStyle(.mint)
                }
                if family == .systemMedium { labels }
                Spacer(minLength: 0)
            }
            if family != .systemMedium { labels }
            HStack {
                Button(intent: PreviousTrackIntent()) { Image(systemName: "backward.end.fill") }.accessibilityLabel("上一首")
                Spacer()
                Button(intent: TogglePlaybackIntent()) { Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel("播放或暂停")
                Spacer()
                Button(intent: NextTrackIntent()) { Image(systemName: "forward.end.fill") }.accessibilityLabel("下一首")
            }
            .buttonStyle(.plain).font(.title3)
        }
        .widgetURL(URL(string: "fluidmusic://player"))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.08, green: 0.22, blue: 0.24), Color(red: 0.04, green: 0.06, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .foregroundStyle(.white)
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.snapshot.title).font(.headline).lineLimit(1)
            Text(entry.snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
@main struct FluidMusicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FluidMusicWidget", provider: MusicProvider()) { MusicWidgetView(entry: $0) }
            .configurationDisplayName("流体音乐").description("封面、正在播放和快捷控制")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
