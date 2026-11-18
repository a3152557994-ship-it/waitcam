import SwiftUI

public struct DarkroomVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WaitCamViewModel

    @State private var inspectedPhoto: InspectedPhotoItem?
    @State private var pendingDeleteRoll: DarkroomRoll?

    public init(viewModel: WaitCamViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    liveActivityStatusCard

                    if viewModel.developingRolls.isEmpty && viewModel.unlockedRolls.isEmpty {
                        emptyVaultCard
                    }

                    if !viewModel.developingRolls.isEmpty {
                        developingSection
                    }

                    if !viewModel.unlockedRolls.isEmpty {
                        unlockedSection
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.05).ignoresSafeArea())
            .navigationTitle("暗房保险箱 Darkroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回拍摄") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.20))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.create30SecondCalibrationRoll() }
                    } label: {
                        Label("30s 实测卷", systemImage: "timer")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.orange)
                }
            }
            .fullScreenCover(item: $inspectedPhoto) { item in
                PhotoLightboxView(item: item)
            }
            .confirmationDialog(
                "确认永久删除该胶卷及暗房加密底片？",
                isPresented: Binding(
                    get: { pendingDeleteRoll != nil },
                    set: { if !$0 { pendingDeleteRoll = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("永久删除", role: .destructive) {
                    if let target = pendingDeleteRoll {
                        pendingDeleteRoll = nil
                        Task { await viewModel.deleteRoll(target) }
                    }
                }
                Button("取消", role: .cancel) {
                    pendingDeleteRoll = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var liveActivityStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.liveActivity.isActivityRunning ? "dot.radiowaves.left.and.right" : "platter.filled.top.and.arrow.up.iphone")
                .font(.title3)
                .foregroundStyle(viewModel.liveActivity.isActivityRunning ? Color.green : Color.orange)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.liveActivity.isActivityRunning ? "灵动岛 & 锁屏倒计时实时运行中" : "灵动岛延迟显影仪式")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(
                    viewModel.liveActivity.statusHint
                        ?? "拍下第一张即自动锁定倒计时，到点自动推送本地通知并解除加密锁。"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var emptyVaultCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 38))
                .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.18))
            Text("暗房暂无显影中的胶卷")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text("回到取景器按下快门即可将照片加密封存入暗房；或点击右上角「30s 实测卷」立即体验灵动岛倒计时 -> 到点通知 -> 一键批量存相册。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }

    private var developingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("显影锁定中（AES-256 不可偷看）", systemImage: "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.22))
                Spacer()
                if !viewModel.storeKit.canUseParallelRollsAndCustomTimer {
                    Button("解锁无限并行 ¥6") {
                        viewModel.activePaywall = .parallelRolls
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                }
            }

            ForEach(viewModel.developingRolls) { roll in
                developingRollCard(roll)
            }
        }
    }

    private func developingRollCard(_ roll: DarkroomRoll) -> some View {
        let progress = roll.progress(at: viewModel.now)
        let countdown = roll.formattedCountdown(at: viewModel.now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(roll.title)
                            .font(.subheadline.monospaced().weight(.bold))
                            .foregroundStyle(.white)
                        Text(roll.filmStock.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                    }
                    Text("已封存 \(roll.shots.count) / \(roll.maxShots) 张 · \(roll.duration.detailLabel)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdown)
                        .font(.title3.monospacedDigit().weight(.heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.54, blue: 0.20))
                    Text("后显影")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            ProgressView(value: progress)
                .tint(Color(red: 1.0, green: 0.45, blue: 0.16))

            // Sealed film canister strip placeholder (prevents peeking before unlockAt)
            HStack(spacing: 6) {
                ForEach(0..<min(8, roll.shots.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 28, height: 36)
                        .overlay {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.2).opacity(0.75))
                        }
                }
                if roll.shots.count > 8 {
                    Text("+\(roll.shots.count - 8)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button(role: .destructive) {
                    pendingDeleteRoll = roll
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.09, green: 0.08, blue: 0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.45, blue: 0.16).opacity(0.35), lineWidth: 1)
        }
    }

    private var unlockedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("显影完毕 · 可开封导出无水印成片", systemImage: "sparkles")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)

            ForEach(viewModel.unlockedRolls) { roll in
                unlockedRollCard(roll)
            }
        }
    }

    private func unlockedRollCard(_ roll: DarkroomRoll) -> some View {
        let imagesByShotID = viewModel.unlockedThumbnails[roll.id] ?? [:]
        let isExporting = viewModel.isExportingRollID == roll.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(roll.title)
                        .font(.subheadline.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(roll.filmStock.displayName) · \(roll.shots.count) 张无水印原画")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if roll.exportedAt != nil {
                    Label("已存相册", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                Button(role: .destructive) {
                    pendingDeleteRoll = roll
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(roll.shots) { shot in
                    if let uiImage = imagesByShotID[shot.id] {
                        Button {
                            inspectedPhoto = InspectedPhotoItem(
                                id: shot.id,
                                frameLabel: String(format: "%@ · #%02d", roll.title, shot.frameNumber),
                                image: uiImage
                            )
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(3.0 / 4.0, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay { ProgressView() }
                    }
                }
            }
            .onAppear {
                viewModel.revealRollPhotosIfUnlocked(roll)
            }

            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.batchExportRollToPhotos(roll) }
                } label: {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                        }
                        Text("一键批量导出全部 \(roll.shots.count) 张至系统相册")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.48, blue: 0.17))
                .foregroundStyle(.black)
                .disabled(isExporting)

                Button {
                    Task { await viewModel.export35mmReelVideo(roll) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "film.stack")
                        Text(WCL10n.pick(zh: "🎬 生成 35mm 胶片显影短片 (免费晒片)", en: "🎬 Create 35mm Film Reel Video (Free)"))
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green.opacity(0.88))
                .foregroundStyle(.black)
                .disabled(isExporting)

                if let reelURL = viewModel.lastGeneratedReelURL {
                    ShareLink(item: reelURL) {
                        Label(
                            WCL10n.pick(zh: "一键分享刚生成的 35mm 胶片短片", en: "Share 35mm Film Reel Now"),
                            systemImage: "square.and.arrow.up"
                        )
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }

                Button {
                    Task { await viewModel.exportContactSheetPoster(roll) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.grid.3x2.fill")
                        Text(WCL10n.pick(zh: "生成 35mm 接触印相单海报", en: "Export 35mm Contact Sheet Poster"))
                        if !viewModel.storeKit.hasFullPro {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
                .disabled(isExporting)
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct InspectedPhotoItem: Identifiable {
    let id: UUID
    let frameLabel: String
    let image: UIImage
}

private struct PhotoLightboxView: View {
    @Environment(\.dismiss) private var dismiss
    let item: InspectedPhotoItem

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Text(item.frameLabel)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                Spacer()
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 12)
                Spacer()
            }
        }
    }
}
