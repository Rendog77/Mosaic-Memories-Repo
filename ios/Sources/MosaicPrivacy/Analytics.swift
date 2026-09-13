import Foundation
import MosaicCore

public enum AnalyticsEventName: String, Sendable {
    case projectStarted = "project_started"
    case heroSelected = "hero_selected"
    case sourceSetConfirmed = "source_set_confirmed"
    case previewCompleted = "preview_completed"
    case tileInspected = "tile_inspected"
    case tileReplaced = "tile_replaced"
    case meaningfulCreationCompleted = "meaningful_creation_completed"
}

public enum AnalyticsField: String, Hashable, Sendable {
    case appVersion = "app_version"
    case engineVersion = "engine_version"
    case workflowStep = "workflow_step"
    case sourceCountBucket = "source_count_bucket"
    case selectionMode = "selection_mode"
    case durationBucket = "duration_bucket"
    case result = "result"
    case failureReason = "failure_reason"
    case exportTier = "export_tier"
}

public struct AnalyticsEvent: Equatable, Sendable {
    public let name: AnalyticsEventName
    public let fields: [AnalyticsField: String]

    public init(name: AnalyticsEventName, fields: [AnalyticsField: String] = [:]) {
        self.name = name
        self.fields = fields
    }
}

public enum AnalyticsValidationError: Error, Equatable, Sendable {
    case disallowedValue(field: AnalyticsField)
}

public struct AnalyticsEventValidator: Sendable {
    public init() {}

    public func validate(_ event: AnalyticsEvent) throws {
        for (field, value) in event.fields {
            guard Self.isAllowed(value, for: field) else {
                throw AnalyticsValidationError.disallowedValue(field: field)
            }
        }
    }

    private static func isAllowed(_ value: String, for field: AnalyticsField) -> Bool {
        switch field {
        case .appVersion:
            return !value.isEmpty && value.count <= 32 && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_" )).contains($0)
            }
        case .engineVersion:
            return Int(value).map { $0 > 0 } ?? false
        case .workflowStep:
            return ["hero", "memories", "source_review", "preview", "edit", "export"].contains(value)
        case .sourceCountBucket:
            return SourceCountBucket(rawValue: value) != nil
        case .selectionMode:
            return ["manual", "smart"].contains(value)
        case .durationBucket:
            return ["under_10s", "10_59s", "1_3m", "3_10m", "over_10m"].contains(value)
        case .result:
            return ["success", "failure", "cancelled"].contains(value)
        case .failureReason:
            return ["permission_denied", "asset_unavailable", "icloud_failed", "cancelled", "invalid_sources", "render_failed", "save_failed"].contains(value)
        case .exportTier:
            return ["screen", "high_resolution"].contains(value)
        }
    }
}

public actor ValidatingAnalyticsRecorder: AnalyticsRecording {
    private let destination: any AnalyticsRecording
    private let validator: AnalyticsEventValidator

    public init(
        destination: any AnalyticsRecording,
        validator: AnalyticsEventValidator = .init()
    ) {
        self.destination = destination
        self.validator = validator
    }

    public func record(_ event: AnalyticsEvent) async {
        guard (try? validator.validate(event)) != nil else { return }
        await destination.record(event)
    }
}

public protocol AnalyticsRecording: Sendable {
    func record(_ event: AnalyticsEvent) async
}

public struct NoOpAnalyticsRecorder: AnalyticsRecording {
    public init() {}
    public func record(_ event: AnalyticsEvent) async {}
}

public enum SourceCountBucket: String, Sendable {
    case under100 = "under_100"
    case from100To249 = "100_249"
    case from250To499 = "250_499"
    case from500To999 = "500_999"
    case over1000 = "1000_plus"

    public init(count: Int) {
        switch count {
        case ..<100: self = .under100
        case 100..<250: self = .from100To249
        case 250..<500: self = .from250To499
        case 500..<1_000: self = .from500To999
        default: self = .over1000
        }
    }
}
