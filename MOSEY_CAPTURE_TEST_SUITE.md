# Mosey ↔ AirDrop Wire-Protocol Capture — Test Suite

**Goal**: Capture every layer Mosey uses during a real Quick Share ↔ AirDrop transfer
with an Apple device. We then diff against our Pixel 8 / 8a / 8 Pro emulation attempts to
identify the exact protocol gaps.

The **single highest-value artifact** is the `nlmon0` netlink pcap during Scenario A
— it tells us whether Mosey uses Wi-Fi Aware / NAN, vendor commands, P2P, or raw
action-frame injection. Everything else is supporting evidence.

---

## 0. What we are trying to learn

| Question | Where the answer lives |
|---|---|
| Does Mosey use Wi-Fi Aware / NAN? | `nlmon0` pcap: `NL80211_CMD_*_NAN_FUNCTION` messages |
| Does Mosey send raw 802.11 action frames? | `nlmon0` pcap: `NL80211_CMD_FRAME` |
| What frame format on the air? (Apple OUI? Vendor OUI? AWDL TLVs?) | Channel-6 monitor pcap (radiotap) |
| What BLE advert payload? `adVr` byte value? | `btsnoop_hci.log` |
| What `_airdrop._tcp` TXT record content? | mDNS pcap + Mac `dns-sd` |
| What HTTPS endpoints? Cert chain? | IP-side pcap on `wlan0`/`wlan1`/`p2p*` |
| Does Mac see the Pixel via AWDL or BLE first? | Mac unified-log timing |
| Does Mac respond with action frames? Which ones? | Mac unified-log + monitor pcap |

If we get just one good capture of **Scenario A** (Pixel sends to Mac), 80 % of these
questions get answered.

---

## 0a. Priority matrix — pick what fits your time budget

Captures and scenarios are not equal. The table below is sorted by **value-per-minute**.
A tester who can only spare 15 minutes should do rows 1–3 of Scenario A and stop.
A tester with half a day can do everything.

### Per-capture priority (apply to whichever scenarios you run)

| Tier | Capture | Setup | Per-run effort | Why it's worth it |
|---|---|---|---|---|
| **S1** | **Pixel `nlmon0` netlink pcap** | 30 s (one `ip link add`) | 1 command, then pull file | **THE** capture. Single pcap reveals whether Mosey uses NAN, vendor cmds, action frames, or none. If you do nothing else, do this. |
| **S2** | **Pixel BT HCI snoop log** | 30 s (Dev Options toggle) | 0 during run; `adb pull` after | Reveals exact BLE advert bytes incl. the `adVr` version byte. Nearly free. |
| **S3** | **Pixel `logcat -b all`** | 0 | 1 command | Mosey/NearbySharing/WifiAware tags in plain text. Free. |
| **S4** | **Mac `/usr/bin/log stream`** | 5 min (install Apple debug profiles) | 1 command | Tells us where in Apple's stack the Pixel was accepted/rejected. Free per run. |
| **A1** | **Pixel `dumpsys` before/after** (NearbySharing, wifiaware, bluetooth_manager) | 0 | 2 quick snapshots | Reveals active NAN sessions, BLE advertising sets, peer device IDs. |
| **A2** | **Frida hook on `mosey_server`** (native syscalls) | 10 min (push frida-server, attach) | reusable across all scenarios | Raw netlink wire bytes per FD + syscall context. Partially overlaps with nlmon0 but adds the process-side view. May need `setenforce 0`. |
| **A3** | **Frida hook on `com.google.android.gms.persistent`** (Java) | same as A2 | reusable | `WifiAwareManager.publish/subscribe`, `BluetoothLeAdvertiser.startAdvertising`, `NsdManager.registerService` — exact Java API arguments. |
| **A4** | **Mac `dns-sd -B _airdrop._tcp / _companion-link._tcp / _rapport._tcp`** | 0 | 1 command | Confirms which mDNS services Pixel publishes and which iface (AWDL vs en0) Mac sees them on. |
| **B1** | **Pixel `dmesg -wT`** | 0 | 1 command | bcmdhd firmware events. Useful but largely redundant with logcat's `bcmdhd` tag. |
| **B2** | **Pixel `tcpdump -i any`** (IP pcap) | 0 | 1 command | TLS handshake + HTTPS payload after discovery. Matters for transfer phase, less for discovery. |
| **B3** | **Mac `tcpdump -i any`** | 0 | 1 command (sudo) | Mac's side of the IP traffic. Largely mirrors B2 if both endpoints traceable. |
| **B4** | **PacketLogger on Mac** | 20 min (download Apple Additional Tools for Xcode) | start/stop GUI | Mac-side BLE view. Mostly redundant with Pixel's HCI snoop (S2). Useful only if S2 is unavailable. |
| **C1** | **Mac Wireless Diagnostics Sniffer (ch6)** | 1 min | start/stop GUI | Often 0-byte pcap on Apple Silicon. Best-effort fallback only. |
| **C2** | **iPad sysdiagnose** | 0 | hold buttons + wait 10 min + sync | Slow and we already have multiple iPad sysdiagnoses. Skip unless iPad behaves unusually. |

