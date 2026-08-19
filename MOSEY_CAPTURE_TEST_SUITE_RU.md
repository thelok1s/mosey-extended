# Mosey ↔ AirDrop Захват проводного протокола — набор тестов

**Цель**: Захватить каждый слой, который Mosey использует при реальной передаче Quick Share ↔ AirDrop
с устройством Apple. Затем мы сравниваем с нашими попытками эмуляции Pixel 8 / 8a / 8 Pro, чтобы
выявить точные пробелы протокола.

**Единственный артефакт с наибольшей ценностью** — это `nlmon0` netlink pcap во время Сценария A
— он показывает нам, использует ли Mosey Wi-Fi Aware / NAN, команды поставщика, P2P или сырой
injection действие-кадра. Все остальное — вспомогательное доказательство.

---

## 0. Что мы пытаемся узнать

| Вопрос | Где находится ответ |
|---|---|
| Использует ли Mosey Wi-Fi Aware / NAN? | `nlmon0` pcap: `NL80211_CMD_*_NAN_FUNCTION` сообщения |
| Отправляет ли Mosey сырые 802.11 action-кадры? | `nlmon0` pcap: `NL80211_CMD_FRAME` |
| Какой формат кадра в эфире? (Apple OUI? Vendor OUI? AWDL TLVs?) | Channel-6 monitor pcap (radiotap) |
| Какая нагрузка BLE-объявления? Значение байта `adVr`? | `btsnoop_hci.log` |
| Какое содержимое TXT-записи `_airdrop._tcp`? | mDNS pcap + Mac `dns-sd` |
| Какие конечные точки HTTPS? Цепь сертификатов? | IP-side pcap на `wlan0`/`wlan1`/`p2p*` |
| Сначала ли Mac видит Pixel через AWDL или BLE? | Timing унифицированного журнала Mac |
| Отвечает ли Mac action-кадрами? Какими именно? | Mac унифицированный журнал + monitor pcap |

Если мы получим всего один хороший захват **Сценария A** (Pixel отправляет на Mac), то получим ответы на 80% этих
вопросов.

---

## 0a. Матрица приоритетов — выбирите что соответствует вашему временному бюджету

Не все захваты и сценарии одинаково ценны. Таблица ниже отсортирована по **стоимости на минуту**.
Тестер, который может выделить всего 15 минут, должен выполнить строки 1–3 Сценария A и остановиться.
Тестер с половиной дня может сделать всё.

### Приоритет для каждого захвата (применяется к любым выполняемым сценариям)

| Уровень | Захват | Настройка | Усилия за запуск | Почему это стоит |
|---|---|---|---|---|
| **S1** | **Pixel `nlmon0` netlink pcap** | 30 сек (один `ip link add`) | 1 команда, затем pull файла | **ТОТ** захват. Один pcap раскрывает, использует ли Mosey NAN, команды поставщика, action-кадры или ничего |
| **S2** | **Pixel BT HCI snoop log** | 30 сек (переключатель Dev Options) | 0 во время запуска; `adb pull` после | Раскрывает точные байты BLE-объявления, включая байт версии `adVr`. Почти бесплатно. |
| **S3** | **Pixel `logcat -b all`** | 0 | 1 команда | Теги Mosey/NearbySharing/WifiAware в простом тексте. Бесплатно. |
| **S4** | **Mac `/usr/bin/log stream`** | 5 мин (установка профилей отладки Apple) | 1 команда | Показывает нам, где в стеке Apple был принят/отклонен Pixel. Бесплатно за запуск. |
| **A1** | **Pixel `dumpsys` до/после** (NearbySharing, wifiaware, bluetooth_manager) | 0 | 2 быстрых снимка | Раскрывает активные NAN-сессии, наборы BLE-объявлений, ID одноранговых устройств. |
| **A2** | **Frida hook на `mosey_server`** (нативные системные вызовы) | 10 мин (push frida-server, attach) | переиспользуется во всех сценариях | Сырые байты netlink за FD + контекст syscall. Частично перекрывается |
| **A3** | **Frida hook на `com.google.android.gms.persistent`** (Java) | то же, что A2 | переиспользуется | `WifiAwareManager.publish/subscribe`, `BluetoothLeAdvertiser.startAdvertising`, `NsdManager.registerService` |
| **A4** | **Mac `dns-sd -B _airdrop._tcp / _companion-link._tcp / _rapport._tcp`** | 0 | 1 команда | Подтверждает, какие mDNS-сервисы публикует Pixel и какой интерфейс (AWDL vs en0) видит Mac. |
| **B1** | **Pixel `dmesg -wT`** | 0 | 1 команда | События прошивки bcmdhd. Полезно, но во многом избыточно с меткой `bcmdhd` в logcat. |
| **B2** | **Pixel `tcpdump -i any`** (IP pcap) | 0 | 1 команда | Рукопожатие TLS + полезная нагрузка HTTPS после обнаружения. Важно для фазы передачи, меньше для обнаружения. |
| **B3** | **Mac `tcpdump -i any`** | 0 | 1 команда (sudo) | Сторона Mac трафика IP. Во многом отражает B2, если оба endpoint отслеживаемы. |
| **B4** | **PacketLogger на Mac** | 20 мин (загрузить Apple Additional Tools для Xcode) | start/stop GUI | Представление BLE со стороны Mac. В основном избыточно с Pixel HCI snoop (S2). Полезно только если S2 недоступен. |
| **C1** | **Mac Wireless Diagnostics Sniffer (ch6)** | 1 мин | start/stop GUI | Часто 0-байтовый pcap на Apple Silicon. Только в крайнем случае. |
| **C2** | **iPad sysdiagnose** | 0 | удерживать кнопки + подождать 10 мин + синк | Медленно и у нас уже есть несколько iPad sysdiagnose. Пропустить, если iPad ведет себя необычно. |

