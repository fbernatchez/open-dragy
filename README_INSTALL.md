# OpenDragy - Mobile App Installation Guide

This guide explains how to install and update the OpenDragy companion application on both **Android** and **iOS** devices from pre-compiled release files (like APKs and IPAs).

---

## 🤖 Android Installation (APK)

Android allows direct installation of external application packages. Follow these steps to install the app on your phone:

1. **Download the APK**: Download the `.apk` file (e.g., `OpenDragy_v1.0.0-beta.1+1.apk`) to your device.
2. **Enable Unknown Apps**:
   * Open the downloaded file.
   * If a security prompt appears saying: *"For your security, your phone is not allowed to install unknown apps from this source,"* tap **Settings**.
   * Toggle the **Allow from this source** switch to give your browser or file manager permission to perform the installation.
3. **Complete Installation**: Return to the package installer screen and tap **Install**.
4. **App Permissions**: On first launch, ensure you grant the app **Bluetooth & Location permissions** so it can scan and establish connection with the ESP32 hardware device.

---

## 🍏 iOS/iPadOS Installation (SideStore Sideloading)

Because Apple restricts installations outside the App Store, you must "sideload" the unsigned `.ipa` file. **SideStore** is the recommended method because it allows you to resign and update the app directly on your phone over Wi-Fi, requiring a computer only **once** for the initial installation.

---

### Step 1: One-Time Computer Setup (SideServer)
*You will need a Mac or Windows PC for this step to load the installer onto your iPhone.*

1. **Prerequisites (Windows only)**: Download and install the standard desktop versions of [iTunes](https://www.apple.com/itunes/) and [iCloud](https://support.apple.com/HT204283) directly from Apple (do not use the Windows Microsoft Store versions).
2. **Download SideServer**: Install **[SideServer](https://sidestore.io/#download)** on your computer.
3. **Connect Your iPhone**: Plug your phone into your computer via a USB cable. Tap **Trust** on your phone screen when prompted.
4. **Install SideStore**:
   * Open SideServer on your computer.
   * Click the SideServer icon in the menu bar (Mac) or system tray (Windows).
   * Select **Install SideStore** and choose your connected phone.
   * Enter your Apple ID and password (these credentials are sent directly to Apple to generate a free developer certificate).
5. **Trust the Certificate**:
   * On your iPhone, go to **Settings** > **General** > **VPN & Device Management**.
   * Under "Developer App", tap on your Apple ID email and tap **Trust**.
6. **Enable Developer Mode**:
   * Go to **Settings** > **Privacy & Security** > **Developer Mode**.
   * Toggle it **On**, restart your device, and tap **Turn On** after rebooting.

---

### Step 2: WireGuard Loopback Configuration
*This configures a local VPN loopback on your phone so SideStore can communicate with Apple's servers to sign its own apps.*

1. **Download WireGuard**: Install the official **[WireGuard](https://apps.apple.com/app/wireguard/id1441195209)** client app from the App Store.
2. **Export Your Pairing File**:
   * Open the **SideStore** app on your iPhone.
   * SideStore will prompt you to export a pairing file. Tap **OK** and save the `SideStore.mobiledevicepairing` file to your device's **Files** app.
3. **Download the WireGuard Profile**:
   * Download the SideStore WireGuard configuration file directly to your phone: **[SideStore.conf](https://sidestore.io/SideStore.conf)**.
4. **Import into WireGuard**:
   * Open **WireGuard**.
   * Tap the **+** (plus) icon in the top right and select **Create from file or archive**.
   * Select the `SideStore.conf` file you just downloaded.
   * Tap **Allow** when iOS asks for permission to add VPN configurations.
5. **Activate the Loopback**:
   * Turn the toggle **On** next to the **SideStore** tunnel in the WireGuard app. *(Keep this active whenever you want to install or refresh apps).*

---

### Step 3: How to Install, Update & Refresh OpenDragy
*Once setup is complete, you no longer need your computer. You can do everything on your phone as long as you are connected to Wi-Fi.*

#### How to Install/Update OpenDragy:
1. Download the latest `OpenDragy_vX.X.X.ipa` file to your phone's **Files** app.
2. Turn the **SideStore VPN tunnel ON** in the WireGuard app.
3. Open **SideStore**:
   * Go to the **My Apps** tab.
   * Tap the **+** (plus) icon in the top-left corner.
   * Select the downloaded `.ipa` file from your Files app.
4. SideStore will ask for your Apple ID credentials again. Enter them to sign and install the app locally.
5. OpenDragy will appear on your home screen!

#### How to Refresh the 7-day Sideloading Timer:
Apple's free developer certificates expire every 7 days, causing sideloaded apps to crash if they aren't refreshed. To keep them working permanently:
1. Connect to any **Wi-Fi** network.
2. Turn the **SideStore VPN tunnel ON** in WireGuard.
3. Open **SideStore**, go to **My Apps**, and tap **Refresh All** (or tap the **[7 days]** badge next to OpenDragy).
4. SideStore will refresh the certificate directly on your phone, giving you another 7 days!
