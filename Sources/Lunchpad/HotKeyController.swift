import Carbon.HIToolbox
import Foundation

enum HotKeyUpdateError: Error, Equatable {
    case managedByEnvironment
    case invalid
    case conflict
    case unavailable
}

@MainActor
final class HotKeyController {
    private let registrar: any GlobalHotKeyRegistering
    private let action: () -> Void
    private var registration: (any GlobalHotKeyRegistration)?

    let environmentOverride: HotKeyEnvironmentOverride?
    private(set) var activeConfiguration: HotKeyConfiguration?
    private(set) var lastError: HotKeyUpdateError?

    init(
        registrar: (any GlobalHotKeyRegistering)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        action: @escaping () -> Void
    ) {
        self.registrar = registrar ?? CarbonHotKeyRegistrar()
        environmentOverride = HotKeyEnvironmentOverride(environment: environment)
        self.action = action
    }

    var isExternallyManaged: Bool { environmentOverride != nil }

    func start(storedPreference: HotKeyPreference) {
        let effectivePreference = environmentOverride?.preference ?? storedPreference
        guard case .configured(let configuration) = effectivePreference else {
            activeConfiguration = nil
            registration = nil
            lastError = nil
            return
        }

        do {
            registration = try registrar.register(
                configuration: configuration,
                action: action
            )
            activeConfiguration = configuration
            lastError = nil
        } catch {
            registration = nil
            activeConfiguration = nil
            lastError = Self.map(error)
        }
    }

    func apply(_ preference: HotKeyPreference) -> Result<Void, HotKeyUpdateError> {
        guard !isExternallyManaged else { return .failure(.managedByEnvironment) }

        switch preference {
        case .disabled:
            registration = nil
            activeConfiguration = nil
            lastError = nil
            return .success(())
        case .configured(let configuration):
            guard configuration.isValid else { return .failure(.invalid) }
            if activeConfiguration == configuration, registration != nil {
                return .success(())
            }

            do {
                let candidate = try registrar.register(
                    configuration: configuration,
                    action: action
                )
                registration = candidate
                activeConfiguration = configuration
                lastError = nil
                return .success(())
            } catch {
                let mappedError = Self.map(error)
                lastError = mappedError
                return .failure(mappedError)
            }
        }
    }

    private static func map(_ error: Error) -> HotKeyUpdateError {
        let error = error as NSError
        if error.domain == NSOSStatusErrorDomain,
           error.code == Int(eventHotKeyExistsErr) {
            return .conflict
        }
        return .unavailable
    }
}