### Приоритет по сценариям

| Уровень | Сценарий | Почему |
|---|---|---|
| **ОБЯЗАТЕЛЬНО** | **A — Pixel → Mac, AirDrop = Everyone** | Полный путь Mosey-как-отправитель. Единственный наиболее информативный сценарий в целом. |
| **ВЫСОКИЙ** | **E — Простой, Quick Share = Everyone-10min, нет одноранговых** | Самые чистые данные (без IP-уровневого шума передачи). Захватывает стабильный паттерн объявление/сканирование. ~3 мин runtime. |
| **ВЫСОКИЙ** | **D — Pixel → Pixel контроль** | Позволяет вычеркнуть слои, специфичные для Apple, из A. Если A показывает "X происходит", D отвечает на "происходит ли X также в чистом потоке Android?". |
| **СРЕДНЕЕ** | **B — Mac → Pixel** | Полезно для рукопожатия на стороне приема, но RX в Mosey менее новаторский, чем TX. |
| **НИЗКИЙ** | **C — iPad → Pixel** | В основном избыточно с B, если только детали iPad-стороны не отличаются. Пропустить, если время ограничено. |

### Предложенные бюджеты времени

| Бюджет | Сделайте это |
|---|---|
| **15 мин** | Единовременная настройка (включение S1, S2, S3) + запуск Сценария A с захватами только S1, S2, S3 |
| **30 мин** | Выше + Сценарий A захватывает S4 + A1 |
| **1 час** | Всё вышеперечисленное + Frida (A2, A3) на Сценарии A. 3 повтора A. |
| **3 часа** | Выше + Сценарии E и D, каждый ×3 повтора, полные S+A захваты уровня |
| **Полдня** | Всё, все 5 сценариев × 3 повтора, все уровни |

### Если вы должны выбрать ОДИН набор для отправки

**Сценарий A запуск 1 с четырьмя S-уровневыми захватами (nlmon0 pcap, btsnoop, logcat, Mac унифицированный журнал) и A1 dumpsys снимки.** Это примерно 20 минут активной работы, ~30 МБ артефактов.

---

## 1. Требуемые инструменты

### На Pixel (Android сторона)

| Инструмент | Источник | Заметки |
|---|---|---|
| `frida-server` arm64 | https://github.com/frida/frida/releases или https://github.com/thelok1s/florida-zygisk | Выберите версию, соответствующую `frida-tools` на хосте, установите zygisk версию |
| `tcpdump` | Уже в многих root distros; иначе статическая сборка aarch64 на https://github.com/the-tcpdump-group/tcpdump | Используется на `nlmon0`, `any` и т.д. |
| `iw` | Опционально, только если вы хотите `iw event`. Bundled в Termux: `pkg install iw` | |
| `nlmon` netdev | Встроено в ядро Linux — `ip link add nlmon0 type nlmon` | Это волшебный примитив, который отражает **весь** netlink трафик |
| HCI snoop | Android Developer Options → "Enable Bluetooth HCI snoop log" | Постоянный параметр, включите один раз |