### Per-scenario priority

| Tier | Scenario | Why |
|---|---|---|
| **MUST** | **A — Pixel → Mac, AirDrop = Everyone** | Full Mosey-as-sender path. Single most informative scenario by a wide margin. |
| **HIGH** | **E — Idle, Quick Share = Everyone-10min, no peer** | Cleanest data (no IP-layer transfer noise). Catches the steady-state advertise/scan pattern. ~3 min of run time. |
| **HIGH** | **D — Pixel → Pixel control** | Lets us diff out the Apple-specific layers from A. If A shows "X happens", D answers "does X also happen in pure-Android flow?". |
| **MED** | **B — Mac → Pixel** | Useful for the receive-side handshake, but Mosey RX is less novel than TX. |
| **LOW** | **C — iPad → Pixel** | Largely redundant with B unless iPad-side details differ. Skip if time is tight. |

### Suggested budgets

| Budget | Do this |
|---|---|
| **15 min** | One-time setup (S1, S2, S3 enablement) + Scenario A run-1 with captures S1, S2, S3 only |
| **30 min** | Above + Scenario A captures S4 + A1 |
| **1 hour** | All of above + Frida (A2, A3) on Scenario A. 3 repeats of A. |
| **3 hours** | Above + Scenarios E and D, each ×3 repeats, full S+A tier captures |
| **Half day** | Everything, all 5 scenarios × 3 repeats, all tiers |

### If you have to pick ONE bundle to send

**Scenario A run 1 with the four S-tier captures (nlmon0 pcap, btsnoop, logcat, Mac unified-log) and the A1 dumpsys snapshots.** That's roughly 20 minutes of attended work, ~30 MB of artifacts, and answers the question "what wire protocol does Mosey actually use?".

---

## 1. Required tools

### On the Pixel (Android side)

| Tool | Source | Notes |
|---|---|---|
| `frida-server` arm64 | https://github.com/frida/frida/releases  or https://github.com/thelok1s/florida-zygisk | Pick the version matching the `frida-tools` you install on host, instal zygisk version for convinience |
| `tcpdump` | Already in many root distros; otherwise static aarch64 build at https://github.com/the-tcpdump-group/tcpdump | We use it on `nlmon0`, `any`, etc. |
| `iw` | Optional, only if you want `iw event`. Bundled in Termux: `pkg install iw` | |
| `nlmon` netdev | Built into the Linux kernel — `ip link add nlmon0 type nlmon` | This is the magic primitive that mirrors **all** netlink traffic |
| HCI snoop | Android Developer Options → "Enable Bluetooth HCI snoop log" | Sticky setting, only enable once |

### On the Mac (Apple peer side)

