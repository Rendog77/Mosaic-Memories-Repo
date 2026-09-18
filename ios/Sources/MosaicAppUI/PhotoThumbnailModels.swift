import Combine
import Foundation
import MosaicCore
import MosaicFeatures

public enum ThumbnailLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded(Data)
    case failed(PhotoSelectionError)
}

@MainActor
public final class HeroPhotoViewModel: ObservableObject {
    @Published public private(set) var reference: AssetReference?
    @Published public private(set) var crop: HeroCrop?
    @Published public private(set) var thumbnailState: ThumbnailLoadingState = .idle

    private let loader: any PhotoAssetLoading

    public init(loader: any PhotoAssetLoading) {
        self.loader = loader
    }

    public func load(_ reference: AssetReference, crop: HeroCrop? = nil, maximumPixelSize: Int = 1_024) async {
        precondition(maximumPixelSize > 0)
        self.reference = reference
        self.crop = crop
        thumbnailState = .loading
        let result = await loadThumbnail(reference, crop: crop, maximumPixelSize: maximumPixelSize)
        guard self.reference == reference, self.crop == crop else { return }
        thumbnailState = result
    }

    public func clear() {
        reference = nil
        crop = nil
        thumbnailState = .idle
    }

    private func loadThumbnail(
        _ reference: AssetReference,
        crop: HeroCrop?,
        maximumPixelSize: Int
    ) async -> ThumbnailLoadingState {
        do {
            let data = try await loader.thumbnail(for: reference, maximumPixelSize: maximumPixelSize, crop: crop)
            guard !data.isEmpty else {
                return .failed(.assetUnavailable(reference.id))
            }
            return .loaded(data)
        } catch let error as PhotoSelectionError {
            return .failed(error)
        } catch {
            return .failed(.assetUnavailable(reference.id))
        }
    }
}

public struct SourceThumbnailItem: Equatable, Identifiable, Sendable {
    public let reference: AssetReference
    public var state: ThumbnailLoadingState

    public var id: String { reference.id }

    public init(reference: AssetReference, state: ThumbnailLoadingState = .idle) {
        self.reference = reference
        self.state = state
    }
}

@MainActor
public final class SourceReviewViewModel: ObservableObject {
    @Published public private(set) var items: [SourceThumbnailItem]

    private let loader: any PhotoAssetLoading

    public init(references: [AssetReference], loader: any PhotoAssetLoading) {
        self.items = references.map { SourceThumbnailItem(reference: $0) }
        self.loader = loader
    }

    public func loadThumbnail(for id: String, maximumPixelSize: Int = 320) async {
        precondition(maximumPixelSize > 0)
        guard let reference = items.first(where: { $0.id == id })?.reference else { return }
        update(id: id, state: .loading)
        do {
            let data = try await loader.thumbnail(for: reference, maximumPixelSize: maximumPixelSize)
            let state: ThumbnailLoadingState = data.isEmpty
                ? .failed(.assetUnavailable(reference.id))
                : .loaded(data)
            update(id: id, state: state)
        } catch let error as PhotoSelectionError {
            update(id: id, state: .failed(error))
        } catch {
            update(id: id, state: .failed(.assetUnavailable(reference.id)))
        }
    }

    public func loadFirst(_ count: Int, maximumPixelSize: Int = 320) async {
        for id in items.prefix(max(0, count)).map(\.id) {
            await loadThumbnail(for: id, maximumPixelSize: maximumPixelSize)
        }
    }

    public func retryFailed(maximumPixelSize: Int = 320) async {
        let failedIDs = items.compactMap { item -> String? in
            if case .failed = item.state { return item.id }
            return nil
        }
        for id in failedIDs {
            await loadThumbnail(for: id, maximumPixelSize: maximumPixelSize)
        }
    }

    public func replaceReferences(_ references: [AssetReference]) {
        var existingStates: [String: ThumbnailLoadingState] = [:]
        for item in items {
            existingStates[item.id] = item.state
        }
        items = references.map {
            SourceThumbnailItem(reference: $0, state: existingStates[$0.id] ?? .idle)
        }
    }

    public func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    private func update(id: String, state: ThumbnailLoadingState) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }
}