### На Mac (Apple одноранговый)

| Инструмент | Источник | Заметки |
|---|---|---|
| Unified log (`/usr/bin/log`) | Встроено | Фильтрация уровня подсистемы, см. команды ниже |
| **PacketLogger.app** | Часть "Additional Tools for Xcode" — https://developer.apple.com/download/all/ | Системный захват HCI BT/BLE, экспорт `.pklg`. PacketLogger требует установленные Bluetooth символы |
| Wireless Diagnostics → Sniffer | Встроено (удерживайте Option, нажмите Wi-Fi → Open Wireless Diagnostics), затем откройте инструменты из statusbar | Режим монитора best-effort; может выдавать пустые pcap на Apple Silicon |
| `dns-sd` | Встроено | Браузер mDNS |
| `tcpdump` | Встроено | Для `awdl0` & `en0` IP pcap |
| Wireshark | https://www.wireshark.org | Для всего анализа и захвата после теста. Может транслировать logcat с устройства Android через ADB |
| BT/Sharing/Wi-Fi профили отладки | https://developer.apple.com/bug-reporting/profiles-and-logs/ → возьмите "Bluetooth", "Sharing", "Wi-Fi Performance", "mDNSResponder" |告诉 unified log излучать отладочные сообщения |

### На iPad (если используется как одноранговый)

| Инструмент | Источник |
|---|---|
| Те же BT/Sharing профили отладки | Тот же URL Apple |
| `sysdiagnose` триггер | Удерживайте Vol-Up + Vol-Down + Side ~1 сек. Сохранено под Settings → Privacy → Analytics → Analytics Data → `sysdiagnose_*.tar.gz` |
| `idevicesyslog` | Brew: `brew install libimobiledevice` |

---

## 2. Единовременная настройка (~30 мин)

### Pixel

```bash
# 2.1  Включите BT HCI snoop log (постоянно)
adb shell settings put secure bluetooth_hci_log 1
adb shell svc bluetooth disable && sleep 2 && adb shell svc bluetooth enable

# 2.2  Push frida-server (подходящая версия)
HOST_FRIDA_VER=$(frida --version)   # на хосте, установите: pip install frida-tools
# Загрузите server подходящей версии с github releases frida
adb push frida-server-${HOST_FRIDA_VER}-android-arm64 /data/local/tmp/frida-server
adb shell su -c 'chmod 755 /data/local/tmp/frida-server'
Or using magisk/KSU:  https://github.com/thelok1s/florida-zygisk или https://github.com/ViRb3/magisk-frida

# 2.3  Добавьте постоянный nlmon интерфейс в init скрипт (или запустите перед каждым тестом)
#      nlmon отражает каждое netlink сообщение между ядром и userspace.
adb shell su -c 'ip link add nlmon0 type nlmon 2>/dev/null; ip link set nlmon0 up'
adb shell ip link show nlmon0     # ожидайте: state UNKNOWN, type nlmon

# 2.4  Увеличьте буфер logcat и verbose теги
adb shell logcat -G 16M
for t in Mosey NearbySharing NearbyConnections WifiAware WifiP2P bcmdhd cfg80211 nl80211; do
  adb shell setprop log.tag.$t VERBOSE
done
```

### Mac

```bash
# 2.5  Установите профили отладки Apple, кликнув на .mobileconfig файлы из
#      https://developer.apple.com/bug-reporting/profiles-and-logs/
#      Вам нужны: Bluetooth, Sharing/AirDrop, Wi-Fi Performance, mDNSResponder
#      System Settings → General → VPN & Device Management для проверки установки.

# 2.6  Откройте PacketLogger.app и Wireless Diagnostics (удерживайте Option + нажмите Wi-Fi icon)
#      Оба будут управляться для каждого сценария.
```

---

## 3. Процедура для каждого сценария

Каждый сценарий работает ~30 сек от начала до конца. Захватывайте ~60 сек (15 сек до, 30 сек во время, 15 сек после).
Запустите каждый сценарий **3 раза** для подтверждения воспроизводимости.

