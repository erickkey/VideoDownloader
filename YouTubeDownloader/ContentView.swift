import SwiftUI
import AppKit

struct ContentView: View {

    @StateObject private var manager = DownloadManager()
    @StateObject private var updateChecker = UpdateChecker()
    @State private var updateGlow = false

    @AppStorage("destinationFolder") private var destinationPath: String =
        (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        ?? NSHomeDirectory()

    @AppStorage("muteChime") private var muteChime = false
    @AppStorage("audioOnly") private var audioOnly = false
    @AppStorage("appearance") private var appearance = "auto"   // auto | light | dark

    @State private var urlString = ""
    @State private var showAdvanced = false

    // 0 = «Максимальное»; otherwise a height in px.
    @AppStorage("qualityHeight") private var qualityHeight = 0

    private static let fallbackHeights = [2160, 1440, 1080, 720, 480, 360]

    /// Heights offered in the picker: real ones after a probe, generic otherwise.
    private var qualityOptions: [Int] {
        manager.availableHeights.isEmpty ? Self.fallbackHeights : manager.availableHeights
    }

    private func qualityLabel(_ h: Int) -> String {
        switch h {
        case 2160: return "2160p (4K)"
        case 1440: return "1440p (2K)"
        default:   return "\(h)p"
        }
    }

    /// "Максимальное" (0) shows the size of the best probed height; otherwise
    /// the size for that exact height, if the probe found one.
    private func approxSizeText(for height: Int) -> String? {
        let h = height == 0 ? manager.availableHeights.first : height
        guard let h, let bytes = manager.approxSizeByHeight[h] else { return nil }
        return "≈ " + Self.formatBytes(bytes)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.2f ГБ", mb / 1000) }
        return String(format: "%.0f МБ", mb)
    }

    private var destinationURL: URL { URL(fileURLWithPath: destinationPath) }

    private var canDownload: Bool {
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty
        && manager.toolsReady
        && !manager.isRunning
        && !manager.isProbing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            urlField
            controlsRow
            destinationRow
            actionRow
            progressSection
            if manager.needsFullDiskAccess { fullDiskAccessBanner }
            if !manager.toolsReady { missingToolsBanner }
            advancedSection
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            manager.refreshTools()
            if appearance == "auto" {
                appearance = Self.systemIsDark() ? "dark" : "light"
            }
            applyAppearance()
            updateChecker.check()
            fillURLFromClipboardIfEmpty()
        }
        .onChange(of: appearance) { _ in applyAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fillURLFromClipboardIfEmpty()
            updateChecker.check()
        }
        .onChange(of: manager.progress) { _ in updateDockProgress() }
        .onChange(of: manager.isRunning) { _ in updateDockProgress() }
    }

    /// Draws a thin progress bar over the app's Dock icon while a download runs.
    private func updateDockProgress() {
        if manager.isRunning {
            NSApp.dockTile.contentView = DockProgressView(progress: manager.progress)
        } else {
            NSApp.dockTile.contentView = nil
        }
        NSApp.dockTile.display()
    }