| Tool | Source | Notes |
|---|---|---|
| Unified log (`/usr/bin/log`) | Built in | Subsystem-level filtering, see commands below |
| **PacketLogger.app** | Part of "Additional Tools for Xcode" — https://developer.apple.com/download/all/  | System-wide BT/BLE HCI capture, exports `.pklg`. PacketLogger requires installed Bluetooth profile on your specific device (mac/ipad/etc) to actually log anything. Get one here: https://developer.apple.com/feedback-assistant/profiles-and-logs/ |
| Wireless Diagnostics → Sniffer | Built in (hold Option, click Wi-Fi → Open Wireless Diagnostics), then open tools from statusbar | Best-effort monitor mode; may produce empty pcaps on Apple Silicon. Capture anyway as fallback. |
| `dns-sd` | Built in | mDNS browser |
| `tcpdump` | Built in | For `awdl0` & `en0` IP pcap |
| Wireshark | https://www.wireshark.org | For all post-test analysis and capture. Can steam logcat from android device via ADB |
| BT/Sharing/Wi-Fi debug profiles | https://developer.apple.com/bug-reporting/profiles-and-logs/ → grab "Bluetooth", "Sharing", "Wi-Fi Performance", "mDNSResponder" | Tells the unified log to emit debug-level messages |

### On the iPad (if used as peer)

| Tool | Source |
|---|---|
| Same BT/Sharing debug profiles | Same Apple URL |
| `sysdiagnose` trigger | Hold Vol-Up + Vol-Down + Side for ~1 s. Saved under Settings → Privacy → Analytics → Analytics Data → `sysdiagnose_*.tar.gz` |
| `idevicesyslog` | Brew: `brew install libimobiledevice` |

---

## 2. One-time setup (~30 min)

### Pixel

```bash
# 2.1  Enable BT HCI snoop log (sticky)
adb shell settings put secure bluetooth_hci_log 1
adb shell svc bluetooth disable && sleep 2 && adb shell svc bluetooth enable

# 2.2  Push frida-server (matched version)
HOST_FRIDA_VER=$(frida --version)   # on your host machine, install: pip install frida-tools
# Download server matching that version from frida github releases
adb push frida-server-${HOST_FRIDA_VER}-android-arm64 /data/local/tmp/frida-server
adb shell su -c 'chmod 755 /data/local/tmp/frida-server'
Or using magisk/KSU:  https://github.com/thelok1s/florida-zygisk or https://github.com/ViRb3/magisk-frida

# 2.3  Add a permanent nlmon interface in init script (or run before each test)
#      nlmon mirrors every netlink message between kernel and userspace.
adb shell su -c 'ip link add nlmon0 type nlmon 2>/dev/null; ip link set nlmon0 up'
adb shell ip link show nlmon0     # expect: state UNKNOWN, type nlmon

# 2.4  Crank up logcat buffer and verbose tags
adb shell logcat -G 16M
for t in Mosey NearbySharing NearbyConnections WifiAware WifiP2P bcmdhd cfg80211 nl80211; do
  adb shell setprop log.tag.$t VERBOSE
done
```

### Mac

```bash
# 2.5  Install Apple debug profiles by clicking the .mobileconfig files Apple ships at
#      https://developer.apple.com/bug-reporting/profiles-and-logs/
#      You need: Bluetooth, Sharing/AirDrop, Wi-Fi Performance, mDNSResponder
#      System Settings → General → VPN & Device Management to verify installation.

# 2.6  Open PacketLogger.app and Wireless Diagnostics (hold Option + click Wi-Fi icon)
#      Both will be controlled per-scenario.
```

---

## 3. Per-scenario procedure

Each scenario runs ~30 s end-to-end. Capture for ~60 s (15 s pre, 30 s during, 15 s post).
Run each scenario **3 times** to confirm reproducibility.

### Scenarios

