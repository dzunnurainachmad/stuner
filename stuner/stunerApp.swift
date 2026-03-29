import SwiftUI

@main
struct stunerApp: App {
    @State private var tunerState = TunerState()

    var body: some Scene {
        WindowGroup {
            TunerView(tunerState: tunerState)
        }
    }
}
