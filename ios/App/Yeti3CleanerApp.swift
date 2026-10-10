import SwiftUI

@main struct Yeti3CleanerApp: App {
    @StateObject private var model = CleanerModel()
    @StateObject private var settings = SettingsStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).environmentObject(settings) }
    }
}
