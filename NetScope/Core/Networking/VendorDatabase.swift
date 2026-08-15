import Foundation

/// Offline OUI (MAC prefix) to vendor lookup.
///
/// Ships a curated set of the assignments actually seen on home and office
/// networks rather than the full 30k-row IEEE registry — the table stays in
/// memory, costs nothing to query and adds no download or paid service.
///
/// Note MAC addresses are only available when the OS exposes an ARP entry for
/// the host; when they are not, vendor stays `nil` and the UI says so.
enum VendorDatabase {

    /// Looks a vendor up from a full MAC (`a4:83:e7:12:34:56`) or a bare OUI.
    static func vendor(forMAC mac: String) -> String? {
        let normalized = mac
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")

        guard normalized.count >= 6 else { return nil }

        // A locally administered address (bit 1 of the first octet) is a
        // privacy-randomised MAC — the OUI is meaningless.
        if let firstOctet = UInt8(normalized.prefix(2), radix: 16), firstOctet & 0x02 != 0 {
            return nil
        }

        return table[String(normalized.prefix(6))]
    }

    /// True when the MAC is randomised, so the UI can explain the missing vendor.
    static func isRandomized(mac: String) -> Bool {
        let normalized = mac.lowercased().replacingOccurrences(of: ":", with: "")
        guard let firstOctet = UInt8(normalized.prefix(2), radix: 16) else { return false }
        return firstOctet & 0x02 != 0
    }

