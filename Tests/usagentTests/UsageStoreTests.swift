import XCTest
@testable import usagent

private struct MockFetcher: UsageFetching {
    let result: Result<UsageSnapshot, UsageFetchError>

    func fetch() async -> Result<UsageSnapshot, UsageFetchError> {
        result
    }
}

@MainActor
final class UsageStoreTests: XCTestCase {
    func testLoadedStatePicksHigherUtilizationAsBindingClock() async {
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 40, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 85, resetsAt: nil),
            sevenDayOpus: nil
        )
        let store = UsageStore(usageClient: MockFetcher(result: .success(snapshot)))

        await store.refresh(force: true)

        guard case .loaded = store.state else {
            return XCTFail("expected .loaded, got \(store.state)")
        }
        XCTAssertEqual(store.clocks.count, 2)
        XCTAssertEqual(store.bindingClock?.id, "7d")
        XCTAssertEqual(store.bindingClock?.utilization, 85)
    }

    func testSevenDayOpusIsIncludedWhenPresent() async {
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 10, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 20, resetsAt: nil),
            sevenDayOpus: UsageWindow(utilization: 95, resetsAt: nil)
        )
        let store = UsageStore(usageClient: MockFetcher(result: .success(snapshot)))

        await store.refresh(force: true)

        XCTAssertEqual(store.clocks.count, 3)
        XCTAssertEqual(store.bindingClock?.id, "7d-opus")
    }

    func testNoCredentialsMapsToDedicatedState() async {
        let store = UsageStore(usageClient: MockFetcher(result: .failure(.noCredentials)))

        await store.refresh(force: true)

        guard case .noCredentials = store.state else {
            return XCTFail("expected .noCredentials, got \(store.state)")
        }
        XCTAssertNil(store.lastGood)
    }

    func testTokenExpiredMapsToDedicatedState() async {
        let store = UsageStore(usageClient: MockFetcher(result: .failure(.tokenExpired)))

        await store.refresh(force: true)

        guard case .tokenExpired = store.state else {
            return XCTFail("expected .tokenExpired, got \(store.state)")
        }
    }

    func testNetworkFailureReportsMessageAndLeavesLastGoodEmpty() async {
        let store = UsageStore(usageClient: MockFetcher(result: .failure(.network("offline"))))

        await store.refresh(force: true)

        guard case .error(let message) = store.state else {
            return XCTFail("expected .error, got \(store.state)")
        }
        XCTAssertEqual(message, "offline")
        XCTAssertNil(store.lastGood)
    }

    func testDisplayedClockRespectsExplicitMode() async {
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 20, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 90, resetsAt: nil),
            sevenDayOpus: nil
        )
        let store = UsageStore(usageClient: MockFetcher(result: .success(snapshot)))
        await store.refresh(force: true)

        XCTAssertEqual(store.displayedClock(for: .closest)?.id, "7d")
        XCTAssertEqual(store.displayedClock(for: .fiveHour)?.id, "5h")
        XCTAssertEqual(store.displayedClock(for: .weekly)?.id, "7d")
    }

    func testThrottleSkipsRefreshWithinMinimumInterval() async {
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 10, resetsAt: nil),
            sevenDay: nil,
            sevenDayOpus: nil
        )
        let store = UsageStore(usageClient: MockFetcher(result: .success(snapshot)))
        await store.refresh(force: true)
        let firstFetchedAt = store.lastGood?.fetchedAt

        // Not forced, and well within the 15s throttle window: should be a no-op.
        await store.refresh(force: false)

        XCTAssertEqual(store.lastGood?.fetchedAt, firstFetchedAt)
    }
}
