import SwiftUI

struct TimelineGuideView: View {
    let channels: [Channel]
    let onSelectChannel: (Channel) -> Void
    @State private var epg = EPGManager.shared
    @State private var reminders = ProgrammeReminderManager.shared
    @State private var timelineStart = Self.currentHourStart()

    private let channelWidth: CGFloat = 132
    private let halfHourWidth: CGFloat = 140

    private static func currentHourStart() -> Date {
        Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
    }

    var body: some View {
        if channels.isEmpty {
            ContentUnavailableView("No Channels", systemImage: "tv.slash", description: Text("Add or reload a playlist to populate the guide."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(channels.prefix(250)) { channel in
                            guideRow(channel)
                        }
                    } header: {
                        timelineHeader
                    }
                }
            }
            .background(tiptvTheme.contentBackground)
            .overlay(alignment: .topTrailing) {
                if epg.isLoading { ProgressView().padding().background(.regularMaterial, in: Capsule()) }
            }
            .navigationTitle("TV Guide")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Now", systemImage: "location.fill") {
                        timelineStart = Self.currentHourStart()
                    }
                        .accessibilityHint("Returns the guide to the current time")
                }
            }
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Text("Channel")
                .font(.caption.bold())
                .frame(width: channelWidth, alignment: .leading)
                .padding(.leading, 12)
            ForEach(0..<8, id: \.self) { index in
                Text(timelineStart.addingTimeInterval(Double(index) * 1800).formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: halfHourWidth, alignment: .leading)
            }
        }
        .frame(height: 42)
        .foregroundStyle(.white)
        .background(tiptvTheme.surface)
        .accessibilityElement(children: .contain)
    }

    private func guideRow(_ channel: Channel) -> some View {
        let allPrograms = epg.programs(for: channel)
        let timelineEnd = timelineStart.addingTimeInterval(4 * 3600)
        let programs = allPrograms.filter { $0.endTime > timelineStart && $0.startTime < timelineEnd }
        let now = Date()
        let currentProgram = allPrograms.first { $0.startTime <= now && $0.endTime >= now }
        return HStack(spacing: 0) {
            Button { onSelectChannel(channel) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.uniformName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let current = currentProgram {
                        Text(current.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: channelWidth - 20, height: 68, alignment: .leading)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(channel.uniformName)")

            if programs.isEmpty {
                Text("No programme information")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: halfHourWidth * 8, height: 68, alignment: .leading)
                    .padding(.leading, 12)
            } else {
                HStack(spacing: 2) {
                    ForEach(programs) { program in
                        Button {
                            if program.isLive { onSelectChannel(channel) }
                            else { Task { await reminders.toggle(program: program, channel: channel) } }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(program.title).font(.caption.weight(.semibold)).lineLimit(2)
                                Text(program.timeRangeString).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .frame(width: programWidth(program), height: 66, alignment: .leading)
                            .background(program.isLive ? tiptvTheme.accent.opacity(0.28) : tiptvTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if reminders.hasReminder(for: program) { Image(systemName: "bell.fill").font(.caption2).padding(6).foregroundStyle(tiptvTheme.aqua) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(program.title), \(program.timeRangeString)")
                        .accessibilityHint(program.isLive ? "Plays this channel" : "Sets or removes a reminder")
                    }
                }
                .frame(width: halfHourWidth * 8, alignment: .leading)
            }
        }
        .frame(height: 70)
        .background(Color.white.opacity(0.025))
    }

    private func programWidth(_ program: EPGProgram) -> CGFloat {
        max(92, min(halfHourWidth * 4, CGFloat(program.endTime.timeIntervalSince(program.startTime) / 1800) * halfHourWidth))
    }
}
