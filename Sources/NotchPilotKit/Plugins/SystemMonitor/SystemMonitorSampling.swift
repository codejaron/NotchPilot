import Foundation

struct SystemMonitorSamplingDemand: Sendable, Equatable {
    let includesProcessDetails: Bool
    let includesPerProcessNetwork: Bool

    init(
        includesProcessDetails: Bool = false,
        includesPerProcessNetwork: Bool = false
    ) {
        self.includesProcessDetails = includesProcessDetails
        self.includesPerProcessNetwork = includesPerProcessNetwork
    }

    static let basic = SystemMonitorSamplingDemand(
        includesProcessDetails: false,
        includesPerProcessNetwork: false
    )
    static let detailed = SystemMonitorSamplingDemand(
        includesProcessDetails: true,
        includesPerProcessNetwork: true
    )
}

protocol SystemMonitorSampling: Sendable {
    func snapshot() -> SystemMonitorSnapshot
    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot
}

extension SystemMonitorSampling {
    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        snapshot()
    }
}

struct SystemMonitorUnavailableSampler: SystemMonitorSampling {
    init() {}

    func snapshot() -> SystemMonitorSnapshot {
        .unavailable
    }
}

struct SystemMonitorStaticSampler: SystemMonitorSampling {
    let storedSnapshot: SystemMonitorSnapshot

    init(snapshot: SystemMonitorSnapshot) {
        self.storedSnapshot = snapshot
    }

    func snapshot() -> SystemMonitorSnapshot {
        storedSnapshot
    }
}

struct SystemMonitorDefaultSampler: SystemMonitorSampling {
    private let collector: @Sendable (SystemMonitorSamplingDemand) -> SystemMonitorSnapshot?
    private let fallback: any SystemMonitorSampling

    init(fallback: any SystemMonitorSampling = SystemMonitorUnavailableSampler()) {
        let bestEffortSampler = SystemMonitorBestEffortSampler()
        self.init(
            collector: { demand in
                bestEffortSampler.snapshot(demand: demand)
            },
            fallback: fallback
        )
    }

    init(
        collector: @escaping @Sendable (SystemMonitorSamplingDemand) -> SystemMonitorSnapshot?,
        fallback: any SystemMonitorSampling = SystemMonitorUnavailableSampler()
    ) {
        self.collector = collector
        self.fallback = fallback
    }

    func snapshot() -> SystemMonitorSnapshot {
        snapshot(demand: .basic)
    }

    func snapshot(demand: SystemMonitorSamplingDemand) -> SystemMonitorSnapshot {
        collector(demand) ?? fallback.snapshot(demand: demand)
    }
}
