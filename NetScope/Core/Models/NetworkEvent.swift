import Foundation

/// A notable change in the network, recorded for the activity timeline.
struct NetworkEvent: Identifiable, Hashable, Sendable, Codable {

    enum Kind: String, Codable, Sendable {
        case deviceAppeared
        case deviceDisappeared
        case deviceReturned
        case networkChanged
        case scanCompleted
        case scanFailed

        var title: String {
            switch self {
            case .deviceAppeared: "New device"
            case .deviceDisappeared: "Device left"
            case .deviceReturned: "Device back"
            case .networkChanged: "Network changed"
            case .scanCompleted: "Scan complete"
            case .scanFailed: "Scan failed"
            }
        }

        var symbolName: String {
            switch self {
            case .deviceAppeared: "plus.circle.fill"
            case .deviceDisappeared: "minus.circle.fill"
            case .deviceReturned: "arrow.uturn.left.circle.fill"
            case .networkChanged: "arrow.triangle.2.circlepath.circle.fill"
            case .scanCompleted: "checkmark.circle.fill"
            case .scanFailed: "exclamationmark.triangle.fill"
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var message: String
    var deviceID: String?
    var networkID: String?
    var timestamp: Date = .now
}

// MARK: - Scan progress

/// Live progress of an in-flight scan, published to the UI.
struct ScanProgress: Hashable, Sendable {

    enum Phase: String, Sendable {
        case idle
        case preparing
        case sweeping
        case resolving
        case probingPorts
        case finishing

        var title: String {
            switch self {
            case .idle: "Idle"
            case .preparing: "Preparing"
            case .sweeping: "Sweeping subnet"
            case .resolving: "Resolving names"
            case .probingPorts: "Probing services"
            case .finishing: "Finishing up"
            }
        }
    }

    var phase: Phase = .idle
    var scannedHosts: Int = 0
    var totalHosts: Int = 0
    var foundDevices: Int = 0
    var startedAt: Date?
    var finishedAt: Date?

    var isRunning: Bool { phase != .idle && finishedAt == nil }

    var fraction: Double {
        guard totalHosts > 0 else { return 0 }
        return min(Double(scannedHosts) / Double(totalHosts), 1)
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? .now).timeIntervalSince(startedAt)
    }

    static let idle = ScanProgress()
}

// MARK: - Scan events

/// Messages emitted by `ScanEngine` while it works.
enum ScanEvent: Sendable {
    case started(totalHosts: Int)
    case phase(ScanProgress.Phase)
    case progress(scanned: Int, total: Int)
    case discovered(Device)
    case updated(Device)
    case finished(deviceCount: Int)
    case failed(String)
}
