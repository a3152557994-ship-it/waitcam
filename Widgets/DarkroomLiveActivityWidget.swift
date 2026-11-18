import ActivityKit
import SwiftUI
import WidgetKit

struct DarkroomLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DarkroomActivityAttributes.self) { context in
            LockScreenDarkroomBanner(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.07))
                .activitySystemActionForegroundColor(Color(red: 1.0, green: 0.48, blue: 0.17))
                .widgetURL(URL(string: "waitcam://darkroom?roll=\(context.attributes.rollID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isReadyToReveal ? "sparkles" : "film.fill")
                            .foregroundStyle(context.state.isReadyToReveal ? .green : Color(red: 1.0, green: 0.48, blue: 0.17))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.rollTitle)
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(context.state.shotCount)/\(context.state.maxShots) 张 · \(context.state.filmStockName)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isReadyToReveal {
                            Text("显影完成")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        } else {
                            Text(timerInterval: context.state.lockedAt...context.state.unlockAt, countsDown: true)
                                .font(.headline.monospacedDigit().weight(.heavy))
                                .foregroundStyle(Color(red: 1.0, green: 0.54, blue: 0.20))
                            Text("后显影")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if context.state.isReadyToReveal {
                            Text("点击开封胶卷并一键批量存相册（无水印）")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            ProgressView(
                                timerInterval: context.state.lockedAt...context.state.unlockAt,
                                countsDown: false
                            ) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(Color(red: 1.0, green: 0.48, blue: 0.17))

                            HStack {
                                Text("暗房锁定中 · 禁止偷看")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.65))
                                Spacer()
                                if context.state.activeRollCount > 1 {
                                    Text("共 \(context.state.activeRollCount) 卷并行")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.isReadyToReveal ? "sparkles" : "film")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isReadyToReveal ? .green : Color(red: 1.0, green: 0.48, blue: 0.17))
                    Text("\(context.state.shotCount)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                if context.state.isReadyToReveal {
                    Text("已显影")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text(timerInterval: context.state.lockedAt...context.state.unlockAt, countsDown: true)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.22))
                        .frame(minWidth: 46)
                }
            } minimal: {
                Image(systemName: context.state.isReadyToReveal ? "checkmark.circle.fill" : "hourglass")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.isReadyToReveal ? .green : Color(red: 1.0, green: 0.48, blue: 0.17))
            }
            .widgetURL(URL(string: "waitcam://darkroom?roll=\(context.attributes.rollID)"))
        }
    }
}

private struct LockScreenDarkroomBanner: View {
    let state: DarkroomActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: state.isReadyToReveal ? "sparkles" : "film.stack.fill")
                        .foregroundStyle(state.isReadyToReveal ? .green : Color(red: 1.0, green: 0.48, blue: 0.17))
                    Text("WAITCAM 暗房")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("· \(state.rollTitle)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("已锁 \(state.shotCount)/\(state.maxShots) 张")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.58, blue: 0.24))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }

            if state.isReadyToReveal {
                HStack {
                    Text("✨ 胶片显影完成 · 点击一键导出系统相册")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                    Spacer()
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(timerInterval: state.lockedAt...state.unlockAt, countsDown: true)
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.18))
                    Text("后显影")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text(state.filmStockName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                ProgressView(
                    timerInterval: state.lockedAt...state.unlockAt,
                    countsDown: false
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Color(red: 1.0, green: 0.48, blue: 0.17))
            }
        }
        .padding(14)
    }
}
