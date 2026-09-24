import Foundation

public struct PhotoImportProgress: Equatable, Sendable {
    public let completedCount: Int
    public let totalCount: Int
    public let currentItemFractionCompleted: Double?

    public init(
        completedCount: Int,
        totalCount: Int,
        currentItemFractionCompleted: Double? = nil
    ) {
        precondition(totalCount > 0)
        precondition((0...totalCount).contains(completedCount))
        if let currentItemFractionCompleted {
            precondition(completedCount < totalCount)
            precondition(currentItemFractionCompleted.isFinite)
            precondition((0...1).contains(currentItemFractionCompleted))
        }
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentItemFractionCompleted = currentItemFractionCompleted
    }

    public var fractionCompleted: Double {
        let currentItemProgress = currentItemFractionCompleted ?? 0
        return (Double(completedCount) + currentItemProgress) / Double(totalCount)
    }

    public var currentItemNumber: Int? {
        guard currentItemFractionCompleted != nil else { return nil }
        return completedCount + 1
    }

    public var currentItemPercentage: Int? {
        currentItemFractionCompleted.map { Int(($0 * 100).rounded(.down)) }
    }
}
