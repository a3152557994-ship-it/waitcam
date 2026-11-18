import SwiftUI

public struct CameraViewfinderView: View {
    @ObservedObject var viewModel: WaitCamViewModel

    public init(viewModel: WaitCamViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.047)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                topUtilityBar
                viewfinderFrame
                filmStockStrip
                shutterDeck
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)

            // Full-screen xenon / Retina screen flash burst
            if viewModel.shutterFlashPulse || viewModel.cameraService.isFrontScreenFlashActive {
                Color.white
                    .opacity(viewModel.cameraService.isFrontScreenFlashActive ? 0.96 : 0.72)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Floating toast or error pill
            VStack {
                if let error = viewModel.errorBanner {
                    toastBanner(text: error, isError: true)
                } else if let toast = viewModel.bannerToast {
                    toastBanner(text: toast, isError: false)
                }
                Spacer()
            }
            .padding(.top, 58)
            .padding(.horizontal, 20)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Top Controls

    private var topUtilityBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.cycleFlashPreference()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.flashPreference.symbolName)
                        .font(.caption.weight(.bold))
                    Text(viewModel.flashPreference.displayTitle)
                        .font(.caption.monospaced().weight(.bold))
                }
                .foregroundStyle(viewModel.flashPreference == .on ? Color.black : Color.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    viewModel.flashPreference == .on
                        ? Color(red: 1.0, green: 0.48, blue: 0.17)
                        : Color.white.opacity(0.12),
                    in: Capsule()
                )
            }

            Button {
                Task { await viewModel.cameraService.toggleCameraPosition() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("切换前后镜头")

            Spacer()

            durationSelectorMenu

            Button {
                viewModel.isSettingsPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("实验室设置")
        }
    }

    private var durationSelectorMenu: some View {
        Menu {
            ForEach(DevelopDuration.productionCases) { duration in
                Button {
                    viewModel.selectDevelopDuration(duration)
                } label: {
                    let locked = duration.requiresCustomTimerUnlock && !viewModel.storeKit.canUseParallelRollsAndCustomTimer
                    let active = viewModel.selectedDuration == duration
                    Label(
                        locked ? "\(duration.detailLabel)（解锁）" : duration.detailLabel,
                        systemImage: active ? "checkmark.circle.fill" : (locked ? "lock.fill" : "clock")
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                    .font(.caption.weight(.bold))
                Text(viewModel.selectedDuration.badgeTitle)
                    .font(.caption.monospaced().weight(.bold))
                if !viewModel.storeKit.canUseParallelRollsAndCustomTimer {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().stroke(Color(red: 1.0, green: 0.42, blue: 0.17).opacity(0.45), lineWidth: 1)
            }
        }
    }

    // MARK: - 3:4 Analog Viewfinder

    private var viewfinderFrame: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = min(proxy.size.height, w * (4.0 / 3.0))

            ZStack {
                Group {
                    if viewModel.cameraService.isUsingSimulatedSensor {
                        SimulatedViewfinderFeed(
                            stock: viewModel.selectedStock,
                            frameNumber: (viewModel.activeRoll?.shots.count ?? 0) + 1,
                            flashOn: viewModel.flashPreference != .off
                        )
                    } else if viewModel.cameraService.authorizationStatus == .authorized {
                        CameraPreviewRepresentable(session: viewModel.cameraService.session)
                    } else {
                        cameraPermissionPlaceholder
                    }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    viewfinderOpticalOverlay(width: w, height: h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func viewfinderOpticalOverlay(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Subtle stock atmosphere tint in preview
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(stockPreviewTint(viewModel.selectedStock))
                .allowsHitTesting(false)

            // Crisp optical viewfinder frame border
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)

            // Center analog focus reticle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    .frame(width: 54, height: 54)
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 12, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 1, height: 12)
            }
            .allowsHitTesting(false)

            // Corner HUD: top-left roll info + top-right zero-watermark pledge + bottom-right live date stamp preview
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.42, blue: 0.17))
                            .frame(width: 7, height: 7)
                        Text(viewModel.activeRoll?.title ?? "待装新卷")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())

                    Spacer()

                    if viewModel.cameraService.isUsingSimulatedSensor {
                        Text("SIMULATOR LAB")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.65), in: Capsule())
                    } else {
                        Text("NO WATERMARK")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                }
                .padding(14)

                Spacer()

                HStack {
                    if let roll = viewModel.activeRoll, !roll.shots.isEmpty {
                        Text("🔒 暗房锁定 \(roll.formattedCountdown(at: viewModel.now))")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.28))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                    Spacer()
                    if let stamp = viewModel.selectedDateStamp.formattedStamp(for: viewModel.now) {
                        Text(stamp)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1.0, green: 0.46, blue: 0.14))
                            .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.0).opacity(0.85), radius: 5)
                    }
                }
                .padding(14)
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
        }
    }

    private var cameraPermissionPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.12))

            VStack(spacing: 14) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 42))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.17))
                Text("需要相机权限以拍摄延迟显影胶片")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("所有照片仅在本地 CoreImage 滤镜渲染后加密封存，绝不上传任何云端服务器。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("前往系统设置开启相机") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.17))
            }
        }
    }

    // MARK: - Film Stock Dial + Frame Counter

    private var filmStockStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Text("FILM ROLL")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                let shots = viewModel.activeRoll?.shots.count ?? 0
                let maxShots = viewModel.activeRoll?.maxShots ?? 24
                Text(String(format: "%02d / %02d EXP", shots, maxShots))
                    .font(.caption.monospacedDigit().weight(.heavy))
                    .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.22))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStock.allCases) { stock in
                        let isSelected = viewModel.selectedStock == stock
                        let isLocked = stock.requiresLifetimePro && !viewModel.storeKit.hasFullPro
                        Button {
                            viewModel.selectFilmStock(stock)
                        } label: {
                            HStack(spacing: 6) {
                                Text(stock.displayName)
                                    .font(.caption.weight(.bold))
                                if stock == .party2AM {
                                    Text("免费")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.24), in: Capsule())
                                        .foregroundStyle(.green)
                                } else if isLocked {
                                    Image(systemName: "crown.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .foregroundStyle(isSelected ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? Color(red: 1.0, green: 0.48, blue: 0.18)
                                    : Color.white.opacity(0.09),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(
                                    isSelected ? Color.clear : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Mechanical Shutter Deck

    private var shutterDeck: some View {
        HStack(alignment: .center, spacing: 18) {
            darkroomVaultButton
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.captureShutter() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.32), lineWidth: 3)
                        .frame(width: 78, height: 78)
                    Circle()
                        .stroke(Color(red: 1.0, green: 0.42, blue: 0.17), lineWidth: 2)
                        .frame(width: 68, height: 68)
                    Circle()
                        .fill(viewModel.isCapturing ? Color.orange : Color.white)
                        .frame(width: 58, height: 58)
                        .scaleEffect(viewModel.isCapturing ? 0.90 : 1.0)
                }
            }
            .disabled(viewModel.isCapturing)
            .accessibilityLabel("拍摄胶片")

            newRollButton
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private var darkroomVaultButton: some View {
        Button {
            viewModel.isDarkroomPresented = true
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.readyToRevealCount > 0 ? "film.stack.fill" : "lock.shield.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            viewModel.readyToRevealCount > 0
                                ? Color.green
                                : Color(red: 1.0, green: 0.56, blue: 0.22)
                        )
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if viewModel.readyToRevealCount > 0 {
                        Text("\(viewModel.readyToRevealCount)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                            .offset(x: 6, y: -4)
                    } else if !viewModel.developingRolls.isEmpty {
                        Text("\(viewModel.developingRolls.count)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 1.0, green: 0.56, blue: 0.22), in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }

                if viewModel.readyToRevealCount > 0 {
                    Text("✨ 待开封")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                } else if let primary = viewModel.primaryCountdownRoll {
                    Text(primary.formattedCountdown(at: viewModel.now))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.22))
                } else {
                    Text("暗房保险箱")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private var newRollButton: some View {
        Button {
            _ = viewModel.requestNewRoll()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !viewModel.storeKit.canUseParallelRollsAndCustomTimer && !viewModel.developingRolls.isEmpty {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(4)
                            .background(Color.orange, in: Circle())
                            .offset(x: 5, y: -4)
                    }
                }

                Text("封卷装新卷")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func toastBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "film")
                .foregroundStyle(isError ? .red : Color(red: 1.0, green: 0.56, blue: 0.22))
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay {
            Capsule().stroke(
                isError ? Color.red.opacity(0.6) : Color(red: 1.0, green: 0.56, blue: 0.22).opacity(0.45),
                lineWidth: 1
            )
        }
    }

    private func stockPreviewTint(_ stock: FilmStock) -> Color {
        switch stock {
        case .party2AM: return Color.cyan.opacity(0.04)
        case .tungsten800T: return Color.blue.opacity(0.08)
        case .chrome100: return Color.orange.opacity(0.07)
        case .clubMono400: return Color.black.opacity(0.22)
        }
    }
}

private struct SimulatedViewfinderFeed: View {
    let stock: FilmStock
    let frameNumber: Int
    let flashOn: Bool

    var body: some View {
        let previewCG = SimulatedPartySceneRenderer.renderPartySnapshotCGImage(
            size: CGSize(width: 600, height: 800),
            frameNumber: frameNumber,
            flashOn: flashOn
        )
        Image(decorative: previewCG, scale: 1.0)
            .resizable()
            .scaledToFill()
            .saturation(stock == .clubMono400 ? 0.0 : 1.08)
    }
}