| ID | Direction | What it isolates |
|---|---|---|
| **A** | Pixel → Mac, Mac AirDrop = Everyone, 10 KB image | **Highest value**: full Mosey-as-sender path |
| **B** | Mac → Pixel, Pixel Quick Share = Everyone-10min, 10 KB image | Receive-side path; how Mosey reacts to Apple beacon |
| **C** | iPad → Pixel | iOS variant of B |
| **D** | Pixel → Pixel (or any Android) | **Control**: what Mosey does without Apple involvement. Diff vs. A. |
| **E** | Pixel: Quick Share = Everyone-10min, NO peer in range, hold for 60 s | Idle advertise/scan pattern, cleanest data |

### Capture orchestration

You'll need 5 Pixel terminals and 3 Mac terminals. Suggest tmux/iTerm split panes.

Replace `SCEN` below with `A`, `B`, etc. Use a fresh output dir per scenario:

```bash
mkdir -p captures/SCEN_run1/pixel captures/SCEN_run1/mac
cd captures/SCEN_run1
```

#### Pixel terminal 1 — full logcat
```bash
adb shell logcat -b all -v threadtime > pixel/logcat.txt
```

#### Pixel terminal 2 — netlink pcap (KEY ARTIFACT)
```bash
adb shell su -c 'tcpdump -i nlmon0 -nn -s 0 -w /sdcard/netlink.pcap'
# Stop with Ctrl-C after the scenario. Then:
adb pull /sdcard/netlink.pcap pixel/netlink.pcap
```

#### Pixel terminal 3 — IP-side pcap on all interfaces
```bash
adb shell su -c 'tcpdump -i any -nn -s 0 -w /sdcard/ip.pcap'
# Stop & pull
adb pull /sdcard/ip.pcap pixel/ip.pcap
```

#### Pixel terminal 4 — kernel dmesg follow
```bash
adb shell su -c 'dmesg -wT' > pixel/dmesg.txt
```

#### Pixel terminal 5 — Frida hooks on Mosey processes

Save the script below as `mosey_observe.js` on the host:

```javascript
// mosey_observe.js — syscall + Java instrumentation of Mosey ecosystem
'use strict';

const wantSyscalls = ['sendto','recvfrom','sendmsg','recvmsg','ioctl','socket','connect','bind'];
const libc = Process.getModuleByName('libc.so');

wantSyscalls.forEach(name => {
    const addr = libc.findExportByName(name);
    if (!addr) return;
    Interceptor.attach(addr, {
        onEnter(args) {
            this.name = name;
            this.fd   = args[0].toInt32();
            if (name === 'sendto' || name === 'sendmsg' || name === 'recvfrom' || name === 'recvmsg') {
                this.buf = args[1];
                this.len = args[2].toInt32();
            }
            if (name === 'socket') {
                this.fam = args[0].toInt32();
                this.typ = args[1].toInt32();
                this.pro = args[2].toInt32();
            }
        },
        onLeave(rv) {
            const ts = Date.now();
            if (this.name === 'socket' && rv.toInt32() >= 0) {
                console.log(`${ts} socket family=${this.fam} type=${this.typ} proto=${this.pro} -> fd=${rv}`);
            }
            if ((this.name === 'sendto' || this.name === 'sendmsg') && this.len > 0 && this.len < 4096) {
                console.log(`${ts} ${this.name} fd=${this.fd} len=${this.len}`);
                console.log(hexdump(this.buf.readByteArray(this.len), {ansi:false}));
            }
            if ((this.name === 'recvfrom' || this.name === 'recvmsg') && rv.toInt32() > 0) {
                const n = Math.min(rv.toInt32(), 4096);
                console.log(`${ts} ${this.name} fd=${this.fd} len=${n}`);
                console.log(hexdump(this.buf.readByteArray(n), {ansi:false}));
            }
        }
    });
});

// Java-side hooks (only attach in app processes — gms.persistent, mosey app)
try {
    Java.perform(() => {
        const classes = [
            'android.net.wifi.aware.WifiAwareManager',
            'android.net.wifi.aware.PublishConfig$Builder',
            'android.net.wifi.aware.SubscribeConfig$Builder',
            'android.net.wifi.aware.DiscoverySession',
            'android.net.nsd.NsdManager',
            'android.bluetooth.le.BluetoothLeAdvertiser',
            'android.bluetooth.le.BluetoothLeScanner',
            'android.bluetooth.le.AdvertiseData$Builder',
            'android.bluetooth.le.ScanFilter$Builder'
        ];
        classes.forEach(cn => {
            try {
                const k = Java.use(cn);
                const proto = k.class.getDeclaredMethods();
                proto.forEach(m => {
                    const name = m.getName();
                    try {
                        const overloads = k[name].overloads;
                        overloads.forEach(ov => {
                            ov.implementation = function() {
                                const args = [].slice.call(arguments).map(a =>
                                    a == null ? 'null' : a.toString());
                                console.log(`JAVA ${cn}.${name}(${args.join(', ')})`);
                                return ov.apply(this, arguments);
                            };
                        });
                    } catch(e){}
                });
            } catch(e){ /* class not present */ }
        });
    });
} catch (e) { /* not a Java process */ }
```

