import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateController {
    let updaterController: SPUStandardUpdaterController
    private var performedLaunchCheck = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkInBackgroundOnLaunch() {
        guard !performedLaunchCheck else { return }
        performedLaunchCheck = true
        guard updaterController.updater.automaticallyChecksForUpdates else { return }
        updaterController.updater.checkForUpdatesInBackground()
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    @MainActor
    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("检查更新…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