### Сценарии

| ID | Направление | Что это изолирует |
|---|---|---|
| **A** | Pixel → Mac, Mac AirDrop = Everyone, 10 KB image | **Наибольшая ценность**: полный путь Mosey-как-отправитель |
| **B** | Mac → Pixel, Pixel Quick Share = Everyone-10min, 10 KB image | Путь приема; как Mosey реагирует на beacon Apple |
| **C** | iPad → Pixel | iOS вариант B |
| **D** | Pixel → Pixel (или любой Android) | **Контроль**: что делает Mosey без участия Apple. Сравните vs. A. |
| **E** | Pixel: Quick Share = Everyone-10min, БЕЗ одноранговых в диапазоне, hold for 60 сек | Стабильный паттерн объявление/сканирование, чистые данные |

### Организация захватов

Вам потребуется 5 терминалов Pixel и 3 терминала Mac. Рекомендуется использовать split panes в tmux/iTerm.

Замените `SCEN` ниже на `A`, `B` и т.д. Используйте свежую директорию output для каждого сценария:

```bash
mkdir -p captures/SCEN_run1/pixel captures/SCEN_run1/mac
cd captures/SCEN_run1
```

#### Pixel терминал 1 — полный logcat
```bash
adb shell logcat -b all -v threadtime > pixel/logcat.txt
```

#### Pixel терминал 2 — netlink pcap (КЛЮЧЕВОЙ АРТЕФАКТ)
```bash
adb shell su -c 'tcpdump -i nlmon0 -nn -s 0 -w /sdcard/netlink.pcap'
# Остановите Ctrl-C после сценария. Затем:
adb pull /sdcard/netlink.pcap pixel/netlink.pcap
```

#### Pixel терминал 3 — IP-side pcap на всех интерфейсах
```bash
adb shell su -c 'tcpdump -i any -nn -s 0 -w /sdcard/ip.pcap'
# Остановите & pull
adb pull /sdcard/ip.pcap pixel/ip.pcap
```

#### Pixel терминал 4 — kernel dmesg follow
```bash
adb shell su -c 'dmesg -wT' > pixel/dmesg.txt
```

#### Pixel терминал 5 — Frida hooks на Mosey процессах

Сохраните скрипт ниже как `mosey_observe.js` на хосте:

```javascript
// mosey_observe.js — syscall + Java instrumentation Mosey экосистемы
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

// Java-side hooks (только attach в app процессах — gms.persistent, mosey app)
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
            } catch(e){ /* класс не присутствует */ }
        });
    });
} catch (e) { /* не Java процесс */ }
```

Запустите с хоста (один процесс на sub-pane терминала):

```bash
# Запустите frida-server на устройстве
adb shell su -c '/data/local/tmp/frida-server -l 0.0.0.0:27042 &'
adb forward tcp:27042 tcp:27042
pip install frida-tools  # если еще не сделано

# Attach к mosey_server (native), GMS persistent (Java), Mosey app (Java)
frida -U -n mosey_server                       -l mosey_observe.js  -o pixel/mosey_server.log &
frida -U -n com.google.android.gms.persistent  -l mosey_observe.js  -o pixel/gms_persistent.log &
frida -U -n com.google.android.mosey           -l mosey_observe.js  -o pixel/mosey_app.log     &
# Опционально: также hook модуль Nearby Connections persistent
frida -U -n com.google.android.gms.ui          -l mosey_observe.js  -o pixel/gms_ui.log        &
```

#### Pixel снимки до/после

До и после каждого сценария запустите:

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
  # Прочитайте 2-3 секунды dmesg tail (уже захвачено терминалом 4, но это снимок)
  adb shell 'su -c "dmesg | tail -200"'                            > pixel/${phase}_dmesg_tail.txt
  echo "Снимок $phase завершен; включите/выключите сценарий сейчас."
  read -p "Нажмите ENTER когда готовы взять следующий снимок..."
