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

