import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOSSL
import NIOFoundationCompat
import Logging

/// Handles decrypted HTTPS traffic after MITM TLS handshake.
/// Receives HTTP requests from the client through the TLS tunnel,
/// checks rules, and either returns mock responses or forwards to the real server.
/// Supports HTTP/1.1 keep-alive: stays alive for multiple request-response cycles.
final class MITMHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let targetHost: String
    private let targetPort: Int
    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let onTrafficCaptured: ((TrafficEntry) -> Void)?
    private let onRecordingEntry: ((TrafficEntry) -> Void)?
    private let logger = Logger(label: "com.mockpod.mitm")

    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()
    private var startTime = Date()

    init(
        targetHost: String,
        targetPort: Int,
        certificateManager: CertificateManager,
        ruleEngine: RuleEngine,
        onTrafficCaptured: ((TrafficEntry) -> Void)?,
        onRecordingEntry: ((TrafficEntry) -> Void)?
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.onTrafficCaptured = onTrafficCaptured
        self.onRecordingEntry = onRecordingEntry
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            requestBody = Data()
            startTime = Date()

        case .body(let buffer):
            var buf = buffer
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                requestBody.append(contentsOf: bytes)
            }

        case .end:
            guard let head = requestHead else { return }
            processRequest(context: context, head: head)
            // Reset state for next request (keep-alive)
            requestHead = nil
            requestBody = Data()
        }
    }

    private func processRequest(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let scheme = "https"
        let fullURL = "\(scheme)://\(targetHost)\(head.uri)"
        let method = head.method.rawValue
        let requestHeaders = head.headers.map { HTTPHeader(name: $0.name, value: $0.value) }

        var entry = TrafficEntry(
            method: method,
            url: fullURL,
            host: targetHost,
            path: head.uri,
            scheme: scheme,
            requestHeaders: requestHeaders,
            requestBody: requestBody.isEmpty ? nil : requestBody
        )

        // Check certificate download endpoint
        if targetHost == "mockpod.local" || head.uri == "/mockpod/cert" {
            serveCertificate(context: context, entry: &entry)
            return
        }

        // Check rule engine - but don't return early!
        // We now forward to server even if rule matches, to get original headers.
        let matchedRule = ruleEngine.matchRule(method: method, url: fullURL)
        
        // Forward to real server (passing the rule if it exists)
        forwardToServer(context: context, head: head, entry: entry, rule: matchedRule)
    }

    // MARK: - Response Helpers

    /// Send a complete HTTP response through the pipeline (goes through HTTPResponseEncoder → TLS)
    private func sendResponse(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        headers: HTTPHeaders,
        body: Data?,
        keepAlive: Bool = true
    ) {
        var responseHeaders = headers
        let bodyCount = body?.count ?? 0
        responseHeaders.replaceOrAdd(name: "Content-Length", value: "\(bodyCount)")
        if keepAlive {
            responseHeaders.replaceOrAdd(name: "Connection", value: "keep-alive")
        } else {
            responseHeaders.replaceOrAdd(name: "Connection", value: "close")
        }

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if let body = body, !body.isEmpty {
            var buf = context.channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        if !keepAlive {
            context.close(promise: nil)
        }
    }

    private func serveCertificate(context: ChannelHandlerContext, entry: inout TrafficEntry) {
        do {
            let (certData, filename) = try certificateManager.rootCAForDownload()

            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/x-x509-ca-cert")
            headers.add(name: "Content-Disposition", value: "attachment; filename=\"\(filename)\"")

            sendResponse(context: context, status: .ok, headers: headers, body: certData, keepAlive: false)

            entry.responseStatusCode = 200
            entry.isComplete = true
            entry.duration = Date().timeIntervalSince(startTime)
            let capturedEntry = entry
            self.onTrafficCaptured?(capturedEntry)
        } catch {
            logger.error("Failed to serve certificate: \(error)")
            sendErrorResponse(context: context, status: .internalServerError, message: "Certificate error")
        }
    }

    private func forwardToServer(context: ChannelHandlerContext, head: HTTPRequestHead, entry: TrafficEntry, rule: MockRule?) {
        let tlsConfig = TLSConfiguration.makeClientConfiguration()
        let sslContext: NIOSSLContext
        do {
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } catch {
            logger.error("Failed TLS config: \(error)")
            sendErrorResponse(context: context, status: .badGateway, message: "TLS error")
            return
        }

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.targetHost)
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.addHTTPClientHandlers()
                }
            }

        bootstrap.connect(host: targetHost, port: targetPort).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let outChannel):
                let collector = MITMResponseCollector(
                    clientContext: context,
                    mitmHandler: self,
                    entry: entry,
                    rule: rule, // Pass the rule to the collector
                    startTime: self.startTime,
                    onTrafficCaptured: self.onTrafficCaptured,
                    onRecordingEntry: self.onRecordingEntry
                )
                outChannel.pipeline.addHandler(collector).whenSuccess {
                    var reqHead = head
                    reqHead.headers.replaceOrAdd(name: "Host", value: self.targetHost)
                    // Remove Accept-Encoding to get uncompressed responses
                    reqHead.headers.remove(name: "Accept-Encoding")
                    outChannel.write(HTTPClientRequestPart.head(reqHead), promise: nil)
                    if !self.requestBody.isEmpty {
                        var buf = outChannel.allocator.buffer(capacity: self.requestBody.count)
                        buf.writeBytes(self.requestBody)
                        outChannel.write(HTTPClientRequestPart.body(.byteBuffer(buf)), promise: nil)
                    }
                    outChannel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
                }
            case .failure(let error):
                // If connection fails but we have a rule, we can fallback to serving the mock directly (offline mode)
                if let rule = rule {
                    self.logger.warning("Connection failed, serving offline mock for \(self.targetHost)")
                    var mutableEntry = entry
                    self.sendMockResponse(context: context, rule: rule, entry: &mutableEntry)
                } else {
                    self.logger.error("Connect to \(self.targetHost):\(self.targetPort) failed: \(error)")
                    self.sendErrorResponse(context: context, status: .badGateway, message: "Connection failed")
                }
            }
        }
    }

    /// Helper to send mock response directly (fallback for offline or explicit mock handling if needed later)
    private func sendMockResponse(context: ChannelHandlerContext, rule: MockRule, entry: inout TrafficEntry) {
        let mock = rule.mockResponse
        let bodyData = mock.body.data(using: .utf8) ?? Data()
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Mockpod-Rule", value: rule.name)
        for h in mock.headers {
            headers.add(name: h.name, value: h.value)
        }
        
        let status = HTTPResponseStatus(statusCode: mock.statusCode)
        
        entry.responseStatusCode = mock.statusCode
        entry.responseHeaders = mock.headers + [HTTPHeader(name: "X-Mockpod-Rule", value: rule.name)]
        entry.responseBody = bodyData
        entry.duration = Date().timeIntervalSince(startTime)
        entry.isComplete = true
        
        let capturedEntry = entry
        
        let doSend = { [weak self] in
            self?.sendResponse(context: context, status: status, headers: headers, body: bodyData)
            self?.onTrafficCaptured?(capturedEntry)
            self?.onRecordingEntry?(capturedEntry)
        }
        
        if let delay = mock.delay {
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(delay * 1000))) { doSend() }
        } else {
            doSend()
        }
    }

    private func sendErrorResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        let body = message.data(using: .utf8) ?? Data()
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        sendResponse(context: context, status: status, headers: headers, body: body, keepAlive: false)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let errorString = "\(error)"
        if errorString.contains("handshakeFailed") || errorString.contains("EOF") {
            logger.debug("TLS handshake failed for \(targetHost) (expected for cert-pinned apps)")
        } else {
            logger.warning("MITMHandler error for \(targetHost): \(error)")
        }
        context.close(promise: nil)
    }
}

