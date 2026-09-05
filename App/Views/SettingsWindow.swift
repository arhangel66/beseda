import ServiceManagement
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case recording
    case storage
    case integrations
    case summary
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recording:
            "Запись"
        case .storage:
            "Хранение"
        case .integrations:
            "Интеграции"
        case .summary:
            "Саммари"
        case .about:
            "О программе"
        }
    }

    var icon: String {
        switch self {
        case .recording:
            "mic"
        case .storage:
            "lock"
        case .integrations:
            "calendar"
        case .summary:
            "sparkles"
        case .about:
            "info.circle"
        }
    }
}

struct SettingsWindow: View {
    let controller: AppController

    @State private var section = SettingsSection.recording

    var body: some View {
        HStack(spacing: 0) {
            navigation

            Divider().overlay(Palette.separator)

            ScrollView {
                Group {
                    switch section {
                    case .recording:
                        RecordingSettings(controller: controller)
                    case .storage:
                        StorageSettings(controller: controller)
                    case .integrations:
                        IntegrationSettings(controller: controller)
                    case .summary:
                        SummarySettings(controller: controller)
                    case .about:
                        AboutSettings(controller: controller)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 700, height: 560)
        .background(Palette.sheetBackground)
        .foregroundStyle(Palette.textPrimary)
        .onAppear {
            consumeRequestedSection()
            controller.refreshStorageUsage()
            controller.refreshCalendar()
        }
        .onChange(of: controller.requestedSettingsSection) { _, _ in
            consumeRequestedSection()
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

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                let isSelected = item == section
                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12))
                        .frame(width: 14)
                    Text(item.title)
                        .font(.system(size: 13))
                }
                .foregroundStyle(isSelected ? Color.white : Palette.textPrimary)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Palette.accent : .clear, in: .rect(cornerRadius: Metrics.controlCorner))
                .contentShape(.rect)
                .onTapGesture { section = item }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 172)
    }
}

private struct RecordingSettings: View {
    let controller: AppController

    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow(
                label: "Включать запись при начале звонка",
                hint: "Zoom, Meet, Telegram — по звуку в системе",
                isOn: Bindable(settings).autoDetectEnabled
            )

            if settings.autoDetectEnabled {
                CallAppList(settings: settings)
            }

            SettingRow(
                label: "Останавливать после минуты тишины",
                hint: "Чтобы не писать пустоту после конца встречи",
                isOn: Bindable(settings).stopOnSilence
            )

            SettingRow(
                label: "Уведомлять, когда расшифровка готова",
                hint: "Баннер с названием разговора",
                isOn: Bindable(settings).notifyWhenReady
            )

            SettingRow(
                label: "Запускать при входе в систему",
                hint: loginItemNote ?? "Beseda будет ждать звонка в меню-баре",
                isOn: Binding(get: { isLoginItemOn }, set: { setLoginItem($0) })
            )

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.okText)
                Text(settings.webhookEnabled
                    ? "Всё обрабатывается на этом Mac. В сеть уходит только расшифровка — на адрес из раздела «Интеграции»."
                    : "Всё обрабатывается на этом Mac. Ни звук, ни текст не уходят в сеть.")
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ok.opacity(0.12), in: .rect(cornerRadius: 9))
        }
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

private struct CallAppList: View {
    @Bindable var settings: AppSettings