Launch from host (one process per terminal sub-pane):

```bash
# Start frida-server on device
adb shell su -c '/data/local/tmp/frida-server -l 0.0.0.0:27042 &'
adb forward tcp:27042 tcp:27042
pip install frida-tools  # if not done

# Attach to mosey_server (native), GMS persistent (Java), Mosey app (Java)
frida -U -n mosey_server                       -l mosey_observe.js  -o pixel/mosey_server.log &
frida -U -n com.google.android.gms.persistent  -l mosey_observe.js  -o pixel/gms_persistent.log &
frida -U -n com.google.android.mosey           -l mosey_observe.js  -o pixel/mosey_app.log     &
# Optional: also hook the Nearby Connections persistent module
frida -U -n com.google.android.gms.ui          -l mosey_observe.js  -o pixel/gms_ui.log        &
```

#### Pixel pre/post snapshots

Before and after each scenario, run:

```bash
for phase in BEFORE AFTER; do
  adb shell dumpsys NearbySharing                                  > pixel/${phase}_nearby.txt
  adb shell dumpsys bluetooth_manager                              > pixel/${phase}_bt.txt
  adb shell dumpsys wifi                                           > pixel/${phase}_wifi.txt
  adb shell dumpsys wifiaware                                      > pixel/${phase}_wifiaware.txt
  adb shell ip link                                                > pixel/${phase}_iplink.txt
  adb shell ip addr                                                > pixel/${phase}_ipaddr.txt
  adb shell 'su -c "iw dev"'                                       > pixel/${phase}_iwdev.txt
  adb shell 'su -c "ls /sys/class/ieee80211/"'                     > pixel/${phase}_phys.txt
  adb shell 'su -c "ls /sys/class/net/"'                           > pixel/${phase}_netdevs.txt
  adb shell ps -A                                                  > pixel/${phase}_procs.txt
  # Read 2-3 seconds of dmesg tail (already captured by terminal 4, but this is a snapshot)
  adb shell 'su -c "dmesg | tail -200"'                            > pixel/${phase}_dmesg_tail.txt
  echo "Snapshot $phase complete; switch on/off the scenario now."
  read -p "Press ENTER when ready to take next snapshot..."
done
```

#### BT HCI snoop pull (after scenario)

```bash
adb shell su -c 'cp /data/misc/bluetooth/logs/btsnoop_hci.log /sdcard/btsnoop.log'
adb pull /sdcard/btsnoop.log pixel/btsnoop.log
# Wireshark opens this directly (filter: bthci_cmd or bthci_evt or btatt)
```

