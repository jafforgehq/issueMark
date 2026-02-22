//
//  IssueMarkApp.swift
//  IssueMark
//
//  Created by Feđa Hadžiselimović on 22. 2. 2026..
//

import SwiftUI

@main
struct IssueMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
