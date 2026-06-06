import SwiftUI

@main
struct enkapp_clipApp: App {
    @State private var model = AppClipViewModel()

    var body: some Scene {
        WindowGroup {
            AppClipRootView(model: model)
                .onOpenURL { url in
                    model.apply(invocation: AppClipInvocation(url: url))
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    model.apply(invocation: AppClipInvocation(url: url))
                }
        }
    }
}