#### Mac terminal 1 — unified log
```bash
/usr/bin/log stream --info --debug \
  --predicate '(subsystem == "com.apple.sharing") OR (subsystem == "com.apple.airdrop") OR (subsystem == "com.apple.bluetooth") OR (subsystem == "com.apple.wireless.awdl") OR (process == "wifid") OR (process == "sharingd") OR (process == "rapportd") OR (process == "wifip2pd") OR (process == "mDNSResponder")' \
  > mac/unifiedlog.txt
```

#### Mac terminal 2 — mDNS browse
```bash
dns-sd -B _airdrop._tcp > mac/dnssd_airdrop.txt &
dns-sd -B _companion-link._tcp > mac/dnssd_companion.txt &
dns-sd -B _rapport._tcp > mac/dnssd_rapport.txt &
```

#### Mac terminal 3 — IP-side pcap
```bash
sudo tcpdump -i any -nn -s 0 -w mac/ip.pcap
# After scenario: Ctrl-C
```

#### Mac PacketLogger
- Open PacketLogger.app → Capture → Start before scenario, Stop after.
- File → Save → `mac/packetlogger.pklg`.

#### Mac Wireless Diagnostics Sniffer
- Hold Option, click Wi-Fi icon → "Open Wireless Diagnostics"
- Window → Sniffer → Channel **6**, Width **20 MHz** → Start
- Stop after scenario; pcap saved to `/var/tmp/wireless_capture_*.wcap`
- Copy: `cp /var/tmp/wireless_capture_*.wcap mac/wifi_ch6.wcap`
- **Note**: on Apple Silicon this often produces 0-byte pcaps due to a known
  monitor-mode limitation. Capture anyway — if it works, it's gold.

---

## 4. Sanity test (run ONCE before any scenarios)

Confirm every collector actually produces data:

```bash
# Pixel: nlmon0 sees activity within a second or two
adb shell su -c 'timeout 3 tcpdump -i nlmon0 -nn -c 5' 2>&1 | head -10
# Expect: at least a few packets dumped

# Pixel: frida sees the process
frida-ps -U | grep -E 'mosey|nearby|gms'
# Expect: mosey_server, com.google.android.mosey, com.google.android.gms.persistent

# Pixel: HCI snoop file growing
adb shell 'su -c "ls -l /data/misc/bluetooth/logs/btsnoop_hci.log"'
# Expect: nonzero size, recent mtime

# Mac: unified log streaming
/usr/bin/log stream --predicate 'process == "sharingd"' --debug --info | head -3
# Expect: at least the sharingd init lines

# Mac: PacketLogger is capturing
# (visually verify packet count incrementing)
```

If any of these is silent — fix it before running scenarios.

---

## 5. What we will look for (so the tester knows what they captured)

These are the indicators that the capture is useful. The tester does **not** need to
verify these themselves — just include the raw artifacts in the bundle.

### In `pixel/netlink.pcap` (open in Wireshark, filter `nl80211`)
- `NL80211_CMD_VENDOR` with vendor OUI `00:1a:11` (Google) → wondertap path is alive
- `NL80211_CMD_PUBLISH_NAN_FUNCTION` / `_SUBSCRIBE_NAN_FUNCTION` → Mosey uses Wi-Fi Aware
- `NL80211_CMD_FRAME` with frame type `0x00D0` (mgmt action) → action-frame injection
- `NL80211_CMD_REGISTER_FRAME` match prefix bytes → which RX frame patterns Mosey arms

### In `pixel/btsnoop.log` (open in Wireshark)
- `HCI_LE_Set_Extended_Advertising_Data` with `Manufacturer Data` company `0x004C` →
  the Apple AirDrop BLE beacon. Critical bytes:
  - Offset 0: `0x05` (AirDrop type)
  - Offset 1: `0x12` (length)
  - **Offset 12: `adVr`** — `0x03` is modern AirDrop, `0x01` is legacy (and rejected by Apple).
- `HCI_LE_Set_Extended_Scan_Parameters` + filters → what Mosey RX-listens for