    /// If the field is empty and the clipboard holds something that looks
    /// like a video URL, drop it in — saves friends a manual paste.
    private func fillURLFromClipboardIfEmpty() {
        guard urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: clip),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil
        else { return }
        urlString = clip
    }

    // MARK: Appearance

    private func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }

    private static func systemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VideoDownloader")
                    .font(.title2.bold())
                Text("YouTube, VK и сотни других сайтов → MP4 / H.264. Вставьте ссылку и нажмите «Скачать».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Оформление", selection: $appearance) {
                Image(systemName: "sun.max.fill").tag("light")
                Image(systemName: "moon.fill").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help("Светлая / тёмная тема")
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Button("О программе") { InfoPanel.about.show() }
                .buttonStyle(.link)
            Button("Правовая информация") { InfoPanel.legal.show() }
                .buttonStyle(.link)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if updateChecker.updateAvailable {
                    Button {
                        updateChecker.openDownload()
                    } label: {
                        Text("Доступно обновление"
                             + (updateChecker.latestVersion.map { " (\($0))" } ?? ""))
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                            .shadow(color: .red.opacity(updateGlow ? 0.85 : 0.25),
                                    radius: updateGlow ? 6 : 2)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                            updateGlow = true
                        }
                    }
                }
                Text("by Yaroslav Lukyanov")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ссылка на видео")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://vk.com/video…  или  https://www.youtube.com/watch?v=…", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .disableAutocorrection(true)
                    .onSubmit { if canDownload { startDownload() } }
                    .onChange(of: urlString) { _ in manager.resetProbe() }
                Button {
                    manager.probeQuality(urlString: urlString)
                } label: {
                    if manager.isProbing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Проверить качество")
                    }
                }
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty
                          || manager.isProbing || manager.isRunning || audioOnly)
            }
            if let title = manager.probedTitle {
                Text("▸ \(title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var controlsRow: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.availableHeights.isEmpty ? "Качество" : "Качество (доступное для этого видео)")
                    .font(.caption)
                    .foregroundStyle(audioOnly ? .tertiary : .secondary)
                Picker("Качество", selection: $qualityHeight) {
                    Text("Максимальное").tag(0)
                    ForEach(qualityOptions, id: \.self) { h in
                        Text(qualityLabel(h)).tag(h)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
                .disabled(audioOnly)
                .onChange(of: manager.availableHeights) { heights in
                    if qualityHeight != 0, !heights.isEmpty, !heights.contains(qualityHeight) {
                        qualityHeight = 0
                    }
                }
                if !audioOnly, let sizeText = approxSizeText(for: qualityHeight) {
                    Text(sizeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(audioOnly
                     ? "Скачивается только звук в .mp3, 320 kbps."
                       + (manager.approxAudioBytes.map { " ≈ " + Self.formatBytes($0) } ?? "")
                     : "Формат всегда .mp4 / H.264. Если сайт отдаёт VP9/AV1 — перекодируется сам.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Только звук — MP3 320 kbps", isOn: $audioOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Отключить звук уведомления", isOn: $muteChime)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Spacer()
        }
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Папка назначения")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(destinationPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                Button("Выбрать…") { chooseFolder() }
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if manager.isRunning {
                Button(role: .destructive) { manager.cancel() } label: {
                    Label("Отменить", systemImage: "stop.fill")
                }
            } else {
                Button { startDownload() } label: {
                    Label("Скачать", systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canDownload)
            }

            Spacer()

            Button {
                if let file = manager.lastDownloadedFile {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            } label: {
                Label("Показать файл", systemImage: "doc.viewfinder")
            }
            .disabled(manager.lastDownloadedFile == nil)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if manager.isRunning && manager.indeterminate {
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: manager.progress)
            }
            Text(manager.statusLine.isEmpty ? " " : manager.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if manager.isRunning && manager.statusLine.hasPrefix("Скачивание сейчас начнётся") {
                Text("Программа запрашивает у сайта данные о видео: адреса потоков и способ обхода защиты. Обычно 2–10 секунд.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if manager.isRunning && manager.fragmentedDownload && manager.slowFragmentedSite {
                Text("Сайт отдаёт видео множеством мелких кусков, а не одним файлом — их приходится качать по очереди, поэтому медленнее обычного. Vimeo почти всегда так.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case let .failed(message) = manager.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var fullDiskAccessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Нужен «Полный доступ к диску»", systemImage: "lock.shield")
                .font(.callout.bold())
            Text("Чтобы взять cookies из Safari для видео, требующих входа, добавьте это приложение в список. Один раз.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Открыть настройки") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Показать приложение") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.5)))
    }

    private var missingToolsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Не хватает инструментов", systemImage: "exclamationmark.triangle")
                .font(.callout.bold())
            Text("yt-dlp: \(manager.ytDlpPath ?? "не найден")\nffmpeg: \(manager.ffmpegPath ?? "не найден")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Установить через Homebrew") { manager.installTools() }
                    .disabled(manager.isRunning || !manager.hasHomebrew)
                Button("Проверить снова") { manager.refreshTools() }
            }
            if !manager.hasHomebrew {
                Text("Homebrew не найден — поставьте его с brew.sh. Обычно инструменты уже вшиты в приложение при сборке.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.4)))
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 12) {
                toolsBlock
                Divider()
                logBlock
            }
            .padding(.top, 8)
        } label: {
            Text("Дополнительно").font(.callout)
        }
    }

    private var toolsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manager.usingBundledTools
                 ? "yt-dlp и ffmpeg встроены в приложение"
                 : "yt-dlp: \(manager.ytDlpPath ?? "—")\nffmpeg: \(manager.ffmpegPath ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Обновить yt-dlp") { manager.updateTools() }
                    .disabled(manager.isRunning || (!manager.usingBundledTools && !manager.hasHomebrew))
                Button("Проверить снова") { manager.refreshTools() }
            }
        }
    }

    private var logBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Журнал").font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(manager.log.isEmpty ? "—" : manager.log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logEnd")
                }
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .onChange(of: manager.log) { _ in
                    withAnimation { proxy.scrollTo("logEnd", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Actions

    private func startDownload() {
        manager.start(
            urlString: urlString,
            destination: destinationURL,
            maxHeight: qualityHeight == 0 ? nil : qualityHeight,
            audioOnly: audioOnly
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Куда сохранять видео"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }
}

// MARK: - Dock icon progress bar

/// Redraws the app icon with a thin progress bar along the bottom, the way
/// Finder/Safari show ongoing downloads in the Dock.
private final class DockProgressView: NSView {
    private let progress: Double

    init(progress: Double) {
        self.progress = progress
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)

        let barHeight: CGFloat = 14
        let inset: CGFloat = 10
        let barRect = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: barHeight)

        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let fillWidth = max(0, min(1, progress)) * barRect.width
        if fillWidth > 1 {
            let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barHeight)
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }
    }
}

// MARK: - Info windows (О программе / Правовая информация)

/// A reusable window shown centred on the screen.
final class InfoPanel {
    static let about = InfoPanel(title: "О программе", size: NSSize(width: 480, height: 600)) {
        AnyView(AboutView(onClose: $0))
    }
    static let legal = InfoPanel(title: "Правовая информация", size: NSSize(width: 520, height: 640)) {
        AnyView(LegalView(onClose: $0))
    }

    private let title: String
    private let size: NSSize
    private let makeContent: (@escaping () -> Void) -> AnyView
    private var window: NSWindow?

    private init(title: String, size: NSSize,
                 makeContent: @escaping (@escaping () -> Void) -> AnyView) {
        self.title = title
        self.size = size
        self.makeContent = makeContent
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: makeContent { [weak self] in self?.window?.close() }
        )
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = title
        win.isReleasedWhenClosed = false
        win.setContentSize(size)
        win.center()
        win.makeKeyAndOrderFront(nil)
        window = win
    }
}

/// Scrollable body + a divider + one closing button at the bottom.
struct InfoScaffold<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let closeTitle: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content()
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Button(closeTitle) { onClose() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(14)
        }
        .frame(width: width, height: height)
    }
}

