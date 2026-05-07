//
//  AppSounds.swift
//  ClarityMail
//

import Foundation
import AVFoundation
import UserNotifications

enum AppNotificationSound: String, CaseIterable, Identifiable {
    case chime
    case pulse
    case glass
    case softBell

    static let storageKey = "newEmailNotificationSound"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chime: return "Chime"
        case .pulse: return "Pulse"
        case .glass: return "Glass"
        case .softBell: return "Soft Bell"
        }
    }

    var fileName: String {
        switch self {
        case .chime: return "ClarityMailChime.wav"
        case .pulse: return "ClarityMailPulse.wav"
        case .glass: return "ClarityMailGlass.wav"
        case .softBell: return "ClarityMailSoftBell.wav"
        }
    }

    var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    static var selected: AppNotificationSound {
        let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? AppNotificationSound.chime.rawValue
        return AppNotificationSound(rawValue: rawValue) ?? .chime
    }
}

@MainActor
final class AppSoundPlayer {
    static let shared = AppSoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    func play(_ fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[fileName] = player
            player.play()
        } catch {
            // Audio previews should never block the app.
        }
    }

    func playNewEmailPreview(_ sound: AppNotificationSound) {
        play(sound.fileName)
    }

    func playSentMail() {
        play("ClarityMailSent.wav")
    }
}
