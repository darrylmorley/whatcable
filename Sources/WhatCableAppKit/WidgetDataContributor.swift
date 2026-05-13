import Combine

@MainActor
public protocol WidgetDataContributor: AnyObject {
    func start()
    func stop()
    var changes: AnyPublisher<Void, Never> { get }
    func recentPower(forPortKey key: String) -> [Double]?
}