/// Bulleted "heading + items" block, shared by both windows.
func infoSection(_ title: String, _ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.headline)
        ForEach(items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(item).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AboutView: View {
    var onClose: () -> Void

    var body: some View {
        InfoScaffold(width: 480, height: 600, closeTitle: "Благодарю", onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Если видео перестало скачиваться — нажмите «Обновить yt-dlp» в разделе «Дополнительно». Сайты периодически меняют защиту, обновление её догоняет.")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))

                Text("VideoDownloader").font(.title2.bold())
                Text("Качает видео с YouTube, VK, Vimeo, Одноклассников, Дзена и ещё ~1750 сайтов. Сохраняет в .mp4 с кодеком H.264 — такой файл открывается где угодно.")
                    .foregroundStyle(.secondary)

                infoSection("Что умеет", [
                    "Скачивать по ссылке в один клик — вставил, нажал «Скачать».",
                    "Сама подставляет ссылку из буфера обмена, если она там есть — скопировал и сразу открыл программу.",
                    "Выбор качества: от 480p до 4K (или «максимальное»).",
                    "Показывает примерный размер файла для каждого качества (после «Проверить качество»).",
                    "Всегда отдаёт .mp4 / H.264. Если сайт прислал видео в другом кодеке — программа сама перекодирует.",
                    "Только звук — скачать в .mp3 320 kbps (галочка).",
                    "Прогресс скачивания виден прямо на иконке в Dock.",
                    "Звук-уведомление по завершении (можно отключить галочкой).",
                    "Кнопка «Показать файл» — открывает скачанное в Finder.",
                    "Работает на Intel и Apple Silicon, macOS 13 и новее.",
                ])

                infoSection("Что не умеет", [
                    "Скачивать платное и защищённое видео (Netflix, Кинопоиск, ivi, Okko, онлайн-кинотеатры и т.д.) — их видео закрыто DRM (система шифрования от копирования), обойти её нельзя.",
                    "Скачивать плейлист целиком — только по одной ссылке за раз.",
                    "Записывать идущие прямые эфиры — только уже завершённые.",
                    "Скачивать субтитры и вырезать фрагменты.",
                ])

                HStack(spacing: 4) {
                    Text("Вопросы, предложения или пожелания —").foregroundStyle(.secondary)
                    Link("написать в тг", destination: URL(string: "https://t.me/lukyanov_yaroslav")!)
                }
                .font(.callout)
                .padding(.top, 4)
            }
        }
    }
}

