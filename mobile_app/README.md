# FaceAttend AI - Expo Go Mobile App

This directory contains the **Expo Go React Native** mobile application codebase for **FaceAttend AI**. 

It uses the device front camera to capture high-quality snapshots and transmits the image data directly to the FastAPI server for under-1-second real-time biometric verification and encryption.

---

## 1. Quick Start Guide (Run on your phone)

### Step 1.1: Install Expo CLI globally
Make sure you have Node.js installed. Open your terminal and run:
```bash
npm install -g expo-cli
```

### Step 1.2: Install mobile dependencies
Navigate to the `mobile_app` folder and install:
```bash
cd mobile_app
npm install
```

### Step 1.3: Configure your LAN IP address
Because the app runs on your mobile phone, it must connect to your backend server over your local Wi-Fi network.
1. Find your computer's local IP address (e.g. `192.168.1.100`):
   - On Windows: run `ipconfig` in cmd
   - On macOS/Linux: run `ifconfig` in terminal
2. Open `mobile_app/App.js` and edit line 10 with your IP:
   ```javascript
   const BACKEND_URL = "http://192.168.1.100:8000/api";
   ```

### Step 1.4: Run the Expo server
Start the Expo development server:
```bash
npx expo start
```
This will print a large **QR Code** in your terminal.

### Step 1.5: Scan & Run
1. Install the **Expo Go** application on your mobile phone (available in the Apple App Store or Google Play Store).
2. Scan the terminal QR code:
   - On Android: Open the **Expo Go** app and tap "Scan QR Code".
   - On iOS: Open your default iOS **Camera app** and scan the QR code (it will prompt to open in Expo Go).
3. The app will build and run on your mobile device instantly!

---

## 2. Dynamic Workflows

### 2.1: Face Enrollment
1. Tap **Enroll New Face Biometric** on your mobile app.
2. Enter the **Employee ID alone** (e.g., `EMP001`).
3. Position your face in front of the camera, looking directly center, and tap **Capture & Save Face**.
4. The mobile app captures a front-facing snapshot, converts it to base64, and sends it to the backend. The backend crops the face, extracts the 512-dimension vector embedding, encrypts it, and saves it.

### 2.2: Attendance Scanner
1. Tap **Mark Attendance (Scan Face)** on your mobile app.
2. Position your face in front of the camera and tap **Verify Face & Mark Attendance**.
3. The app captures a snapshot, sends it to the backend. The backend matches it against the database in under 1 second, logs the attendance status (Check-In or Check-Out), and returns the successful verification results to your phone!
