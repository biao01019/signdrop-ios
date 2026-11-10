import SwiftUI

// MARK: - ⑤ 任务
struct TasksView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("任务").font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        Button("清空已完成") { app.currentTask = nil }
                            .font(.system(size: 15)).foregroundColor(.sdBlue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                    if let t = app.currentTask {
                        progressCard(t).padding(.horizontal, 20).padding(.bottom, 16)
                        stepsCard(t).padding(.horizontal, 20).padding(.bottom, 16)
                        cancelButton.padding(.horizontal, 20).padding(.bottom, 16)
                        infoCard(t).padding(.horizontal, 20)
                    } else {
                        Card {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 44)).foregroundColor(Color(hex: 0xC4C9D4))
                                Text("暂无进行中的任务")
                                    .font(.system(size: 15)).foregroundColor(.sub)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 48)
                        }
                        .padding(.horizontal, 20)
                    }
                    Color.clear.frame(height: 130)
                }
            }
        }
    }

    private func progressCard(_ t: AppState.SignTaskModel) -> some View {
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.track, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: max(0.01, t.progress))
                        .stroke(Color.sdBlue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: t.progress)
                    Text("\(Int(t.progress * 100))%")
                        .font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                }
                .frame(width: 120, height: 120)
                Text(t.running ? "正在签名" : "签名完成")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.ink)
                Text("\(t.fileName) · \(String(format: "%.1f", t.sizeMB)) MB")
                    .font(.system(size: 14)).foregroundColor(.sub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    private func stepsCard(_ t: AppState.SignTaskModel) -> some View {
        Card {
            VStack(spacing: 0) {
                ForEach(SignStep.allCases, id: \.self) { step in
                    let state = stepState(step, current: t.step, running: t.running)
                    HStack(spacing: 12) {
                        stepIcon(state)
                        Text(step.title)
                            .font(.system(size: 16, weight: state == .current ? .semibold : .regular))
                            .foregroundColor(state == .pending ? .faint : .ink)
                        Spacer()
                        Text(stepText(state))
                            .font(.system(size: 14))
                            .foregroundColor(stepColor(state))
                    }
                    .padding(.horizontal, 18).frame(height: 54)
                    if step != SignStep.allCases.last {
                        Divider().background(Color.divider).padding(.leading, 48)
                    }
                }
            }
        }
    }

    private enum StepState { case done, current, pending }
    private func stepState(_ s: SignStep, current: SignStep, running: Bool) -> StepState {
        if s.rawValue < current.rawValue { return .done }
        if s == current { return running ? .current : .done }
        return .pending
    }
    private func stepIcon(_ st: StepState) -> some View {
        switch st {
        case .done:
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22)).foregroundColor(.sdGreen))
        case .current:
            return AnyView(ProgressView().tint(.sdBlue).scaleEffect(1.1).frame(width: 22, height: 22))
        case .pending:
            return AnyView(Circle().stroke(Color(hex: 0xD5D9E2), lineWidth: 2)
                .frame(width: 21, height: 21))
        }
    }
    private func stepText(_ st: StepState) -> String {
        switch st {
        case .done: return "已完成"
        case .current: return "进行中"
        case .pending: return "等待中"
        }
    }
    private func stepColor(_ st: StepState) -> Color {
        switch st {
        case .done: return .sdGreen
        case .current: return .sdBlue
        case .pending: return .faint
        }
    }

    private var cancelButton: some View {
        Button {
            app.currentTask?.running = false
        } label: {
            Text("取消任务")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.sdRed)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.card).cornerRadius(20)
        }
    }

    private func infoCard(_ t: AppState.SignTaskModel) -> some View {
        Card {
            VStack(spacing: 0) {
                InfoRow(label: "目标设备", value: t.targetDevice)
                Divider().background(Color.divider)
                InfoRow(label: "使用证书", value: t.certName)
                Divider().background(Color.divider)
                InfoRow(label: "开始时间", value: "今天 " + t.startTime.formatted(date: .omitted, time: .shortened))
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
        }
    }
}
