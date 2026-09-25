import Foundation
import Testing
@testable import Aquinas_iOS

struct InsightTreeResetTests {
    @Test func clearsInsightKeysFilesAndLeavesOtherDefaults() throws {
        let suite = "InsightTreeResetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("x", forKey: "aquinas.saved.insights.v1")
        defaults.set("x", forKey: "AquinasSeenInsightIDs")
        defaults.set("x", forKey: "aquinas.insight-tree.positions.v1")
        defaults.set("x", forKey: "aquinas.insight-tree.make-node-children.v1:global")
        defaults.set("keep", forKey: "aquinas.settings.hapticFeedback")

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let treeDirectory = root.appending(path: "Aquinas/InsightTree/CanvasState")
        try FileManager.default.createDirectory(at: treeDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: treeDirectory.appending(path: "a.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        InsightTreeReset.clearPersistedData(defaults: defaults, applicationSupport: root)

        #expect(defaults.object(forKey: "aquinas.saved.insights.v1") == nil)
        #expect(defaults.object(forKey: "AquinasSeenInsightIDs") == nil)
        #expect(defaults.object(forKey: "aquinas.insight-tree.positions.v1") == nil)
        #expect(defaults.object(forKey: "aquinas.insight-tree.make-node-children.v1:global") == nil)
        #expect(defaults.string(forKey: "aquinas.settings.hapticFeedback") == "keep")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Aquinas/InsightTree").path))
    }
}
