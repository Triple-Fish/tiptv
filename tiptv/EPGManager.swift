//
//  EPGManager.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

struct EPGProgram: Identifiable, Sendable {
    let id: UUID
    let channelId: UUID
    let title: String
    let subtitle: String?
    let synopsis: String
    let category: String
    let startTime: Date
    let endTime: Date

    var isLive: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    var progress: Double {
        let now = Date()
        guard now >= startTime else { return 0 }
        guard now <= endTime else { return 1.0 }
        let total = endTime.timeIntervalSince(startTime)
        guard total > 0 else { return 0 }
        return (now.timeIntervalSince(startTime)) / total
    }

    nonisolated private static let timeRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var timeRangeString: String {
        "\(Self.timeRangeFormatter.string(from: startTime)) - \(Self.timeRangeFormatter.string(from: endTime))"
    }

    var durationString: String {
        let minutes = Int(endTime.timeIntervalSince(startTime) / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(remainingMinutes)m"
        }
    }

    var remainingTimeString: String {
        let now = Date()
        guard isLive else { return "" }
        let remainingMinutes = max(1, Int(endTime.timeIntervalSince(now) / 60))
        if remainingMinutes >= 60 {
            return "Ends in \(remainingMinutes / 60)h \(remainingMinutes % 60)m"
        } else {
            return "Ends in \(remainingMinutes)m"
        }
    }
}

@MainActor
final class EPGManager: ObservableObject {
    static let shared = EPGManager()

    private var cache: [UUID: [EPGProgram]] = [:]

    // Predefined schedules per channel genre for realistic EPG display
    private let sportsTemplates = [
        ("Premier League Live: Matchday", "Live coverage of top-tier football matches with expert pre-match and post-match analysis.", 120),
        ("Super Sunday: Analysis & Highlights", "In-depth highlights, goals of the week, and expert studio punditry.", 60),
        ("Formula 1: Qualifying Session", "Full coverage of the high-octane qualifying shootout ahead of the Grand Prix.", 90),
        ("Champions League Tonight", "All the goals and key moments from Europe's elite club competition.", 60),
        ("Live Tennis: Grand Slam Championship", "Center court live tennis action with player interviews and stats.", 150),
        ("Boxing: World Title Fight Preview", "Exclusive interviews, training camp footage, and breakdown of fight night.", 45),
        ("SportsCenter Live Bulletin", "Roundup of the latest breaking news, transfer rumors, and scores across global sports.", 30),
        ("Motorsport Weekly Round", "Highlights and behind-the-scenes access to rally, endurance, and touring car racing.", 45)
    ]

    private let movieTemplates = [
        ("The Dark Knight", "When the menace known as the Joker wreaks havoc, Batman must accept one of the greatest psychological tests.", 152),
        ("Inception", "A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea.", 148),
        ("Interstellar", "A team of explorers travel through a wormhole in space in an attempt to ensure humanity's survival.", 169),
        ("Gladiator", "A former Roman General sets out to exact vengeance against the corrupt emperor who murdered his family.", 155),
        ("Blade Runner 2049", "A young blade runner's discovery of a long-buried secret leads him to track down former blade runner Rick Deckard.", 164),
        ("Pulp Fiction", "The lives of two mob hitmen, a boxer, a gangster and his wife intertwine in four tales of violence and redemption.", 154),
        ("The Matrix", "When a beautiful stranger leads computer hacker Neo to a forbidding underworld, he discovers the shocking truth.", 136),
        ("Mad Max: Fury Road", "In a post-apocalyptic wasteland, a woman rebels against a tyrannical ruler in search for her homeland.", 120)
    ]

