import Foundation

// Sample data for SwiftUI previews. Compiled into the app but referenced only
// from `#Preview` blocks and `AppEnvironment.preview()`.

extension NetworkSnapshot {
    static var previewSample: NetworkSnapshot {
        var snapshot = NetworkSnapshot()
        snapshot.interfaceName = "en0"
        snapshot.interfaceType = .wifi
        snapshot.localAddress = IPv4("192.168.1.42")
        snapshot.netmask = IPv4("255.255.255.0")
        snapshot.subnet = IPv4Subnet(address: IPv4("192.168.1.42")!, prefixLength: 24)
        snapshot.gateway = IPv4("192.168.1.1")
        snapshot.broadcast = IPv4("192.168.1.255")
        snapshot.dnsServers = [IPv4("192.168.1.1")!, IPv4("1.1.1.1")!]
        snapshot.ssid = "Aurora 5G"
        snapshot.isSecure = true
        snapshot.externalRouterVendor = "Ubiquiti"
        return snapshot
    }
}

extension Device {

    static var previewSamples: [Device] {
        let networkID = NetworkSnapshot.previewSample.networkID

        func make(
            ip: String,
            name: String?,
            vendor: String?,
            kind: DeviceKind,
            latency: Double?,
            ports: [UInt16],
            mac: String? = nil,
            isGateway: Bool = false,
            isLocal: Bool = false,
            favorite: Bool = false,
            online: Bool = true
        ) -> Device {
            var device = Device(id: mac.map { "mac:\($0)" } ?? "\(networkID)|\(ip)", ipAddress: IPv4(ip)!)
            device.bonjourName = name
            device.vendor = vendor
            device.kind = kind
            device.macAddress = mac
            device.latency = latency
            device.latencySamples = latency.map { base in
                (0..<12).map { _ in base * Double.random(in: 0.7...1.4) }
            } ?? []
            device.services = ports.map {
                ServiceInfo(port: $0, name: PortCatalog.name(for: $0), connectTime: 0.012)
            }
            device.isGateway = isGateway
            device.isLocalDevice = isLocal
            device.isFavorite = favorite
            device.responded = online
            device.networkID = networkID
            device.timesSeen = Int.random(in: 1...40)
            device.firstSeen = .now.addingTimeInterval(-Double.random(in: 3600...600_000))
            device.lastSeen = .now.addingTimeInterval(-Double.random(in: 0...600))
            return device
        }

        return [
            make(
                ip: "192.168.1.1", name: "UniFi Gateway", vendor: "Ubiquiti", kind: .router,
                latency: 0.0032, ports: [53, 80, 443, 22], mac: "24:a4:3c:11:22:33",
                isGateway: true, favorite: true
            ),
            make(
                ip: "192.168.1.42", name: "iPhone 16 Pro", vendor: "Apple", kind: .phone,
                latency: 0.0008, ports: [62078], mac: "a4:83:e7:aa:bb:cc", isLocal: true
            ),
            make(
                ip: "192.168.1.57", name: "Studio Mac", vendor: "Apple", kind: .computer,
                latency: 0.0121, ports: [22, 445, 5900, 80], mac: "f0:98:9d:de:ad:01", favorite: true
            ),
            make(
                ip: "192.168.1.64", name: "Living Room Apple TV", vendor: "Apple", kind: .tv,
                latency: 0.0243, ports: [7000, 3689, 49152], mac: "dc:2b:2a:00:11:22"
            ),
            make(
                ip: "192.168.1.70", name: "Office LaserJet", vendor: "HP", kind: .printer,
                latency: 0.0451, ports: [80, 515, 631, 9100], mac: "94:57:7d:ff:ee:dd"
            ),
            make(
                ip: "192.168.1.88", name: "DiskStation", vendor: "Synology", kind: .storage,
                latency: 0.0067, ports: [22, 80, 443, 445, 5000, 5001], mac: "00:11:32:ab:cd:ef"
            ),
            make(
                ip: "192.168.1.101", name: nil, vendor: "Espressif (ESP32)", kind: .iot,
                latency: 0.1832, ports: [80, 1883], mac: "24:0a:c4:12:34:56"
            ),
            make(
                ip: "192.168.1.113", name: "Kitchen Speaker", vendor: "Sonos", kind: .speaker,
                latency: 0.0325, ports: [80, 1400], mac: "94:9f:3e:0a:0b:0c"
            ),
            make(
                ip: "192.168.1.150", name: nil, vendor: nil, kind: .unknown,
                latency: nil, ports: [], online: false
            ),
            make(
                ip: "192.168.1.201", name: "raspberrypi", vendor: "Raspberry Pi (Trading)", kind: .server,
                latency: 0.0094, ports: [22, 80, 8123], mac: "dc:a6:32:99:88:77"
            )
        ]
    }
}
