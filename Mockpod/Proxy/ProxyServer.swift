import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import Logging

/// The main HTTP/HTTPS proxy server built on SwiftNIO
final class ProxyServer {
    private var channel: Channel?
    private let group: MultiThreadedEventLoopGroup
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let logger = Logger(label: "com.mockpod.proxy")

    /// Callback invoked on the main thread when a traffic entry is captured
    var onTrafficCaptured: ((TrafficEntry) -> Void)?

    /// Callback invoked when recording is active
    var onRecordingEntry: ((TrafficEntry) -> Void)?

    let port: Int

    init(port: Int = 8080, certificateManager: CertificateManager, ruleEngine: RuleEngine) {
        self.port = port
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    func start() throws {
        let certManager = self.certificateManager
        let ruleEng = self.ruleEngine
        let trafficCallback = self.onTrafficCaptured
        let recordingCallback = self.onRecordingEntry

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let handler = ProxyChannelHandler(
                    certificateManager: certManager,
                    ruleEngine: ruleEng,
                    onTrafficCaptured: trafficCallback,
                    onRecordingEntry: recordingCallback
                )
                return channel.pipeline.addHandler(handler)
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        logger.info("Proxy server started on port \(port)")
    }

    func stop() {
        channel?.close(mode: .all, promise: nil)
        channel = nil
        logger.info("Proxy server stopped")
    }

    func shutdown() {
        stop()
        try? group.syncShutdownGracefully()
    }

    deinit {
        shutdown()
    }
}
