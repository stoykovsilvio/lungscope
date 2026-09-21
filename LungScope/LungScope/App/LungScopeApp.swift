//
//  LungScopeApp.swift
//  LungScope
//
//  Created by Stoykov, Silvio on 29.06.26.
//

import SwiftUI
import UserNotifications

@main
struct LungScopeApp: App {
    @StateObject private var viewModel = AssessmentViewModel()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDisplayDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            AssessmentCoordinatorView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.resultsStore)
        }
    }
}

// Shows notification banners even when the app is in the foreground.
private final class NotificationDisplayDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDisplayDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
