import Foundation

/// Infers a device's likely type from the signals a sandboxed app can see:
/// vendor (via OUI), Bonjour service types and TXT records, hostname, and the
/// shape of its open-port set.
///
/// Everything here is a heuristic. iOS deliberately withholds the precise model
/// of other devices, so the UI presents this as a guess, never as fact.
enum DeviceClassifier {

    static func classify(
        vendor: String?,
        hostname: String?,
        bonjourName: String?,
        bonjourTypes: [String],
        advertisedModel: String?,
        openPorts: [UInt16],
        isGateway: Bool
    ) -> DeviceKind {
        if isGateway { return .router }

        let ports = Set(openPorts)
        let types = Set(bonjourTypes.map { $0.lowercased() })
        let text = [vendor, hostname, bonjourName, advertisedModel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        // 1. Bonjour is the strongest signal we get.
        if types.contains(where: { $0.contains("_ipp") || $0.contains("_printer") || $0.contains("_pdl-datastream") }) {
            return .printer
        }
        if types.contains(where: { $0.contains("_scanner") }) { return .printer }
        if types.contains(where: { $0.contains("_googlecast") || $0.contains("_airplay") }) {
            return text.contains("homepod") || text.contains("speaker") ? .speaker : .tv
        }
        if types.contains(where: { $0.contains("_sonos") || $0.contains("_spotify-connect") || $0.contains("_raop") }) {
            return .speaker
        }
        if types.contains(where: { $0.contains("_hap") || $0.contains("_homekit") }) { return .iot }
        if types.contains(where: { $0.contains("_smb") || $0.contains("_afpovertcp") || $0.contains("_nfs") }) {
            return text.contains("macbook") || text.contains("imac") ? .computer : .storage
        }
        if types.contains(where: { $0.contains("_workstation") || $0.contains("_rfb") || $0.contains("_rdlink") }) {
            return .computer
        }

        // 2. Apple model identifiers advertised in TXT records.
        if let model = advertisedModel?.lowercased() {
            if model.hasPrefix("iphone") { return .phone }
            if model.hasPrefix("ipad") { return .tablet }
            if model.hasPrefix("watch") { return .wearable }
            if model.hasPrefix("macbook") || model.hasPrefix("imac") || model.hasPrefix("macmini") || model.hasPrefix("macpro") || model.hasPrefix("mac") {
                return .computer
            }
            if model.hasPrefix("appletv") || model.contains("j305") || model.contains("j105") { return .tv }
            if model.hasPrefix("audioaccessory") || model.contains("homepod") { return .speaker }
        }

        // 3. Names people actually give devices.
        for (needle, kind) in nameHints where text.contains(needle) {
            return kind
        }

        // 4. Port fingerprints.
        if ports.contains(62078) { return .phone }                       // iOS sync service
        if ports.contains(9100) || ports.contains(515) || ports.contains(631) { return .printer }
        if ports.contains(32400) || ports.contains(8200) || ports.contains(3689) { return .tv }
        if ports.contains(445) && ports.contains(139) { return .storage }
        if ports.contains(5000) && ports.contains(5001) { return .storage }
        if ports.contains(554) || ports.contains(8554) { return .camera }
        if ports.contains(3389) || ports.contains(5900) { return .computer }
        if ports.contains(22) && (ports.contains(80) || ports.contains(443)) { return .server }
        if ports.contains(1883) || ports.contains(8123) { return .iot }
        if ports.contains(53) && ports.contains(80) { return .router }

        // 5. Vendor of last resort.
        if let vendor = vendor?.lowercased() {
            for (needle, kind) in vendorHints where vendor.contains(needle) {
                return kind
            }
        }

        return .unknown
    }

    /// Picks the friendliest name from everything we know about a host.
    static func bestName(hostname: String?, bonjourName: String?, vendor: String?) -> String? {
        if let bonjourName, !bonjourName.isEmpty { return bonjourName }
        if let hostname, !hostname.isEmpty { return Device.prettifyHostname(hostname) }
        return vendor
    }

    private static let nameHints: [(String, DeviceKind)] = [
        ("iphone", .phone), ("ipad", .tablet), ("apple watch", .wearable), ("applewatch", .wearable),
        ("macbook", .computer), ("imac", .computer), ("mac-mini", .computer), ("macmini", .computer),
        ("mac-pro", .computer), ("mac-studio", .computer),
        ("apple-tv", .tv), ("appletv", .tv), ("homepod", .speaker),
        ("android", .phone), ("galaxy", .phone), ("pixel", .phone), ("oneplus", .phone),
        ("redmi", .phone), ("huawei-p", .phone),
        ("printer", .printer), ("officejet", .printer), ("laserjet", .printer),
        ("deskjet", .printer), ("envy", .printer), ("epson", .printer), ("brother", .printer),
        ("kyocera", .printer), ("canon", .printer),
        ("chromecast", .tv), ("roku", .tv), ("firetv", .tv), ("fire-tv", .tv),
        ("shield", .tv), ("bravia", .tv), ("smart-tv", .tv), ("samsungtv", .tv),
        ("sonos", .speaker), ("echo", .speaker), ("alexa", .speaker), ("nest-mini", .speaker),
        ("nest-hub", .speaker), ("bose", .speaker),
        ("router", .router), ("gateway", .router), ("fritz", .router), ("openwrt", .router),
        ("unifi", .router), ("mikrotik", .router), ("archer", .router), ("asus-rt", .router),
        ("nas", .storage), ("synology", .storage), ("diskstation", .storage),
        ("qnap", .storage), ("truenas", .storage), ("freenas", .storage),
        ("camera", .camera), ("ipcam", .camera), ("hikvision", .camera), ("dahua", .camera),
        ("doorbell", .camera), ("wyze", .camera),
        ("playstation", .console), ("ps5", .console), ("ps4", .console),
        ("xbox", .console), ("nintendo", .console), ("switch", .console),
        ("raspberry", .server), ("raspberrypi", .server), ("ubuntu", .server),
        ("debian", .server), ("proxmox", .server), ("docker", .server), ("server", .server),
        ("esp", .iot), ("shelly", .iot), ("tasmota", .iot), ("sonoff", .iot),
        ("hue", .iot), ("tplink-plug", .iot), ("thermostat", .iot), ("sensor", .iot)
    ]

    private static let vendorHints: [(String, DeviceKind)] = [
        ("raspberry", .server), ("espressif", .iot), ("tuya", .iot), ("sonoff", .iot),
        ("philips hue", .iot), ("nest", .iot), ("belkin", .iot),
        ("sonos", .speaker), ("bose", .speaker),
        ("roku", .tv), ("tivo", .tv),
        ("hikvision", .camera), ("dahua", .camera), ("axis", .camera),
        ("synology", .storage), ("qnap", .storage), ("buffalo", .storage),
        ("brother", .printer), ("lexmark", .printer), ("kyocera", .printer),
        ("ricoh", .printer), ("xerox", .printer), ("epson", .printer),
        ("nintendo", .console), ("playstation", .console), ("xbox", .console),
        ("ubiquiti", .router), ("mikrotik", .router), ("netgear", .router),
        ("tp-link", .router), ("d-link", .router), ("avm", .router), ("asus", .computer),
        ("vmware", .server), ("qemu", .server), ("oracle virtualbox", .server),
        ("dell", .computer), ("lenovo", .computer), ("intel", .computer),
        ("microsoft", .computer), ("acer", .computer)
    ]
}
