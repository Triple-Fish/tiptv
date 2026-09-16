//
//  AcknowledgementsView.swift
//  tiptv
//

import SwiftUI

struct OpenSourceLibrary: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let license: String
    let url: String
    let copyrightNotice: String
}

struct AcknowledgementsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    private let libraries: [OpenSourceLibrary] = [
        OpenSourceLibrary(
            name: "KSPlayer",
            role: "Cross-Platform Video Player Framework",
            license: "LGPL / GPL v3",
            url: "https://github.com/kingslay/KSPlayer",
            copyrightNotice: """
            Copyright (c) 2019-2024 Kingslay (kingslay@icloud.com)

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), under the terms of the GNU Lesser General Public License as published by the Free Software Foundation.
            """
        ),
        OpenSourceLibrary(
            name: "FFmpegKit",
            role: "FFmpeg Wrapper for iOS & macOS",
            license: "LGPL v3.0",
            url: "https://github.com/arthenica/ffmpeg-kit",
            copyrightNotice: """
            Copyright (c) 2019-2023 Taner Sener

            Licensed under the GNU Lesser General Public License, version 3.0 (LGPL-3.0). You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.html.
            """
        ),
        OpenSourceLibrary(
            name: "FFmpeg",
            role: "Multimedia Demuxing & Decoding Framework",
            license: "LGPL v2.1+ / v3.0",
            url: "https://ffmpeg.org",
            copyrightNotice: """
            FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.
            Copyright (c) 2000-2024 the FFmpeg developers.

            FFmpeg is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation.
            """
        )
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("tiptv is made possible thanks to the following open-source software libraries. In accordance with their license terms and Apple App Store Review Guideline 5.2.2, copyright notices and links to source repositories are provided below.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(3)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(tiptvTheme.cardBackground)

            Section("Libraries & Frameworks") {
                ForEach(libraries) { lib in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Text(lib.name)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(lib.license)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(tiptvTheme.aqua)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tiptvTheme.aqua.opacity(0.15), in: Capsule())
                        }

                        Text(lib.role)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))

                        Text(lib.copyrightNotice)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(8)
                            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                        if let url = URL(string: lib.url) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("Visit Source Repository")
                                        .font(.system(.caption, design: .rounded).weight(.medium))
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                }
                                .foregroundStyle(tiptvTheme.aqua)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .listRowBackground(tiptvTheme.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(tiptvTheme.contentBackground.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
