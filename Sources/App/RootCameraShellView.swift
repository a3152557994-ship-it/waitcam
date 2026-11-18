import SwiftUI

public struct RootCameraShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = WaitCamViewModel()

    public init() {}

    public var body: some View {
        CameraViewfinderView(viewModel: viewModel)
            .preferredColorScheme(.dark)
            .task {
                await viewModel.onAppear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.handleSceneDidBecomeActive() }
                }
            }
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
            .sheet(isPresented: $viewModel.isDarkroomPresented) {
                DarkroomVaultView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isSettingsPresented) {
                LabSettingsSheetView(viewModel: viewModel)
            }
            .sheet(item: $viewModel.activePaywall) { reason in
                ImpulsePaywallSheetView(storeKit: viewModel.storeKit, reason: reason)
            }
    }
}
