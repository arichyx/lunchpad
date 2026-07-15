import Foundation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLoginItemService: LoginItemManaging {
    private let service: SMAppService
    private let bundleURL: URL

    init(
        service: SMAppService? = nil,
        bundleURL: URL? = nil
    ) {
        self.service = service ?? .mainApp
        self.bundleURL = bundleURL ?? Bundle.main.bundleURL
    }

    var isAvailable: Bool {
        bundleURL.pathExtension.lowercased() == "app"
    }

    var isEnabled: Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { throw LoginItemUpdateError.unavailable }
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

enum LoginItemUpdateError: LocalizedError, Equatable {
    case unavailable
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The packaged application is required."
        case .operationFailed(let message):
            return message
        }
    }
}

@MainActor
final class LoginItemController {
    private let service: any LoginItemManaging

    init(service: (any LoginItemManaging)? = nil) {
        self.service = service ?? SystemLoginItemService()
    }

    var isAvailable: Bool { service.isAvailable }
    var isEnabled: Bool { service.isEnabled }

    func setEnabled(_ enabled: Bool) -> Result<Bool, LoginItemUpdateError> {
        guard service.isAvailable else { return .failure(.unavailable) }
        do {
            try service.setEnabled(enabled)
            return .success(service.isEnabled)
        } catch {
            return .failure(.operationFailed(error.localizedDescription))
        }
    }
}
