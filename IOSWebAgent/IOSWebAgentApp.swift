import SwiftUI

@main
struct IOSWebAgentApp: App {
    @StateObject private var browser = BrowserController()
    @StateObject private var agent = AgentController()

    var body: some Scene {
        WindowGroup {
            ContentView(browser: browser, agent: agent)
                .onAppear {
                    agent.attach(browser: browser)
                }
        }
    }
}
