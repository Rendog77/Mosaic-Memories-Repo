import MosaicCore

public enum HeroCropPreset: String, CaseIterable, Sendable {
    case original
    case center
    case upper
    case lower

    public var title: String {
        switch self {
        case .original: return "Original"
        case .center: return "Center"
        case .upper: return "Upper"
        case .lower: return "Lower"
        }
    }

    public var crop: HeroCrop? {
        switch self {
        case .original: return nil
        case .center: return try? HeroCrop(x: 0.125, y: 0.125, width: 0.75, height: 0.75)
        case .upper: return try? HeroCrop(x: 0.125, y: 0, width: 0.75, height: 0.75)
        case .lower: return try? HeroCrop(x: 0.125, y: 0.25, width: 0.75, height: 0.75)
        }
    }

    public static func selected(for crop: HeroCrop?) -> HeroCropPreset? {
        allCases.first { $0.crop == crop }
    }
}
