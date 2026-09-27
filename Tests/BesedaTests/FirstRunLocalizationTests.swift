import Foundation
import Testing
@testable import Beseda

@Test func firstRunCopyIsLocalizedWithoutRequestingPermissions() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    #expect(FirstRunText.get("Аудио остаётся на этом Mac", locale: english) == "Audio stays on this Mac")
    #expect(FirstRunText.get("Аудио остаётся на этом Mac", locale: russian) == "Аудио остаётся на этом Mac")
    #expect(FirstRunText.get("Доступ к микрофону запрещён в системных настройках", locale: english).contains("System Settings"))
    #expect(FirstRunText.get("Доступ к микрофону запрещён в системных настройках", locale: russian).contains("системных настройках"))
    #expect(FirstRunText.get("Parakeet понимает 25 языков, GigaAM — только русский, зато почти вдвое легче", locale: english).contains("Russian only"))
    #expect(FirstRunText.get("Беседа записывает звонки и превращает их в текст прямо здесь, аудио в сеть не уходит. Текст уходит в облако, только если вы сами включите: итоги через OpenRouter, Jev или живые тезисы с ключом.", locale: english).contains("cloud only if"))
    #expect(FirstRunText.get("Разрешить доступ", locale: english) == "Allow access")
    #expect(FirstRunText.get("Разрешить доступ", locale: russian) == "Разрешить доступ")
}