done
```

#### BT HCI snoop pull (после сценария)

```bash
adb shell su -c 'cp /data/misc/bluetooth/logs/btsnoop_hci.log /sdcard/btsnoop.log'
adb pull /sdcard/btsnoop.log pixel/btsnoop.log
# Wireshark открывает это прямо (фильтр: bthci_cmd или bthci_evt или btatt)
```

#### Mac терминал 1 — unified log
```bash
/usr/bin/log stream --info --debug \
  --predicate '(subsystem == "com.apple.sharing") OR (subsystem == "com.apple.airdrop") OR (subsystem == "com.apple.bluetooth") OR (subsystem == "com.apple.wireless.awdl") OR (process == "wifid")[...]
  > mac/unifiedlog.txt
```

#### Mac терминал 2 — mDNS browse
```bash
dns-sd -B _airdrop._tcp > mac/dnssd_airdrop.txt &
dns-sd -B _companion-link._tcp > mac/dnssd_companion.txt &
dns-sd -B _rapport._tcp > mac/dnssd_rapport.txt &
```

#### Mac терминал 3 — IP-side pcap
```bash
sudo tcpdump -i any -nn -s 0 -w mac/ip.pcap
# После сценария: Ctrl-C
```

#### Mac PacketLogger
- Откройте PacketLogger.app → Capture → Start перед сценарием, Stop после.
- File → Save → `mac/packetlogger.pklg`.

#### Mac Wireless Diagnostics Sniffer
- Удерживайте Option, нажмите Wi-Fi icon → "Open Wireless Diagnostics"
- Window → Sniffer → Channel **6**, Width **20 MHz** → Start
- Остановите после сценария; pcap сохранен в `/var/tmp/wireless_capture_*.wcap`
- Copy: `cp /var/tmp/wireless_capture_*.wcap mac/wifi_ch6.wcap`
- **Заметка**: на Apple Silicon часто выдает 0-байтовые pcap из-за известного
  ограничения monitor-mode. Захватывайте все равно — если работает, это золото.

---

## 4. Sanity тест (запустите ОДИН РАЗ перед любыми сценариями)

Подтвердите, что каждый сборщик действительно выдает данные:

```bash
# Pixel: nlmon0 видит активность в течение секунды или двух
adb shell su -c 'timeout 3 tcpdump -i nlmon0 -nn -c 5' 2>&1 | head -10
# Ожидайте: по крайней мере несколько выведенных пакетов

# Pixel: frida видит процесс
frida-ps -U | grep -E 'mosey|nearby|gms'
# Ожидайте: mosey_server, com.google.android.mosey, com.google.android.gms.persistent

# Pixel: HCI snoop файл растет
adb shell 'su -c "ls -l /data/misc/bluetooth/logs/btsnoop_hci.log"'
# Ожидайте: ненулевой размер, свежее mtime

# Mac: unified log streaming
/usr/bin/log stream --predicate 'process == "sharingd"' --debug --info | head -3
# Ожидайте: по крайней мере строки инициализации sharingd

