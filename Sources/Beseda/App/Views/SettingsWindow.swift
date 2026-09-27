import ServiceManagement
import SwiftUI

/// Raw values are the deep-link names other views use through `SettingsSectionLink`.
private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case recording
    case processing
    case storage
    case integrations

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            SettingsText.get("Основные")
        case .recording:
            SettingsText.get("Запись")
        case .processing:
            SettingsText.get("Обработка")
        case .storage:
            SettingsText.get("Хранение")
        case .integrations:
            SettingsText.get("Интеграции")
        }
    }

    var icon: String {
        switch self {
        case .general:
            "gearshape"
        case .recording:
            "mic"
        case .processing:
            "waveform"
        case .storage:
            "internaldrive"
        case .integrations:
            "link"
        }
    }
}

struct SettingsWindow: View {
    let controller: AppController

    @State private var section = SettingsSection.general

    var body: some View {
        TabView(selection: $section) {
            ForEach(SettingsSection.allCases) { item in
                pane(item)
                    .tabItem { Label(item.title, systemImage: item.icon) }
                    .tag(item)
            }
        }
        .frame(width: 680, height: section == .general ? 390 : 560)
        .onAppear {
            consumeRequestedSection()
            controller.refreshStorageUsage()
            controller.refreshCalendar()
        }
        .onChange(of: controller.requestedSettingsSection) { _, _ in
            consumeRequestedSection()
        }
        // TabView builds every pane up front, so each pane's refresh runs only when it is shown
        .onChange(of: section, initial: true) { _, section in
            switch section {
            case .processing:
                controller.refreshSummaryModels()
            case .integrations:
                controller.webhooks.refresh()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func pane(_ item: SettingsSection) -> some View {
        switch item {
        case .general:
            GeneralPane(controller: controller)
        case .recording:
            RecordingPane(controller: controller)
        case .processing:
            ProcessingPane(controller: controller)
        case .storage:
            StoragePane(controller: controller)
        case .integrations:
            IntegrationsPane(controller: controller)
        }
    }

    private func consumeRequestedSection() {
        guard let raw = controller.requestedSettingsSection,
              let requested = SettingsSection(rawValue: raw) else {
            return
        }
        section = requested
        controller.requestedSettingsSection = nil
    }
}

// MARK: - General

private struct GeneralPane: View {
    let controller: AppController

    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private var updater: AppUpdater {
        controller.updater
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsText.get("Запускать при входе в систему"), isOn: Binding(get: { isLoginItemOn }, set: { setLoginItem($0) }))
                Toggle(SettingsText.get("Уведомлять, когда расшифровка готова"), isOn: Bindable(controller.settings).notifyWhenReady)
            } footer: {
                Text(loginItemNote ?? SettingsText.get("Беседа ждёт звонка в строке меню и не показывается в Dock."))
            }

            Section(SettingsText.get("Обновления")) {
                if updater.isAvailable {
                    Toggle(SettingsText.get("Устанавливать обновления автоматически"), isOn: Binding(
                        get: { updater.installsAutomatically },
                        set: { updater.installsAutomatically = $0 }
                    ))
                    LabeledContent(SettingsText.get("Версия"), value: updater.version)
                    LabeledContent(SettingsText.get("Последняя проверка"), value: lastCheckNote)
                    HStack {
                        Spacer()
                        Button(SettingsText.get("Проверить сейчас…")) {
                            updater.checkForUpdates()
                        }
                    }
                } else {
                    LabeledContent(SettingsText.get("Версия"), value: String(format: SettingsText.get("%@, development build"), updater.version))
                    Text(SettingsText.get("Обновления в этой сборке не проверяются."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckNote: String {
        guard let date = updater.lastCheckDate else {
            return SettingsText.get("ещё не было")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var isLoginItemOn: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    private var loginItemNote: String? {
        if let loginItemError {
            return loginItemError
        }
        if loginItemStatus == .requiresApproval {
            return SettingsText.get("Подтвердите Беседу в Системных настройках → Основные → Объекты входа.")
        }
        return nil
    }

    private func setLoginItem(_ enabled: Bool) {
        loginItemError = nil
        if IsolatedCopy.skips("SMAppService.mainApp.register") {
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}

// MARK: - Recording

private struct RecordingPane: View {
    let controller: AppController

    @State private var monitor = LevelMonitor()

    private var settings: AppSettings {
        controller.settings
    }

    /// Telegram ships under three bundle ids; the list offers each app once
    private var appNames: [String] {
        var seen: Set<String> = []
        return CallDetector.knownCallApps.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsText.get("Включать запись при начале звонка"), isOn: Bindable(settings).autoDetectEnabled)
            } footer: {
                Text(SettingsText.get("Беседа узнаёт звонок по звуку из приложения и записывает микрофон и системный звук."))
            }

            Section {
                Toggle(SettingsText.get("Останавливать после минуты тишины"), isOn: Bindable(settings).stopOnSilence)
            } footer: {
                Text(SettingsText.get("Чтобы не записывать пустоту после конца встречи."))
            }

            Section {
                Toggle(SettingsText.get("Расшифровывать во время звонка"), isOn: Bindable(settings).transcribesDuringCall)
            } footer: {
                Text(SettingsText.get("Черновик разговора и ключевые моменты в меню, пока идёт запись. Итоговая расшифровка всё равно делается после звонка."))
            }

            Section {
                HStack(spacing: 12) {
                    LevelMeter(level: max(monitor.microphoneLevel, monitor.systemAudioLevel), color: .green)
                    Button(monitor.isRunning ? SettingsText.get("Проверка…") : SettingsText.get("Проверить звук")) {
                        monitor.start()
                    }
                    .disabled(monitor.isRunning)
                }
                if let failure = monitor.failure {
                    Text(SettingsText.get(failure)).foregroundStyle(.red)
                } else if monitor.heardMicrophone || monitor.heardSystemAudio {
                    Text(soundCheckResult).foregroundStyle(.secondary)
                }
            } footer: {
                Text(SettingsText.get("Проверяет микрофон и системный звук 10 секунд. Запись не сохраняется."))
            }

            if settings.autoDetectEnabled {
                Section(SettingsText.get("Приложения")) {
                    ForEach(appNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { isEnabled(name) },
                            set: { setEnabled(name, $0) }
                        ))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { monitor.stop() }
    }

    private var soundCheckResult: String {
        if monitor.heardMicrophone && monitor.heardSystemAudio {
            return SettingsText.get("Микрофон и системный звук слышны")
        }
        if monitor.heardMicrophone {
            return SettingsText.get("Микрофон слышен, системный звук пока молчит")
        }
        return SettingsText.get("Системный звук слышен, микрофон пока молчит")
    }

    private func bundleIDs(named name: String) -> [String] {
        CallDetector.knownCallApps.filter { $0.name == name }.map(\.bundleID)
    }

    private func isEnabled(_ name: String) -> Bool {
        bundleIDs(named: name).contains { settings.enabledCallApps.contains($0) }
    }

    private func setEnabled(_ name: String, _ enabled: Bool) {
        var apps = settings.enabledCallApps
        for bundleID in bundleIDs(named: name) {
            if enabled {
                apps.insert(bundleID)
            } else {
                apps.remove(bundleID)
            }
        }
        settings.enabledCallApps = apps
    }
}

// MARK: - Processing

private struct ProcessingPane: View {
    let controller: AppController

    @State private var isAdvancedOpen = false

    private var settings: AppSettings {
        controller.settings
    }

    /// what leaves this Mac under the settings as they are now
    private var privacySinks: [String] {
        var sinks: [String] = []
        if settings.effectiveSummaryProvider == .openRouter {
            sinks.append(SettingsText.get("в OpenRouter (openrouter.ai) уходит текст расшифровки — для итогов и ключевых моментов во время звонка"))
        } else if settings.effectiveSummaryProvider == .lmStudio, let host = settings.remoteSummaryHost {
            sinks.append(String(format: SettingsText.get("transcript text goes to summary server %@"), host))
        }
        if settings.classifiesWithJev, settings.callTypes.count > 1 {
            sinks.append(SettingsText.get("в OpenRouter уходят время, длительность и начало расшифровки — чтобы Jev выбрал тип звонка"))
        }
        if settings.sendsWebhooks {
            sinks.append(SettingsText.get("расшифровка уходит на ваш сервис из раздела «Интеграции»"))
        }
        return sinks
    }

    /// the one privacy note in Settings
    private var privacyNote: String {
        let sinks = privacySinks
        if sinks.isEmpty {
            return settings.effectiveSummaryProvider == settings.summaryProvider
                ? SettingsText.get("Всё обрабатывается на этом Mac: ни звук, ни текст не уходят в сеть.")
                : SettingsText.get("Всё обрабатывается на этом Mac: итоги пишет встроенная модель, ни звук, ни текст не уходят в сеть.")
        }
        return SettingsText.get("Звук остаётся на этом Mac, но ") + sinks.joined(separator: "; ") + "."
    }

    var body: some View {
        Form {
            Section {
                SpeechModelList(controller: controller)
                LabeledContent(SettingsText.get("Разделение собеседников"), value: Diarizer.bytes.byteSizeDescription)
                DisclosureGroup(SettingsText.get("Подробнее о модели разделения")) {
                    Link(
                        String(format: SettingsText.get("%@ · license %@"), Diarizer.title, Diarizer.licence),
                        destination: Diarizer.licenceURL
                    )
                    .font(.caption)
                }
                if let progress = controller.speakerResplitProgress {
                    Text(String(format: SettingsText.get("Speaker separation updated: %d of %d"), progress.done, progress.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(SettingsText.get("Распознавание речи"))
            } footer: {
                Text(String(format: SettingsText.get("Models on disk: %@. Models run on this Mac; speaker separation downloads in the background after you choose a speech model. Changing models does not change existing transcripts."), (controller.runtime.diskUsage() + (controller.diarizer.isDownloaded ? Diarizer.bytes : 0)).byteSizeDescription))
            }

            Section {
                Picker(SettingsText.get("Кто пишет итоги"), selection: Bindable(settings).summaryProvider) {
                    ForEach(SummaryProvider.allCases) { provider in
                        Text(SettingsText.get(provider.title)).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(SettingsText.get("Только локально"), isOn: Bindable(settings).localOnly)
                    .disabled(settings.strictMode)
                Label(privacyNote, systemImage: privacySinks.isEmpty ? "lock" : "icloud.and.arrow.up")
                    .foregroundStyle(.secondary)
                if settings.effectiveSummaryProvider != settings.summaryProvider {
                    Label(
                        String(format: SettingsText.get("While Local only is on, the built-in model writes summaries instead of %@."), SettingsText.get(settings.summaryProvider.title)),
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                // under «Только локально» the rows are the ones of the model that actually runs
                switch settings.effectiveSummaryProvider {
                case .openRouter:
                    openRouterRows
                case .builtIn:
                    BundledSummaryRow(installer: controller.bundledSummary)
                case .lmStudio:
                    lmStudioRows
                }

                HStack {
                    if let summaryCheckResult = controller.summaryCheckResult {
                        Text(summaryCheckResult)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(controller.isCheckingSummary ? SettingsText.get("Проверка…") : SettingsText.get("Проверить")) {
                        controller.checkSummaryConnection()
                    }
                    .disabled(controller.isCheckingSummary)
                }
                if settings.effectiveSummaryProvider == .lmStudio {
                    DisclosureGroup(SettingsText.get("Дополнительно"), isExpanded: $isAdvancedOpen) {
                        TextField(SettingsText.get("Адрес сервера"), text: Bindable(settings).summaryServerURL, prompt: Text(SettingsText.get("определяется сам")))
                    }
                }
            } header: {
                Text(SettingsText.get("Итоги"))
            } footer: {
                Text(providerNote)
            }

            Section {
                Toggle(SettingsText.get("Обрабатывать звонки автоматически"), isOn: Bindable(settings).autoProcessCalls)
                ForEach(Bindable(settings).callTypes) { $type in
                    DisclosureGroup {
                        TextField(SettingsText.get("Название"), text: $type.name)
                        TextField(SettingsText.get("Когда выбирать"), text: $type.description, prompt: Text(SettingsText.get("одной фразой, для выбора типа")))
                        TextEditor(text: $type.prompt)
                            .font(.body)
                            .frame(minHeight: 120)
                        HStack {
                            Button(SettingsText.get("Сбросить инструкцию")) {
                                type.prompt = ChatCompletionsProvider.defaultPrompt
                            }
                            Spacer()
                            Button(SettingsText.get("Удалить тип"), role: .destructive) {
                                settings.deleteCallType(id: type.id)
                            }
                            .disabled(type.isOther)
                        }
                        .controlSize(.small)
                    } label: {
                        Text(type.name.isEmpty ? SettingsText.get("Без названия") : type.isOther ? SettingsText.get(type.name) : type.name)
                    }
                }
                Button(SettingsText.get("Добавить тип")) {
                    settings.callTypes.append(
                        CallType(name: SettingsText.get("Новый тип"), description: "", prompt: ChatCompletionsProvider.defaultPrompt)
                    )
                }
                Picker(SettingsText.get("Определение типа"), selection: Bindable(settings).classifyLocally) {
                    Text(SettingsText.get("Jev через OpenRouter (по умолчанию, если есть ключ)")).tag(false)
                    Text(SettingsText.get("Локально")).tag(true)
                }
                // Jev needs the key even when another provider writes summaries.
                if !settings.classifyLocally && settings.summaryProvider != .openRouter {
                    SecretField(title: SettingsText.get("Ключ OpenRouter"), text: Bindable(settings).openRouterAPIKey, isLoading: !settings.secretsLoaded)
                }
            } header: {
                Text(SettingsText.get("Типы звонков"))
            } footer: {
                Text(String(format: SettingsText.get("The %@ type always exists: its instructions write summaries when no other type fits. With multiple types, Jev via OpenRouter chooses from the call time, duration, and start of the transcript. Without an OpenRouter key or if Jev fails, the summary model chooses. Do not use # headings in instructions: summaries show only bold text and line breaks."), SettingsText.get(CallType.otherName)))
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.summaryProvider) {
            controller.refreshSummaryModels()
        }
    }

    @ViewBuilder
    private var openRouterRows: some View {
        SecretField(title: SettingsText.get("Ключ"), text: Bindable(settings).openRouterAPIKey, isLoading: !settings.secretsLoaded)
        TextField(SettingsText.get("Модель"), text: Bindable(settings).openRouterModel, prompt: Text(OpenRouter.defaultModel))
    }

    @ViewBuilder
    private var lmStudioRows: some View {
        LabeledContent(SettingsText.get("Сервер"), value: controller.summaryServerStatus.map { SettingsText.get($0) } ?? SettingsText.get("проверка…"))
        Picker(SettingsText.get("Модель"), selection: Bindable(settings).summaryModel) {
            Text(SettingsText.get("Автоматически")).tag("")
            ForEach(modelOptions, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        HStack {
            Spacer()
            if LocalModelSupport.isInstalled, controller.isServerDown {
                Button(controller.isStartingLocalModelServer ? SettingsText.get("Запуск…") : SettingsText.get("Запустить LM Studio")) {
                    controller.startLocalModelServer()
                }
                .disabled(controller.isStartingLocalModelServer)
            }
            Button(SettingsText.get("Обновить список")) {
                controller.refreshSummaryModels()
            }
        }
    }

    /// what this provider costs the user: money, memory, or another app to keep running
    private var providerNote: String {
        switch settings.effectiveSummaryProvider {
        case .openRouter:
            SettingsText.get("Ключ создаётся на openrouter.ai, оплата по факту: час разговора на gemini-flash стоит несколько центов.")
        case .builtIn:
            SettingsText.get("Модель работает на этом Mac, без интернета и без ключей. Запускается на время итогов и занимает около 5 ГБ памяти, потом выгружается.")
        case .lmStudio:
            LocalModelSupport.isInstalled
                ? SettingsText.get("Итоги пишет модель, загруженная в LM Studio. Приложение должно быть запущено с включённым Local Server.")
                : SettingsText.get(LocalModelSupport.manualInstructions)
        }
    }

    /// the stored model always appears, even one the server no longer lists, so the picker never silently changes it
    private var modelOptions: [String] {
        guard !settings.summaryModel.isEmpty, !controller.summaryModels.contains(settings.summaryModel) else {
            return controller.summaryModels
        }
        return [settings.summaryModel] + controller.summaryModels
    }
}

/// The built-in model as one row: what it is on the left, and the only action it has on the right.
private struct BundledSummaryRow: View {
    let installer: BundledSummaryInstaller

    var body: some View {
        LabeledContent {
            control
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(BundledSummary.current.title) · \(BundledSummary.current.modelBytes.byteSizeDescription)")
                Text(SettingsText.get(BundledSummary.current.subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        if let stage = installer.stage {
            HStack(spacing: 8) {
                if let fraction = installer.fraction {
                    Text("\(SettingsText.get(stage.title)) \(Int(fraction * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: fraction)
                        .frame(width: 90)
                        .accessibilityLabel(SettingsText.get(stage.title))
                } else {
                    Text(SettingsText.get(stage.title))
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } else if let failure = installer.failure {
            HStack(spacing: 8) {
                Text(SettingsText.get(failure))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .help(SettingsText.get(failure))
                Button(SettingsText.get("Повторить")) {
                    installer.install()
                }
            }
        } else if installer.isReady {
            HStack(spacing: 8) {
                Text(SettingsText.get("Скачана"))
                    .foregroundStyle(.secondary)
                Button(SettingsText.get("Удалить")) {
                    try? installer.remove()
                }
            }
        } else {
            Button(SettingsText.get("Скачать")) {
                installer.install()
            }
        }
    }
}

// MARK: - Storage

private struct StoragePane: View {
    let controller: AppController

    @State private var fileVaultIsOn: Bool?
    @State private var isConfirmingStrictMode = false

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsText.get("Строгий режим"), isOn: Binding(
                    get: { settings.strictMode },
                    set: { on in
                        if on, !settings.strictModeConfirmed {
                            isConfirmingStrictMode = true
                        } else {
                            setStrictMode(on)
                        }
                    }
                ))
                Toggle(SettingsText.get("Не включать записи в резервные копии (Time Machine и др.)"), isOn: Binding(
                    get: { settings.excludesFromBackup },
                    set: { excluded in
                        settings.excludesFromBackup = excluded
                        controller.applyBackupExclusion()
                    }
                ))
                .disabled(settings.strictMode)
                Text(SettingsText.get("Уже сделанные копии и снимки Time Machine не удаляются. Выключите, чтобы записи снова попадали в копии: без копии сломанный диск унесёт все записи."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if fileVaultIsOn == false {
                    HStack {
                        Label(SettingsText.get("FileVault выключен: при краже Mac записи можно прочитать."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(SettingsText.get("Открыть настройки FileVault")) {
                            NSWorkspace.shared.open(FileVault.settingsURL)
                        }
                    }
                }
            } header: {
                Text(SettingsText.get("Приватность"))
            } footer: {
                Text(SettingsText.get("Строгий режим удаляет аудио сразу после расшифровки, выключает экспорт, включает «Только локально» и не пускает записи в резервные копии. Пока он включён, эти настройки заблокированы; выключение вернёт прежние значения."))
            }

            Section {
                retentionPicker(
                    SettingsText.get("Исходное аудио"),
                    size: controller.storageUsage.rawAudioBytes,
                    selection: Bindable(settings).rawAudioRetention
                )
                .disabled(settings.strictMode)
                retentionPicker(
                    SettingsText.get("Подготовленное аудио"),
                    size: controller.storageUsage.normalizedAudioBytes,
                    selection: Bindable(settings).normalizedAudioRetention
                )
                .disabled(settings.strictMode)
                LabeledContent(String(format: SettingsText.get("Transcripts, %@"), controller.storageUsage.textBytes.byteSizeDescription), value: SettingsText.get("всегда"))
                HStack {
                    Text(cleanupHint)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(SettingsText.get("Очистить сейчас")) {
                        controller.runCleanupNow()
                    }
                    .disabled(controller.expiredAudioBytes == 0)
                }
            } header: {
                Text(SettingsText.get("Сколько хранить"))
            } footer: {
                Text(SettingsText.get("«Сразу» удаляет аудио, как только расшифровка сохранена, остальные сроки проверяются раз в сутки. Исходное аудио — WAV с микрофона и системного звука, подготовленное — промежуточный файл для расшифровки."))
            }

            Section {
                LabeledContent(SettingsText.get("Папка экспорта")) {
                    Text(settings.exportFolder.isEmpty ? SettingsText.get("не выбрана") : settings.exportFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(SettingsText.get("Очистить")) {
                        settings.exportFolder = ""
                    }
                    .disabled(settings.exportFolder.isEmpty)
                    Button(SettingsText.get("Выбрать…")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.exportFolder = url.path
                        }
                    }
                }
                .disabled(settings.strictMode)
                if ICloudDrive.contains(settings.exportFolder) {
                    Label(SettingsText.get("Папка в iCloud Drive: экспорт уходит в облако Apple."), systemImage: "icloud")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(SettingsText.get("Экспорт результатов"))
            } footer: {
                Text(SettingsText.get("Каждый готовый результат обработки сохраняется сюда файлом Markdown: заголовок, дата, тип, результат и расшифровка."))
            }

            Section(SettingsText.get("Папка")) {
                LabeledContent(SettingsText.get("Записи")) {
                    Text(controller.callsDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button(SettingsText.get("Показать в Finder")) {
                        controller.openCallsFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BESEDA_PREVIEW_FILEVAULT_OFF"] != nil {
                fileVaultIsOn = false
                return
            }
            #endif
            fileVaultIsOn = await Task.detached { FileVault.isOn() }.value
        }
        .confirmationDialog(SettingsText.get("Включить строгий режим?"), isPresented: $isConfirmingStrictMode) {
            Button(SettingsText.get("Включить и удалять аудио"), role: .destructive) {
                settings.strictModeConfirmed = true
                setStrictMode(true)
            }
        } message: {
            Text(SettingsText.get("Аудио уже расшифрованных записей удалится при следующей очистке, а новое — сразу после расшифровки. Удалённое аудио не вернуть, даже если выключить режим."))
        }
    }

    private func setStrictMode(_ on: Bool) {
        settings.setStrictMode(on)
        controller.applyBackupExclusion()
        controller.refreshStorageUsage()
    }

    private func retentionPicker(_ title: String, size: Int64, selection: Binding<RetentionRule>) -> some View {
        Picker("\(title), \(size.byteSizeDescription)", selection: Binding(
            get: { selection.wrappedValue },
            set: { rule in
                selection.wrappedValue = rule
                controller.refreshStorageUsage()
            }
        )) {
            ForEach(RetentionRule.allCases) { rule in
                Text(SettingsText.get(rule.title)).tag(rule)
            }
        }
    }

    private var cleanupHint: String {
        controller.expiredAudioBytes > 0
            ? String(format: SettingsText.get("%@ matches the current rules."), controller.expiredAudioBytes.byteSizeDescription)
            : SettingsText.get("Под текущие правила ничего не попадает.")
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    let controller: AppController

    @State private var isCalendarPickerOpen = false
    @State private var isWebhookDetailsOpen = false

    private var settings: AppSettings {
        controller.settings
    }

    private var webhooks: WebhookService {
        controller.webhooks
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsText.get("Брать название из календаря"), isOn: Binding(
                    get: { settings.calendarEnabled },
                    set: { controller.setCalendarEnabled($0) }
                ))
                let accessAction = CalendarService.accessAction(for: controller.calendarService.authorization)
                LabeledContent(accessLine(for: accessAction)) {
                    switch accessAction {
                    case .requestAccess:
                        Button(SettingsText.get("Разрешить доступ к календарю")) {
                            controller.requestCalendarAccess()
                        }
                    case .openSettings:
                        Button(SettingsText.get("Открыть настройки…")) {
                            PermissionsModel.openPrivacySettings(pane: "Privacy_Calendars")
                        }
                    case .chooseCalendars:
                        Button(SettingsText.get("Выбрать календари…")) {
                            isCalendarPickerOpen = true
                        }
                        .popover(isPresented: $isCalendarPickerOpen, arrowEdge: .bottom) {
                            CalendarPicker(controller: controller)
                        }
                        .disabled(!settings.calendarEnabled)
                    }
                }
                .foregroundStyle(accessAction == .openSettings ? Color.red : Color.primary)
            } header: {
                Text(SettingsText.get("Календарь"))
            } footer: {
                Text(String(format: SettingsText.get("%@. Uses the event at recording start (±5 minutes). Recording still starts when call audio is detected."), calendarStateLine))
            }

            Section {
                Toggle(SettingsText.get("Отправлять расшифровку на свой сервис"), isOn: Bindable(settings).webhookEnabled)
                TextField(SettingsText.get("Адрес"), text: Bindable(settings).webhookURL, prompt: Text("https://example.com/webhook"))
                if settings.webhookEnabled, case .failure(.plainHTTP) = WebhookSender.checkedEndpoint(from: settings.webhookURL) {
                    Text(String(format: SettingsText.get("Not sent. %@"), SettingsText.get(EndpointRefusal.plainHTTP.rawValue)))
                        .foregroundStyle(.red)
                }
                SecretField(title: SettingsText.get("Секрет"), text: Bindable(settings).webhookSecret, isLoading: !settings.secretsLoaded)
                Text(SettingsText.get("После готовой расшифровки Беседа отправит на указанный адрес текст, участников, итоги и время звонка."))
                    .foregroundStyle(.secondary)
                DisclosureGroup(SettingsText.get("Подробнее для разработчиков"), isExpanded: $isWebhookDetailsOpen) {
                    Text(SettingsText.get("Отправляется POST-запрос. Секрет передаётся как заголовок Authorization без Bearer. Разрешён https; http — только для localhost."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(webhooks.testResult.map { SettingsText.webhookMessage($0) } ?? SettingsText.get("Сервис должен принять пробный запрос."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(webhooks.isTesting ? SettingsText.get("Отправка…") : SettingsText.get("Отправить тест")) {
                        webhooks.sendTest()
                    }
                    .disabled(webhooks.isTesting)
                }
            } header: {
                Text(SettingsText.get("Свой сервис"))
            }

            Section(SettingsText.get("Журнал доставок")) {
                if webhooks.recent.isEmpty {
                    Text(SettingsText.get("Пока ничего не отправлялось"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(webhooks.recent) { delivery in
                        WebhookDeliveryRow(delivery: delivery, inJournal: true, controller: controller)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func accessLine(for action: CalendarAccessAction) -> String {
        switch action {
        case .requestAccess:
            SettingsText.get("Беседа запросит доступ только после нажатия кнопки")
        case .openSettings:
            SettingsText.get("Включите Беседу в разделе «Календари» в настройках конфиденциальности")
        case .chooseCalendars:
            settings.calendarEnabled
                ? (controller.calendarService.linkingProblem(selected: settings.calendarIdentifiers).map { SettingsText.get($0) } ?? SettingsText.get("Календари этого Mac"))
                : SettingsText.get("Доступ к календарю разрешён")
        }
    }

    private var calendarStateLine: String {
        if settings.calendarEnabled,
           controller.calendarService.linkingProblem(selected: settings.calendarIdentifiers) != nil {
            return SettingsText.get("Новые разговоры не получат названия, пока не выбран доступный календарь")
        }
        let coverage = controller.eventCoverage
        guard coverage.total > 0 else {
            return SettingsText.get("Разговоров пока нет")
        }
        return String(format: SettingsText.get("Calendar events matched %d of %d previous calls"), coverage.matched, coverage.total)
    }
}

/// A key typed once and hidden after, with a button to read it back.
private struct SecretField: View {
    let title: String
    let text: Binding<String>
    let isLoading: Bool

    @State private var isShown = false

    var body: some View {
        HStack {
            if isShown {
                TextField(title, text: text, prompt: isLoading ? Text(SettingsText.get("Загрузка…")) : nil)
            } else {
                SecureField(title, text: text, prompt: isLoading ? Text(SettingsText.get("Загрузка…")) : nil)
            }
            Button(isShown ? SettingsText.get("Скрыть") : SettingsText.get("Показать")) {
                isShown.toggle()
            }
            .accessibilityLabel(isShown ? String(format: SettingsText.get("Hide %@"), title) : String(format: SettingsText.get("Show %@"), title))
            .controlSize(.small)
        }
    }
}

/// One attempt: when · what · how it went. The settings journal names the call and offers a
/// retry; the call's own list already has both above it.
struct WebhookDeliveryRow: View {
    let delivery: StoredWebhookDelivery
    let inJournal: Bool
    let controller: AppController

    var body: some View {
        HStack(spacing: 10) {
            Text(delivery.createdDate.map { CallFormatting.when($0) } ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            if inJournal {
                Text(delivery.callTitle)
                    .lineLimit(1)
            } else {
                Text(String(format: SettingsText.get("attempt %d"), delivery.attempt))
            }

            Spacer(minLength: 0)

            Text([SettingsText.get(delivery.stateLabel), SettingsText.webhookMessage(delivery.detailLine)].filter { !$0.isEmpty }.joined(separator: " · "))
                .lineLimit(1)
                .foregroundStyle(stateColor)

            if inJournal, delivery.state == "failed", !controller.webhooks.sending.contains(delivery.callID) {
                Button(SettingsText.get("Повторить")) {
                    controller.webhooks.sendNow(callID: delivery.callID)
                }
                .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private var stateColor: Color {
        switch delivery.state {
        case "delivered":
            .green
        case "failed":
            .red
        default:
            .secondary
        }
    }
}

private struct CalendarPicker: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SettingsText.get("Пустой список — берутся все календари"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(controller.calendarService.availableCalendars(), id: \.id) { calendar in
                Toggle(calendar.title, isOn: Binding(
                    get: { controller.settings.calendarIdentifiers.contains(calendar.id) },
                    set: { isOn in
                        var identifiers = controller.settings.calendarIdentifiers
                        if isOn {
                            identifiers.insert(calendar.id)
                        } else {
                            identifiers.remove(calendar.id)
                        }
                        controller.settings.calendarIdentifiers = identifiers
                        controller.refreshCalendar()
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
