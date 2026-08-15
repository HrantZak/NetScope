# NetScope — LAN Network Analyzer for iPhone

A native iOS app that discovers and analyses every device on the Wi-Fi network
you are connected to. Built with **SwiftUI + Swift 6** (strict concurrency),
MVVM, and zero paid services — no accounts, no servers, no third-party SDKs.
Everything runs on device.

---

## Opening the project

1. Open `NetScope.xcodeproj` in **Xcode 16 or newer**.
2. Select the `NetScope` scheme and a **physical iPhone** (see below).
3. Set your own team under *Signing & Capabilities* — the bundle identifier is
   `com.netscope.NetScope`, change it if it is taken.
4. Build and run.

> **Run on a real device.** The iOS Simulator shares the Mac's network stack: it
> does not enforce Local Network permission, cannot open ICMP sockets the way a
> device does, and its ARP view is the Mac's. Discovery results there are not
> representative.

Requirements: iOS 17.0+, Xcode 16+, Swift 6 language mode.

The target uses an Xcode 16 *synchronised folder group*, so new files added
under `NetScope/` are picked up automatically — no `project.pbxproj` edits.

---

## Architecture

Three layers, one direction of dependency: **UI → Data → Network**.

```
NetScope/
├── App/                     Composition root and scan orchestration
│   ├── NetScopeApp.swift        @main, scene phase wiring
│   ├── AppEnvironment.swift     Owns stores, coordinator, path observer
│   ├── ScanCoordinator.swift    Engine events → UI state (coalesced)
│   └── RootView.swift           Tab container + permission banner
│
├── Core/
│   ├── Models/              Sendable value types (Device, IPv4, ScanConfiguration…)
│   ├── Networking/          Everything that touches a socket
│   │   ├── ICMPSweeper          Batch ping: one socket, non-blocking, poll(2)
│   │   ├── TCPProbe             NWConnection connect-scan with RST detection
│   │   ├── PortScanner          Bounded-concurrency port sweep
│   │   ├── BonjourDiscovery     NWBrowser browse + UDP-based resolve
│   │   ├── RouteTable           Gateway + ARP cache via sysctl(3)
│   │   ├── InterfaceProvider    Local interfaces via getifaddrs(3)
│   │   ├── DNSResolver          Reverse DNS + configured resolvers
│   │   ├── VendorDatabase       Offline OUI → vendor table
│   │   ├── DeviceClassifier     Device-type heuristics
│   │   └── ScanEngine           Actor orchestrating the whole pipeline
│   ├── Services/            Persistence, settings, export, notifications
│   └── Utilities/           Concurrency helpers, formatters, haptics
│
├── DesignSystem/            Tokens, surfaces, reusable components, radar
└── Features/                One folder per screen, each with its view model
```

**Concurrency model**

| Type | Isolation | Why |
|---|---|---|
| `ScanEngine` | `actor` | Owns scan state; makes double-taps a no-op |
| `FileStore`, `NotificationService` | `actor` | Serialised IO off the main thread |
| Repositories, view models, `AppEnvironment` | `@MainActor @Observable` | Read directly by SwiftUI |
| `Device`, `IPv4`, `ScanConfiguration`, … | `Sendable` structs | Cross actor boundaries freely |

---

## How the scan works

```
Bonjour browse  ──────────────────────────────────┐  (parallel, whole scan)
ICMP sweep ──► ARP harvest ──► TCP fallback*      │
                                    └─► reverse DNS ──► port probes
```

1. **ICMP sweep** — a single `SOCK_DGRAM`/`IPPROTO_ICMP` socket sends echo
   requests to every host in the subnet with light pacing, then drains replies
   with `poll(2)` on one thread. A /24 completes in well under a second.
2. **ARP harvest** — probing populates the kernel neighbour table, so hosts that
   silently drop ICMP still show up, along with their MAC addresses.
3. **TCP fallback** — only when ICMP returned almost nothing (filtered network).
   Connecting to every silent address is an order of magnitude slower, so it is
   deliberately conditional.
4. **Bonjour** — runs concurrently for the whole scan; contributes friendly
   names, service types, TXT metadata, and occasionally hosts nothing else found.
5. **Reverse DNS** and **port probes** run with bounded concurrency pools.

Hosts are emitted as soon as they answer, so the list fills in live.

**Why it stays smooth with hundreds of devices**

- Engine events reach the UI through one `AsyncStream` consumed on the main
  actor — not one task hop per event.
- Device updates are **coalesced** and flushed at ~8 fps, so the list re-sorts a
  handful of times per scan instead of once per host.
- Filtering/sorting/grouping happens once per input change in
  `DeviceListViewModel`, never inside `body`.
- List rows use solid surfaces; blur is reserved for the few floating elements
  that are always on screen.
- The radar's `TimelineView` only exists while a scan is running.

---

## Features

- Device discovery with live results and manual or automatic scanning
- IP, hostname, Bonjour name, MAC, vendor, device-type guess, open services
- Four list layouts: cards, compact, grid, table
- Search across every field including port numbers; filters, sorting, grouping
- Per-device detail page: live ping chart (min/avg/max/jitter/loss), on-demand
  port scan, reachability check, HTTP fingerprint, notes, rename, history
- Favourites and a full cross-network device history
- Current connection details: interface, local IP, subnet, gateway, DNS,
  broadcast, SSID (when entitled)
- Statistics with Swift Charts: type composition, latency distribution, scan
  trend over time, most common services
- Local notifications when devices join or leave
- CSV / JSON export via the share sheet
- Scan tuning: profile, concurrency, timeouts, retries, host cap, retention
- Light/dark/system appearance, Dynamic Type, reduced-motion support

---

## Permissions and platform limits

**Local Network** (`NSLocalNetworkUsageDescription`) is required. iOS provides no
API to query its status, so the app advertises a private Bonjour service and
browses for it — seeing its own advertisement proves access was granted. If the
permission is refused, a banner explains how to re-enable it in Settings.

The app is honest about what iOS does not allow, and shows only what is
available rather than inventing data:

| Limitation | Behaviour |
|---|---|
| MAC addresses are only visible when the OS has an ARP entry | Field shows "Unavailable" with an explanation |
| Private (randomised) Wi-Fi addresses hide the real vendor | Detected and explained on the detail page |
| Exact hardware models are not exposed | Device type is presented as a heuristic guess |
| SSID needs the *Access Wi-Fi Information* capability | Falls back to identifying the network by subnet |
| No background network scanning | Automatic scans run only while the app is open |

No private APIs are used. Every system call — `getifaddrs`, `sysctl(CTL_NET,
PF_ROUTE)`, `socket`/`poll`/`recvfrom`, `getnameinfo`, `res_ninit` — is public
BSD or Foundation API available to sandboxed apps.

### Optional capability

To show the Wi-Fi network name, add **Access Wi-Fi Information** in
*Signing & Capabilities*. Without it `NEHotspotNetwork.fetchCurrent` returns
`nil`, which the app handles gracefully — scanning is unaffected.

`libresolv` is linked (`OTHER_LDFLAGS = -lresolv`) to read the configured DNS
servers. If you prefer to drop that dependency, remove the flag and
`DNSResolver.systemResolvers()`; the UI already falls back to showing the
gateway.

---

## Privacy

NetScope scans only the network the device is currently joined to. Results are
stored in the app container (`Application Support/NetScopeData`) as JSON and are
never uploaded. There is no analytics, no account, and no network traffic beyond
the LAN probes themselves and the optional HTTP fingerprint of a host you open.