    /// Telegram ships under three bundle ids; the list offers each app once
    private var appNames: [String] {
        var seen: Set<String> = []
        return CallDetector.knownCallApps.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appNames, id: \.self) { name in
                HStack(spacing: 8) {
                    Toggle(name, isOn: Binding(
                        get: { isEnabled(name) },
                        set: { setEnabled(name, $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                    Spacer()
                }
            }
        }
        .padding(.leading, 4)
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

private struct IntegrationSettings: View {
    let controller: AppController

    @State private var isCalendarPickerOpen = false

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow(
                label: "Брать название из календаря",
                hint: "Событие, которое идёт в момент начала записи, ±5 минут",
                isOn: Binding(
                    get: { settings.calendarEnabled },
                    set: { controller.setCalendarEnabled($0) }
                )
            )

            HStack(spacing: 11) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accessLine)
                        .font(.system(size: 12.5))
                    Text(coverageLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer(minLength: 0)

                if controller.calendarService.isAuthorized {
                    Button("Выбрать календари") {
                        isCalendarPickerOpen = true
                    }
                    .controlSize(.small)
                    .popover(isPresented: $isCalendarPickerOpen, arrowEdge: .bottom) {
                        CalendarPicker(controller: controller)
                    }
                } else {
                    Button("Открыть доступ") {
                        openPrivacySettings()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.fillHover, in: .rect(cornerRadius: 9))
            .opacity(settings.calendarEnabled ? 1 : 0.5)

            Text("Календарь только даёт разговору имя и показывает, что впереди. Запись по-прежнему начинается от звука в звонковом приложении.")
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Palette.textTertiary)

            Divider()

            WebhookSettings(controller: controller)
        }
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

private struct WebhookSettings: View {
    let controller: AppController

    @State private var isSecretShown = false

    private var settings: AppSettings {
        controller.settings
    }

    private var webhooks: WebhookService {
        controller.webhooks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingRow(
                label: "Отправлять расшифровку на свой сервис",
                hint: "POST после каждой готовой расшифровки",
                isOn: Bindable(settings).webhookEnabled
            )

            Text("Это единственное, что покидает ваш Mac. Уходит только на этот адрес: расшифровка, участники, саммари и время звонка.")
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Palette.textTertiary)

            addressCard
                .opacity(settings.webhookEnabled ? 1 : 0.5)

            testRow

            journal
        }
        .onAppear {
            webhooks.refresh()
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Адрес")
                    .font(.system(size: 12.5))
                    .frame(width: 56, alignment: .leading)
                TextField("https://kushetka.slotik.app/api/webhooks/krisp", text: Bindable(settings).webhookURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Palette.fillHover, in: .rect(cornerRadius: Metrics.controlCorner))
            }

            HStack(spacing: 8) {
                Text("Секрет")
                    .font(.system(size: 12.5))
                    .frame(width: 56, alignment: .leading)
                Group {
                    if isSecretShown {
                        TextField("", text: Bindable(settings).webhookSecret)
                    } else {
                        SecureField("", text: Bindable(settings).webhookSecret)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Palette.fillHover, in: .rect(cornerRadius: Metrics.controlCorner))

                Button(isSecretShown ? "Скрыть" : "Показать") {
                    isSecretShown.toggle()
                }
            }

            Text("Уходит в заголовках Authorization и X-Podushka-Secret")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.windowBackground.opacity(0.5), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Palette.separator, lineWidth: 0.5)
        }
    }

    private var testRow: some View {
        HStack(spacing: 10) {
            Button(webhooks.isTesting ? "Отправляю…" : "Отправить тест") {
                webhooks.sendTest()
            }
            .buttonStyle(.borderedProminent)
            .disabled(webhooks.isTesting)

            Text(webhooks.testResult ?? "Отправлю пробный запрос, сервис его пропустит")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Журнал доставок")
                .font(.system(size: 12.5, weight: .semibold))

            if webhooks.recent.isEmpty {
                Text("Пока ничего не отправлялось")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(webhooks.recent) { delivery in
                    WebhookDeliveryRow(delivery: delivery, inJournal: true, controller: controller)
                }
            }
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
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 110, alignment: .leading)

            if inJournal {
                Text(delivery.callTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
            } else {
                Text("попытка \(delivery.attempt)")
                    .font(.system(size: 12))
            }

            Spacer(minLength: 0)

            Text([delivery.stateLabel, delivery.detailLine].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(stateColor)

            if inJournal, delivery.state == "failed", !controller.webhooks.sending.contains(delivery.callID) {
                Button("Повторить") {
                    controller.webhooks.sendNow(callID: delivery.callID)
                }
                .controlSize(.small)
            }
        }
    }

    private var stateColor: Color {
        switch delivery.state {
        case "delivered":
            Palette.okText
        case "failed":
            Palette.recording
        default:
            Palette.textSecondary
        }
    }
}

private struct CalendarPicker: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Пустой список — беру все календари")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)

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
                .font(.system(size: 12.5))
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

private struct SummarySettings: View {
    let controller: AppController

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            serverCard
            modelRow
            promptCard
            checkRow
        }
        .onAppear {
            controller.refreshSummaryModels()
        }
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.summaryServerStatus ?? "Проверяю…")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)

            HStack(spacing: 8) {
                TextField("автоматически (lms server status)", text: Bindable(settings).summaryServerURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Palette.fillHover, in: .rect(cornerRadius: Metrics.controlCorner))

                Button("Обновить") {
                    controller.refreshSummaryModels()
                }

                if LocalModelSupport.isInstalled, controller.isServerDown {
                    Button(controller.isStartingLocalModelServer ? "Запускаю…" : "Запустить") {
                        controller.startLocalModelServer()
                    }
                    .disabled(controller.isStartingLocalModelServer)
                }
            }

            if !LocalModelSupport.isInstalled {
                Text(LocalModelSupport.manualInstructions)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.windowBackground.opacity(0.5), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Palette.separator, lineWidth: 0.5)
        }
    }

    private var modelRow: some View {
        HStack(spacing: 10) {
            Text("Модель")
                .font(.system(size: 12.5))
            Spacer(minLength: 0)
            Picker("", selection: Bindable(settings).summaryModel) {
                Text("Автоматически").tag("")
                ForEach(modelOptions, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 300)
        }
    }

    /// the stored model always appears, even one the server no longer lists, so the picker never silently changes it
    private var modelOptions: [String] {
        guard !settings.summaryModel.isEmpty, !controller.summaryModels.contains(settings.summaryModel) else {
            return controller.summaryModels
        }
        return [settings.summaryModel] + controller.summaryModels
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Промпт")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                Button("Сбросить") {
                    settings.summaryPrompt = ""
                }
                .controlSize(.small)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Bindable(settings).summaryPrompt)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)

                if settings.summaryPrompt.isEmpty {
                    Text(LocalModelProvider.defaultPrompt)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }

            Text("Без заголовков `#` — панель показывает только жирный текст и переносы.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.windowBackground.opacity(0.5), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Palette.separator, lineWidth: 0.5)
        }
    }

    private var checkRow: some View {
        HStack(spacing: 10) {
            Button(controller.isCheckingSummary ? "Проверяю…" : "Проверить") {
                controller.checkSummaryConnection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isCheckingSummary)

            if let summaryCheckResult = controller.summaryCheckResult {
                Text(summaryCheckResult)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

private struct AboutSettings: View {
    let controller: AppController

    private var updater: AppUpdater {
        controller.updater
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Beseda \(updater.version)")
                .font(.system(size: 15, weight: .semibold))

            if updater.isAvailable {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Обновления ставятся сами, раз в час проверяется новая версия.")
                        .font(.system(size: 12.5))
                    Text(lastCheckNote)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }

                Button("Проверить сейчас…") {
                    updater.checkForUpdates()
                }
            } else {
                Text("Сборка для разработки: обновления не проверяются.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var lastCheckNote: String {
        guard let date = updater.lastCheckDate else {
            return "Ещё не проверялось"
        }
        return "Последняя проверка: " + date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SettingRow: View {
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                Text(hint)
                    .font(.system(size: 11.5))
                    .lineSpacing(1)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct StorageSettings: View {
    let controller: AppController

    private var settings: AppSettings {
        controller.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Что удалять и когда")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("правило применяется раз в сутки")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
            }

            VStack(spacing: 0) {
                headerRow

                KeepRow(
                    label: "Исходное аудио",
                    hint: "WAV с микрофона и системного звука",
                    size: controller.storageUsage.rawAudioBytes,
                    selection: Bindable(settings).rawAudioRetention,
                    onChange: { controller.refreshStorageUsage() }
                )
                .overlay(alignment: .top) { rowSeparator }

                KeepRow(
                    label: "Нормализованное аудио",
                    hint: "Промежуточный файл для расшифровки",
                    size: controller.storageUsage.normalizedAudioBytes,
                    selection: Bindable(settings).normalizedAudioRetention,
                    onChange: { controller.refreshStorageUsage() }
                )
                .overlay(alignment: .top) { rowSeparator }

                KeepRow(
                    label: "Расшифровки",
                    hint: "Текст занимает мало и остаётся всегда",
                    size: controller.storageUsage.textBytes,
                    selection: .constant(.forever),
                    isFixed: true
                )
                .overlay(alignment: .top) { rowSeparator }
            }
            .background(Palette.windowBackground.opacity(0.5), in: .rect(cornerRadius: Metrics.cardCorner))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCorner)
                    .strokeBorder(Palette.separator, lineWidth: 0.5)
            }

            HStack(spacing: 12) {
                Text(cleanupHint)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Button("Очистить сейчас") {
                    controller.runCleanupNow()
                }
                .buttonStyle(.borderedProminent)
            }

            Rectangle()
                .fill(Palette.separator)
                .frame(height: 0.5)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Папка")
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(Palette.textSecondary)
                Text(controller.callsDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Показать") {
                    controller.openCallsFolder()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
            .font(.system(size: 12))

            Rectangle()
                .fill(Palette.separator)
                .frame(height: 0.5)

            engineBlock
        }
    }

    /// which model recognises speech and what the downloaded ones take on disk
    private var engineBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Речевая модель")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(controller.runtime.diskUsage().byteSizeDescription)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }

            SpeechModelList(controller: controller)

            Text("Модель работает на вашем Mac, звук никуда не уходит. Смена модели не трогает уже сделанные расшифровки.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cleanupHint: String {
        controller.expiredAudioBytes > 0
            ? "Сейчас под правила попадает \(controller.expiredAudioBytes.byteSizeDescription)."
            : "Под текущие правила ничего не попадает."
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Файлы").frame(maxWidth: .infinity, alignment: .leading)
            Text("Объём").frame(width: 74, alignment: .trailing)
            Text("Хранить").frame(width: 232, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.4)
        .textCase(.uppercase)
        .foregroundStyle(Palette.textQuaternary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.fillHover)
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.5)
    }
}

private struct KeepRow: View {
    let label: String
    let hint: String
    let size: Int64
    @Binding var selection: RetentionRule
    var onChange: () -> Void = {}
    var isFixed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5))
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(size.byteSizeDescription)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 74, alignment: .trailing)

            HStack(spacing: 2) {
                ForEach(options) { option in
                    let isOn = isFixed || option == selection
                    Text(option.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Palette.selectedTabBackground)
                                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            guard !isFixed else {
                                return
                            }
                            selection = option
                            onChange()
                        }
                }
            }
            .padding(2)
            .frame(width: 232)
            .background(Palette.fillSubtle, in: .rect(cornerRadius: Metrics.controlCorner))
            .opacity(isFixed ? 0.55 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var options: [RetentionRule] {
        isFixed ? [.forever] : RetentionRule.allCases
    }
}