struct LegalView: View {
    var onClose: () -> Void

    var body: some View {
        InfoScaffold(width: 520, height: 640, closeTitle: "Понятно", onClose: onClose) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Это не юридическая консультация — только общие ориентиры. В спорной ситуации советуйтесь с юристом.")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))

                para("Сама программа легальна.", "Внутри — открытый движок yt-dlp, а VideoDownloader просто удобная оболочка над ним. Программа ничего не взламывает: она берёт те же видеопотоки, что сайт отдаёт обычному браузеру. Инструменты такого рода не запрещены ни в России, ни в большинстве стран.")

                infoSection("Личное использование (формально серая зона, но на практике безопасно)", [
                    "В России ст. 1273 ГК РФ разрешает воспроизводить правомерно обнародованное произведение исключительно в личных целях — например, скачать ролик, чтобы посмотреть офлайн.",
                    "Во многих странах ЕС действует «право на частную копию».",
                    "Это может нарушать пользовательское соглашение сайта (например, YouTube) — но это спор с сайтом, а не преступление. За личное скачивание людей не преследуют.",
                ])

                infoSection("Нельзя", [
                    "Перезаливать чужое видео, продавать его, вставлять в рекламу или коммерческий продукт — это нарушение авторских прав. За распространение в крупном размере в России есть и уголовная ответственность (ст. 146 УК).",
                    "Обходить платную подписку и DRM (Netflix, Кинопоиск, онлайн-кинотеатры) — прямое нарушение закона (в РФ — ст. 1299 ГК, в США — DMCA § 1201). Программа этого и не умеет.",
                ])

                infoSection("Ответственность", [
                    "Автор не отвечает за то, какие видео и с каких сайтов вы скачиваете, и за соблюдение вами законов, авторских прав и правил этих сайтов.",
                    "Автор не отвечает за любой вред: потерю или повреждение файлов, сбои в работе, блокировку ваших аккаунтов, претензии правообладателей или сайтов.",
                    "Автор не гарантирует, что программа работает, работает правильно или продолжит работать в будущем.",
                ])

                Text("Программа распространяется бесплатно, в текущем виде, без каких-либо гарантий. Скачивая что-либо через программу, вы действуете на свой страх и риск и полностью принимаете ответственность на себя.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func para(_ lead: String, _ rest: String) -> some View {
        (Text(lead).bold() + Text(" " + rest))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Update checker

/// Fetches a tiny JSON file from GitHub on launch and compares its "version"
/// to this build's own version. No auto-download — just points at the
/// GitHub Release's stable "latest" URL for the user to grab themselves.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion: String?

    private let versionURL = URL(string:
        "https://raw.githubusercontent.com/erickkey/VideoDownloader/main/version.json")!
    private let downloadURL = URL(string:
        "https://github.com/erickkey/VideoDownloader/releases/latest/download/VideoDownloader.dmg")!

    func check() {
        let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        Task {
            var request = URLRequest(url: versionURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remote = json["version"] as? String
            else { return }

            if Self.isNewer(remote, than: currentVersion) {
                self.latestVersion = remote
                self.updateAvailable = true
            }
        }
    }

    func openDownload() {
        NSWorkspace.shared.open(downloadURL)
    }

    /// Simple dotted-version compare ("1.10" > "1.9").
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
