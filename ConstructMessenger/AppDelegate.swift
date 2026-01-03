//
//  AppDelegate.swift
//  Construct Messenger
//
//  Created by Claude on 03.01.2026.
//

import UIKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        Logger.log("Application did finish launching", level: .info)

        // CRITICAL: Register background tasks BEFORE app finishes launching
        // This must be done early in the launch process
        BackgroundFetchManager.shared.registerBackgroundTasks()

        // Check if user has enabled background fetch in settings
        // If enabled, schedule the first background fetch task
        let userDefaults = UserDefaults.standard
        let isBackgroundFetchEnabled = userDefaults.bool(forKey: "backgroundFetchEnabled")

        if isBackgroundFetchEnabled {
            BackgroundFetchManager.shared.scheduleBackgroundFetch()
            Logger.log("Background fetch is enabled, scheduled first task", level: .info)
        } else {
            Logger.log("Background fetch is disabled by user", level: .info)
        }

        // Initialize local notification manager
        // This ensures it's ready when needed
        _ = LocalNotificationManager.shared

        return true
    }

    // MARK: - Scene Lifecycle (iOS 13+)

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    // MARK: - Application Lifecycle

    func applicationWillTerminate(_ application: UIApplication) {
        Logger.log("Application will terminate", level: .info)

        // Cancel all scheduled background tasks if user has disabled them
        let userDefaults = UserDefaults.standard
        let isBackgroundFetchEnabled = userDefaults.bool(forKey: "backgroundFetchEnabled")

        if !isBackgroundFetchEnabled {
            BackgroundFetchManager.shared.cancelAllBackgroundTasks()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Logger.log("Application did become active", level: .debug)

        // Clear badge when app becomes active
        LocalNotificationManager.shared.clearBadge()

        // Remove all delivered notifications
        LocalNotificationManager.shared.removeAllNotifications()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.log("Application did enter background", level: .debug)

        // Ensure background fetch is scheduled if enabled
        let userDefaults = UserDefaults.standard
        let isBackgroundFetchEnabled = userDefaults.bool(forKey: "backgroundFetchEnabled")

        if isBackgroundFetchEnabled {
            BackgroundFetchManager.shared.scheduleBackgroundFetch()
        }
    }
}
