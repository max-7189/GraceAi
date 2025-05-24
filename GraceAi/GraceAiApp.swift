//
//  GraceAiApp.swift
//  GraceAi
//
//  Created by 赵子源 on 2025/2/10.
//

import SwiftUI

@main
struct GraceAiApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
