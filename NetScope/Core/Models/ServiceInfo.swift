import Foundation

/// A TCP port found open on a host, plus whatever we could learn about it.
struct ServiceInfo: Identifiable, Hashable, Sendable, Codable {

    var port: UInt16
    /// Well-known name (`SSH`, `HTTP`, …) or `nil` for unrecognised ports.
    var name: String?
    /// Free-form detail captured from a banner / HTTP headers, when available.
    var detail: String?
    /// Round-trip time of the successful TCP handshake.
    var connectTime: TimeInterval?
    /// True when the entry came from Bonjour rather than a port probe.
    var discoveredViaBonjour: Bool = false

    var id: UInt16 { port }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return PortCatalog.name(for: port) ?? "Port \(port)"
    }

    var symbolName: String { PortCatalog.symbol(for: port) }
}

/// Static knowledge about well-known ports: names, icons and the scan profiles.
enum PortCatalog {

    /// Ports probed by the *fast* profile — chosen to identify a device type
    /// with as few connections as possible.
    static let quickPorts: [UInt16] = [
        80, 443, 22, 445, 139, 8080, 62078, 5000, 7000, 548, 3689, 9100, 631, 53, 23, 21
    ]

    /// Ports probed by the *balanced* profile.
    static let commonPorts: [UInt16] = [
        21, 22, 23, 25, 53, 80, 81, 88, 110, 111, 135, 139, 143, 389, 443, 445, 465,
        500, 515, 548, 554, 587, 631, 636, 873, 902, 993, 995, 1080, 1194, 1433, 1521,
        1723, 1883, 1900, 2049, 2222, 2375, 3000, 3128, 3260, 3306, 3389, 3689, 4200,
        5000, 5001, 5060, 5222, 5353, 5432, 5555, 5900, 6000, 6379, 7000, 7070, 8000,
        8008, 8009, 8080, 8081, 8083, 8088, 8123, 8181, 8200, 8443, 8888, 9000, 9090,
        9100, 9200, 10000, 11211, 27017, 32400, 49152, 51413, 62078
    ]

    /// Ports probed by the *thorough* profile: common set + a dense low range.
    static var thoroughPorts: [UInt16] {
        let low = (1...1024).map(UInt16.init)
        return Array(Set(low).union(commonPorts)).sorted()
    }

    private static let names: [UInt16: String] = [
        20: "FTP-Data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS",
        67: "DHCP", 68: "DHCP", 69: "TFTP", 80: "HTTP", 81: "HTTP-Alt", 88: "Kerberos",
        110: "POP3", 111: "RPC", 123: "NTP", 135: "MS-RPC", 137: "NetBIOS", 138: "NetBIOS",
        139: "NetBIOS-SSN", 143: "IMAP", 161: "SNMP", 389: "LDAP", 427: "SLP",
        443: "HTTPS", 445: "SMB", 465: "SMTPS", 500: "IPsec", 515: "LPD",
        548: "AFP", 554: "RTSP", 587: "SMTP", 631: "IPP", 636: "LDAPS", 873: "rsync",
        902: "VMware", 993: "IMAPS", 995: "POP3S", 1080: "SOCKS", 1194: "OpenVPN",
        1433: "MSSQL", 1521: "Oracle", 1723: "PPTP", 1883: "MQTT", 1900: "SSDP",
        2049: "NFS", 2222: "SSH-Alt", 2375: "Docker", 3000: "Dev/HTTP", 3128: "Squid",
        3260: "iSCSI", 3306: "MySQL", 3389: "RDP", 3689: "DAAP", 4200: "Dev/HTTP",
        5000: "UPnP/HTTP", 5001: "Synology", 5060: "SIP", 5222: "XMPP", 5353: "mDNS",
        5432: "PostgreSQL", 5555: "ADB", 5900: "VNC", 6000: "X11", 6379: "Redis",
        7000: "AirPlay", 7070: "RTSP-Alt", 8000: "HTTP-Alt", 8008: "Chromecast",
        8009: "Chromecast", 8080: "HTTP-Proxy", 8081: "HTTP-Alt", 8083: "HTTP-Alt",
        8088: "HTTP-Alt", 8123: "Home Assistant", 8181: "HTTP-Alt", 8200: "DLNA",
        8443: "HTTPS-Alt", 8888: "HTTP-Alt", 9000: "HTTP-Alt", 9090: "HTTP-Alt",
        9100: "Printer (RAW)", 9200: "Elasticsearch", 10000: "Webmin",
        11211: "Memcached", 27017: "MongoDB", 32400: "Plex", 49152: "UPnP",
        51413: "Transmission", 62078: "iOS Sync"
    ]

    static func name(for port: UInt16) -> String? { names[port] }

    static func symbol(for port: UInt16) -> String {
        switch port {
        case 80, 81, 443, 8000, 8008, 8080, 8081, 8083, 8088, 8181, 8443, 8888, 3000, 4200, 9000, 9090:
            return "globe"
        case 22, 23, 2222, 5900, 3389:
            return "terminal"
        case 139, 445, 548, 2049, 873:
            return "externaldrive.connected.to.line.below"
        case 515, 631, 9100:
            return "printer"
        case 554, 7000, 7070, 8200, 32400, 3689:
            return "play.rectangle"
        case 1433, 3306, 5432, 6379, 9200, 11211, 27017:
            return "cylinder.split.1x2"
        case 53, 5353:
            return "arrow.triangle.branch"
        case 1883, 8123:
            return "sensor"
        default:
            return "bolt.horizontal"
        }
    }

    /// Maps a Bonjour service type (`_airplay._tcp`) onto a friendly label.
    static func bonjourLabel(for type: String) -> String {
        let trimmed = type
            .replacingOccurrences(of: "._tcp.", with: "")
            .replacingOccurrences(of: "._udp.", with: "")
            .replacingOccurrences(of: "._tcp", with: "")
            .replacingOccurrences(of: "._udp", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch trimmed {
        case "http": return "Web Server"
        case "https": return "Web Server (TLS)"
        case "ssh": return "SSH"
        case "sftp-ssh": return "SFTP"
        case "smb": return "SMB Share"
        case "afpovertcp": return "AFP Share"
        case "nfs": return "NFS Share"
        case "ipp", "ipps", "printer", "pdl-datastream": return "Printer"
        case "scanner": return "Scanner"
        case "airplay": return "AirPlay"
        case "raop": return "AirPlay Audio"
        case "googlecast": return "Chromecast"
        case "spotify-connect": return "Spotify Connect"
        case "sonos": return "Sonos"
        case "hap", "homekit": return "HomeKit"
        case "companion-link": return "Apple Companion"
        case "rdlink": return "Apple Remote Desktop"
        case "device-info": return "Device Info"
        case "workstation": return "Workstation"
        case "rfb": return "Screen Sharing"
        case "daap": return "iTunes Library"
        case "dacp", "touch-able": return "Remote Control"
        default: return trimmed.capitalized
        }
    }
}
