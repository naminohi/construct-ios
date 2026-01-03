//
//  ConstructMessengerApp.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI
import CoreData

@main
struct Construct_MessengerApp: App {
    static let persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "ConstructMessenger")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    @StateObject private var authViewModel = AuthViewModel(context: Construct_MessengerApp.persistentContainer.viewContext)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, Construct_MessengerApp.persistentContainer.viewContext)
                .environmentObject(authViewModel)
        }
    }
}
