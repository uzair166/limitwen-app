import Foundation
import Testing
@testable import LimitwenCore

@Test func providerCatalogContainsOnlyTheFocusedProducts() throws {
    #expect(ProviderID.allCases.map(\.rawValue) == ["claude", "codex"])
    #expect(ProviderID.codex.name == "Codex & ChatGPT")
    #expect(ProviderID.codex.dashboard == "https://chatgpt.com/codex/settings/usage")
    #expect(Preferences().enabled == [.claude, .codex])
    #expect(Preferences().pinned == [.claude, .codex])
}

@Test(arguments: ["cursor", "grok", "gemini", "copilot", "future-provider"])
func retiredProviderPreferencesPreserveTheUsersChoices(retired: String) throws {
    let json = """
    {"meterStyle":"Bars","enabled":["claude","\(retired)","codex"],
     "pinned":["\(retired)","codex"],"showInitials":false,"alertsEnabled":true,"threshold":35,
     "resetReminders":{"claude:weekly":800000000,"\(retired):monthly":800000000}}
    """
    var preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    preferences.normalize()
    #expect(preferences.enabled == [.claude, .codex])
    #expect(preferences.visiblePins == [.codex])
    #expect(!preferences.showInitials)
    #expect(preferences.alertsEnabled && preferences.threshold == 35)
    #expect(preferences.resetReminders == ["claude:weekly": Date(timeIntervalSinceReferenceDate: 800000000)])
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
}

@Test func removingTheLastSelectedProviderDoesNotEnableOthers() throws {
    let json = #"{"meterStyle":"Bars","enabled":["cursor"],"pinned":["cursor"],"showInitials":false,"alertsEnabled":false,"threshold":20,"resetReminders":{}}"#
    var preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    preferences.normalize()
    #expect(preferences.enabled.isEmpty)
    #expect(preferences.visiblePins.isEmpty, "The app item must remain the fallback instead of adding new pins")
}

@Test func normalizationPreservesChosenOrderAndRemovesDuplicates() {
    var preferences = Preferences()
    preferences.enabled = [.codex, .claude, .codex]
    preferences.pinned = [.codex, .claude, .codex]
    preferences.normalize()
    #expect(preferences.enabled == [.codex, .claude])
    #expect(preferences.visiblePins == [.codex, .claude])
    preferences.normalize()
    #expect(preferences.visiblePins == [.codex, .claude])
}

@Test func legacyBarPreferenceIsIgnoredWithoutResettingOtherChoices() throws {
    let json = #"{"meterStyle":"Bars","enabled":["codex","claude"],"pinned":["codex"],"showInitials":false,"alertsEnabled":true,"threshold":35,"resetReminders":{"codex:weekly":900000000}}"#
    let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    #expect(preferences.enabled == [.codex, .claude])
    #expect(preferences.pinned == [.codex] && !preferences.showInitials)
    #expect(preferences.alertsEnabled && preferences.threshold == 35)
    #expect(preferences.resetReminders["codex:weekly"] != nil)
    let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
    #expect(saved["meterStyle"] == nil, "The removed presentation option must not be persisted")
}
