import SwiftUI

struct ConversationsWindow: View {
    let controller: AppController

    @State private var player = CallPlayer()
    @State private var isSidebarOpen = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().overlay(Palette.separator)

            HStack(spacing: 0) {
                if isSidebarOpen {
                    CallSidebar(controller: controller)
                    Divider().overlay(Palette.separator)
                }
                CallDetailView(controller: controller, player: player, isReadingCentred: !isSidebarOpen)
                    .frame(minWidth: 520, maxWidth: .infinity)
            }
        }
        .background(Palette.windowBackground)
        .foregroundStyle(Palette.textPrimary)
        .frame(minWidth: 880, minHeight: 560)
        // the window hides its title bar; without this the toolbar starts below the traffic lights
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .bottom) {
            if let toast = controller.toast {
                ToastOverlay(text: toast)
                    .padding(.bottom, 88)
            }
        }
        .animation(.easeOut(duration: 0.18), value: controller.toast)
        .onAppear {
            controller.refreshCallBrowser(selectFirstIfNeeded: true)
            controller.refreshStorageUsage()
            controller.refreshCalendar()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // the traffic lights live in this strip, so the row opens with room for them
            Color.clear.frame(width: 56, height: 1)

            Button {
                isSidebarOpen.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(isSidebarOpen ? Palette.accent : Palette.textTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)

            if isSidebarOpen {
                Text("Разговоры")
                    .font(.system(size: 13, weight: .semibold))
            }

            searchField

            Spacer(minLength: 8)

            autoRecordPill
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Palette.toolbarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            TextField(
                "Искать в разговорах",
                text: Bindable(controller).searchQuery
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))

            if !controller.searchQuery.isEmpty {
                Button {
                    controller.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 260, height: Metrics.controlHeight)
        .background(Palette.fillSubtle, in: .rect(cornerRadius: Metrics.controlCorner))
    }

    private var autoRecordPill: some View {
        SettingsSectionLink(section: "recording", controller: controller) {
            HStack(spacing: 7) {
                Circle()
                    .fill(controller.settings.autoDetectEnabled ? Palette.ok : Palette.textQuaternary)
                    .frame(width: 7, height: 7)
                Text(controller.settings.autoDetectEnabled ? "Автозапись включена" : "Автозапись выключена")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.controlHeight)
        }
        .buttonStyle(.plain)
    }
}
