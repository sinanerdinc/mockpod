import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOSSL
import NIOFoundationCompat
import Logging

/// Handles each incoming connection to the proxy server.
/// Parses the first HTTP request to determine if it's a regular HTTP proxy request
/// or a CONNECT tunnel (for HTTPS MITM).
final class ProxyChannelHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let certificateManager: CertificateManager
    private let ruleEngine: RuleEngine
    private let onTrafficCaptured: ((TrafficEntry) -> Void)?
    private let onRecordingEntry: ((TrafficEntry) -> Void)?
    private let logger = Logger(label: "com.mockpod.handler")

    private var buffer = ByteBuffer()
    private enum State {
        case awaitingRequest
        case httpProxy
        case connectTunnel(host: String, port: Int)
    }
    private var state: State = .awaitingRequest

    init(
        certificateManager: CertificateManager,
        ruleEngine: RuleEngine,
        onTrafficCaptured: ((TrafficEntry) -> Void)?,
        onRecordingEntry: ((TrafficEntry) -> Void)?
    ) {
        self.certificateManager = certificateManager
        self.ruleEngine = ruleEngine
        self.onTrafficCaptured = onTrafficCaptured
        self.onRecordingEntry = onRecordingEntry
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        buffer.writeBuffer(&buf)

        guard let requestLine = parseRequestLine() else { return }

        if requestLine.method == "CONNECT" {
            handleConnect(context: context, requestLine: requestLine)
        } else {
            handleHTTPProxy(context: context, requestLine: requestLine)
        }
    }

    // MARK: - CONNECT Tunnel (HTTPS MITM)

    private func handleConnect(context: ChannelHandlerContext, requestLine: RequestLine) {
        let parts = requestLine.uri.split(separator: ":")
        let host = String(parts[0])
        let port = parts.count > 1 ? Int(parts[1]) ?? 443 : 443

        // Send 200 Connection Established
        var response = context.channel.allocator.buffer(capacity: 64)
        response.writeString("HTTP/1.1 200 Connection Established\r\n\r\n")
        context.channel.writeAndFlush(response, promise: nil)

        // Clear buffer and remove this handler
        buffer.clear()

        // Now add TLS server handler for MITM
        do {
            var tlsConfig = try certificateManager.getTLSConfiguration(for: host)
            tlsConfig.certificateVerification = .none

            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            let mitmHandler = MITMHandler(
                targetHost: host,
                targetPort: port,
                certificateManager: certificateManager,
                ruleEngine: ruleEngine,
                onTrafficCaptured: onTrafficCaptured,
                onRecordingEntry: onRecordingEntry
            )

            context.pipeline.removeHandler(self, promise: nil)
            _ = context.pipeline.addHandler(sslHandler).flatMap {
                context.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
            }.flatMap {
                context.pipeline.addHandler(HTTPResponseEncoder())
            }.flatMap {
                context.pipeline.addHandler(mitmHandler)
            }
        } catch {
            logger.error("Failed to setup MITM for \(host): \(error)")
            context.close(promise: nil)
        }
    }

    // MARK: - HTTP Proxy (non-SSL)

    private func handleHTTPProxy(context: ChannelHandlerContext, requestLine: RequestLine) {
        guard let url = URL(string: requestLine.uri) else {
            context.close(promise: nil)
            return
        }

        let host = url.host ?? ""
        let port = url.port ?? 80
        let path = url.path.isEmpty ? "/" : url.path + (url.query.map { "?\($0)" } ?? "")
        let scheme = url.scheme ?? "http"
        let fullURL = requestLine.uri

        // Read remaining headers and body from buffer
        let (headers, body) = parseHeadersAndBody()

        let requestHeaders = headers.map { HTTPHeader(name: $0.0, value: $0.1) }
        let startTime = Date()

        var entry = TrafficEntry(
            method: requestLine.method,
            url: fullURL,
            host: host,
            path: path,
            scheme: scheme,
            requestHeaders: requestHeaders,
            requestBody: body
        )

        // Check rule engine
        if let rule = ruleEngine.matchRule(method: requestLine.method, url: fullURL) {
            sendMockResponse(context: context, rule: rule, entry: &entry, startTime: startTime)
            return
        }

        // Forward to real server
        forwardHTTPRequest(
            context: context,
            host: host,
            port: port,
            method: requestLine.method,
            path: path,
            headers: headers,
            body: body,
            entry: entry,
            startTime: startTime
        )
    }

    private func forwardHTTPRequest(
        context: ChannelHandlerContext,
        host: String,
        port: Int,
        method: String,
        path: String,
        headers: [(String, String)],
        body: Data?,
        entry: TrafficEntry,
        startTime: Date
    ) {
        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers()
            }

        bootstrap.connect(host: host, port: port).whenComplete { [weak self] result in
            switch result {
            case .success(let outChannel):
                self?.sendRequestAndCollectResponse(
                    clientContext: context,
                    outChannel: outChannel,
                    method: method,
                    path: path,
                    host: host,
                    headers: headers,
                    body: body,
                    entry: entry,
                    startTime: startTime
                )
            case .failure(let error):
                self?.logger.error("Failed to connect to \(host):\(port): \(error)")
                self?.sendErrorResponse(context: context, status: .badGateway, message: "Failed to connect: \(error)")
                context.close(promise: nil)
            }
        }
    }

    private func sendRequestAndCollectResponse(
        clientContext: ChannelHandlerContext,
        outChannel: Channel,
        method: String,
        path: String,
        host: String,
        headers: [(String, String)],
        body: Data?,
        entry: TrafficEntry,
        startTime: Date
    ) {
        let collector = HTTPResponseCollector(
            channel: outChannel,
            onComplete: { [weak self] responseHead, responseBody in
                var updatedEntry = entry
                updatedEntry.responseStatusCode = Int(responseHead.status.code)
                updatedEntry.responseHeaders = responseHead.headers.map { HTTPHeader(name: $0.name, value: $0.value) }
                updatedEntry.responseBody = responseBody
                updatedEntry.duration = Date().timeIntervalSince(startTime)
                updatedEntry.isComplete = true

                // Forward response to client
                self?.forwardResponseToClient(
                    context: clientContext,
                    head: responseHead,
                    body: responseBody
                )

                // Notify traffic capture
                self?.onTrafficCaptured?(updatedEntry)
                self?.onRecordingEntry?(updatedEntry)
            }
        )

        outChannel.pipeline.addHandler(collector).whenSuccess {
            // Build request
            let httpMethod = HTTPMethod(rawValue: method)
            var reqHead = HTTPRequestHead(version: .http1_1, method: httpMethod, uri: path)
            reqHead.headers.add(name: "Host", value: host)
            for (name, value) in headers where name.lowercased() != "host" && name.lowercased() != "proxy-connection" && name.lowercased() != "accept-encoding" {
                reqHead.headers.add(name: name, value: value)
            }

            outChannel.write(HTTPClientRequestPart.head(reqHead), promise: nil)
            if let body = body {
                var buf = outChannel.allocator.buffer(capacity: body.count)
                buf.writeBytes(body)
                outChannel.write(HTTPClientRequestPart.body(.byteBuffer(buf)), promise: nil)
            }
            outChannel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        }
    }

    private func forwardResponseToClient(
        context: ChannelHandlerContext,
        head: HTTPResponseHead,
        body: Data?
    ) {
        var rawResponse = context.channel.allocator.buffer(capacity: 1024)
        rawResponse.writeString("HTTP/\(head.version.major).\(head.version.minor) \(head.status.code) \(head.status.reasonPhrase)\r\n")
        for header in head.headers {
            rawResponse.writeString("\(header.name): \(header.value)\r\n")
        }
        rawResponse.writeString("\r\n")
        if let body = body {
            rawResponse.writeBytes(body)
        }
        context.channel.writeAndFlush(rawResponse, promise: nil)
    }

    private func sendMockResponse(
        context: ChannelHandlerContext,
        rule: MockRule,
        entry: inout TrafficEntry,
        startTime: Date
    ) {
        let mock = rule.mockResponse

        entry.responseStatusCode = mock.statusCode
        entry.responseHeaders = mock.headers
        entry.responseBody = mock.body.data(using: .utf8)
        entry.duration = Date().timeIntervalSince(startTime)
        entry.isComplete = true

        let bodyData = mock.body.data(using: .utf8) ?? Data()
        var rawResponse = context.channel.allocator.buffer(capacity: 512)
        rawResponse.writeString("HTTP/1.1 \(mock.statusCode) \(NetworkUtils.statusCodeDescription(mock.statusCode))\r\n")
        rawResponse.writeString("Content-Type: application/json\r\n")
        rawResponse.writeString("Content-Length: \(bodyData.count)\r\n")
        for header in mock.headers {
            rawResponse.writeString("\(header.name): \(header.value)\r\n")
        }
        rawResponse.writeString("\r\n")
        rawResponse.writeBytes(bodyData)

        let capturedEntry = entry
        if let delay = mock.delay {
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(delay * 1000))) { [weak self] in
                context.channel.writeAndFlush(rawResponse, promise: nil)
                self?.onTrafficCaptured?(capturedEntry)
                self?.onRecordingEntry?(capturedEntry)
            }
        } else {
            context.channel.writeAndFlush(rawResponse, promise: nil)
            onTrafficCaptured?(capturedEntry)
            onRecordingEntry?(capturedEntry)
        }
    }

    private func sendErrorResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        var rawResponse = context.channel.allocator.buffer(capacity: 256)
        rawResponse.writeString("HTTP/1.1 \(status.code) \(status.reasonPhrase)\r\nContent-Type: text/plain\r\nContent-Length: \(message.count)\r\n\r\n\(message)")
        context.channel.writeAndFlush(rawResponse, promise: nil)
    }

    // MARK: - Parsing Helpers

    private struct RequestLine {
        let method: String
        let uri: String
        let version: String
    }

    private func parseRequestLine() -> RequestLine? {
        guard let data = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes),
              let lineEnd = data.range(of: "\r\n") else { return nil }
        let line = String(data[data.startIndex..<lineEnd.lowerBound])
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return RequestLine(
            method: String(parts[0]),
            uri: String(parts[1]),
            version: parts.count > 2 ? String(parts[2]) : "HTTP/1.1"
        )
    }

    private func parseHeadersAndBody() -> ([(String, String)], Data?) {
        guard let raw = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            return ([], nil)
        }

        var headers: [(String, String)] = []
        var body: Data?

        if let headerEnd = raw.range(of: "\r\n\r\n") {
            let headerSection = raw[raw.index(after: raw.range(of: "\r\n")!.upperBound)..<headerEnd.lowerBound]
            for line in headerSection.split(separator: "\r\n") {
                if let colonIndex = line.firstIndex(of: ":") {
                    let name = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    headers.append((name, value))
                }
            }

            let bodyStart = headerEnd.upperBound
            if bodyStart < raw.endIndex {
                body = String(raw[bodyStart...]).data(using: .utf8)
            }
        }

        return (headers, body)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("ProxyChannelHandler error: \(error)")
        context.close(promise: nil)
    }
}

// MARK: - HTTP Response Collector

/// Collects a full HTTP response from an outbound channel
final class HTTPResponseCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let channel: Channel
    private let onComplete: (HTTPResponseHead, Data?) -> Void
    private var head: HTTPResponseHead?
    private var bodyBuffer = Data()

    init(channel: Channel, onComplete: @escaping (HTTPResponseHead, Data?) -> Void) {
        self.channel = channel
        self.onComplete = onComplete
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let responseHead):
            self.head = responseHead
        case .body(let buffer):
            var buf = buffer
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                bodyBuffer.append(contentsOf: bytes)
            }
        case .end:
            if let head = head {
                onComplete(head, bodyBuffer.isEmpty ? nil : bodyBuffer)
            }
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