// MARK: - MITM Response Collector

/// Collects response from real server and forwards it back to the MITM client.
/// Can apply mock rule modifications (headers/body) if a rule is present.
final class MITMResponseCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let clientContext: ChannelHandlerContext
    private weak var mitmHandler: MITMHandler?
    private let startTime: Date
    private let onTrafficCaptured: ((TrafficEntry) -> Void)?
    private let onRecordingEntry: ((TrafficEntry) -> Void)?
    private var entry: TrafficEntry
    private let rule: MockRule?
    private var responseHead: HTTPResponseHead?
    private var bodyBuffer = Data()

    init(
        clientContext: ChannelHandlerContext,
        mitmHandler: MITMHandler,
        entry: TrafficEntry,
        rule: MockRule?,
        startTime: Date,
        onTrafficCaptured: ((TrafficEntry) -> Void)?,
        onRecordingEntry: ((TrafficEntry) -> Void)?
    ) {
        self.clientContext = clientContext
        self.mitmHandler = mitmHandler
        self.entry = entry
        self.rule = rule
        self.startTime = startTime
        self.onTrafficCaptured = onTrafficCaptured
        self.onRecordingEntry = onRecordingEntry
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            responseHead = head

        case .body(let buffer):
            var buf = buffer
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                bodyBuffer.append(contentsOf: bytes)
            }

        case .end:
            guard let head = responseHead else {
                context.close(promise: nil)
                return
            }

            // Determine final status, headers, and body
            var finalStatus = head.status
            var finalBody = bodyBuffer
            var finalHeaders = HTTPHeaders()
            
            // 1. Start with original headers (filtered)
            for header in head.headers {
                let lower = header.name.lowercased()
                if lower == "transfer-encoding" || lower == "content-encoding"
                    || lower == "content-length" || lower == "connection" {
                    continue
                }
                finalHeaders.add(name: header.name, value: header.value)
            }
            
            // 2. Apply Mock Rule overrides (if any)
            if let rule = rule {
                let mock = rule.mockResponse
                
                // Override Status
                finalStatus = HTTPResponseStatus(statusCode: mock.statusCode)
                
                // Override Body
                if let mockBodyData = mock.body.data(using: .utf8) {
                    finalBody = mockBodyData
                }
                
                // Merge/Overwrite Headers
                // "sadece orjinal response içerisinde benim mock olarak eklediğim keyleri alıp orjinalinin üzerine yaz"
                for h in mock.headers {
                     // If header exists, replace it. If not, add it.
                    finalHeaders.replaceOrAdd(name: h.name, value: h.value)
                }
                
                // Add marker header
                finalHeaders.replaceOrAdd(name: "X-Mockpod-Rule", value: rule.name)
            }

            // 3. Set standard headers
            finalHeaders.replaceOrAdd(name: "Content-Length", value: "\(finalBody.count)")
            finalHeaders.replaceOrAdd(name: "Connection", value: "keep-alive")

            // Send through the pipeline
            let clientHead = HTTPResponseHead(version: .http1_1, status: finalStatus, headers: finalHeaders)
            let headPart = HTTPServerResponsePart.head(clientHead)
            clientContext.write(NIOAny(headPart), promise: nil)

            if !finalBody.isEmpty {
                var buf = clientContext.channel.allocator.buffer(capacity: finalBody.count)
                buf.writeBytes(finalBody)
                let bodyPart = HTTPServerResponsePart.body(.byteBuffer(buf))
                clientContext.write(NIOAny(bodyPart), promise: nil)
            }

            let endPart = HTTPServerResponsePart.end(nil)
            
            // Use writeAndFlush for the last part to ensure transmission
            // Handle optional delay
            if let delay = rule?.mockResponse.delay {
                 clientContext.eventLoop.scheduleTask(in: .milliseconds(Int64(delay * 1000))) {
                     self.clientContext.writeAndFlush(NIOAny(endPart), promise: nil)
                 }
            } else {
                clientContext.writeAndFlush(NIOAny(endPart), promise: nil)
            }

            // Update traffic entry
            entry.responseStatusCode = Int(finalStatus.code)
            entry.responseHeaders = finalHeaders.map { HTTPHeader(name: $0.name, value: $0.value) }
            entry.responseBody = finalBody.isEmpty ? nil : finalBody
            entry.duration = Date().timeIntervalSince(startTime)
            entry.isComplete = true

            let capturedEntry = entry
            onTrafficCaptured?(capturedEntry)
            onRecordingEntry?(capturedEntry)

            // Close the outbound connection to the real server
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
