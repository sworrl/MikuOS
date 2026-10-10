# Settings parity: MikuSettings vs stock Settings

This is the map for retiring the stock AOSP/HiBy Settings app (`com.android.settings`, `/system_ext/priv-app/Settings`) in favor of MikuSettings (`com.miku.settings`, module `mikuos-settings`, installed to `/system/app/MikuSettings` by `build_mikuos_super.sh`).

Sources: `aapt2 dump xmltree` of the device's stock Settings.apk (349 activities, 249 with intent filters, runs as `android.uid.system`), the device's `services.jar`, `service-connectivity.jar` (tethering APEX), `framework.jar`, `framework-res.apk` and `Bluetooth.apk` from `m500-system-archive/extracted_fs`, and the MikuSettings source. The tables in sections 3 and 4 are generated from those dumps, so every stock entry point is listed. Nothing here was tested on hardware yet; section 8 is the device checklist.

## 1. Summary

| Status | Unique actions | Meaning |
|---|---|---|
| DONE | 16 | An existing MikuOS screen already covered it |
| IMPLEMENTED | 120 | Built in this pass as a real MikuOS screen or dialog |
| DEEP-LINK | 63 | MikuOS receives the intent and forwards it to the stock page. Interim; this is the remaining work |
| NOT NEEDED | 25 | Does not apply to this device (no biometrics, work profile, dialer, stylus, VR). MikuOS still receives it, opens stock if present, otherwise explains |
| STOCK ONLY | 22 | Not mirrored on purpose (internal to stock, keyguard credential flows, or flows that check the launching app's identity) |
| Total | 246 | Unique actions across all stock activity intent filters (MAIN-only launcher/tile filters excluded) |

What changed in `mikuos-settings`:

- **Router.** `route/SettingsRouterActivity` plus 11 permission aliases now declare every stock activity intent filter (actions, categories, data schemes and MIME types copied one for one, `android:priority="10"`). Filters were generated from the stock manifest; `route/StockMap.kt` keeps the matching stock component for each action so interim deep links go to the exact stock activity. When stock is gone, the router opens a MikuOS page that says the screen is not built yet instead of failing.
- **Pages.** `pages/MikuPageActivity` hosts the new screens: Wi-Fi (list, join, password, hidden network, details, forget, saved networks, preferences), Internet (airplane mode, private DNS), Mobile network, Hotspot and tethering, VPN, Data usage, NFC, Connection preferences (USB mode, Bluetooth name), Apps (list, App info with force stop, disable, uninstall, clear storage/cache, sizes, battery, data, links, special access), App notifications and categories, App language, Default apps, Special app access (13 kinds plus notification listeners and device admins), Notifications, Do Not Disturb, Sound, More display settings, Storage (with SD eject/mount), Location, Security & privacy, Accessibility (services with warning, color, contrast, extra dim, animations, magnification, captions, mono audio), Date & time, Languages, Keyboard, Accounts and Add account, Users, Developer options, Reset (network reset and factory reset).
- **Dialogs.** Battery optimization request, device admin activation, Bluetooth pairing (PIN, passkey, numeric comparison, consent, display codes) with a priority-1000 receiver that aborts the stock one, Bluetooth enable/disable/discoverable requests, Wi-Fi enable/disable/scan-always requests, widget bind, and the Wi-Fi "no internet" prompt under the exact class name ConnectivityService builds.
- **Boot.** `home/MikuFallbackHome` (shipped disabled) replaces stock FallbackHome only when stock's is gone. `BootReceiver` and the first app open run `PreferredRouting` (section 2).
- **Existing screens.** The links that used to hand off to AOSP (Wi-Fi, hotspot, airplane, apps, storage, display, developer options, connected devices) now open the MikuOS pages. Battery gained a Battery Saver toggle and app battery list. New home tiles for the new areas.

Can the stock APK be deleted today? **No.** Blockers, in order: MikuSettings must move to priv-app so its intent priority counts (section 2); the 63 deep-link screens; keyguard credential confirm and lock setup (section 3); and the hardcoded framework references in section 5 (USB notification, data-usage notification, Bluetooth access requests). Hiding the stock launcher entry is safe now (section 7).

## 2. How intents reach MikuSettings

1. **Priority is ignored for /system/app.** `ComponentResolver.adjustPriority` in this device's `services.jar` resets any `android:priority` above 0 to 0 when the package is not privileged. MikuSettings is in `/system/app`, so its priority 10 counts as 0. Of the stock filters, 157 are priority 1 and win outright; 129 are priority 0 and tie, and a tie shows the system chooser. That is the dual-UI problem.
2. **Interim fix shipped: preferred activities.** `route/PreferredRouting` runs on boot, on app update and on first open. For every mirrored action where MikuSettings ties for the top priority it registers a preferred activity, the same record the chooser's "Always" button writes (`addPreferredActivity`, needs `SET_PREFERRED_APPLICATIONS`, granted by platform signing). It logs `settings intent routing: Outcome(claimed=…, stockWins=…, …)` under tag `MikuSettingsRouting`. It cannot beat stock's priority-1 filters.
3. **Real fix (build script, not applied here): install MikuSettings as a priv-app.** In `build_mikuos_super.sh` lines 453 to 459, change `system/app/MikuSettings` to `system/priv-app/MikuSettings` (mkdir, mode, write, labels; same `system_file` label). Priority 10 then beats stock's 1 for every mirrored action. VIEW-based filters (APN editor, HiBy teen mode) are protected actions and stay at 0 by design. `ro.control_privapp_permissions` is `enforce` on this device and the check has no exemption for platform-signed apps (verified in `PermissionManagerServiceImpl`), so every privileged permission the app requests must be in the allowlist or boot stops. The allowlist is now complete (section 6). The old entry was missing `MODIFY_PHONE_STATE` and `CHANGE_CONFIGURATION`, so moving the app before this change would have stopped boot.
4. **The framework finds "the settings app" by resolution.** `ConnectivityService.getSettingsPackageName` resolves `android.settings.SETTINGS` and starts `<that package>.wifi.WifiNoInternetDialog`. Once MikuSettings wins that action, the system will start `com.miku.settings/com.miku.settings.wifi.WifiNoInternetDialog`, which now exists. `KeyguardManager` resolves `CONFIRM_DEVICE_CREDENTIAL` the same way, which is why that action is not mirrored.
5. **Deep links forward the result slot.** The router starts the stock page with `FLAG_ACTIVITY_FORWARD_RESULT`, so a caller using `startActivityForResult` gets its answer from the stock page. The stock page sees MikuSettings as the launching app, so stock flows that authorize or label the caller by launching package (add networks, autofill picker, manage credentials, profile owner, new password) are not mirrored; they stay STOCK ONLY until rebuilt.
6. **Permission parity.** Stock activities with `android:permission` are mirrored through activity-aliases that carry the same permission, and the dialogs carry theirs. MikuSettings holds those permissions itself, so without this any app could reach a protected stock page through it.


## 3. System-critical flows

These are the entry points other apps or the OS itself launch. Every one of them must work before the stock APK is deleted.

| Action | What it does | Miku status | Handled by |
|---|---|---|---|
| `android.settings.SETTINGS` | Main settings list | **DONE** | MikuSettingsActivity home |
| `android.settings.panel.action.INTERNET_CONNECTIVITY` | Internet panel (apps open it to ask for a connection) | **IMPLEMENTED** | Page internet (full page, not a sheet) |
| `android.net.action.PROMPT_LOST_VALIDATION` | Wi-Fi lost internet, switch to mobile? | **IMPLEMENTED** | Same dialog, setAvoidUnvalidated |
| `android.net.action.PROMPT_UNVALIDATED` | No internet on this Wi-Fi, stay connected? | **IMPLEMENTED** | com.miku.settings.wifi.WifiNoInternetDialog (class name fixed by ConnectivityService) |
| `android.net.wifi.action.REQUEST_ENABLE` | App asks to turn Wi-Fi on | **IMPLEMENTED** | WifiRequestActivity |
| `android.settings.WIFI_ADD_NETWORKS` | App proposes networks to save, gets per-network result codes | **STOCK ONLY** | Not mirrored: reads launching app identity |
| `android.settings.WIFI_SETTINGS` | Wi-Fi list, connect, password, forget | **IMPLEMENTED** | Page wifi: toggle, scan, join (PSK/SAE/WEP/open/OWE), hidden network, details, disconnect, forget |
| `android.settings.panel.action.WIFI` | Wi-Fi panel | **IMPLEMENTED** | Page wifi |
| `com.android.settings.wifi.action.NETWORK_REQUEST` | App-requested peer network picker (WifiNetworkSpecifier) | **DEEP-LINK** | Interim deep link; needed by IoT pairing apps |
| `android.settings.APN_SETTINGS` | APN list | **DEEP-LINK** | Interim deep link (ApnSettingsActivity). Google Fi APN comes from apns-conf-mikuos.xml |
| `android.settings.NETWORK_OPERATOR_SETTINGS` | Mobile network settings | **IMPLEMENTED** | Page mobile: SIM info, data, roaming, network type |
| `android.settings.TETHER_SETTINGS` | Hotspot and tethering | **IMPLEMENTED** | Page hotspot: Wi-Fi hotspot on/off, name, password, USB and Bluetooth tethering |
| `android.settings.VPN_SETTINGS` | VPN list and always-on | **IMPLEMENTED** | Page vpn: VPN apps, always-on, lockdown. Built-in IKEv2 profiles stay stock |
| `android.settings.DATA_USAGE_SETTINGS` | Data usage summary | **IMPLEMENTED** | Page data_usage: month totals, Data Saver. Per-app limits stay stock |
| `android.bluetooth.adapter.action.REQUEST_DISCOVERABLE` | App asks to make device visible | **IMPLEMENTED** | BluetoothRequestActivity; result = seconds |
| `android.bluetooth.adapter.action.REQUEST_ENABLE` | App asks to turn Bluetooth on | **IMPLEMENTED** | BluetoothRequestActivity |
| `android.bluetooth.device.action.PAIRING_REQUEST` | Pairing PIN / passkey / consent dialog | **IMPLEMENTED** | PairingRequestReceiver (priority 1000, aborts stock) + BluetoothPairingActivity |
| `android.settings.BLUETOOTH_SETTINGS` | Bluetooth on/off, pair, connect, forget | **DONE** | Existing Bluetooth screen |
| `android.settings.NFC_SETTINGS` | NFC on/off | **IMPLEMENTED** | Page nfc |
| `android.settings.panel.action.NFC` | NFC panel | **IMPLEMENTED** | Page nfc |
| `android.settings.APPLICATION_DETAILS_SETTINGS` | App info for package: | **IMPLEMENTED** | Page app/&lt;pkg&gt;: open, force stop, disable/enable, uninstall, clear storage/cache, sizes, notifications, permissions link, language, battery, data, links, special access |
| `android.settings.VOICE_INPUT_SETTINGS` | Assistant and voice input | **IMPLEMENTED** | Page default_apps (assistant role) |
| `android.app.action.ADD_DEVICE_ADMIN` | Activate device admin | **IMPLEMENTED** | DeviceAdminAddActivity (setActiveAdmin) |
| `android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` | Notification listener list | **IMPLEMENTED** | Page access/listener |
| `android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION` | All files access list | **IMPLEMENTED** | Page access/files |
| `android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` | All files access for one app | **IMPLEMENTED** | Page access/files/&lt;pkg&gt; (uid mode, as stock) |
| `android.settings.MANAGE_UNKNOWN_APP_SOURCES` | Install unknown apps | **IMPLEMENTED** | Page access/install[/pkg] |
| `android.settings.NOTIFICATION_LISTENER_DETAIL_SETTINGS` | One notification listener | **IMPLEMENTED** | Page listener/&lt;component&gt; with warning |
| `android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | App asks to skip battery optimization | **IMPLEMENTED** | RequestIgnoreBatteryOptActivity (PowerExemptionManager) |
| `android.settings.USAGE_ACCESS_SETTINGS` | Usage access | **IMPLEMENTED** | Page access/usage[/pkg] |
| `android.settings.action.MANAGE_OVERLAY_PERMISSION` | Display over other apps | **IMPLEMENTED** | Page access/overlay[/pkg] |
| `android.settings.action.MANAGE_WRITE_SETTINGS` | Modify system settings | **IMPLEMENTED** | Page access/write[/pkg] |
| `android.appwidget.action.APPWIDGET_BIND` | Launcher asks to place a widget | **IMPLEMENTED** | AppWidgetBindActivity |
| `android.settings.APP_NOTIFICATION_SETTINGS` | One app's notifications | **IMPLEMENTED** | Page appnotif/&lt;pkg&gt;: on/off, badge, categories |
| `android.settings.CHANNEL_NOTIFICATION_SETTINGS` | One notification category | **IMPLEMENTED** | Page channel/&lt;pkg&gt;/&lt;id&gt;: importance (locked like stock) |
| `android.settings.NOTIFICATION_SETTINGS` | Notification settings | **IMPLEMENTED** | Page notifications: app list, lock screen, dots, snooze, DND, listener access |
| `android.settings.SOUND_SETTINGS` | Volumes, ringtones, system sounds | **IMPLEMENTED** | Page sound + link to DAC page |
| `android.settings.panel.action.VOLUME` | Volume panel | **IMPLEMENTED** | Page sound |
| `android.settings.DISPLAY_SETTINGS` | Display | **DONE** | Display & Light screen; More display settings page added |
| `android.settings.BATTERY_SAVER_SETTINGS` | Battery Saver | **IMPLEMENTED** | Battery screen: telemetry (existing) + saver toggle, app battery list |
| `android.settings.INTERNAL_STORAGE_SETTINGS` | Storage | **IMPLEMENTED** | Page storage: volumes, used/free, SD eject/mount, apps, files |
| `android.settings.LOCATION_SOURCE_SETTINGS` | Location on/off | **IMPLEMENTED** | Page location (setLocationEnabledForUser) + permission link |
| `android.app.action.CONFIRM_DEVICE_CREDENTIAL` | Confirm PIN/pattern for an app | **STOCK ONLY** | Not mirrored: KeyguardManager picks the package by resolution; must stay stock |
| `android.app.action.SET_NEW_PASSWORD` | Set screen lock (apps, DPC) | **STOCK ONLY** | Not mirrored: reads launching app identity for complexity |
| `android.settings.LOCK_SCREEN_SETTINGS` | Lock screen | **IMPLEMENTED** | Page security; lock setup hands off to SET_NEW_PASSWORD (stock ChooseLockGeneric is not exported) |
| `android.settings.SECURITY_SETTINGS` | Security | **IMPLEMENTED** | Page security: lock status, encryption, patch, permission manager, app pinning |
| `android.settings.ACCESSIBILITY_DETAILS_SETTINGS` | One accessibility service | **IMPLEMENTED** | Page a11y/&lt;component&gt; with full-control warning |
| `android.settings.ACCESSIBILITY_SETTINGS` | Accessibility | **IMPLEMENTED** | Page a11y: services, inversion, color correction, contrast, extra dim, animations, magnification, captions, mono |
| `android.settings.ADD_ACCOUNT_SETTINGS` | Add account (Play Store, setup) | **IMPLEMENTED** | Page accounts_add; honors account_types; RESULT_OK on add |
| `android.settings.APPLICATION_DEVELOPMENT_SETTINGS` | Developer options | **IMPLEMENTED** | Page developer: dev toggle, USB/wireless debugging, revoke keys, stay awake, taps, pointer, animation scales, don't keep activities |
| `android.settings.DATE_SETTINGS` | Date, time, time zone, 24-hour | **IMPLEMENTED** | Page datetime (AlarmManager.setTime/setTimeZone) |
| `android.settings.INPUT_METHOD_SETTINGS` | On-screen keyboards | **IMPLEMENTED** | Page keyboard: enable/disable IMEs, switch, IME settings |
| `android.settings.LOCALE_SETTINGS` | System language | **IMPLEMENTED** | Page languages (LocalePicker.updateLocales) |
| `android.settings.USER_SETTINGS` | Users | **IMPLEMENTED** | Page users (list); add user/guest stays stock |
| `com.android.settings.action.FACTORY_RESET` | Factory reset | **IMPLEMENTED** | Page reset: network reset + erase all (FRP block wipe as stock, then ACTION_FACTORY_RESET) |
| `android.settings.DEVICE_INFO_SETTINGS` | About device | **DONE** | About MikuOS screen; legal links added |

Two critical flows deliberately stay on stock Settings and block deletion until rebuilt: `CONFIRM_DEVICE_CREDENTIAL` (apps that ask for your PIN) and `SET_NEW_PASSWORD` (lock screen setup). Both only matter if a screen lock is ever set; MikuOS runs with `cmd lock_settings set-disabled true`. `WIFI_ADD_NETWORKS` and `NETWORK_REQUEST` also stay stock for now.


## 4. Every stock entry point

One row per action declared by the 249 stock activities that have intent filters (249 activities with filters out of 349). "Caller needs" is the `android:permission` on the stock activity, mirrored on the MikuOS side. "Miku uses" is the main permission the MikuOS implementation relies on. Status key: DONE = an existing MikuOS screen already covered it, IMPLEMENTED = built in this pass, DEEP-LINK = MikuOS receives the intent and forwards it to the stock component (interim, remaining work), NOT NEEDED = not applicable to this device (MikuOS still receives it and opens stock if present, or explains), STOCK ONLY = not mirrored on purpose (reason given).

| # | Action | Data | Stock component | Category | What it does | Miku status | Crit | Caller needs / Miku uses | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `android.settings.SETTINGS` | - | .homepage.SettingsHomepageActivity | Home | Main settings list | DONE | YES | - | MikuSettingsActivity home |
| 2 | `android.settings.AIRPLANE_MODE_SETTINGS` | - | Settings$NetworkDashboardActivity | Network | Airplane mode | IMPLEMENTED |  | NETWORK_SETTINGS | Page internet, ConnectivityManager.setAirplaneMode |
| 3 | `android.settings.WIRELESS_SETTINGS` | - | Settings$NetworkDashboardActivity | Network | Network & internet hub | IMPLEMENTED |  | NETWORK_SETTINGS | Page internet |
| 4 | `android.settings.panel.action.INTERNET_CONNECTIVITY` | - | .panel.SettingsPanelActivity | Network | Internet panel (apps open it to ask for a connection) | IMPLEMENTED | YES | NETWORK_SETTINGS | Page internet (full page, not a sheet) |
| 5 | `android.net.action.PROMPT_LOST_VALIDATION` | - | .wifi.WifiNoInternetDialog | Wi-Fi | Wi-Fi lost internet, switch to mobile? | IMPLEMENTED | YES | caller: NETWORK_STACK | Same dialog, setAvoidUnvalidated |
| 6 | `android.net.action.PROMPT_UNVALIDATED` | - | .wifi.WifiNoInternetDialog | Wi-Fi | No internet on this Wi-Fi, stay connected? | IMPLEMENTED | YES | caller: NETWORK_STACK | com.miku.settings.wifi.WifiNoInternetDialog (class name fixed by ConnectivityService) |
| 7 | `android.net.wifi.PICK_WIFI_NETWORK` | - | .wifi.WifiPickerActivity | Wi-Fi | Pick a network (setup flows) | IMPLEMENTED |  | caller: CHANGE_WIFI_STATE | Page wifi |
| 8 | `android.net.wifi.action.REQUEST_DISABLE` | - | .wifi.RequestToggleWiFiActivity | Wi-Fi | App asks to turn Wi-Fi off | IMPLEMENTED |  | caller: CHANGE_WIFI_STATE | WifiRequestActivity |
| 9 | `android.net.wifi.action.REQUEST_ENABLE` | - | .wifi.RequestToggleWiFiActivity | Wi-Fi | App asks to turn Wi-Fi on | IMPLEMENTED | YES | caller: CHANGE_WIFI_STATE | WifiRequestActivity |
| 10 | `android.net.wifi.action.REQUEST_SCAN_ALWAYS_AVAILABLE` | - | .wifi.WifiScanModeActivity | Wi-Fi | App asks for always-on scanning | IMPLEMENTED |  | WRITE_SECURE_SETTINGS | WifiRequestActivity |
| 11 | `android.settings.NETWORK_PROVIDER_SETTINGS` | - | Settings$NetworkProviderSettingsActivity | Wi-Fi | Wi-Fi and carrier list | IMPLEMENTED |  | NETWORK_SETTINGS | Page wifi |
| 12 | `android.settings.PROCESS_WIFI_EASY_CONNECT_URI` | DPP | .wifi.dpp.WifiDppConfiguratorActivity | Wi-Fi | Handle DPP: URI | DEEP-LINK |  | - | Interim deep link |
| 13 | `android.settings.WIFI_ADD_NETWORKS` | - | .wifi.addappnetworks.AddAppNetworksActivity | Wi-Fi | App proposes networks to save, gets per-network result codes | STOCK ONLY | YES | - | Not mirrored: reads launching app identity |
| 14 | `android.settings.WIFI_DETAILS_SETTINGS` | - | Settings$WifiDetailsSettingsActivity | Wi-Fi | Details of one network | IMPLEMENTED |  | caller: CHANGE_WIFI_STATE | Page wifi (details dialog per network) |
| 15 | `android.settings.WIFI_DPP_CONFIGURATOR_QR_CODE_GENERATOR` | - | .wifi.dpp.WifiDppConfiguratorActivity | Wi-Fi | Share Wi-Fi as QR | DEEP-LINK |  | - | Interim deep link |
| 16 | `android.settings.WIFI_DPP_CONFIGURATOR_QR_CODE_SCANNER` | - | .wifi.dpp.WifiDppConfiguratorActivity | Wi-Fi | Easy Connect QR scan | DEEP-LINK |  | - | Interim deep link |
| 17 | `android.settings.WIFI_DPP_ENROLLEE_QR_CODE_SCANNER` | - | .wifi.dpp.WifiDppEnrolleeActivity | Wi-Fi | Join by QR | DEEP-LINK |  | - | Interim deep link |
| 18 | `android.settings.WIFI_IP_SETTINGS` | - | Settings$ConfigureWifiSettingsActivity | Wi-Fi | Wi-Fi preferences | IMPLEMENTED |  | WRITE_SECURE_SETTINGS | Page wifi_prefs: wakeup, open-network notice, scanning, addresses. Certificates stay stock |
| 19 | `android.settings.WIFI_SAVED_NETWORK_SETTINGS` | - | Settings$SavedAccessPointsSettingsActivity | Wi-Fi | Saved networks list | IMPLEMENTED |  | NETWORK_SETTINGS | Page wifi_saved |
| 20 | `android.settings.WIFI_SCANNING_SETTINGS` | - | Settings$WifiScanningSettingsActivity | Wi-Fi | Wi-Fi scanning toggle | IMPLEMENTED |  | caller: CHANGE_WIFI_STATE | Page location |
| 21 | `android.settings.WIFI_SETTINGS` | - | Settings$WifiSettingsActivity | Wi-Fi | Wi-Fi list, connect, password, forget | IMPLEMENTED | YES | NETWORK_SETTINGS, CHANGE_WIFI_STATE | Page wifi: toggle, scan, join (PSK/SAE/WEP/open/OWE), hidden network, details, disconnect, forget |
| 22 | `android.settings.panel.action.WIFI` | - | .panel.SettingsPanelActivity | Wi-Fi | Wi-Fi panel | IMPLEMENTED | YES | NETWORK_SETTINGS | Page wifi |
| 23 | `com.android.settings.WIFI_DIALOG` | - | .wifi.WifiDialogActivity | Wi-Fi | Stock Wi-Fi edit dialog with extras | DEEP-LINK |  | caller: CHANGE_WIFI_STATE | Interim deep link |
| 24 | `com.android.settings.wifi.action.NETWORK_REQUEST` | - | .wifi.NetworkRequestDialogActivity | Wi-Fi | App-requested peer network picker (WifiNetworkSpecifier) | DEEP-LINK | YES | caller: NETWORK_SETTINGS | Interim deep link; needed by IoT pairing apps |
| 25 | `android.intent.action.EDIT` | vnd.android.cursor.item/telephony-carrier | Settings$ApnEditorActivity | Mobile | APN editor (typed data telephony-carrier) | DEEP-LINK |  | - | Interim deep link |
| 26 | `android.intent.action.INSERT` | vnd.android.cursor.dir/telephony-carrier | Settings$ApnEditorActivity | Mobile | New APN | DEEP-LINK |  | - | Interim deep link |
| 27 | `android.settings.APN_SETTINGS` | - | Settings$ApnSettingsActivity | Mobile | APN list | DEEP-LINK | YES | - | Interim deep link (ApnSettingsActivity). Google Fi APN comes from apns-conf-mikuos.xml |
| 28 | `android.settings.DATA_ROAMING_SETTINGS` | - | Settings$MobileNetworkActivity | Mobile | Roaming | IMPLEMENTED |  | MODIFY_PHONE_STATE | Page mobile |
| 29 | `android.settings.MANAGE_ALL_SIM_PROFILES_SETTINGS` | - | Settings$MobileNetworkListActivity | Mobile | eSIM/SIM profiles | IMPLEMENTED |  | - | Page mobile (single physical SIM) |
| 30 | `android.settings.MMS_MESSAGE_SETTING` | - | Settings$MobileNetworkActivity | Mobile | MMS data setting | IMPLEMENTED |  | - | Page mobile (no separate MMS switch yet) |
| 31 | `android.settings.MOBILE_NETWORK_LIST` | - | Settings$MobileNetworkListActivity | Mobile | SIM list | IMPLEMENTED |  | READ_PHONE_STATE | Page mobile |
| 32 | `android.settings.NETWORK_OPERATOR_SETTINGS` | - | Settings$MobileNetworkActivity | Mobile | Mobile network settings | IMPLEMENTED | YES | MODIFY_PHONE_STATE, READ_PRIVILEGED_PHONE_STATE | Page mobile: SIM info, data, roaming, network type |
| 33 | `android.settings.WIFI_CALLING_SETTINGS` | - | Settings$WifiCallingSettingsActivity | Mobile | Wi-Fi calling | NOT NEEDED |  | - | No dialer on this device |
| 34 | `android.telephony.ims.action.SHOW_CAPABILITY_DISCOVERY_OPT_IN` | - | Settings$MobileNetworkActivity | Mobile | IMS contact discovery opt-in | NOT NEEDED |  | - | No calling/RCS on a DAP |
| 35 | `android.settings.TETHER_PROVISIONING_UI` | - | .network.TetherProvisioningActivity | Hotspot | Carrier tethering entitlement check UI | DEEP-LINK |  | caller: TETHER_PRIVILEGED | Interim deep link; only shown if the carrier config requires entitlement |
| 36 | `android.settings.TETHER_SETTINGS` | - | Settings$TetherSettingsActivity | Hotspot | Hotspot and tethering | IMPLEMENTED | YES | TETHER_PRIVILEGED, NETWORK_SETTINGS | Page hotspot: Wi-Fi hotspot on/off, name, password, USB and Bluetooth tethering |
| 37 | `android.settings.TETHER_UNSUPPORTED_CARRIER_UI` | - | .network.TetherProvisioningCarrierDialogActivity | Hotspot | Carrier blocks tethering notice | DEEP-LINK |  | caller: TETHER_PRIVILEGED | Interim deep link |
| 38 | `com.android.settings.WIFI_TETHER_SETTINGS` | - | Settings$WifiTetherSettingsActivity | Hotspot | Wi-Fi hotspot | IMPLEMENTED |  | TETHER_PRIVILEGED | Page hotspot |
| 39 | `android.net.vpn.SETTINGS` | - | Settings$VpnSettingsActivity | VPN | Legacy VPN action | IMPLEMENTED |  | - | Page vpn |
| 40 | `android.settings.VPN_SETTINGS` | - | Settings$VpnSettingsActivity | VPN | VPN list and always-on | IMPLEMENTED | YES | CONTROL_VPN, CONTROL_ALWAYS_ON_VPN | Page vpn: VPN apps, always-on, lockdown. Built-in IKEv2 profiles stay stock |
| 41 | `android.settings.DATA_SAVER_SETTINGS` | - | Settings$DataSaverSummaryActivity | Data | Data Saver | IMPLEMENTED |  | MANAGE_NETWORK_POLICY | Page data_usage |
| 42 | `android.settings.DATA_USAGE_SETTINGS` | - | Settings$DataUsageSummaryActivity | Data | Data usage summary | IMPLEMENTED | YES | READ_NETWORK_USAGE_HISTORY | Page data_usage: month totals, Data Saver. Per-app limits stay stock |
| 43 | `android.settings.IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS` | package | .datausage.AppDataUsageActivity | Data | Unrestricted data for one app | IMPLEMENTED |  | MANAGE_NETWORK_POLICY | App info: Unrestricted mobile data |
| 44 | `android.settings.MOBILE_DATA_USAGE` | - | Settings$MobileDataUsageListActivity | Data | Mobile data usage | IMPLEMENTED |  | READ_NETWORK_USAGE_HISTORY | Page data_usage |
| 45 | `android.bluetooth.adapter.action.REQUEST_DISABLE` | - | .bluetooth.RequestPermissionActivity | Bluetooth | App asks to turn Bluetooth off | IMPLEMENTED |  | caller: BLUETOOTH_CONNECT | BluetoothRequestActivity |
| 46 | `android.bluetooth.adapter.action.REQUEST_DISCOVERABLE` | - | .bluetooth.RequestPermissionActivity | Bluetooth | App asks to make device visible | IMPLEMENTED | YES | caller: BLUETOOTH_CONNECT / BLUETOOTH_PRIVILEGED | BluetoothRequestActivity; result = seconds |
| 47 | `android.bluetooth.adapter.action.REQUEST_ENABLE` | - | .bluetooth.RequestPermissionActivity | Bluetooth | App asks to turn Bluetooth on | IMPLEMENTED | YES | caller: BLUETOOTH_CONNECT | BluetoothRequestActivity |
| 48 | `android.bluetooth.device.action.CONNECTION_ACCESS_CANCEL` | - | .bluetooth.BluetoothPermissionActivity | Bluetooth | Cancel of the above | DEEP-LINK |  | caller: BLUETOOTH_CONNECT | Interim deep link |
| 49 | `android.bluetooth.device.action.CONNECTION_ACCESS_REQUEST` | - | .bluetooth.BluetoothPermissionActivity | Bluetooth | Phonebook/message/SIM access prompt | DEEP-LINK |  | caller: BLUETOOTH_CONNECT | Interim deep link. Bluetooth targets the receiver by package via its pairing_ui_package string |
| 50 | `android.bluetooth.device.action.PAIRING_REQUEST` | - | .bluetooth.BluetoothPairingDialog | Bluetooth | Pairing PIN / passkey / consent dialog | IMPLEMENTED | YES | caller: BLUETOOTH_PRIVILEGED / BLUETOOTH_PRIVILEGED | PairingRequestReceiver (priority 1000, aborts stock) + BluetoothPairingActivity |
| 51 | `android.bluetooth.devicepicker.action.LAUNCH` | - | .bluetooth.DevicePickerActivity | Bluetooth | Device picker for Bluetooth sharing (OPP) | DEEP-LINK |  | - | Interim deep link |
| 52 | `android.settings.BLUETOOTH_LE_AUDIO_QR_CODE_SCANNER` | - | .bluetooth.QrCodeScanModeActivity | Bluetooth | LE Audio QR join | DEEP-LINK |  | caller: BLUETOOTH_CONNECT | Interim deep link |
| 53 | `android.settings.BLUETOOTH_NEW_SETTINGS` | - | Settings$BlueToothNewSettingsActivity | Bluetooth | HiBy Bluetooth page | DONE |  | - | Existing Bluetooth screen |
| 54 | `android.settings.BLUETOOTH_PAIRING_SETTINGS` | - | Settings$BlueToothPairingActivity | Bluetooth | Pair new device | DONE |  | caller: BLUETOOTH_SCAN | Existing Bluetooth screen (scan + pair) |
| 55 | `android.settings.BLUETOOTH_SETTINGS` | - | Settings$ConnectedDeviceDashboardActivity, Settings$BlueToothNewSettingsActivity | Bluetooth | Bluetooth on/off, pair, connect, forget | DONE | YES | BLUETOOTH_PRIVILEGED | Existing Bluetooth screen |
| 56 | `android.settings.BLUTOOTH_FIND_BROADCASTS_ACTIVITY` | - | Settings$BluetoothFindBroadcastsActivity | Bluetooth | Find LE Audio broadcasts | DEEP-LINK |  | caller: BLUETOOTH_CONNECT | Interim deep link |
| 57 | `android.settings.MEDIA_BROADCAST_DIALOG` | - | Settings$BluetoothBroadcastActivity | Bluetooth | LE Audio broadcast | DEEP-LINK |  | caller: BLUETOOTH_CONNECT | Interim deep link |
| 58 | `com.android.settings.BLUETOOTH_DEVICE_DETAIL_SETTINGS` | - | Settings$BluetoothDeviceDetailActivity | Bluetooth | One paired device | DONE |  | caller: BLUETOOTH_CONNECT | Existing Bluetooth screen (no per-device page yet) |
| 59 | `com.android.settings.BLUETOOTH_NEW_SETTINGS` | - | Settings$BlueToothNewSettingsActivity | Bluetooth | HiBy Bluetooth page | DONE |  | - | Existing Bluetooth screen |
| 60 | `android.settings.ACTION_PRINT_SETTINGS` | printjob | Settings$PrintSettingsActivity, Settings$PrintJobSettingsActivity | Connected | Printing services / print job | DEEP-LINK |  | - | Interim deep link |
| 61 | `android.settings.CAST_SETTINGS` | - | Settings$WifiDisplaySettingsActivity | Connected | Screen cast | DEEP-LINK |  | - | Interim deep link |
| 62 | `com.android.settings.ADVANCED_CONNECTED_DEVICE_SETTINGS` | - | Settings$AdvancedConnectedDeviceActivity | Connected | Connection preferences | IMPLEMENTED |  | MANAGE_USB, BLUETOOTH_CONNECT | Page connected: BT name, USB mode, NFC. Cast and printing stay stock |
| 63 | `android.nfc.cardemulation.action.ACTION_CHANGE_DEFAULT` | - | .nfc.PaymentDefaultDialog | NFC | App asks to become payment default | DEEP-LINK |  | - | Interim deep link |
| 64 | `android.settings.NFCSHARING_SETTINGS` | - | Settings$AndroidBeamSettingsActivity | NFC | Android Beam (removed in 14) | IMPLEMENTED |  | - | Page nfc |
| 65 | `android.settings.NFC_PAYMENT_SETTINGS` | - | Settings$PaymentSettingsActivity | NFC | Contactless payment default | DEEP-LINK |  | - | Interim deep link |
| 66 | `android.settings.NFC_SETTINGS` | - | Settings$NfcSettingsActivity | NFC | NFC on/off | IMPLEMENTED | YES | WRITE_SECURE_SETTINGS | Page nfc |
| 67 | `android.settings.panel.action.NFC` | - | .panel.SettingsPanelActivity | NFC | NFC panel | IMPLEMENTED | YES | - | Page nfc |
| 68 | `android.intent.action.AUTO_REVOKE_PERMISSIONS` | package | .applications.InstalledAppDetails | Apps | App info (unused-app permission removal) | IMPLEMENTED |  | - | Page app/&lt;pkg&gt;; the toggle itself lives in PermissionController |
| 69 | `android.intent.action.MANAGE_PACKAGE_STORAGE` | - | Settings$StorageUseActivity | Apps | Free up app storage | IMPLEMENTED |  | - | Page apps |
| 70 | `android.settings.APPLICATION_DETAILS_SETTINGS` | package | .applications.InstalledAppDetails | Apps | App info for package: | IMPLEMENTED | YES | FORCE_STOP_PACKAGES, CLEAR_APP_USER_DATA, DELETE_CACHE_FILES, CHANGE_COMPONENT_ENABLED_STATE, PACKAGE_USAGE_STATS | Page app/&lt;pkg&gt;: open, force stop, disable/enable, uninstall, clear storage/cache, sizes, notifications, permissions link, language, battery, data, links, special access |
| 71 | `android.settings.APPLICATION_SETTINGS` | - | Settings$ManageApplicationsActivity | Apps | App list | IMPLEMENTED |  | QUERY_ALL_PACKAGES | Page apps (search, system toggle) |
| 72 | `android.settings.APP_LOCALE_SETTINGS` | package | .localepicker.AppLocalePickerActivity | Apps | Per-app language | IMPLEMENTED |  | CHANGE_CONFIGURATION | Page applocale/&lt;pkg&gt; (LocaleManager) |
| 73 | `android.settings.APP_MEMORY_USAGE` | - | Settings$AppMemoryUsageActivity | Apps | Memory use per app | DEEP-LINK |  | - | Interim deep link |
| 74 | `android.settings.APP_OPEN_BY_DEFAULT_SETTINGS` | package | .applications.InstalledAppOpenByDefaultActivity | Apps | Open supported links | IMPLEMENTED |  | UPDATE_DOMAIN_VERIFICATION_USER_SELECTION | App info toggle (DomainVerificationManager) |
| 75 | `android.settings.CREDENTIAL_PROVIDER` | package | Settings$AccountDashboardActivity | Apps | Passwords and credential providers | DEEP-LINK |  | - | Interim deep link |
| 76 | `android.settings.MANAGE_ALL_APPLICATIONS_SETTINGS` | - | Settings$ManageApplicationsActivity | Apps | All apps | IMPLEMENTED |  | - | Page apps |
| 77 | `android.settings.MANAGE_APPLICATIONS_SETTINGS` | - | Settings$ManageApplicationsActivity | Apps | App list | IMPLEMENTED |  | - | Page apps |
| 78 | `android.settings.MANAGE_CLONED_APPS_SETTINGS` | - | Settings$ClonedAppsListActivity | Apps | Cloned apps | NOT NEEDED |  | - | No app cloning profile |
| 79 | `android.settings.MANAGE_DOMAIN_URLS` | - | Settings$ManageDomainUrlsActivity | Apps | Opening links list | IMPLEMENTED |  | - | Page apps, then per-app toggle |
| 80 | `android.settings.REQUEST_SET_AUTOFILL_SERVICE` | package | .applications.autofill.AutofillPickerTrampolineActivity | Apps | App asks to be autofill service | STOCK ONLY |  | - | Not mirrored: reads launching app identity |
| 81 | `android.settings.VIEW_ADVANCED_POWER_USAGE_DETAIL` | package | .fuelgauge.AdvancedPowerUsageDetailActivity | Apps | Battery detail for one app | IMPLEMENTED |  | DEVICE_POWER | App info: Unrestricted battery |
| 82 | `android.settings.VOICE_INPUT_SETTINGS` | - | Settings$ManageAssistActivity | Apps | Assistant and voice input | IMPLEMENTED | YES | MANAGE_ROLE_HOLDERS | Page default_apps (assistant role) |
| 83 | `com.android.settings.APP_OPEN_BY_DEFAULT_SETTINGS` | package | .applications.InstalledAppOpenByDefaultActivity | Apps | Same, old action | IMPLEMENTED |  | - | App info toggle |
| 84 | `android.app.action.ADD_DEVICE_ADMIN` | - | .applications.specialaccess.deviceadmin.DeviceAdminAdd | Special access | Activate device admin | IMPLEMENTED | YES | MANAGE_DEVICE_ADMINS | DeviceAdminAddActivity (setActiveAdmin) |
| 85 | `android.app.action.SET_PROFILE_OWNER` | - | .applications.specialaccess.deviceadmin.ProfileOwnerAdd | Special access | Set profile owner | STOCK ONLY |  | - | Not mirrored: reads launching app identity; no MDM use |
| 86 | `android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` | - | Settings$NotificationAccessSettingsActivity | Special access | Notification listener list | IMPLEMENTED | YES | MANAGE_NOTIFICATION_LISTENERS | Page access/listener |
| 87 | `android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS` | - | Settings$HighPowerApplicationsActivity | Special access | Battery optimization list | IMPLEMENTED |  | DEVICE_POWER | Page access/battery |
| 88 | `android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION` | - | Settings$ManageExternalStorageActivity | Special access | All files access list | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/files |
| 89 | `android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` | package | Settings$AppManageExternalStorageActivity | Special access | All files access for one app | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/files/&lt;pkg&gt; (uid mode, as stock) |
| 90 | `android.settings.MANAGE_APP_LONG_RUNNING_JOBS` | package | Settings$LongBackgroundTasksActivity, Settings$LongBackgroundTasksAppActivity | Special access | Long background tasks | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/longjobs[/pkg] |
| 91 | `android.settings.MANAGE_APP_OVERLAY_PERMISSION` | package | Settings$AppDrawOverlaySettingsActivity | Special access | Overlay for one app (system callers) | IMPLEMENTED |  | caller: INTERNAL_SYSTEM_WINDOW | Page access/overlay/&lt;pkg&gt; |
| 92 | `android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT` | package | .AppManageFullScreenIntent | Special access | Full screen notifications | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/fullscreen/&lt;pkg&gt; |
| 93 | `android.settings.MANAGE_CROSS_PROFILE_ACCESS` | package | Settings$InteractAcrossProfilesSettingsActivity, Settings$AppInteractAcrossProfilesSettingsActivity | Special access | Connected work and personal apps | NOT NEEDED |  | - | No work profile |
| 94 | `android.settings.MANAGE_UNKNOWN_APP_SOURCES` | package | Settings$ManageExternalSourcesActivity, Settings$ManageAppExternalSourcesActivity | Special access | Install unknown apps | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/install[/pkg] |
| 95 | `android.settings.NOTIFICATION_ASSISTANT_SETTINGS` | - | Settings$NotificationAssistantSettingsActivity | Special access | Notification assistant | DEEP-LINK |  | - | Interim deep link |
| 96 | `android.settings.NOTIFICATION_LISTENER_DETAIL_SETTINGS` | - | Settings$NotificationAccessDetailsActivity | Special access | One notification listener | IMPLEMENTED | YES | MANAGE_NOTIFICATION_LISTENERS | Page listener/&lt;component&gt; with warning |
| 97 | `android.settings.NOTIFICATION_POLICY_ACCESS_DETAIL_SETTINGS` | package | Settings$ZenAccessDetailSettingsActivity | Special access | DND access for one app | IMPLEMENTED |  | STATUS_BAR_SERVICE | Page access/dnd/&lt;pkg&gt; |
| 98 | `android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS` | - | Settings$ZenAccessSettingsActivity | Special access | Do Not Disturb access | IMPLEMENTED |  | STATUS_BAR_SERVICE | Page access/dnd |
| 99 | `android.settings.PICTURE_IN_PICTURE_SETTINGS` | package | Settings$PictureInPictureSettingsActivity, Settings$AppPictureInPictureSettingsActivity | Special access | Picture-in-picture | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/pip[/pkg] |
| 100 | `android.settings.PREMIUM_SMS_SETTINGS` | package | Settings$PremiumSmsAccessActivity | Special access | Premium SMS access | DEEP-LINK |  | - | Interim deep link |
| 101 | `android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | package | .fuelgauge.RequestIgnoreBatteryOptimizations | Special access | App asks to skip battery optimization | IMPLEMENTED | YES | DEVICE_POWER | RequestIgnoreBatteryOptActivity (PowerExemptionManager) |
| 102 | `android.settings.REQUEST_MANAGE_MEDIA` | package | Settings$MediaManagementAppsActivity, Settings$AppMediaManagementAppsActivity | Special access | Media management | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/media[/pkg] |
| 103 | `android.settings.REQUEST_SCHEDULE_EXACT_ALARM` | package | Settings$AlarmsAndRemindersActivity, Settings$AlarmsAndRemindersAppActivity | Special access | Alarms & reminders | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/alarms[/pkg] |
| 104 | `android.settings.TURN_SCREEN_ON_SETTINGS` | package | Settings$TurnScreenOnSettingsActivity, Settings$AppTurnScreenOnSettingsActivity | Special access | Turn screen on | IMPLEMENTED |  | MANAGE_APP_OPS_MODES | Page access/screenon[/pkg] |
| 105 | `android.settings.USAGE_ACCESS_SETTINGS` | package | Settings$UsageAccessSettingsActivity, Settings$AppUsageAccessSettingsActivity | Special access | Usage access | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/usage[/pkg] |
| 106 | `android.settings.VR_LISTENER_SETTINGS` | - | Settings$VrListenersSettingsActivity | Special access | VR helper services | NOT NEEDED |  | - | No VR |
| 107 | `android.settings.action.MANAGE_OVERLAY_PERMISSION` | package | Settings$OverlaySettingsActivity | Special access | Display over other apps | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/overlay[/pkg] |
| 108 | `android.settings.action.MANAGE_WRITE_SETTINGS` | package | Settings$WriteSettingsActivity, Settings$AppWriteSettingsActivity | Special access | Modify system settings | IMPLEMENTED | YES | MANAGE_APP_OPS_MODES | Page access/write[/pkg] |
| 109 | `android.appwidget.action.APPWIDGET_BIND` | - | .AllowBindAppWidgetActivity | Launcher | Launcher asks to place a widget | IMPLEMENTED | YES | BIND_APPWIDGET, MODIFY_APPWIDGET_BIND_PERMISSIONS | AppWidgetBindActivity |
| 110 | `android.appwidget.action.APPWIDGET_PICK` | - | .AppWidgetPickActivity | Launcher | Widget picker for launchers | DEEP-LINK |  | - | Interim deep link |
| 111 | `android.intent.action.PICK_ACTIVITY` | - | .ActivityPicker | Launcher | Activity picker for shortcuts | DEEP-LINK |  | - | Interim deep link |
| 112 | `android.settings.ACTION_APP_NOTIFICATION_REDACTION` | - | .notification.RedactionSettingsStandalone | Notifications | Lock screen redaction | DEEP-LINK |  | - | Interim deep link |
| 113 | `android.settings.ACTION_CONDITION_PROVIDER_SETTINGS` | - | Settings$ZenModeAutomationSettingsActivity | Notifications | DND rule providers | DEEP-LINK |  | - | Interim deep link |
| 114 | `android.settings.ALL_APPS_NOTIFICATION_SETTINGS` | - | Settings$NotificationAppListActivity | Notifications | All apps' notifications | IMPLEMENTED |  | STATUS_BAR_SERVICE | Page notifications |
| 115 | `android.settings.ALL_APPS_NOTIFICATION_SETTINGS_FOR_REVIEW` | - | Settings$NotificationReviewPermissionsActivity | Notifications | Review after upgrade | STOCK ONLY |  | - | Not exported in stock |
| 116 | `android.settings.APP_NOTIFICATION_BUBBLE_SETTINGS` | - | Settings$AppBubbleNotificationSettingsActivity | Notifications | Bubbles for one app | DEEP-LINK |  | - | Interim deep link |
| 117 | `android.settings.APP_NOTIFICATION_SETTINGS` | - | Settings$AppNotificationSettingsActivity | Notifications | One app's notifications | IMPLEMENTED | YES | STATUS_BAR_SERVICE | Page appnotif/&lt;pkg&gt;: on/off, badge, categories |
| 118 | `android.settings.CHANNEL_NOTIFICATION_SETTINGS` | - | .notification.app.ChannelPanelActivity | Notifications | One notification category | IMPLEMENTED | YES | STATUS_BAR_SERVICE | Page channel/&lt;pkg&gt;/&lt;id&gt;: importance (locked like stock) |
| 119 | `android.settings.CONVERSATION_SETTINGS` | - | Settings$ConversationListSettingsActivity | Notifications | Conversations | DEEP-LINK |  | - | Interim deep link |
| 120 | `android.settings.NOTIFICATION_HISTORY` | - | .notification.history.NotificationHistoryActivity | Notifications | Notification history | DEEP-LINK |  | - | Interim deep link |
| 121 | `android.settings.NOTIFICATION_SETTINGS` | - | Settings$ConfigureNotificationSettingsActivity | Notifications | Notification settings | IMPLEMENTED | YES | STATUS_BAR_SERVICE, WRITE_SECURE_SETTINGS | Page notifications: app list, lock screen, dots, snooze, DND, listener access |
| 122 | `android.settings.ZEN_MODE_AUTOMATION_SETTINGS` | - | Settings$ZenModeAutomationSettingsActivity | Notifications | DND schedules | DEEP-LINK |  | - | Interim deep link |
| 123 | `android.settings.ZEN_MODE_EVENT_RULE_SETTINGS` | - | Settings$ZenModeEventRuleSettingsActivity | Notifications | DND event rule | DEEP-LINK |  | - | Interim deep link |
| 124 | `android.settings.ZEN_MODE_ONBOARDING` | - | .notification.zen.ZenOnboardingActivity | Notifications | DND first-run | DEEP-LINK |  | - | Interim deep link |
| 125 | `android.settings.ZEN_MODE_PRIORITY_SETTINGS` | - | Settings$ZenModeSettingsActivity | Notifications | DND priority | IMPLEMENTED |  | - | Page dnd; detailed exceptions stay stock |
| 126 | `android.settings.ZEN_MODE_SCHEDULE_RULE_SETTINGS` | - | Settings$ZenModeScheduleRuleSettingsActivity | Notifications | One DND schedule | DEEP-LINK |  | - | Interim deep link |
| 127 | `android.settings.ZEN_MODE_SETTINGS` | - | Settings$ZenModeSettingsActivity | Notifications | Do Not Disturb | IMPLEMENTED |  | STATUS_BAR_SERVICE | Page dnd (on/off, priority/alarms/silence) |
| 128 | `android.settings.ACTION_MEDIA_CONTROLS_SETTINGS` | - | Settings$MediaControlsSettingsActivity | Sound | Media controls in QS | DEEP-LINK |  | - | Interim deep link (MikuOS SystemUI owns media UI) |
| 129 | `android.settings.ACTION_OTHER_SOUND_SETTINGS` | - | Settings$SoundSettingsActivity | Sound | Other sounds | IMPLEMENTED |  | - | Page sound |
| 130 | `android.settings.AUDIO_SETTINGS` | - | Settings$AudioSettingsActivity | Sound | HiBy audio page | DONE |  | - | DAC & Audio screen |
| 131 | `android.settings.SOUND_SETTINGS` | - | Settings$SoundSettingsActivity | Sound | Volumes, ringtones, system sounds | IMPLEMENTED | YES | MODIFY_AUDIO_SETTINGS, WRITE_SETTINGS | Page sound + link to DAC page |
| 132 | `android.settings.WORK_MODE` | - | Settings$WorkModeSettingsActivity | Sound | HiBy work-mode page | DEEP-LINK |  | - | Interim deep link (HiBy feature) |
| 133 | `android.settings.audio.teen.switch` | - | .audio.teen.ui.TeenModeSwitchActivity | Sound | HiBy teen-mode volume limit | DEEP-LINK |  | - | Interim deep link (HiBy feature) |
| 134 | `android.settings.panel.action.VOLUME` | - | .panel.SettingsPanelActivity | Sound | Volume panel | IMPLEMENTED | YES | - | Page sound |
| 135 | `com.android.settings.SOUND_SETTINGS` | - | Settings$SoundSettingsActivity | Sound | Same | IMPLEMENTED |  | - | Page sound |
| 136 | `android.settings.ACTION_POWER_MENU_SETTINGS` | - | Settings$PowerMenuSettingsActivity | Display | Power menu options | DEEP-LINK |  | - | Interim deep link (MikuOS power menu is in SystemUI) |
| 137 | `android.settings.ADAPTIVE_BRIGHTNESS_SETTINGS` | - | Settings$AdaptiveBrightnessActivity | Display | Adaptive brightness | IMPLEMENTED |  | WRITE_SETTINGS | Page display_more (warns about MikuOS ambient service) |
| 138 | `android.settings.ASSIST_GESTURE_SETTINGS` | - | Settings$AssistGestureSettingsActivity | Display | Squeeze for assistant | NOT NEEDED |  | - | No such hardware |
| 139 | `android.settings.AUTO_ROTATE_SETTINGS` | - | Settings$SmartAutoRotateSettingsActivity | Display | Auto-rotate | IMPLEMENTED |  | WRITE_SETTINGS | Page display_more |
| 140 | `android.settings.COMMUNAL_SETTINGS` | - | Settings$CommunalSettingsActivity | Display | Hub mode | NOT NEEDED |  | - | Not used |
| 141 | `android.settings.DARK_THEME_SETTINGS` | - | Settings$DarkThemeSettingsActivity | Display | Dark theme | IMPLEMENTED |  | MODIFY_DAY_NIGHT_MODE | Page display_more (UiModeManager) |
| 142 | `android.settings.DISPLAY_SETTINGS` | - | Settings$DisplaySettingsActivity | Display | Display | DONE | YES | WRITE_SETTINGS | Display & Light screen; More display settings page added |
| 143 | `android.settings.DREAM_SETTINGS` | - | Settings$DreamSettingsActivity | Display | Screen saver | DEEP-LINK |  | - | Interim deep link |
| 144 | `android.settings.NIGHT_DISPLAY_SETTINGS` | - | Settings$NightDisplaySettingsActivity | Display | Night Light | IMPLEMENTED |  | CONTROL_DISPLAY_COLOR_TRANSFORMS | Page display_more (ColorDisplayManager) |
| 145 | `android.settings.WALLPAPER_SETTINGS` | - | .wallpaper.WallpaperSuggestionActivity | Display | Wallpaper | IMPLEMENTED |  | - | Hands off to ACTION_SET_WALLPAPER (launcher/picker) |
| 146 | `android.settings.action.ONE_HANDED_SETTINGS` | - | Settings$OneHandedSettingsActivity | Display | One-handed mode | NOT NEEDED |  | - | Small screen, not used |
| 147 | `com.android.settings.BUTTON_NAVIGATION_SETTINGS` | - | Settings$ButtonNavigationSettingsActivity | Display | Button navigation | DONE |  | - | Display & Light |
| 148 | `com.android.settings.DISPLAY_SETTINGS` | - | Settings$DisplaySettingsActivity | Display | Same | DONE |  | - | Display & Light screen |
| 149 | `com.android.settings.GESTURE_NAVIGATION_SETTINGS` | - | Settings$GestureNavigationSettingsActivity | Display | Gesture navigation | DONE |  | - | Display & Light |
| 150 | `com.android.settings.NAVIGATION_MODE_SETTINGS` | - | Settings$NavigationModeSettingsActivity | Display | Navigation mode | DONE |  | WRITE_SECURE_SETTINGS | Display & Light (navigation mode) |
| 151 | `com.android.settings.STYLUS_USI_DETAILS_SETTINGS` | - | Settings$StylusUsiDetailsActivity | Display | Stylus | NOT NEEDED |  | - | No stylus |
| 152 | `android.intent.action.POWER_USAGE_SUMMARY` | - | Settings$PowerUsageSummaryActivity | Battery | Battery usage | IMPLEMENTED |  | - | Battery screen; per-app history stays stock |
| 153 | `android.settings.BATTERY_SAVER_SETTINGS` | - | Settings$BatterySaverSettingsActivity | Battery | Battery Saver | IMPLEMENTED | YES | DEVICE_POWER, POWER_SAVER | Battery screen: telemetry (existing) + saver toggle, app battery list |
| 154 | `com.android.settings.BATTERY_SAVER_SCHEDULE_SETTINGS` | - | Settings$BatterySaverScheduleSettingsActivity | Battery | Saver schedule | DEEP-LINK |  | - | Interim deep link |
| 155 | `android.provider.action.DOCUMENT_ROOT_SETTINGS` | content, vnd.android.document/root | Settings$PublicVolumeSettingsActivity | Storage | Settings for a Files root (from Files app) | IMPLEMENTED |  | - | Page storage |
| 156 | `android.settings.INTERNAL_STORAGE_SETTINGS` | - | Settings$StorageDashboardActivity | Storage | Storage | IMPLEMENTED | YES | MOUNT_UNMOUNT_FILESYSTEMS, PACKAGE_USAGE_STATS | Page storage: volumes, used/free, SD eject/mount, apps, files |
| 157 | `android.settings.MEMORY_CARD_SETTINGS` | - | Settings$StorageDashboardActivity | Storage | SD card | IMPLEMENTED |  | - | Page storage; format/adopt stays stock |
| 158 | `android.settings.STORAGE_MANAGER_SETTINGS` | - | Settings$AutomaticStorageManagerSettingsActivity | Storage | Automatic storage manager | DEEP-LINK |  | - | Interim deep link |
| 159 | `android.settings.LOCATION_SCANNING_SETTINGS` | - | Settings$ScanningSettingsActivity | Location | Wi-Fi/BT scanning | IMPLEMENTED |  | WRITE_SECURE_SETTINGS | Page location |
| 160 | `android.settings.LOCATION_SOURCE_SETTINGS` | - | Settings$LocationSettingsActivity | Location | Location on/off | IMPLEMENTED | YES | WRITE_SECURE_SETTINGS | Page location (setLocationEnabledForUser) + permission link |
| 161 | `android.app.action.CONFIRM_DEVICE_CREDENTIAL` | - | .password.ConfirmDeviceCredentialActivity | Security | Confirm PIN/pattern for an app | STOCK ONLY | YES | - | Not mirrored: KeyguardManager picks the package by resolution; must stay stock |
| 162 | `android.app.action.CONFIRM_DEVICE_CREDENTIAL_WITH_USER` | - | .password.ConfirmDeviceCredentialActivity$InternalActivity | Security | Confirm for another user | STOCK ONLY |  | caller: MANAGE_USERS | Not exported |
| 163 | `android.app.action.CONFIRM_FRP_CREDENTIAL` | - | .password.ConfirmDeviceCredentialActivity | Security | Factory reset protection check | STOCK ONLY |  | - | Same |
| 164 | `android.app.action.CONFIRM_REMOTE_DEVICE_CREDENTIAL` | - | .ConfirmRemoteDeviceCredentialActivity | Security | Remote lock screen check | STOCK ONLY |  | caller: CHECK_REMOTE_LOCKSCREEN | Same |
| 165 | `android.app.action.SET_NEW_PARENT_PROFILE_PASSWORD` | - | .password.SetNewPasswordActivity | Security | Parent profile lock | STOCK ONLY |  | - | Same |
| 166 | `android.app.action.SET_NEW_PASSWORD` | - | .password.SetNewPasswordActivity | Security | Set screen lock (apps, DPC) | STOCK ONLY | YES | - | Not mirrored: reads launching app identity for complexity |
| 167 | `android.credentials.UNLOCK` | - | Settings$SecurityDashboardActivity | Security | Unlock credential storage | DEEP-LINK |  | - | Interim deep link |
| 168 | `android.security.MANAGE_CREDENTIALS` | - | .security.RequestManageCredentials | Security | App asks to manage credentials | STOCK ONLY |  | - | Not mirrored: reads launching app identity |
| 169 | `android.settings.ADVANCED_MEMORY_PROTECTION_SETTINGS` | - | Settings$MemtagPageActivity | Security | Memory tagging | NOT NEEDED |  | - | No MTE on SM6225 |
| 170 | `android.settings.BIOMETRIC_ENROLL` | - | .biometrics.BiometricEnrollActivity | Security | Enroll biometric | NOT NEEDED |  | - | No sensor |
| 171 | `android.settings.ENTERPRISE_PRIVACY_SETTINGS` | - | Settings$EnterprisePrivacySettingsActivity | Security | Managed device info | NOT NEEDED |  | - | No device management |
| 172 | `android.settings.FACE_ENROLL` | - | .biometrics.face.FaceEnrollIntroduction | Security | Enroll face | NOT NEEDED |  | - | No sensor |
| 173 | `android.settings.FACE_SETTINGS` | - | Settings$FaceSettingsActivity | Security | Face unlock | NOT NEEDED |  | - | No face sensor |
| 174 | `android.settings.FINGERPRINT_ENROLL` | - | .biometrics.fingerprint.FingerprintEnrollIntroduction | Security | Enroll fingerprint | NOT NEEDED |  | - | No sensor |
| 175 | `android.settings.FINGERPRINT_SETTINGS` | - | Settings$FingerprintSettingsActivity | Security | Fingerprint | NOT NEEDED |  | - | No fingerprint sensor |
| 176 | `android.settings.FINGERPRINT_SETUP` | - | .biometrics.fingerprint.SetupFingerprintEnrollIntroduction | Security | Setup fingerprint | NOT NEEDED |  | caller: MANAGE_FINGERPRINT | No sensor |
| 177 | `android.settings.LOCK_SCREEN_SETTINGS` | - | Settings$LockScreenSettingsActivity | Security | Lock screen | IMPLEMENTED | YES | - | Page security; lock setup hands off to SET_NEW_PASSWORD (stock ChooseLockGeneric is not exported) |
| 178 | `android.settings.MANAGED_PROFILE_SETTINGS` | - | Settings$ManagedProfileSettingsActivity | Security | Work profile | NOT NEEDED |  | caller: MANAGE_USERS | No work profile |
| 179 | `android.settings.SECURITY_SETTINGS` | - | Settings$SecurityDashboardActivity | Security | Security | IMPLEMENTED | YES | - | Page security: lock status, encryption, patch, permission manager, app pinning |
| 180 | `android.settings.SHOW_ADMIN_SUPPORT_DETAILS` | - | .enterprise.ActionDisabledByAdminDialog | Security | "Blocked by your admin" dialog | DEEP-LINK |  | - | Interim deep link |
| 181 | `android.settings.SHOW_REMOTE_BUGREPORT_DIALOG` | - | .RemoteBugreportActivity | Security | Admin bug report request | NOT NEEDED |  | caller: DUMP | No device management |
| 182 | `android.settings.SHOW_RESTRICTED_SETTING_DIALOG` | - | .ActionDisabledByAppOpsDialog | Security | Restricted setting dialog for sideloaded apps | DEEP-LINK |  | - | Interim deep link. MikuOS pages write the settings directly, so they do not hit this gate |
| 183 | `android.settings.WORK_MODE_VIEW` | - | .connecteddevice.WorkModeActivity | Security | Work apps toggle | NOT NEEDED |  | - | No work profile |
| 184 | `com.android.credentials.INSTALL` | - | .security.CredentialStorage | Security | Install certificate | STOCK ONLY |  | - | Not mirrored: keystore work runs as uid system |
| 185 | `com.android.credentials.RESET` | - | .security.CredentialStorage | Security | Clear credentials | STOCK ONLY |  | - | Same |
| 186 | `com.android.settings.MONITORING_CERT_INFO` | - | .MonitoringCertInfoActivity | Security | "Network may be monitored" CA notice | DEEP-LINK |  | - | Interim deep link (CertificateMonitor sends this) |
| 187 | `com.android.settings.MORE_SECURITY_PRIVACY_SETTINGS` | - | Settings$MoreSecurityPrivacySettingsActivity | Security | More security and privacy | IMPLEMENTED |  | - | Page security |
| 188 | `com.android.settings.SETUP_LOCK_SCREEN` | - | .password.SetupChooseLockGeneric | Security | Setup wizard lock step | STOCK ONLY |  | - | Setup wizard removed |
| 189 | `com.android.settings.TRUSTED_CREDENTIALS` | - | Settings$TrustedCredentialsSettingsActivity | Security | Trusted CA list | DEEP-LINK |  | - | Interim deep link |
| 190 | `com.android.settings.TRUSTED_CREDENTIALS_USER` | - | Settings$TrustedCredentialsSettingsActivity | Security | User CA list | DEEP-LINK |  | - | Interim deep link |
| 191 | `com.android.settings.security.SECURITY_ADVANCED_SETTINGS` | - | Settings$SecurityAdvancedSettings | Security | More security | IMPLEMENTED |  | - | Page security |
| 192 | `android.settings.PRIVACY_ADVANCED_SETTINGS` | - | Settings$MoreSecurityPrivacySettingsActivity | Privacy | Advanced privacy | IMPLEMENTED |  | - | Page security |
| 193 | `android.settings.PRIVACY_CONTROLS` | - | Settings$PrivacyControlsActivity | Privacy | Privacy controls | IMPLEMENTED |  | - | Page security |
| 194 | `android.settings.PRIVACY_SETTINGS` | - | Settings$PrivacyDashboardActivity | Privacy | Privacy | IMPLEMENTED |  | - | Page security |
| 195 | `android.settings.REQUEST_ENABLE_CONTENT_CAPTURE` | - | Settings$PrivacyDashboardActivity | Privacy | Content capture opt-in | DEEP-LINK |  | - | Interim deep link |
| 196 | `android.settings.ACCESSIBILITY_COLOR_MOTION_SETTINGS` | - | Settings$ColorAndMotionActivity | Accessibility | Color and motion | IMPLEMENTED |  | - | Page a11y |
| 197 | `android.settings.ACCESSIBILITY_DETAILS_SETTINGS` | - | Settings$AccessibilityDetailsSettingsActivity | Accessibility | One accessibility service | IMPLEMENTED | YES | caller: OPEN_ACCESSIBILITY_DETAILS_SETTINGS | Page a11y/&lt;component&gt; with full-control warning |
| 198 | `android.settings.ACCESSIBILITY_SETTINGS` | - | Settings$AccessibilitySettingsActivity | Accessibility | Accessibility | IMPLEMENTED | YES | WRITE_SECURE_SETTINGS | Page a11y: services, inversion, color correction, contrast, extra dim, animations, magnification, captions, mono |
| 199 | `android.settings.ACCESSIBILITY_SETTINGS_FOR_SUW` | - | .accessibility.AccessibilitySettingsForSetupWizardActivity | Accessibility | Setup wizard accessibility | IMPLEMENTED |  | - | Page a11y |
| 200 | `android.settings.CAPTIONING_SETTINGS` | - | Settings$CaptioningSettingsActivity | Accessibility | Captions | IMPLEMENTED |  | - | Page a11y (on/off; caption style stays stock) |
| 201 | `android.settings.COLOR_INVERSION_SETTINGS` | - | Settings$AccessibilityInversionSettingsActivity | Accessibility | Color inversion | IMPLEMENTED |  | - | Page a11y |
| 202 | `android.settings.REDUCE_BRIGHT_COLORS_SETTINGS` | - | Settings$ReduceBrightColorsSettingsActivity | Accessibility | Extra dim | IMPLEMENTED |  | - | Page a11y |
| 203 | `android.settings.TEXT_READING_SETTINGS` | - | Settings$TextReadingSettingsActivity | Accessibility | Text size and display size | IMPLEMENTED |  | - | Page a11y, links to Display & Light |
| 204 | `com.android.settings.ACCESSIBILITY_COLOR_SPACE_SETTINGS` | - | Settings$AccessibilityDaltonizerSettingsActivity | Accessibility | Color correction | IMPLEMENTED |  | - | Page a11y |
| 205 | `com.android.settings.TTS_SETTINGS` | - | Settings$TextToSpeechSettingsActivity | Accessibility | Text-to-speech | DEEP-LINK |  | - | Interim deep link |
| 206 | `android.settings.ACCOUNT_SYNC_SETTINGS` | - | Settings$AccountSyncSettingsActivity | System | One account's sync | DEEP-LINK |  | - | Interim deep link (remove account needs uid system) |
| 207 | `android.settings.ADD_ACCOUNT_SETTINGS` | - | .accounts.AddAccountSettings | System | Add account (Play Store, setup) | IMPLEMENTED | YES | - | Page accounts_add; honors account_types; RESULT_OK on add |
| 208 | `android.settings.APPLICATION_DEVELOPMENT_SETTINGS` | - | Settings$DevelopmentSettingsDashboardActivity, .development.DevelopmentSettingsDisabledActivity | System | Developer options | IMPLEMENTED | YES | WRITE_SECURE_SETTINGS, MANAGE_DEBUGGING, SET_ALWAYS_FINISH | Page developer: dev toggle, USB/wireless debugging, revoke keys, stay awake, taps, pointer, animation scales, don't keep activities |
| 209 | `android.settings.BUGREPORT_HANDLER_SETTINGS` | - | Settings$BugReportHandlerPickerActivity | System | Bug report handler | DEEP-LINK |  | - | Interim deep link |
| 210 | `android.settings.DATE_SETTINGS` | - | Settings$DateTimeSettingsActivity | System | Date, time, time zone, 24-hour | IMPLEMENTED | YES | SET_TIME, SET_TIME_ZONE | Page datetime (AlarmManager.setTime/setTimeZone) |
| 211 | `android.settings.HARD_KEYBOARD_SETTINGS` | - | Settings$PhysicalKeyboardActivity | System | Physical keyboard | IMPLEMENTED |  | - | Page keyboard; layouts stay stock |
| 212 | `android.settings.INPUT_METHOD_SETTINGS` | - | Settings$AvailableVirtualKeyboardActivity | System | On-screen keyboards | IMPLEMENTED | YES | WRITE_SECURE_SETTINGS | Page keyboard: enable/disable IMEs, switch, IME settings |
| 213 | `android.settings.INPUT_METHOD_SUBTYPE_SETTINGS` | - | .inputmethod.InputMethodAndSubtypeEnablerActivity | System | Keyboard languages | IMPLEMENTED |  | - | Page keyboard (subtypes via the IME's own settings) |
| 214 | `android.settings.LANGUAGE_SETTINGS` | - | Settings$LanguageAndInputSettingsActivity, Settings$LanguageSettingsActivity | System | Languages & input | IMPLEMENTED |  | CHANGE_CONFIGURATION | Page languages |
| 215 | `android.settings.LOCALE_SETTINGS` | - | Settings$LocalePickerActivity | System | System language | IMPLEMENTED | YES | CHANGE_CONFIGURATION | Page languages (LocalePicker.updateLocales) |
| 216 | `android.settings.REGIONAL_PREFERENCES_SETTINGS` | - | Settings$RegionalPreferencesActivity | System | Units, first day of week | DEEP-LINK |  | - | Interim deep link |
| 217 | `android.settings.SYNC_SETTINGS` | - | Settings$AccountDashboardActivity | System | Accounts and sync | IMPLEMENTED |  | GET_ACCOUNTS_PRIVILEGED, WRITE_SYNC_SETTINGS | Page accounts: list, add, master sync. Per-account sync/remove stays stock |
| 218 | `android.settings.USER_DICTIONARY_SETTINGS` | - | Settings$UserDictionarySettingsActivity | System | Personal dictionary | DEEP-LINK |  | - | Interim deep link |
| 219 | `android.settings.USER_SETTINGS` | - | Settings$UserSettingsActivity | System | Users | IMPLEMENTED | YES | MANAGE_USERS | Page users (list); add user/guest stays stock |
| 220 | `android.settings.WEBVIEW_SETTINGS` | - | .WebViewImplementation | System | WebView implementation | DEEP-LINK |  | - | Interim deep link |
| 221 | `android.settings.development.START_DSU_LOADER` | - | .development.DSULoader | System | Dynamic system update loader | NOT NEEDED |  | - | Not used |
| 222 | `com.android.settings.APPLICATION_DEVELOPMENT_SETTINGS` | - | Settings$DevelopmentSettingsDashboardActivity, .development.DevelopmentSettingsDisabledActivity | System | Same | IMPLEMENTED |  | - | Page developer |
| 223 | `com.android.settings.USER_DICTIONARY_INSERT` | - | .inputmethod.UserDictionaryAddWordActivity | System | Add word (framework sends this) | DEEP-LINK |  | - | Interim deep link |
| 224 | `com.android.settings.action.FACTORY_RESET` | - | Settings$FactoryResetActivity | System | Factory reset | IMPLEMENTED | YES | caller: BACKUP | Page reset: network reset + erase all (FRP block wipe as stock, then ACTION_FACTORY_RESET) |
| 225 | `android.settings.CERTIFICATE_HIBY` | - | .SettingsCertificateActivity | About | HiBy certification images | DEEP-LINK |  | - | Interim deep link |
| 226 | `android.settings.DEVICE_INFO_SETTINGS` | - | Settings$MyDeviceInfoActivity, .deviceinfo.AboutHiByActivity | About | About device | DONE | YES | - | About MikuOS screen; legal links added |
| 227 | `android.settings.DEVICE_NAME` | - | Settings$MyDeviceInfoActivity, .deviceinfo.AboutHiByActivity | About | Device name | DONE |  | - | About screen (Bluetooth name in Connection preferences) |
| 228 | `android.settings.HIBY_SETTINGS_ABOUT` | - | .deviceinfo.AboutHiByActivity | About | HiBy about page | DONE |  | - | About MikuOS screen |
| 229 | `android.settings.LICENSE` | - | .SettingsLicenseActivity | About | Open source licenses | DEEP-LINK |  | - | Interim deep link (About links to it) |
| 230 | `android.settings.MODULE_LICENSES` | - | Settings$ModuleLicensesActivity | About | Mainline module licenses | DEEP-LINK |  | - | Interim deep link |
| 231 | `android.settings.SHOW_MANUAL` | - | .ManualDisplayActivity | About | Manual | DEEP-LINK |  | - | Interim deep link |
| 232 | `android.settings.SHOW_REGULATORY_INFO` | - | .RegulatoryInfoDisplayActivity | About | Regulatory labels | DEEP-LINK |  | - | Interim deep link |
| 233 | `com.android.settings.ANDROID_VERSION_SETTINGS` | - | Settings$AndroidVersionSettingsActivity | About | Android version | DONE |  | - | About MikuOS screen |
| 234 | `com.android.settings.action.SUPPORT_SETTINGS` | - | .support.SupportDashboardActivity | About | Support | NOT NEEDED |  | - | Not used |
| 235 | `android.intent.action.VIEW` | HiByTeenMode, settings, vnd.android.cursor.item/telephony-carrier | .slices.SliceDeepLinkSpringBoard, Settings$ApnEditorActivity, .audio.teen.ui.TeenModeSwitchActivity | Mixed | APN editor (typed data), HiBy teen mode (HiByTeenMode:), stock slices (settings://, not mirrored) | DEEP-LINK |  | caller: MODIFY_PHONE_STATE | Interim deep link |
| 236 | `android.settings.VOICE_CONTROL_AIRPLANE_MODE` | - | .AirplaneModeVoiceActivity | Voice | Voice-assistant airplane toggle | NOT NEEDED |  | - | Voice interaction filters not mirrored; no voice assistant |
| 237 | `android.settings.VOICE_CONTROL_BATTERY_SAVER_MODE` | - | .fuelgauge.BatterySaverModeVoiceActivity | Voice | Voice-assistant saver toggle | NOT NEEDED |  | - | Same |
| 238 | `android.settings.VOICE_CONTROL_DO_NOT_DISTURB_MODE` | - | .notification.zen.ZenModeVoiceActivity | Voice | Voice-assistant DND toggle | NOT NEEDED |  | - | Same |
| 239 | `android.intent.action.CREATE_SHORTCUT` | - | Settings$CreateShortcutActivity | Internal | Offers stock pages as launcher shortcuts | STOCK ONLY |  | - | Stock-only feature |
| 240 | `android.intent.action.QUICK_CLOCK` | - | Settings$DateTimeSettingsActivity | Internal | Voice launch alias for date and time | STOCK ONLY |  | - | Voice-launch alias |
| 241 | `android.service.quicksettings.action.QS_TILE_PREFERENCES` | - | Settings$DevelopmentSettingsDashboardActivity | Internal | Long-press target for developer QS tiles | STOCK ONLY |  | - | Stock developer tiles only |
| 242 | `android.settings.SETTINGS_EMBED_DEEP_LINK_ACTIVITY` | - | .homepage.DeepLinkHomepageActivity | Internal | Two-pane deep link host (disabled in stock) | STOCK ONLY |  | caller: LAUNCH_MULTI_PANE_SETTINGS_DEEP_LINK | Internal to stock |
| 243 | `com.android.intent.action.SHOW_CONTRAST_DIALOG` | - | Settings$DevelopmentSettingsDashboardActivity | Internal | Contrast dialog from stock QS | STOCK ONLY |  | - | Stock only |
| 244 | `com.android.settings.SEARCH_RESULT_TRAMPOLINE` | - | .search.SearchResultTrampoline | Internal | Stock search result hop | STOCK ONLY |  | - | Internal to stock |
| 245 | `com.android.settings.action.IA_SETTINGS` | - | .backup.UserBackupSettingsActivity | Internal | Tile injection (MikuOS injects its own tile here) | STOCK ONLY |  | - | MikuSettingsActivity already declares it |
| 246 | `com.android.settings.action.SETTINGS` | - | Settings$AudioSettingsActivity, Settings$SMQQtiFeedbackActivity, Settings$DevelopmentSettingsDashboardActivity, Settings$UserSettingsActivity, .deviceinfo.AboutHiByActivity, Settings$WorkModeSettingsActivity | Internal | Tile injection query action | STOCK ONLY |  | - | Not an entry point |

## 5. Beyond activities: receivers, providers, services and hardcoded references

| Item | Who uses it | Status after stock removal | What to do |
|---|---|---|---|
| `BluetoothPairingRequest` receiver (`PAIRING_REQUEST`) | Bluetooth stack. `BondStateMachine.sendDisplayPinIntent` sends an implicit ordered broadcast with `FLAG_RECEIVER_INCLUDE_BACKGROUND` and `BLUETOOTH_CONNECT` (checked in this device's Bluetooth.apk) | IMPLEMENTED. `dialogs.PairingRequestReceiver` at priority 1000 shows the MikuOS dialog and aborts the broadcast so the stock dialog does not also open. Pairing started from the MikuOS Bluetooth page keeps its old auto-confirm for "just works" and numeric comparison | Verify on device (section 8) |
| `BluetoothPermissionRequest` receiver (`CONNECTION_ACCESS_REQUEST`) | Bluetooth MAP/PBAP/SAP. Bluetooth.apk sends it with `setPackage(<string pairing_ui_package>)`, value `com.android.settings` | Unanswered requests time out and are denied | Low impact (no phonebook on a DAP; car kits may ask). Fix later with an RRO on `com.android.bluetooth` overriding `string/pairing_ui_package` to `com.miku.settings` plus a receiver |
| `FallbackHome` (HOME, priority -1000, direct boot aware) | ActivityTaskManager while user storage is locked | IMPLEMENTED as `home.MikuFallbackHome`, shipped disabled. `syncWithStock` enables it on BOOT_COMPLETED when stock's is missing or disabled; it takes effect the boot after. Two enabled copies would put a chooser on the boot screen, which is why it is not simply enabled | After removal, reboot twice and confirm the launcher comes up |
| `UsbDeviceManager` | Hardcodes `com.android.settings/.Settings$UsbDetailsActivity` (permission `MANAGE_USB`) as the tap target of the USB notification | Tapping the USB notification does nothing | USB mode is on the MikuOS Connection preferences page. Optionally have MikuOS SystemUI handle the tap |
| `LingerMonitor` (service-connectivity) | Hardcodes `Settings$DataUsageSummaryActivity` for the "switched to mobile data" notification | Tap does nothing | Low impact |
| `CertificateMonitor` | Sends `com.android.settings.MONITORING_CERT_INFO` (implicit) when a user CA is installed | DEEP-LINK today; unavailable page after removal | Rebuild if user CAs are used |
| `KeyguardManager.createConfirmDeviceCredentialIntent` | Resolves `CONFIRM_DEVICE_CREDENTIAL` by package; falls back to `com.android.settings` | STOCK ONLY | Required while any screen lock exists. MikuOS disables the lock screen at boot, so this only matters if a user sets a PIN |
| `KeyChain` | `setPackage("com.android.settings")` for `MANAGE_CREDENTIALS` | STOCK ONLY | Rare (enterprise apps) |
| `BiometricNotificationUtils` | `setPackage("com.android.settings")` for re-enroll notifications | Not reachable: no biometric hardware | None |
| `ProcessList`, `UriGrantsManagerService`, `PreBootBroadcaster`, `DisplayPolicy` | Name `com.android.settings`, its file/license authorities, `HelpTrampoline`, and a HiBy teen-mode package check | Harmless when missing | None |
| Providers: slices, search indexables, battery usage, contextual cards, suggestions | Stock panels, SettingsIntelligence search, stock homepage | Only stock-internal consumers found | Check logcat for failed provider lookups after hiding |
| Services: `TetherService`, developer QS tiles | Tethering entitlement re-checks when the carrier requires them; stock developer tiles | TetherService matters only if Google Fi's carrier config requires tethering entitlement | Test hotspot on Fi before removal |
| Receivers: `SettingsInitialize`, SIM, battery usage, anomaly, safety center | Stock housekeeping | Nothing else depends on them | None |

Other MikuOS modules (read only, not changed here):

- `mikuos-launcher` already hides `com.android.settings` from the app drawer (`blacklistedPackages`) and maps its icon to the Miku settings icon.
- `app` (Miku Music) has an "Open Stock Android Settings" row that uses `getLaunchIntentForPackage("com.android.settings")`; it breaks when the stock launcher alias is disabled and should point at `com.miku.settings`.
- `hardware-settings` reads `fn_function_title`/`fn_function_value` arrays from `com.android.settings` resources (logging only).
- `app` sends `com.android.settings.action.MAX_VOLUME_CHANGED`; no stock Settings receiver declares it.
- `mikuos-systemui` opens `MANAGE_OVERLAY_PERMISSION`, `ACCESSIBILITY_SETTINGS` and `ACTION_NOTIFICATION_LISTENER_SETTINGS` implicitly; all three are IMPLEMENTED.

## 6. Permissions

MikuSettings is platform-signed, so every signature-level permission below is granted today from `/system/app`. The manifest now requests: `NETWORK_SETTINGS`, `NETWORK_STACK`, `NETWORK_AIRPLANE_MODE`, `OVERRIDE_WIFI_CONFIG`, `TETHER_PRIVILEGED`, `MANAGE_USB`, `READ_PRIVILEGED_PHONE_STATE`, `READ_PHONE_NUMBERS`, `PACKAGE_USAGE_STATS`, `READ_NETWORK_USAGE_HISTORY`, `MANAGE_NETWORK_POLICY`, `FORCE_STOP_PACKAGES`, `CLEAR_APP_USER_DATA`, `DELETE_CACHE_FILES`, `CHANGE_COMPONENT_ENABLED_STATE`, `REQUEST_DELETE_PACKAGES`, `QUERY_ALL_PACKAGES`, `GRANT_RUNTIME_PERMISSIONS`, `MANAGE_ROLE_HOLDERS`, `MANAGE_APP_OPS_MODES`, `GET_APP_OPS_STATS`, `UPDATE_APP_OPS_STATS`, `MANAGE_NOTIFICATION_LISTENERS`, `STATUS_BAR_SERVICE`, `MANAGE_NOTIFICATIONS`, `ACCESS_NOTIFICATION_POLICY`, `MANAGE_DEVICE_ADMINS`, `BIND_APPWIDGET`, `MODIFY_APPWIDGET_BIND_PERMISSIONS`, `SET_TIME`, `SET_TIME_ZONE`, `SUGGEST_MANUAL_TIME_AND_ZONE`, `MODIFY_DAY_NIGHT_MODE`, `CONTROL_DISPLAY_COLOR_TRANSFORMS`, `MOUNT_UNMOUNT_FILESYSTEMS`, `GET_ACCOUNTS_PRIVILEGED`, `GET_ACCOUNTS`, `READ_SYNC_SETTINGS`, `WRITE_SYNC_SETTINGS`, `MASTER_CLEAR`, `ACCESS_PDB_STATE`, `CONTROL_ALWAYS_ON_VPN`, `CONTROL_VPN`, `SET_PREFERRED_APPLICATIONS`, `START_ACTIVITIES_FROM_BACKGROUND`, `SET_ALWAYS_FINISH`, `BACKUP`, `DUMP`, `MANAGE_FINGERPRINT`, `OPEN_ACCESSIBILITY_DETAILS_SETTINGS`, `INTERNAL_SYSTEM_WINDOW`, `UPDATE_DOMAIN_VERIFICATION_USER_SELECTION`, `POWER_SAVER`, `READ_APP_SPECIFIC_LOCALES`, `LOCAL_MAC_ADDRESS`, `INTERACT_ACROSS_USERS`, `VIBRATE`, `NFC`, on top of the existing set. Several of these (`BACKUP`, `DUMP`, `MANAGE_FINGERPRINT`, `INTERNAL_SYSTEM_WINDOW`, `OPEN_ACCESSIBILITY_DETAILS_SETTINGS`, `NETWORK_STACK`) are only there so the router may forward to the stock pages guarded by them.

Privileged allowlist. These are the 37 requested permissions whose protection level on this build's `framework-res.apk` has the privileged flag. They are now in the `com.miku.settings` block of `mikuos/build/permissions/privapp-permissions-mikuos.xml` (the file `PERMISSIONS_XML` in `build_mikuos_super.sh` writes to system, system_ext and product). The four entries that were already there and are not privileged (`NETWORK_SETTINGS`, `DEVICE_POWER`, `INTERACT_ACROSS_USERS_FULL`, `MODIFY_AUDIO_SETTINGS`) were kept.

```xml
<privapp-permissions package="com.miku.settings">
    <permission name="android.permission.BLUETOOTH_PRIVILEGED"/>
    <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
    <permission name="android.permission.MODIFY_PHONE_STATE"/>
    <permission name="android.permission.STATUS_BAR"/>
    <permission name="android.permission.REBOOT"/>
    <permission name="android.permission.MANAGE_USERS"/>
    <permission name="android.permission.MANAGE_DEBUGGING"/>
    <permission name="android.permission.INTERACT_ACROSS_USERS"/>
    <permission name="android.permission.CHANGE_CONFIGURATION"/>
    <permission name="android.permission.OVERRIDE_WIFI_CONFIG"/>
    <permission name="android.permission.TETHER_PRIVILEGED"/>
    <permission name="android.permission.MANAGE_USB"/>
    <permission name="android.permission.READ_PRIVILEGED_PHONE_STATE"/>
    <permission name="android.permission.PACKAGE_USAGE_STATS"/>
    <permission name="android.permission.READ_NETWORK_USAGE_HISTORY"/>
    <permission name="android.permission.FORCE_STOP_PACKAGES"/>
    <permission name="android.permission.DELETE_CACHE_FILES"/>
    <permission name="android.permission.CHANGE_COMPONENT_ENABLED_STATE"/>
    <permission name="android.permission.GET_APP_OPS_STATS"/>
    <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
    <permission name="android.permission.BIND_APPWIDGET"/>
    <permission name="android.permission.MODIFY_APPWIDGET_BIND_PERMISSIONS"/>
    <permission name="android.permission.SET_TIME"/>
    <permission name="android.permission.SET_TIME_ZONE"/>
    <permission name="android.permission.MODIFY_DAY_NIGHT_MODE"/>
    <permission name="android.permission.CONTROL_DISPLAY_COLOR_TRANSFORMS"/>
    <permission name="android.permission.MOUNT_UNMOUNT_FILESYSTEMS"/>
    <permission name="android.permission.GET_ACCOUNTS_PRIVILEGED"/>
    <permission name="android.permission.MASTER_CLEAR"/>
    <permission name="android.permission.CONTROL_VPN"/>
    <permission name="android.permission.START_ACTIVITIES_FROM_BACKGROUND"/>
    <permission name="android.permission.SET_ALWAYS_FINISH"/>
    <permission name="android.permission.BACKUP"/>
    <permission name="android.permission.DUMP"/>
    <permission name="android.permission.MANAGE_FINGERPRINT"/>
    <permission name="android.permission.POWER_SAVER"/>
    <permission name="android.permission.LOCAL_MAC_ADDRESS"/>
</privapp-permissions>
```

Rule for future edits: any new `uses-permission` in `mikuos-settings` must be checked against `framework-res` (privileged flag 0x10 in `protectionLevel`) and added here before the app is a priv-app, or the device will not boot.

## 7. Hiding stock Settings without deleting it

Recommended, in this order. None of it is applied by this change.

1. **Hide only the launcher entry.** `com.android.settings/.Settings` is an activity-alias (MAIN/LAUNCHER) whose target is `SettingsHomepageActivity`. Disabling the alias removes the icon and nothing else; every deep link, dialog and FallbackHome keeps working. Add next to the other `exec_background - system system --` lines in the init block of `build_mikuos_super.sh`:

   ```
   exec_background - system system -- /system/bin/cmd package disable com.android.settings/.Settings
   ```

   The state is stored in `/data/system/users/0/package-restrictions.xml` and survives reboots; running it every boot is harmless. Do not use `pm disable-user com.android.settings` (whole package): it kills every deep link, the pairing fallback, credential confirm and FallbackHome. An RRO cannot do this (manifests are not overlayable). Miku Music's "Open Stock Android Settings" row will stop working after this.
2. **Move MikuSettings to `/system/priv-app`** (section 2, item 3). From then on every mirrored action resolves to MikuSettings without a chooser, and stock pages are only reached through MikuOS deep links.
3. **If MikuSettings has to stay in `/system/app`**, the priority-1 stock filters can only be beaten by disabling the stock components. These stock activities serve only actions that are DONE, IMPLEMENTED or NOT NEEDED, so no MikuOS deep link points at them and they can be disabled the same way (`cmd package disable com.android.settings/<class>`):

   - `.AllowBindAppWidgetActivity`
   - `.AppManageFullScreenIntent`
   - `.RemoteBugreportActivity`
   - `.Settings$AccessibilityDaltonizerSettingsActivity`
   - `.Settings$AccessibilityDetailsSettingsActivity`
   - `.Settings$AccessibilityInversionSettingsActivity`
   - `.Settings$AccessibilitySettingsActivity`
   - `.Settings$AdaptiveBrightnessActivity`
   - `.Settings$AdvancedConnectedDeviceActivity`
   - `.Settings$AlarmsAndRemindersActivity`
   - `.Settings$AlarmsAndRemindersAppActivity`
   - `.Settings$AndroidBeamSettingsActivity`
   - `.Settings$AndroidVersionSettingsActivity`
   - `.Settings$AppDrawOverlaySettingsActivity`
   - `.Settings$AppInteractAcrossProfilesSettingsActivity`
   - `.Settings$AppManageExternalStorageActivity`
   - `.Settings$AppMediaManagementAppsActivity`
   - `.Settings$AppNotificationSettingsActivity`
   - `.Settings$AppPictureInPictureSettingsActivity`
   - `.Settings$AppTurnScreenOnSettingsActivity`
   - `.Settings$AppUsageAccessSettingsActivity`
   - `.Settings$AppWriteSettingsActivity`
   - `.Settings$AssistGestureSettingsActivity`
   - `.Settings$AudioSettingsActivity`
   - `.Settings$AvailableVirtualKeyboardActivity`
   - `.Settings$BatterySaverSettingsActivity`
   - `.Settings$BlueToothNewSettingsActivity`
   - `.Settings$BlueToothPairingActivity`
   - `.Settings$BluetoothDeviceDetailActivity`
   - `.Settings$ButtonNavigationSettingsActivity`
   - `.Settings$CaptioningSettingsActivity`
   - `.Settings$ClonedAppsListActivity`
   - `.Settings$ColorAndMotionActivity`
   - `.Settings$CommunalSettingsActivity`
   - `.Settings$ConfigureNotificationSettingsActivity`
   - `.Settings$ConnectedDeviceDashboardActivity`
   - `.Settings$DarkThemeSettingsActivity`
   - `.Settings$DataSaverSummaryActivity`
   - `.Settings$DateTimeSettingsActivity`
   - `.Settings$DisplaySettingsActivity`
   - `.Settings$EnterprisePrivacySettingsActivity`
   - `.Settings$FaceSettingsActivity`
   - `.Settings$FactoryResetActivity`
   - `.Settings$FingerprintSettingsActivity`
   - `.Settings$GestureNavigationSettingsActivity`
   - `.Settings$HighPowerApplicationsActivity`
   - `.Settings$InteractAcrossProfilesSettingsActivity`
   - `.Settings$LanguageAndInputSettingsActivity`
   - `.Settings$LanguageSettingsActivity`
   - `.Settings$LocalePickerActivity`
   - `.Settings$LocationSettingsActivity`
   - `.Settings$LockScreenSettingsActivity`
   - `.Settings$LongBackgroundTasksActivity`
   - `.Settings$LongBackgroundTasksAppActivity`
   - `.Settings$ManageAppExternalSourcesActivity`
   - `.Settings$ManageApplicationsActivity`
   - `.Settings$ManageAssistActivity`
   - `.Settings$ManageDomainUrlsActivity`
   - `.Settings$ManageExternalSourcesActivity`
   - `.Settings$ManageExternalStorageActivity`
   - `.Settings$ManagedProfileSettingsActivity`
   - `.Settings$MediaManagementAppsActivity`
   - `.Settings$MemtagPageActivity`
   - `.Settings$MobileDataUsageListActivity`
   - `.Settings$MobileNetworkListActivity`
   - `.Settings$MoreSecurityPrivacySettingsActivity`
   - `.Settings$MyDeviceInfoActivity`
   - `.Settings$NavigationModeSettingsActivity`
   - `.Settings$NetworkDashboardActivity`
   - `.Settings$NetworkProviderSettingsActivity`
   - `.Settings$NfcSettingsActivity`
   - `.Settings$NightDisplaySettingsActivity`
   - `.Settings$NotificationAccessDetailsActivity`
   - `.Settings$NotificationAccessSettingsActivity`
   - `.Settings$NotificationAppListActivity`
   - `.Settings$OneHandedSettingsActivity`
   - `.Settings$OverlaySettingsActivity`
   - `.Settings$PictureInPictureSettingsActivity`
   - `.Settings$PrivacyControlsActivity`
   - `.Settings$PublicVolumeSettingsActivity`
   - `.Settings$ReduceBrightColorsSettingsActivity`
   - `.Settings$SavedAccessPointsSettingsActivity`
   - `.Settings$ScanningSettingsActivity`
   - `.Settings$SecurityAdvancedSettings`
   - `.Settings$SmartAutoRotateSettingsActivity`
   - `.Settings$SoundSettingsActivity`
   - `.Settings$StorageUseActivity`
   - `.Settings$StylusUsiDetailsActivity`
   - `.Settings$TetherSettingsActivity`
   - `.Settings$TextReadingSettingsActivity`
   - `.Settings$TurnScreenOnSettingsActivity`
   - `.Settings$UsageAccessSettingsActivity`
   - `.Settings$VrListenersSettingsActivity`
   - `.Settings$WifiCallingSettingsActivity`
   - `.Settings$WifiDetailsSettingsActivity`
   - `.Settings$WifiScanningSettingsActivity`
   - `.Settings$WifiTetherSettingsActivity`
   - `.Settings$WriteSettingsActivity`
   - `.Settings$ZenAccessDetailSettingsActivity`
   - `.Settings$ZenAccessSettingsActivity`
   - `.accessibility.AccessibilitySettingsForSetupWizardActivity`
   - `.accounts.AddAccountSettings`
   - `.applications.InstalledAppDetails`
   - `.applications.InstalledAppOpenByDefaultActivity`
   - `.applications.specialaccess.deviceadmin.DeviceAdminAdd`
   - `.biometrics.BiometricEnrollActivity`
   - `.biometrics.face.FaceEnrollIntroduction`
   - `.biometrics.fingerprint.FingerprintEnrollIntroduction`
   - `.biometrics.fingerprint.SetupFingerprintEnrollIntroduction`
   - `.bluetooth.BluetoothPairingDialog`
   - `.bluetooth.RequestPermissionActivity`
   - `.connecteddevice.WorkModeActivity`
   - `.datausage.AppDataUsageActivity`
   - `.development.DSULoader`
   - `.deviceinfo.AboutHiByActivity`
   - `.fuelgauge.AdvancedPowerUsageDetailActivity`
   - `.fuelgauge.RequestIgnoreBatteryOptimizations`
   - `.inputmethod.InputMethodAndSubtypeEnablerActivity`
   - `.localepicker.AppLocalePickerActivity`
   - `.notification.app.ChannelPanelActivity`
   - `.panel.SettingsPanelActivity`
   - `.support.SupportDashboardActivity`
   - `.wallpaper.WallpaperSuggestionActivity`
   - `.wifi.RequestToggleWiFiActivity`
   - `.wifi.WifiPickerActivity`
   - `.wifi.WifiScanModeActivity`

   Leave `FallbackHome`, `wifi.WifiNoInternetDialog` (ConnectivityService targets it by name while stock resolves `android.settings.SETTINGS`) and `homepage.SettingsHomepageActivity` enabled unless you disable them together with the priv-app move.
4. **Check**: `adb shell cmd package resolve-activity --brief -a android.settings.WIFI_SETTINGS` should print a `com.miku.settings` component, and the stock icon should be gone from any launcher.

## 8. Device checks before deleting the stock APK

Run with stock Settings present but hidden, after the priv-app move:

1. Resolution: for a sample of actions (`WIFI_SETTINGS`, `APPLICATION_DETAILS_SETTINGS -d package:com.miku.player`, `action.MANAGE_OVERLAY_PERMISSION -d package:…`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS -d package:…`, `panel.action.INTERNET_CONNECTIVITY`) `cmd package resolve-activity --brief` returns `com.miku.settings`. `logcat -s MikuSettingsRouting MikuSettingsRouter` shows the route taken.
2. Bluetooth: pair headphones (just works), a keyboard (passkey display) and a car kit or phone (numeric comparison, PIN). Only the MikuOS dialog may appear. Run an app that fires `ACTION_REQUEST_ENABLE` and `ACTION_REQUEST_DISCOVERABLE`; check the result codes. Test this one first: the MikuOS receiver aborts the broadcast once it has asked for its dialog, so if a background-start restriction silently blocked the dialog, no pairing UI would appear at all. MikuSettings holds `START_ACTIVITIES_FROM_BACKGROUND` (granted by platform signing) for exactly this, but it has not been seen working on hardware yet.
3. Wi-Fi: join WPA2, WPA3, open and hidden networks; forget; saved list; hotspot on/off, rename, new password; USB tethering. Join a Wi-Fi with no internet and confirm `com.miku.settings.wifi.WifiNoInternetDialog` appears.
4. App flows from real apps: Play Store install from unknown source (PackageInstaller "Settings" button), an app requesting overlay, all files access, usage access, notification listener, exact alarms and battery optimization exemption. Each returns to the app and the app sees the grant.
5. App info: force stop, clear cache, clear storage, disable a system app, uninstall a user app, notification on/off and a channel importance change survive a reboot.
6. Accessibility: enable a third-party service; confirm `com.miku.systemui/.MikuNotificationShadeService` stays enabled throughout.
7. Device admin: activate and deactivate one (any app with a DeviceAdminReceiver).
8. Date and time manual set with automatic off; time zone change; 24-hour toggle. Language change (open apps restart) and back. Keyboard enable/disable and switch.
9. Developer options: USB debugging toggle, animation scales, revoke authorizations (adb must ask again).
10. Location, NFC, airplane mode, Battery Saver, dark theme, Night Light, screen timeout.
11. Accounts: "Add account" from Play Store with no account signed in reaches the Google sign-in and returns.
12. Widgets: a third-party launcher placing a widget gets the MikuOS bind dialog.
13. Factory reset: last, on a unit you can reflash. Confirm the device wipes and reboots, and note whether setup asks for the old Google account.
14. Then remove the stock APK on a test image and repeat 1 to 12, plus: two reboots reach the Miku launcher (FallbackHome swap), `dumpsys package com.miku.settings | grep -A2 MikuFallbackHome` shows it enabled, and every DEEP-LINK row lands on the MikuOS "not available" page rather than crashing the caller.

## 9. Remaining work (DEEP-LINK rows)

These still forward to stock pages and must be rebuilt (or accepted as lost) before the APK is deleted:

- **Wi-Fi**: `android.settings.PROCESS_WIFI_EASY_CONNECT_URI` (Handle DPP: URI), `android.settings.WIFI_DPP_CONFIGURATOR_QR_CODE_GENERATOR` (Share Wi-Fi as QR), `android.settings.WIFI_DPP_CONFIGURATOR_QR_CODE_SCANNER` (Easy Connect QR scan), `android.settings.WIFI_DPP_ENROLLEE_QR_CODE_SCANNER` (Join by QR), `com.android.settings.WIFI_DIALOG` (Stock Wi-Fi edit dialog with extras), `com.android.settings.wifi.action.NETWORK_REQUEST` (App-requested peer network picker (WifiNetworkSpecifier))
- **Mobile**: `android.intent.action.EDIT` (APN editor (typed data telephony-carrier)), `android.intent.action.INSERT` (New APN), `android.settings.APN_SETTINGS` (APN list)
- **Hotspot**: `android.settings.TETHER_PROVISIONING_UI` (Carrier tethering entitlement check UI), `android.settings.TETHER_UNSUPPORTED_CARRIER_UI` (Carrier blocks tethering notice)
- **Bluetooth**: `android.bluetooth.device.action.CONNECTION_ACCESS_CANCEL` (Cancel of the above), `android.bluetooth.device.action.CONNECTION_ACCESS_REQUEST` (Phonebook/message/SIM access prompt), `android.bluetooth.devicepicker.action.LAUNCH` (Device picker for Bluetooth sharing (OPP)), `android.settings.BLUETOOTH_LE_AUDIO_QR_CODE_SCANNER` (LE Audio QR join), `android.settings.BLUTOOTH_FIND_BROADCASTS_ACTIVITY` (Find LE Audio broadcasts), `android.settings.MEDIA_BROADCAST_DIALOG` (LE Audio broadcast)
- **Connected**: `android.settings.ACTION_PRINT_SETTINGS` (Printing services / print job), `android.settings.CAST_SETTINGS` (Screen cast)
- **NFC**: `android.nfc.cardemulation.action.ACTION_CHANGE_DEFAULT` (App asks to become payment default), `android.settings.NFC_PAYMENT_SETTINGS` (Contactless payment default)
- **Apps**: `android.settings.APP_MEMORY_USAGE` (Memory use per app), `android.settings.CREDENTIAL_PROVIDER` (Passwords and credential providers)
- **Special access**: `android.settings.NOTIFICATION_ASSISTANT_SETTINGS` (Notification assistant), `android.settings.PREMIUM_SMS_SETTINGS` (Premium SMS access)
- **Launcher**: `android.appwidget.action.APPWIDGET_PICK` (Widget picker for launchers), `android.intent.action.PICK_ACTIVITY` (Activity picker for shortcuts)
- **Notifications**: `android.settings.ACTION_APP_NOTIFICATION_REDACTION` (Lock screen redaction), `android.settings.ACTION_CONDITION_PROVIDER_SETTINGS` (DND rule providers), `android.settings.APP_NOTIFICATION_BUBBLE_SETTINGS` (Bubbles for one app), `android.settings.CONVERSATION_SETTINGS` (Conversations), `android.settings.NOTIFICATION_HISTORY` (Notification history), `android.settings.ZEN_MODE_AUTOMATION_SETTINGS` (DND schedules), `android.settings.ZEN_MODE_EVENT_RULE_SETTINGS` (DND event rule), `android.settings.ZEN_MODE_ONBOARDING` (DND first-run), `android.settings.ZEN_MODE_SCHEDULE_RULE_SETTINGS` (One DND schedule)
- **Sound**: `android.settings.ACTION_MEDIA_CONTROLS_SETTINGS` (Media controls in QS), `android.settings.WORK_MODE` (HiBy work-mode page), `android.settings.audio.teen.switch` (HiBy teen-mode volume limit)
- **Display**: `android.settings.ACTION_POWER_MENU_SETTINGS` (Power menu options), `android.settings.DREAM_SETTINGS` (Screen saver)
- **Battery**: `com.android.settings.BATTERY_SAVER_SCHEDULE_SETTINGS` (Saver schedule)
- **Storage**: `android.settings.STORAGE_MANAGER_SETTINGS` (Automatic storage manager)
- **Security**: `android.credentials.UNLOCK` (Unlock credential storage), `android.settings.SHOW_ADMIN_SUPPORT_DETAILS` ("Blocked by your admin" dialog), `android.settings.SHOW_RESTRICTED_SETTING_DIALOG` (Restricted setting dialog for sideloaded apps), `com.android.settings.MONITORING_CERT_INFO` ("Network may be monitored" CA notice), `com.android.settings.TRUSTED_CREDENTIALS` (Trusted CA list), `com.android.settings.TRUSTED_CREDENTIALS_USER` (User CA list)
- **Privacy**: `android.settings.REQUEST_ENABLE_CONTENT_CAPTURE` (Content capture opt-in)
- **Accessibility**: `com.android.settings.TTS_SETTINGS` (Text-to-speech)
- **System**: `android.settings.ACCOUNT_SYNC_SETTINGS` (One account's sync), `android.settings.BUGREPORT_HANDLER_SETTINGS` (Bug report handler), `android.settings.REGIONAL_PREFERENCES_SETTINGS` (Units, first day of week), `android.settings.USER_DICTIONARY_SETTINGS` (Personal dictionary), `android.settings.WEBVIEW_SETTINGS` (WebView implementation), `com.android.settings.USER_DICTIONARY_INSERT` (Add word (framework sends this))
- **About**: `android.settings.CERTIFICATE_HIBY` (HiBy certification images), `android.settings.LICENSE` (Open source licenses), `android.settings.MODULE_LICENSES` (Mainline module licenses), `android.settings.SHOW_MANUAL` (Manual), `android.settings.SHOW_REGULATORY_INFO` (Regulatory labels)
- **Mixed**: `android.intent.action.VIEW` (APN editor (typed data), HiBy teen mode (HiByTeenMode:), stock slices (settings://, not mirrored))

Also STOCK ONLY flows that need a rebuild if they matter: `CONFIRM_DEVICE_CREDENTIAL`, `SET_NEW_PASSWORD` (lock setup), `WIFI_ADD_NETWORKS`, `REQUEST_SET_AUTOFILL_SERVICE`, `android.security.MANAGE_CREDENTIALS`, certificate install. "Reset app preferences" has no exported stock entry and is not built.

## 10. Files

- `mikuos-settings/src/main/AndroidManifest.xml`: permissions, router, aliases, dialogs, FallbackHome, pairing receiver (filters generated).
- `route/`: `Routes.kt` (action to destination), `SettingsRouterActivity.kt`, `PreferredRouting.kt`, `StockMap.kt` (generated).
- `pages/`: `MikuPageActivity.kt` (host and navigation), `WifiPages.kt`, `NetworkPages.kt`, `AppPages.kt`, `AccessPages.kt`, `DevicePages.kt`, `SystemPages.kt`.
- `dialogs/Dialogs.kt`, `wifi/WifiNoInternetDialog.kt`, `home/MikuFallbackHome.kt`, `sys/Hidden.kt` (reflection for @SystemApi/@hide calls), `ui/Components.kt`.
- `MikuSettingsActivity.kt`, `Receivers.kt`: new tiles, AOSP hand-offs replaced, Battery Saver, routing setup at boot.
- `mikuos/build/permissions/privapp-permissions-mikuos.xml`: `com.miku.settings` block.

