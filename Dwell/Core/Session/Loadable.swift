import Foundation

/// Every async surface in the app goes through this, so loading / empty /
/// error are real states rather than an afterthought.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let m) = self { return m }
        return nil
    }
}

extension Loadable: Equatable where Value: Equatable {}
