//
//  Aquinas_iOSApp.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/11/26.
//

import SwiftUI

@main
struct Aquinas_iOSApp: App {
    private let runtime = AquinasApplicationRuntime.shared

    /// True when Xcode's test runner launched the app only to host the unit test bundle.
    private static let isHostingUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }()

    var body: some Scene {
        WindowGroup {
            if Self.isHostingUnitTests {
                // Unit tests don't use the interface. Skipping it keeps its animations off the
                // main actor, which many tests share (it starved timing tests on CI simulators).
                Color.clear
            } else if ProcessInfo.processInfo.arguments.contains("--litert-probe") {
                LiteRTDeviceProbeView()
            } else {
                ContentView(modelTasks: runtime.modelTasks)
                    .environment(\.aquinasModel, runtime.model)
                    .environment(\.embeddingProvider, runtime.embeddingProvider)
            }
        }
    }
}