### In `pixel/mosey_server.log` (Frida)
- Lines beginning `socket family=16` → every netlink socket Mosey opens
- Hex dumps of `sendto` / `sendmsg` on those FDs → raw nl80211 attribute bytes
- Pattern: a flurry of activity right when Quick Share is opened

### In `mac/unifiedlog.txt`
- `IO80211AWDLPeerManager: actionFrameReport SUI from <Pixel MAC>` → Mac kernel received
  our action frame
- `RPNearbyActionV2Discovery adVr=3` lines from `rapportd` → confirms the BLE beacon was
  validated end-to-end
- `wifip2pd: AWDLBrowse _airdrop._tcp.local was started` → confirms Mac is browsing
  AirDrop services via AWDL
- `sharingd: Sender ... <Pixel ID>` → final discovery success

### In `mac/wifi_ch6.wcap` (if not 0-byte)
- 802.11 mgmt action frames sourced from Pixel MAC → ground truth of frame format
- Decoded vendor IE OUIs

---

## 6. Deliverable packaging

Per scenario, zip the directory:

```bash
zip -r captures_SCEN_run1.zip captures/SCEN_run1/
```

Send all zips. Approximate total ≈ 300–800 MB across 5 scenarios × 3 repeats.
If size is a problem, **prioritize Scenario A run 1** — that's the single most
informative bundle.

---

## 7. Quick reference — what each artifact answers

| File | Answers |
|---|---|
| `netlink.pcap` | Which `nl80211` / Wi-Fi-Aware / vendor commands Mosey uses |
| `btsnoop.log` | Exact BLE advert + scan-filter bytes, `adVr` version |
| `mosey_server.log` (Frida) | Raw netlink wire bytes per socket, syscall pattern |
| `gms_persistent.log` (Frida) | Java-side `WifiAwareManager` / `Nsd` / `BLE` API calls |
| `logcat.txt` | Mosey / NearbySharing trace messages, errors |
| `dmesg.txt` | bcmdhd firmware events (action-frame TX completion, NAN events) |
| `ip.pcap` (Pixel) | HTTPS to Apple peer, TLS handshake, mDNS over Wi-Fi |
| `unifiedlog.txt` (Mac) | Where in Apple's stack the Pixel was seen / accepted / rejected |
| `packetlogger.pklg` (Mac) | Mac-side BLE view of the Pixel's beacon |
| `wifi_ch6.wcap` (Mac) | Over-the-air 802.11 (may be empty on Apple Silicon) |
| `dnssd_*.txt` (Mac) | Whether the Pixel's `_airdrop._tcp` was published and via which iface |
| `BEFORE_*.txt` / `AFTER_*.txt` | Delta in WifiAware sessions, BT advertising IDs, etc. |

---

## 8. Estimated effort

| Step | Time |
|---|---|
| One-time setup (profiles, frida-server, nlmon, HCI snoop) | 30–45 min |
| Sanity test | 5 min |
| Each scenario incl. 3 repeats | ~30 min |
| All 5 scenarios | ~2.5 h |
| Zip + upload | 30 min |

**Total**: half a day of attended testing.

---

## 9. If anything fails

- `nlmon0` returns `RTNETLINK answers: Operation not supported` →
  the kernel was built without `CONFIG_NLMON`. Try `tcpdump -i any -nn 'proto 0x000c'`
  as a partial fallback, or use `strace` on `mosey_server` instead.
- Frida can't attach to `mosey_server` → SELinux blocks; try
  `setenforce 0` first (be aware it lowers system security temporarily).
- HCI snoop log empty → BT was toggled before the setting took effect. Toggle BT
  off/on once more, wait 10 s, retry.
- PacketLogger missing → install "Additional Tools for Xcode" from Apple Dev portal
  (the Xcode app alone doesn't include it).
- Wireless Diagnostics produces 0-byte pcap → known Apple Silicon issue, ignore;
  the on-device netlink pcap is what we really need.
