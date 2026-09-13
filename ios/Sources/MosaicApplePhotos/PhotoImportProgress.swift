import Foundation

public struct PhotoImportProgress: Equatable, Sendable {
    public let completedCount: Int
    public let totalCount: Int

    public init(completedCount: Int, totalCount: Int) {
        precondition(totalCount > 0)
        precondition((0...totalCount).contains(completedCount))
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    public var fractionCompleted: Double {
        Double(completedCount) / Double(totalCount)
    }
}