    private static let table: [String: String] = [
        // Apple
        "a483e7": "Apple", "ac87a3": "Apple", "b8e856": "Apple", "d0817a": "Apple",
        "f0989d": "Apple", "3c0754": "Apple", "40b395": "Apple", "68967b": "Apple",
        "7c6d62": "Apple", "8866a5": "Apple", "9803d8": "Apple", "a45e60": "Apple",
        "b065bd": "Apple", "c82a14": "Apple", "dc2b2a": "Apple", "e0accb": "Apple",
        "f0dbf8": "Apple", "04d3cf": "Apple", "0c3021": "Apple", "1499e2": "Apple",
        "1c1ac0": "Apple", "24a074": "Apple", "28cfe9": "Apple", "2c1f23": "Apple",
        "34363b": "Apple", "38484c": "Apple", "3c2ef9": "Apple", "44d884": "Apple",
        "4c57ca": "Apple", "5855ca": "Apple", "5c95ae": "Apple", "6c4008": "Apple",
        "70cd60": "Apple", "78ca39": "Apple", "80929f": "Apple", "84fcfe": "Apple",
        "8c8590": "Apple", "90b21f": "Apple", "9810e8": "Apple", "a0999b": "Apple",
        "a8667f": "Apple", "b418d1": "Apple", "b8c111": "Apple", "bc926b": "Apple",
        "c0847a": "Apple", "cc25ef": "Apple", "d023db": "Apple", "d49a20": "Apple",
        "e498d6": "Apple", "e88d28": "Apple", "f4f15a": "Apple", "fc253f": "Apple",

        // Samsung
        "002454": "Samsung", "0021d1": "Samsung", "1c62b8": "Samsung", "3423ba": "Samsung",
        "5001bb": "Samsung", "5cf6dc": "Samsung", "78bdbc": "Samsung", "8425db": "Samsung",
        "8c7712": "Samsung", "a02195": "Samsung", "c81479": "Samsung", "e8508b": "Samsung",
        "f409d8": "Samsung", "fc0012": "Samsung", "0812a5": "Samsung", "381dd9": "Samsung",

        // Google / Nest
        "3c5ab4": "Google", "6466b3": "Google", "94eb2c": "Google", "a4778b": "Google",
        "f4f5d8": "Google", "f4f5e8": "Google", "1c53f9": "Google", "d84734": "Google",
        "18b430": "Nest Labs", "641666": "Nest Labs",

        // Amazon
        "0c47c9": "Amazon", "1c12b0": "Amazon", "34d270": "Amazon", "44650d": "Amazon",
        "68370e": "Amazon", "747548": "Amazon", "a002dc": "Amazon", "ac63be": "Amazon",
        "f0272d": "Amazon", "fc65de": "Amazon", "40b4cd": "Amazon",

        // Microsoft
        "0017fa": "Microsoft", "00155d": "Microsoft (Hyper-V)", "281878": "Microsoft",
        "5cba37": "Microsoft", "7c1e52": "Microsoft", "c8960d": "Microsoft",

        // Intel
        "001b21": "Intel", "3c9709": "Intel", "5cc5d4": "Intel", "7c7a91": "Intel",
        "8c1645": "Intel", "94659c": "Intel", "a0a8cd": "Intel", "e4b318": "Intel",
        "f8631f": "Intel", "0c8bfd": "Intel", "48f17f": "Intel",

        // Routers / networking
        "001a2b": "AVM (FRITZ!Box)", "3c37e6": "AVM (FRITZ!Box)", "c80e14": "AVM (FRITZ!Box)",
        "0018e7": "Cameo/TP-Link", "50c7bf": "TP-Link", "a42bb0": "TP-Link", "b0be76": "TP-Link", "c006c3": "TP-Link", "e894f6": "TP-Link",
        "f4f26d": "TP-Link", "1c3bf3": "TP-Link", "5c628b": "TP-Link",
        "002722": "Ubiquiti", "24a43c": "Ubiquiti", "44d9e7": "Ubiquiti", "788a20": "Ubiquiti",
        "802aa8": "Ubiquiti", "b4fbe4": "Ubiquiti", "dc9fdb": "Ubiquiti", "fcecda": "Ubiquiti",
        "000c42": "MikroTik", "4c5e0c": "MikroTik", "6c3b6b": "MikroTik", "cc2de0": "MikroTik",
        "e48d8c": "MikroTik", "748114": "MikroTik",
        "00095b": "Netgear", "204e7f": "Netgear", "2c3033": "Netgear", "44944c": "Netgear",
        "6cb0ce": "Netgear", "9c3dcf": "Netgear", "a06391": "Netgear", "c03f0e": "Netgear",
        "001cf0": "D-Link", "1cbdb9": "D-Link", "3c1e04": "D-Link", "b8a386": "D-Link",
        "0013e8": "Intel/Linksys", "48f8b3": "Linksys", "c0c1c0": "Linksys",
        "001d7e": "Cisco-Linksys", "00259c": "Cisco-Linksys", "58bc27": "Cisco",
        "70df2f": "Cisco", "e8ba70": "Cisco",
        "001e2a": "Netgear", "0026f2": "Netgear",
        "b827eb": "Raspberry Pi Foundation",
        "dca632": "Raspberry Pi (Trading)", "e45f01": "Raspberry Pi (Trading)",
        "2ccf67": "Raspberry Pi (Trading)", "d83add": "Raspberry Pi (Trading)",
        "001fc6": "ASUS", "04d9f5": "ASUS", "1c872c": "ASUS", "2c56dc": "ASUS",
        "38d547": "ASUS", "50465d": "ASUS", "704d7b": "ASUS", "ac220b": "ASUS",
        "d017c2": "ASUS", "f832e4": "ASUS",
        "0024a5": "Buffalo", "4ce676": "Buffalo",
        "001478": "Huawei", "045fa7": "Huawei", "10c61f": "Huawei",
        "20f3a3": "Huawei", "48db50": "Huawei", "781dba": "Huawei", "e0247f": "Huawei",
        "00664b": "Huawei", "d4b110": "Huawei",
        "0c1dc2": "Xiaomi", "286c07": "Xiaomi", "34ce00": "Xiaomi", "50ec50": "Xiaomi",
        "64b473": "Xiaomi", "78115b": "Xiaomi", "8c53c3": "Xiaomi", "9c99a0": "Xiaomi",
        "a0866f": "Xiaomi", "f0b429": "Xiaomi", "fc64ba": "Xiaomi",
        "247f3c": "Huawei", "acf7f3": "Xiaomi",

        // NAS / storage
        "001132": "Synology", "0024f7": "Synology",
        "000c29": "VMware", "005056": "VMware", "080027": "Oracle VirtualBox",
        "00089b": "ICP Electronics", "245ebe": "QNAP",
        "00d861": "QNAP", "1c6f65": "Giga-Byte", "00e04c": "Realtek",

        // Printers
        "0017c8": "Kyocera", "002673": "Brother", "008077": "Brother", "3c2af4": "Brother",
        "0000aa": "Xerox", "9c934e": "Xerox", "00000f": "NeXT/HP",
        "3464a9": "HP", "6cc217": "HP", "94577d": "HP", "b05cda": "HP", "d48564": "HP",
        "ecb1d7": "HP", "70106f": "HP", "308d99": "HP",
        "0021b7": "Lexmark", "00040b": "Canon", "88519d": "Canon", "2c9ef6": "Canon",
        "001ba9": "Ricoh", "00265c": "Epson", "38f32e": "Epson",
        "a4ee57": "Epson", "e0bb9e": "Epson",

        // Media / TV / audio
        "000e58": "Sonos", "347e5c": "Sonos", "5caafd": "Sonos",
        "78288b": "Sonos", "949f3e": "Sonos", "b8e937": "Sonos",
        "001dba": "Sony", "3417eb": "Sony", "544249": "Sony", "78843c": "Sony",
        "ac9b0a": "Sony", "fc0fe6": "Sony",
        "0009b0": "Onkyo", "001eb2": "LG Electronics",
        "2c598a": "LG Electronics", "5c497d": "LG Electronics", "a816b2": "LG Electronics",
        "cc2d8c": "LG Electronics", "e85b5b": "LG Electronics",
        "0024e4": "Withings", "b0a737": "Roku", "d83134": "Roku", "dc3a5e": "Roku",
        "cc6da0": "Roku", "8c49b1": "Roku",
        "d052a8": "Philips Hue", "001788": "Philips Hue", "ecb5fa": "Philips Hue",
        "000b78": "TiVo", "0022f7": "Conceptronic", "b4750e": "Belkin/Wemo",
        "94103e": "Belkin/Wemo", "086698": "Belkin/Wemo",

        // Consoles
        "0009bf": "Nintendo", "0017ab": "Nintendo", 
        "00191d": "Nintendo", "5c521e": "Nintendo", "98b6e9": "Nintendo", "e84ece": "Nintendo",
        "001315": "Sony (PlayStation)", "0015c1": "Sony (PlayStation)",
        "0d2544": "Sony (PlayStation)", 
        "709e29": "Sony (PlayStation)", "bc60a7": "Sony (PlayStation)",
        "002248": "Microsoft (Xbox)", 

        // Cameras / IoT
        "001a1e": "Aruba Networks", "00408c": "Axis Communications", "accc8e": "Axis Communications",
        "b8272f": "Hikvision", "4cbd8f": "Hikvision",
        "c0561d": "Hikvision", "586848": "Dahua", "3cef8c": "Dahua",
        "240ac4": "Espressif (ESP32)", "2462ab": "Espressif (ESP32)",
        "30aea4": "Espressif (ESP32)", "3c6105": "Espressif (ESP32)", "5ccf7f": "Espressif (ESP8266)",
        "8caab5": "Espressif (ESP32)", "a4cf12": "Espressif (ESP32)", "b4e62d": "Espressif (ESP32)",
        "cc50e3": "Espressif (ESP32)", "d8a01d": "Espressif (ESP32)", "ecfabc": "Espressif (ESP32)",
        "84f3eb": "Espressif (ESP8266)", "68c63a": "Espressif (ESP32)",
        "000ee8": "Shenzhen Sonoff", "dc4f22": "Espressif (ESP32)",
        "18fe34": "Espressif (ESP8266)", "600194": "Espressif (ESP32)",
        "7c87ce": "Tuya Smart", "10d561": "Tuya Smart", "d4a651": "Tuya Smart",
        "500291": "Tuya Smart",

        // Misc computing
        "001ec9": "Dell", "14feb5": "Dell",
        "18a99b": "Dell", "246e96": "Dell", "b083fe": "Dell", "d067e5": "Dell",
        "f8bc12": "Dell", "0026b9": "Dell",
        "0016d3": "Wistron", "001a6b": "Lenovo", "3c970e": "Lenovo",
        "54ee75": "Lenovo", "6c0b84": "Lenovo", "8cec4b": "Lenovo",
        "000f1f": "Dell",
        "001966": "Acer", "003067": "Acer", "b8ac6f": "Dell",
        "3ca82a": "Hewlett Packard Enterprise", "0018fe": "HP",
        "00e018": "ASUSTek", "0c9d92": "ASUSTek",
        "525400": "QEMU/KVM"
    ]
}
