import XCTest
@testable import MahzenCore

final class ExportPlanTests: XCTestCase {
    private func file(_ name: String, in folder: UUID?, size: Int64 = 10) -> FileRecord {
        FileRecord(id: UUID(), name: name, size: size, contentType: nil, folderID: folder)
    }

    func testFolderExportKeepsTreeAndSkipsTrash() {
        var index = VaultIndex()
        let tatil = Folder(name: "Tatil")
        let deniz = Folder(name: "Deniz", parentID: tatil.id)
        let bos = Folder(name: "Boş", parentID: tatil.id)
        var silinmis = Folder(name: "Silinmiş", parentID: tatil.id)
        silinmis.deletedAt = Date()
        let a = file("a.jpg", in: tatil.id), b = file("b.jpg", in: deniz.id)
        var c = file("c.jpg", in: deniz.id); c.deletedAt = Date()
        let d = file("d.jpg", in: silinmis.id)
        index.folders = [tatil, deniz, bos, silinmis]
        index.files = [a, b, c, d]

        let plan = index.exportPlan(files: [], folders: [tatil.id])
        XCTAssertEqual(plan.roots.count, 1)
        let root = plan.roots[0]
        XCTAssertEqual(root.name, "Tatil")
        XCTAssertEqual(Set(root.directories), [["Boş"], ["Deniz"]])
        XCTAssertEqual(root.files.map(\.record.name), ["a.jpg", "b.jpg"])
        XCTAssertEqual(root.files.map(\.directory), [[], ["Deniz"]])
        XCTAssertTrue(plan.looseFiles.isEmpty)
        XCTAssertEqual(plan.totalSize, 20)
    }

    func testNestedSelectionIsNotExportedTwice() {
        var index = VaultIndex()
        let ust = Folder(name: "Üst")
        let alt = Folder(name: "Alt", parentID: ust.id)
        let icteki = file("icteki.txt", in: alt.id)
        let disardaki = file("disardaki.txt", in: nil)
        index.folders = [ust, alt]
        index.files = [icteki, disardaki]

        let plan = index.exportPlan(files: [icteki.id, disardaki.id], folders: [ust.id, alt.id])
        XCTAssertEqual(plan.roots.map(\.name), ["Üst"])
        XCTAssertEqual(plan.looseFiles.map(\.name), ["disardaki.txt"])
        XCTAssertEqual(plan.allFiles.count, 2)
    }

    func testUnsafeNamesAreCleaned() {
        XCTAssertEqual(VaultIndex.safeFileName("a/b"), "a-b")
        XCTAssertEqual(VaultIndex.safeFileName(".."), "_")
        XCTAssertEqual(VaultIndex.safeFileName("  "), "_")
        XCTAssertEqual(VaultIndex.safeFileName("Rapor 2026"), "Rapor 2026")
    }
}
