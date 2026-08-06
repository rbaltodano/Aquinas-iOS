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

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--litert-probe") {
                LiteRTDeviceProbeView()
            } else {
                ContentView(modelTasks: runtime.modelTasks)
                    .environment(\.aquinasModel, runtime.model)
                    .environment(\.embeddingProvider, runtime.embeddingProvider)
            }
        }
    }
}
