import XCTest

extension String {
    func normalizedImageName() -> String {
        let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789éè")

        return self.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil)
            .filter { allowedCharacters.contains($0) }
    }
}

class StringNormalizationTests: XCTestCase {
    
    func testNormalizedImageName_withAccents() {
        let input = "L'Étrange Noël de Monsieur Jack"
        let expectedOutput = "LEtrangeNoelDeMonsieurJack"
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }

    func testNormalizedImageName_withSpaces() {
        let input = "Pirates of the Caribbean"
        let expectedOutput = "PiratesOfTheCaribbean"
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }

    func testNormalizedImageName_withSpecialCharacters() {
        let input = "It's a Small World - After All!"
        let expectedOutput = "ItsASmallWorldAfterAll"
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }

    func testNormalizedImageName_withNumbers() {
        let input = "Star Tours - The Adventures Continue 3D"
        let expectedOutput = "StarToursTheAdventuresContinue3D"
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }

    func testNormalizedImageName_withMixedCase() {
        let input = "Big Thunder Mountain"
        let expectedOutput = "BigThunderMountain"
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }

    func testNormalizedImageName_withEmptyString() {
        let input = ""
        let expectedOutput = ""
        let output = input.normalizedImageName()
        XCTAssertEqual(output, expectedOutput)
    }
}
