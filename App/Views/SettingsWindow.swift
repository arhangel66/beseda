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
            "Основные"
        case .recording:
            "Запись"
        case .processing:
            "Обработка"
        case .storage:
            "Хранение"
        case .integrations:
            "Интеграции"
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
        .frame(width: 680, height: 560)
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
                Toggle("Запускать при входе в систему", isOn: Binding(get: { isLoginItemOn }, set: { setLoginItem($0) }))
                Toggle("Уведомлять, когда расшифровка готова", isOn: Bindable(controller.settings).notifyWhenReady)
            } footer: {
                Text(loginItemNote ?? "Beseda ждёт звонка в строке меню и не показывается в Dock.")
            }

            Section("Обновления") {
                if updater.isAvailable {
                    Toggle("Устанавливать обновления автоматически", isOn: Binding(
                        get: { updater.installsAutomatically },
                        set: { updater.installsAutomatically = $0 }
                    ))
                    LabeledContent("Версия", value: updater.version)
                    LabeledContent("Последняя проверка", value: lastCheckNote)
                    HStack {
                        Spacer()
                        Button("Проверить сейчас…") {
                            updater.checkForUpdates()
                        }
                    }
                } else {
                    LabeledContent("Версия", value: "\(updater.version), сборка для разработки")
                    Text("Обновления в этой сборке не проверяются.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckNote: String {
        guard let date = updater.lastCheckDate else {
            return "ещё не было"
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
            return "Подтвердите Beseda в Системных настройках → Основные → Объекты входа."
        }
        return nil
    }

    private func setLoginItem(_ enabled: Bool) {
        loginItemError = nil
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
                Toggle("Включать запись при начале звонка", isOn: Bindable(settings).autoDetectEnabled)
            } footer: {
                Text("Beseda узнаёт звонок по звуку, который издаёт приложение, и пишет микрофон и системный звук.")
            }

            if settings.autoDetectEnabled {
                Section("Приложения") {
                    ForEach(appNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { isEnabled(name) },
                            set: { setEnabled(name, $0) }
                        ))
                    }
                }
            }

            Section {
                Toggle("Останавливать после минуты тишины", isOn: Bindable(settings).stopOnSilence)
            } footer: {
                Text("Чтобы не записывать пустоту после конца встречи.")
            }

            Section {
                Label(processingNote, systemImage: "lock")
            }
        }
        .formStyle(.grouped)
    }

    /// what leaves this Mac under the settings as they are now
    private var processingNote: String {
        var sinks: [String] = []
        if settings.summaryProvider == .openRouter {
            sinks.append("расшифровка уходит в OpenRouter")
        } else if let host = remoteSummaryHost {
            sinks.append("расшифровка уходит на сервер итогов \(host)")
        }
        if settings.webhookEnabled {
            sinks.append("расшифровка уходит на вебхук из раздела «Интеграции»")
        }
        if sinks.isEmpty {
            return "Всё обрабатывается на этом Mac. Ни звук, ни текст не уходят в сеть."
        }
        return "Звук остаётся на этом Mac, но " + sinks.joined(separator: "; ") + "."
    }

    private var remoteSummaryHost: String? {
        guard settings.summaryProvider == .lmStudio,
              let host = URL(string: settings.summaryServerURL)?.host,
              !["localhost", "127.0.0.1", "::1"].contains(host) else {
            return nil
        }
        return host
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
    @State private var isKeyShown = false

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        Form {
            Section {
                SpeechModelList(controller: controller)
            } header: {
                Text("Распознавание речи")
            } footer: {
                Text("Модели на диске: \(controller.runtime.diskUsage().byteSizeDescription). Модель работает на вашем Mac. Смена модели не трогает уже сделанные расшифровки.")
            }

            Section {
                Picker("Кто пишет итоги", selection: Bindable(settings).summaryProvider) {
                    ForEach(SummaryProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.summaryProvider {
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
                    Button(controller.isCheckingSummary ? "Проверка…" : "Проверить") {
                        controller.checkSummaryConnection()
                    }
                    .disabled(controller.isCheckingSummary)
                }
                DisclosureGroup("Дополнительно", isExpanded: $isAdvancedOpen) {
                    if settings.summaryProvider == .lmStudio {
                        TextField("Адрес сервера", text: Bindable(settings).summaryServerURL, prompt: Text("автоматически (lms server status)"))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Инструкция модели")
                            Spacer()
                            Button("Сбросить") {
                                settings.summaryPrompt = ""
                            }
                            .controlSize(.small)
                            .disabled(settings.summaryPrompt.isEmpty)
                        }
                        TextEditor(text: Bindable(settings).summaryPrompt)
                            .font(.body)
                            .frame(minHeight: 120)
                            .overlay(alignment: .topLeading) {
                                if settings.summaryPrompt.isEmpty {
                                    Text(ChatCompletionsProvider.defaultPrompt)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                        Text("Без заголовков `#`: панель показывает только жирный текст и переносы.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Итоги")
            } footer: {
                Text(providerNote)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.summaryProvider) {
            controller.refreshSummaryModels()
        }
    }

    @ViewBuilder
    private var openRouterRows: some View {
        HStack {
            if isKeyShown {
                TextField("Ключ", text: Bindable(settings).openRouterAPIKey)
            } else {
                SecureField("Ключ", text: Bindable(settings).openRouterAPIKey)
            }
            Button(isKeyShown ? "Скрыть" : "Показать") {
                isKeyShown.toggle()
            }
            .controlSize(.small)
        }
        TextField("Модель", text: Bindable(settings).openRouterModel, prompt: Text(OpenRouter.defaultModel))
    }

    @ViewBuilder
    private var lmStudioRows: some View {
        LabeledContent("Сервер", value: controller.summaryServerStatus ?? "проверка…")
        Picker("Модель", selection: Bindable(settings).summaryModel) {
            Text("Автоматически").tag("")
            ForEach(modelOptions, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        HStack {
            Spacer()
            if LocalModelSupport.isInstalled, controller.isServerDown {
                Button(controller.isStartingLocalModelServer ? "Запуск…" : "Запустить LM Studio") {
                    controller.startLocalModelServer()
                }
                .disabled(controller.isStartingLocalModelServer)
            }
            Button("Обновить список") {
                controller.refreshSummaryModels()
            }
        }
    }

    /// what this provider costs the user: money, memory, or another app to keep running
    private var providerNote: String {
        switch settings.summaryProvider {
        case .openRouter:
            "Ключ создаётся на openrouter.ai, платный по факту. Расшифровка уходит туда, звук остаётся здесь. Час разговора на gemini-flash обходится в несколько центов."
        case .builtIn:
            "Модель работает на этом Mac, без интернета и без ключей. Запускается на время итогов и занимает около 5 ГБ памяти, потом выгружается."
        case .lmStudio:
            LocalModelSupport.isInstalled
                ? "Итоги пишет модель, загруженная в LM Studio. Приложение должно быть запущено с включённым Local Server."
                : LocalModelSupport.manualInstructions
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
                Text(BundledSummary.current.subtitle)
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
                    Text("\(stage.title) \(Int(fraction * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: fraction)
                        .frame(width: 90)
                } else {
                    Text(stage.title)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } else if let failure = installer.failure {
            HStack(spacing: 8) {
                Text(failure)
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .help(failure)
                Button("Повторить") {
                    installer.install()
                }
            }
        } else if installer.isReady {
            HStack(spacing: 8) {
                Text("Скачана")
                    .foregroundStyle(.secondary)
                Button("Удалить") {
                    try? installer.remove()
                }
            }
        } else {
            Button("Скачать") {
                installer.install()
            }
        }
    }
}

// MARK: - Storage

private struct StoragePane: View {
    let controller: AppController

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        Form {
            Section {
                retentionPicker(
                    "Исходное аудио",
                    size: controller.storageUsage.rawAudioBytes,
                    selection: Bindable(settings).rawAudioRetention
                )
                retentionPicker(
                    "Нормализованное аудио",
                    size: controller.storageUsage.normalizedAudioBytes,
                    selection: Bindable(settings).normalizedAudioRetention
                )
                LabeledContent("Расшифровки, \(controller.storageUsage.textBytes.byteSizeDescription)", value: "всегда")
                HStack {
                    Text(cleanupHint)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Очистить сейчас") {
                        controller.runCleanupNow()
                    }
                    .disabled(controller.expiredAudioBytes == 0)
                }
            } header: {
                Text("Сколько хранить")
            } footer: {
                Text("Правила применяются раз в сутки. Исходное аудио — WAV с микрофона и системного звука, нормализованное — промежуточный файл для расшифровки.")
            }

            Section("Папка") {
                LabeledContent("Записи") {
                    Text(controller.callsDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Показать в Finder") {
                        controller.openCallsFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                Text(rule.title).tag(rule)
            }
        }
    }

    private var cleanupHint: String {
        controller.expiredAudioBytes > 0
            ? "Под правила попадает \(controller.expiredAudioBytes.byteSizeDescription)."
            : "Под текущие правила ничего не попадает."
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    let controller: AppController

    @State private var isCalendarPickerOpen = false
    @State private var isSecretShown = false

    private var settings: AppSettings {
        controller.settings
    }

    private var webhooks: WebhookService {
        controller.webhooks
    }

    var body: some View {
        Form {
            Section {
                Toggle("Брать название из календаря", isOn: Binding(
                    get: { settings.calendarEnabled },
                    set: { controller.setCalendarEnabled($0) }
                ))
                LabeledContent(accessLine) {
                    if controller.calendarService.isAuthorized {
                        Button("Выбрать календари…") {
                            isCalendarPickerOpen = true
                        }
                        .popover(isPresented: $isCalendarPickerOpen, arrowEdge: .bottom) {
                            CalendarPicker(controller: controller)
                        }
                    } else {
                        Button("Открыть доступ…") {
                            openPrivacySettings()
                        }
                    }
                }
                .disabled(!settings.calendarEnabled)
            } header: {
                Text("Календарь")
            } footer: {
                Text("\(coverageLine). Берётся событие, которое идёт в момент начала записи, ±5 минут. Запись по-прежнему начинается от звука в звонковом приложении.")
            }

            Section {
                Toggle("Отправлять расшифровку на свой сервис", isOn: Bindable(settings).webhookEnabled)
                TextField("Адрес", text: Bindable(settings).webhookURL, prompt: Text("https://example.com/webhook"))
                HStack {
                    if isSecretShown {
                        TextField("Секрет", text: Bindable(settings).webhookSecret)
                    } else {
                        SecureField("Секрет", text: Bindable(settings).webhookSecret)
                    }
                    Button(isSecretShown ? "Скрыть" : "Показать") {
                        isSecretShown.toggle()
                    }
                    .controlSize(.small)
                }
                HStack {
                    Text(webhooks.testResult ?? "Пробный запрос сервис должен пропустить.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(webhooks.isTesting ? "Отправка…" : "Отправить тест") {
                        webhooks.sendTest()
                    }
                    .disabled(webhooks.isTesting)
                }
            } header: {
                Text("Вебхук")
            } footer: {
                Text("POST после каждой готовой расшифровки: текст, участники, итоги и время звонка. Секрет уходит в заголовках Authorization и X-Podushka-Secret.")
            }

            Section("Журнал доставок") {
                if webhooks.recent.isEmpty {
                    Text("Пока ничего не отправлялось")
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

    private var accessLine: String {
        controller.calendarService.isAuthorized ? "Календари этого Mac" : "Доступ к календарю не выдан"
    }

    private var coverageLine: String {
        let coverage = controller.eventCoverage
        guard coverage.total > 0 else {
            return "Разговоров пока нет"
        }
        return "Событие нашлось у \(coverage.matched) из \(coverage.total) разговоров"
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
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
                Text("попытка \(delivery.attempt)")
            }

            Spacer(minLength: 0)

            Text([delivery.stateLabel, delivery.detailLine].filter { !$0.isEmpty }.joined(separator: " · "))
                .lineLimit(1)
                .foregroundStyle(stateColor)

            if inJournal, delivery.state == "failed", !controller.webhooks.sending.contains(delivery.callID) {
                Button("Повторить") {
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
            Text("Пустой список — берутся все календари")
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