# Mac: PacketLogger захватывает
# (визуально проверьте увеличение количества пакетов)
```

Если что-либо из этого молчит — исправьте это перед запуском сценариев.

---

## 5. Что мы будем искать (чтобы тестер знал, что он захватил)

Это индикаторы, что захват полезен. Тестер **не должен**
сам проверять это — просто включите сырые артефакты в набор.

### В `pixel/netlink.pcap` (откройте в Wireshark, фильтр `nl80211`)
- `NL80211_CMD_VENDOR` с vendor OUI `00:1a:11` (Google) → путь wondertap активен
- `NL80211_CMD_PUBLISH_NAN_FUNCTION` / `_SUBSCRIBE_NAN_FUNCTION` → Mosey использует Wi-Fi Aware
- `NL80211_CMD_FRAME` с типом кадра `0x00D0` (mgmt action) → injection action-кадра
- `NL80211_CMD_REGISTER_FRAME` match prefix bytes → какие RX кадр-паттерны вооружает Mosey

### В `pixel/btsnoop.log` (откройте в Wireshark)
- `HCI_LE_Set_Extended_Advertising_Data` с `Manufacturer Data` компания `0x004C` →
  beacon AirDrop BLE Apple. Критические байты:
  - Offset 0: `0x05` (тип AirDrop)
  - Offset 1: `0x12` (длина)
  - **Offset 12: `adVr`** — `0x03` это современный AirDrop, `0x01` это legacy (и отклонен Apple).
- `HCI_LE_Set_Extended_Scan_Parameters` + фильтры → что RX-слушает Mosey

### В `pixel/mosey_server.log` (Frida)
- Строки начиная с `socket family=16` → каждый netlink сокет, открытый Mosey
- Hex dumps `sendto` / `sendmsg` на этих FD → сырые байты атрибута nl80211
- Паттерн: взрыв активности сразу при открытии Quick Share

### В `mac/unifiedlog.txt`
- `IO80211AWDLPeerManager: actionFrameReport SUI from <Pixel MAC>` → Mac kernel получил
  наш action-кадр
- `RPNearbyActionV2Discovery adVr=3` строки из `rapportd` → подтверждает beacon BLE был
  проверен end-to-end
- `wifip2pd: AWDLBrowse _airdrop._tcp.local was started` → подтверждает Mac просматривает
  сервисы AirDrop через AWDL
- `sharingd: Sender ... <Pixel ID>` → финальный успех обнаружения

### В `mac/wifi_ch6.wcap` (если не 0-байт)
- 802.11 mgmt action-кадры из Pixel MAC → ground truth формата кадра
- Декодированные vendor IE OUI

---

## 6. Упаковка доставляемого продукта

За сценарий, zip директорию:

```bash
zip -r captures_SCEN_run1.zip captures/SCEN_run1/
```

Отправьте все zips. Приблизительный итог ≈ 300–800 МБ через 5 сценариев × 3 повтора.
Если размер проблематичен, **приоритизируйте Scenario A run 1** — это единственный наиболее
информативный набор.

---

## 7. Быстрый справочник — что каждый артефакт отвечает

| Файл | Отвечает |
|---|---|
| `netlink.pcap` | Какие `nl80211` / Wi-Fi-Aware / vendor команды использует Mosey |
| `btsnoop.log` | Точные байты BLE advert + scan-filter, версия `adVr` |
| `mosey_server.log` (Frida) | Сырые байты netlink за сокет, паттерн syscall |
| `gms_persistent.log` (Frida) | Java-side `WifiAwareManager` / `Nsd` / `BLE` вызовы API |
| `logcat.txt` | Mosey / NearbySharing trace сообщения, ошибки |
| `dmesg.txt` | bcmdhd события прошивки (action-frame TX completion, NAN события) |
| `ip.pcap` (Pixel) | HTTPS на Apple одноранговый, TLS рукопожатие, mDNS по Wi-Fi |
| `unifiedlog.txt` (Mac) | Где в стеке Apple был замечен/принят/отклонен Pixel |
| `packetlogger.pklg` (Mac) | Представление BLE со стороны Mac beacon Pixel |
| `wifi_ch6.wcap` (Mac) | Over-the-air 802.11 (может быть пуст на Apple Silicon) |
| `dnssd_*.txt` (Mac) | Был ли опубликован `_airdrop._tcp` Pixel и через какой интерфейс (AWDL vs en0) |
| `BEFORE_*.txt` / `AFTER_*.txt` | Дельта в NAN сессиях, BLE advertising ID и т.д. |

---

## 8. Ориентировочные усилия

| Шаг | Время |
|---|---|
| Единовременная настройка (профили, frida-server, nlmon, HCI snoop) | 30–45 мин |
| Sanity тест | 5 мин |
| Каждый сценарий с 3 повторами | ~30 мин |
| Все 5 сценариев | ~2.5 ч |
| Zip + upload | 30 мин |

**Итого**: полдня активного тестирования.

---

## 9. Если что-то не сработает

- `nlmon0` возвращает `RTNETLINK answers: Operation not supported` →
  ядро было построено без `CONFIG_NLMON`. Попробуйте `tcpdump -i any -nn 'proto 0x000c'`
  как частичный fallback, или используйте `strace` на `mosey_server` вместо.
- Frida не может attach к `mosey_server` → SELinux блокирует; попробуйте
  `setenforce 0` сначала (имейте в виду, это временно снижает безопасность системы).
- HCI snoop log пуст → BT был переключен перед тем как параметр вступил в силу. Переключите BT
  off/on еще раз, подождите 10 сек, повторите попытку.
- PacketLogger отсутствует → установите "Additional Tools for Xcode" с портала Apple Dev
  (само приложение Xcode этого не включает).
- Wireless Diagnostics выдает 0-байтовый pcap → известная проблема Apple Silicon, игнорируйте;
  on-device netlink pcap это то, что нам действительно нужно.
