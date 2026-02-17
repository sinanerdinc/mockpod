import Foundation
import X509
import SwiftASN1
import Crypto
import NIOSSL

/// Manages Root CA and dynamic leaf certificate generation for MITM proxying
final class CertificateManager {
    private let rootCAKey: P256.Signing.PrivateKey
    private let rootCACert: X509.Certificate
    private lazy var rootCANIOSSL: NIOSSLCertificate = {
        var serializer = DER.Serializer()
        try! rootCACert.serialize(into: &serializer)
        return try! NIOSSLCertificate(bytes: serializer.serializedBytes, format: .der)
    }()
    private var leafCache: [String: (NIOSSLCertificate, NIOSSLPrivateKey)] = [:]
    private let lock = NSLock()

    private let storageDir: URL

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("Mockpod/Certificates", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let keyFile = storageDir.appendingPathComponent("rootCA.key.pem")
        let certFile = storageDir.appendingPathComponent("rootCA.cert.pem")

        if FileManager.default.fileExists(atPath: keyFile.path),
           FileManager.default.fileExists(atPath: certFile.path) {
            // Load existing Root CA
            let keyPEM = try String(contentsOf: keyFile, encoding: .utf8)
            rootCAKey = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)

            let certPEM = try String(contentsOf: certFile, encoding: .utf8)
            let pemDoc = try PEMDocument(pemString: certPEM)
            rootCACert = try X509.Certificate(derEncoded: pemDoc.derBytes)
        } else {
            // Generate new Root CA
            let key = P256.Signing.PrivateKey()
            let name = try DistinguishedName {
                CommonName("Mockpod Proxy CA")
                OrganizationName("Mockpod")
                CountryName("US")
            }

            let certPublicKey = Certificate.PublicKey(key.publicKey)

            let extensions = try X509.Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                SubjectKeyIdentifier(hash: certPublicKey)
            }

            let cert = try X509.Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: .init(key.publicKey),
                notValidBefore: Date(),
                notValidAfter: Date().addingTimeInterval(86400 * 365 * 10),
                issuer: name,
                subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: extensions,
                issuerPrivateKey: .init(key)
            )

            self.rootCAKey = key
            self.rootCACert = cert

            // Save to disk
            try key.pemRepresentation.write(to: keyFile, atomically: true, encoding: .utf8)
            let certPEM = try self.exportRootCAPEM()
            try certPEM.write(to: certFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Leaf Certificate Generation

    func getTLSConfiguration(for host: String) throws -> TLSConfiguration {
        lock.lock()
        defer { lock.unlock() }

        if let cached = leafCache[host] {
            var config = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cached.0), .certificate(rootCANIOSSL)],
                privateKey: .privateKey(cached.1)
            )
            config.minimumTLSVersion = .tlsv12
            return config
        }

        let (cert, key) = try generateLeafCertificate(for: host)
        leafCache[host] = (cert, key)

        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(cert), .certificate(rootCANIOSSL)],
            privateKey: .privateKey(key)
        )
        config.minimumTLSVersion = .tlsv12
        return config
    }

    private func generateLeafCertificate(for domain: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        let leafKey = P256.Signing.PrivateKey()

        let subject = try DistinguishedName {
            CommonName(domain)
            OrganizationName("Mockpod")
        }

        _ = Certificate.PublicKey(leafKey.publicKey)

        let extensions = try X509.Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true))
            try ExtendedKeyUsage([.serverAuth])
            SubjectAlternativeNames([.dnsName(domain)])
        }

        let cert = try X509.Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: .init(leafKey.publicKey),
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(86400 * 825),
            issuer: rootCACert.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: .init(rootCAKey)
        )

        // Convert to NIO-SSL types
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let nioSSLCert = try NIOSSLCertificate(bytes: serializer.serializedBytes, format: .der)
        let nioSSLKey = try NIOSSLPrivateKey(bytes: Array(leafKey.pemRepresentation.utf8), format: .pem)

        return (nioSSLCert, nioSSLKey)
    }

    // MARK: - Root CA Export

    func exportRootCAPEM() throws -> String {
        var serializer = DER.Serializer()
        try rootCACert.serialize(into: &serializer)
        let pemDoc = PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes)
        return pemDoc.pemString
    }

    func exportRootCADER() throws -> Data {
        var serializer = DER.Serializer()
        try rootCACert.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    /// Path to the Root CA PEM file on disk
    var rootCAPEMPath: URL {
        storageDir.appendingPathComponent("rootCA.cert.pem")
    }

    /// Serve Root CA certificate data with appropriate content type
    func rootCAForDownload() throws -> (data: Data, filename: String) {
        let der = try exportRootCADER()
        return (data: der, filename: "MockpodCA.der")
    }
}
