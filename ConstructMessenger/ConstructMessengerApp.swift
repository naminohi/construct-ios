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
    // IMPORTANT: AppDelegate for background tasks registration
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static let persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "ConstructMessenger")

        // Enable automatic lightweight migration for Core Data model changes
        if let description = container.persistentStoreDescriptions.first {
            description.shouldInferMappingModelAutomatically = true
            description.shouldMigrateStoreAutomatically = true
        }

        // ✅ FIX: Wait for persistent stores to load before returning container
        // This ensures persistentStoreCoordinator is ready when we use the context
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { description, error in
            if let error = error {
                loadError = error
                print("❌ Failed to load persistent stores: \(error)")
            } else {
                print("✅ Persistent stores loaded successfully")
            }
            semaphore.signal()
        }

        // Wait for stores to load (with timeout)
        let timeout = semaphore.wait(timeout: .now() + 10)
        if timeout == .timedOut {
            fatalError("Timeout waiting for persistent stores to load")
        }

        if let error = loadError {
            fatalError("Unable to load persistent stores: \(error)")
        }

        return container
    }()

    @StateObject private var authViewModel = AuthViewModel(context: Construct_MessengerApp.persistentContainer.viewContext)
    // TODO: Add PIN code security state management
    // @StateObject private var securityViewModel = SecurityViewModel()
    // See: TODO.md for detailed requirements

    var body: some Scene {
        WindowGroup {
            // TODO: Wrap ContentView with PIN lock screen when security is enabled
            // Example:
            // if securityViewModel.isPinEnabled && !securityViewModel.isUnlocked {
            //     PinCodeView()
            //         .environmentObject(securityViewModel)
            // } else {
            //     ContentView()
            //         .environment(\.managedObjectContext, ...)
            //         .environmentObject(authViewModel)
            // }
            ContentView()
                .environment(\.managedObjectContext, Construct_MessengerApp.persistentContainer.viewContext)
                .environmentObject(authViewModel)
                .environmentObject(appDelegate.deepLinkHandler)
                // TODO: Add environment object for security
                // .environmentObject(securityViewModel)
        }
    }
}
