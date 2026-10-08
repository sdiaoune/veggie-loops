import Foundation
import XCTest
@testable import VLCore

final class ProjectTests: XCTestCase {
    func testDemoRoundtripRetainsEveryMusicalSetting() throws {
        let project = VLProject.demo()
        XCTAssertEqual(try ProjectDocument.decode(ProjectDocument.encode(project)), project)
        XCTAssertEqual(project.tracks.count, 5)
        XCTAssertFalse(project.clips.isEmpty)
        XCTAssertNoThrow(try project.validated())
    }

    func testMalformedProjectsNeverReachAudioRenderer() throws {
        var project = VLProject.demo()
        project.tempo = .nan
        XCTAssertThrowsError(try project.validated())
        project = .demo(); project.tracks[0].notes[0].beat = -1
        XCTAssertThrowsError(try project.validated())
        project = .demo(); project.clips[0].trackID = UUID()
        XCTAssertThrowsError(try project.validated())
        project = .demo(); project.tracks[0].mixer.delaySend = 2
        XCTAssertThrowsError(try project.validated())
        project = .demo(); project.tracks.append(project.tracks[0])
        XCTAssertThrowsError(try project.validated())
    }

    func testUnsupportedAndOversizedDocumentsFailWithUsefulErrors() throws {
        var project = VLProject.empty(); project.formatVersion = 99
        XCTAssertThrowsError(try project.validated()) { XCTAssertTrue($0.localizedDescription.contains("version")) }
        XCTAssertThrowsError(try ProjectDocument.decode(Data(repeating: 0, count: 4_000_001)))
        XCTAssertThrowsError(try ProjectDocument.decode(Data("{bad}".utf8)))
    }

    func testSavingToDiskIsLossless() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VL-test-\(UUID()).vlp")
        defer { try? FileManager.default.removeItem(at: url) }
        let project = VLProject.demo()
        try ProjectDocument.save(project, to: url)
        XCTAssertEqual(try ProjectDocument.load(from: url), project)
    }
}