    private let newsTemplates = [
        ("Global News Hour", "Live international headlines, in-depth reports, and live correspondence from global capitals.", 60),
        ("Prime Time Briefing", "Comprehensive coverage of major political, economic, and social developments.", 60),
        ("Business & Markets Today", "Real-time market updates, stock indices, corporate earnings, and CEO interviews.", 30),
        ("World Weather & Climate Special", "Detailed regional weather forecasts and environmental reporting.", 30),
        ("Breaking News Live", "Fast-moving reporting on the developing top stories around the globe.", 60),
        ("Investigative Insight", "In-depth documentary series exploring geopolitical conflicts and human stories.", 60)
    ]

    private let entertainmentTemplates = [
        ("Late Night Talk Show", "Celebrity guest interviews, comedy monologues, and musical guest performances.", 60),
        ("The Great Cooking Challenge", "Aspiring chefs face culinary hurdles in front of a panel of world-renowned culinary judges.", 60),
        ("Mystery Island: Drama Series", "Suspenseful drama series following a community on a remote coastal island.", 45),
        ("Comedy Central: Stand-Up Special", "Live hilarious comedy special recorded at legendary international venues.", 45),
        ("Wildlife Planet: Ocean Giants", "Breathtaking 4K nature documentary chronicling the marine wildlife in the deep Pacific.", 60),
        ("Grand Designs: Modern Architecture", "Ambitious homeowners build unconventional, cutting-edge eco-homes from the ground up.", 60)
    ]

    private let kidsTemplates = [
        ("Adventures in Toyland", "Fun-filled animated escapades with magical toys and their friendly companions.", 30),
        ("Space Explorers: Galactic Rescue", "Young astronauts journey across asteroid belts to solve cosmic mysteries.", 30),
        ("Dino Academy", "Friendly dinosaurs learn teamwork, friendship, and problem-solving skills.", 30),
        ("Superhero Pals", "Kid superheroes use clever gadgets and kindness to save their neighborhood.", 30)
    ]

    func programs(for channel: Channel, date: Date = Date()) -> [EPGProgram] {
        if let existing = cache[channel.id], !existing.isEmpty {
            return existing
        }

        let generated = generateSchedule(for: channel, baseDate: date)
        cache[channel.id] = generated
        return generated
    }

    func currentProgram(for channel: Channel) -> EPGProgram? {
        let list = programs(for: channel)
        let now = Date()
        return list.first { $0.startTime <= now && $0.endTime >= now }
    }

    func nextProgram(for channel: Channel) -> EPGProgram? {
        let list = programs(for: channel)
        let now = Date()
        return list.first { $0.startTime > now }
    }

    private func generateSchedule(for channel: Channel, baseDate: Date) -> [EPGProgram] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: baseDate)

        // Select suitable templates based on category
        let templates: [(String, String, Int)]
        let cat = channel.category
        switch cat {
        case .sports:
            templates = sportsTemplates
        case .movies:
            templates = movieTemplates
        case .news:
            templates = newsTemplates
        case .kids:
            templates = kidsTemplates
        default:
            templates = entertainmentTemplates
        }

        var result: [EPGProgram] = []
        var currentTime = startOfDay.addingTimeInterval(-4 * 3600) // Start 4 hours before today for smooth past browsing
        let endTimeLimit = startOfDay.addingTimeInterval(28 * 3600) // 4 hours into tomorrow

        // Use a hash of channel name to ensure repeatable but varied schedules per channel
        var templateIndex = abs(channel.name.hashValue) % templates.count

        while currentTime < endTimeLimit {
            let (title, synopsis, baseMinutes) = templates[templateIndex % templates.count]
            // Slight jitter based on channel id so different channels don't align identically
            let durationSeconds = TimeInterval(baseMinutes * 60)
            let programEnd = currentTime.addingTimeInterval(durationSeconds)

            let program = EPGProgram(
                id: UUID(),
                channelId: channel.id,
                title: title,
                subtitle: channel.group ?? channel.category.rawValue,
                synopsis: synopsis,
                category: channel.category.rawValue,
                startTime: currentTime,
                endTime: programEnd
            )

            result.append(program)
            currentTime = programEnd
            templateIndex += 1
        }

        return result
    }

    func clearCache() {
        cache.removeAll()
    }
}
