import XCTest
@testable import MahzenCore

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        Localization.language = .tr
    }

    func testSystemLanguageSelection() {
        XCTAssertEqual(Localization.systemLanguage(preferences: ["tr-TR", "en-US"]), .tr)
        XCTAssertEqual(Localization.systemLanguage(preferences: ["en-GB", "tr-TR"]), .en)
        XCTAssertEqual(Localization.systemLanguage(preferences: ["de-DE", "tr-TR"]), .tr)
        XCTAssertEqual(Localization.systemLanguage(preferences: ["de-DE", "fr-FR"]), .en, "Türkçe tercih edilmiyorsa İngilizce")
        XCTAssertEqual(Localization.systemLanguage(preferences: []), .en)
    }

    func testTurkishIsReturnedUnchanged() {
        Localization.language = .tr
        XCTAssertEqual(L("Parola yanlış."), "Parola yanlış.")
        XCTAssertEqual(LN("{0} dosya", 3), "3 dosya")
        XCTAssertEqual(VaultError.passwordTooShort(8).localizedDescription, "Parola en az 8 karakter olmalı.")
    }

    func testEnglishTranslationAndPlurals() {
        Localization.language = .en
        XCTAssertEqual(L("Parola yanlış."), "Wrong password.")
        XCTAssertEqual(LN("{0} dosya", 1), "1 file")
        XCTAssertEqual(LN("{0} dosya", 3), "3 files")
        XCTAssertEqual(L("Taşındı: {0}", "Tatil"), "Moved to Tatil")
        XCTAssertEqual(VaultError.passwordTooShort(8).localizedDescription, "The password must be at least 8 characters.")
        XCTAssertEqual(L("sözlükte olmayan metin"), "sözlükte olmayan metin")
    }

    func testEnglishTableKeepsPlaceholders() {
        for (key, value) in englishStrings {
            for form in value.components(separatedBy: "|") {
                for i in 0..<4 where key.contains("{\(i)}") {
                    XCTAssertTrue(form.contains("{\(i)}"), "\"\(key)\" çevirisinde {\(i)} eksik")
                }
            }
        }
    }
}
