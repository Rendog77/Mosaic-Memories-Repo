import MosaicCore

public struct SourceSelectionValidator: Sendable {
    public init() {}

    public func validate(
        _ references: [AssetReference],
        for request: SourceSelectionRequest
    ) throws -> [AssetReference] {
        guard references.count <= request.maximumCount else {
            throw SourceSelectionValidationError.tooManySources(
                maximum: request.maximumCount,
                actual: references.count
            )
        }

        var seenIdentifiers = Set<String>()
        var duplicateIdentifiers = Set<String>()
        for reference in references {
            if !seenIdentifiers.insert(reference.id).inserted {
                duplicateIdentifiers.insert(reference.id)
            }
            guard Self.isAllowed(reference.origin, for: request.accessMode) else {
                throw SourceSelectionValidationError.unexpectedOrigin(
                    reference.origin,
                    accessMode: request.accessMode
                )
            }
        }

        guard duplicateIdentifiers.isEmpty else {
            throw SourceSelectionValidationError.duplicateReferences(
                duplicateIdentifiers.sorted()
            )
        }
        return references
    }

    private static func isAllowed(_ origin: AssetReference.Origin, for mode: PhotoAccessMode) -> Bool {
        if origin == .testFixture { return true }
        switch mode {
        case .selectedPhotos:
            return origin == .photoPicker || origin == .importedFile
        case .smartLibrary:
            return origin == .photoLibrary
        }
    }
}

public enum SourceSelectionValidationError: Error, Equatable, Sendable {
    case tooManySources(maximum: Int, actual: Int)
    case duplicateReferences([String])
    case unexpectedOrigin(AssetReference.Origin, accessMode: PhotoAccessMode)
}

