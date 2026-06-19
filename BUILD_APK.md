# FaceAttend AI - Build & Release Guide

This guide explains how to generate the Android standalone APK file for FaceAttend AI. The application is configured to build an APK using Expo Application Services (EAS). You can build it locally on your computer, or automatically via GitHub Actions whenever you publish a new Release.

## Prerequisites: EXPO_TOKEN Setup

To build using EAS in automated environments (like GitHub Actions), you need an Expo Access Token.

1. Create a free account at [Expo.dev](https://expo.dev/) if you don't have one.
2. Go to your Expo Account Settings -> **Access Tokens** ([Direct Link](https://expo.dev/settings/access-tokens)).
3. Click **Create token** and copy the generated value.
4. Go to your GitHub repository: `https://github.com/sudharshan200601/ektabio`.
5. Navigate to **Settings** -> **Secrets and variables** -> **Actions**.
6. Click **New repository secret**.
7. Set the **Name** to `EXPO_TOKEN` and paste your copied token into the **Secret** field.
8. Click **Add secret**.

*(Note: The `GITHUB_TOKEN` used in the workflow is provided automatically by GitHub, you only need to add `EXPO_TOKEN`).*

---

## 1. Automated Building via GitHub Releases (Recommended)

This project has a GitHub Actions workflow (`.github/workflows/build-apk.yml`) that automatically builds an APK and attaches it to GitHub releases.

**How to trigger an automated build:**
1. Open your GitHub repository in the browser.
2. Click on **Releases** (on the right sidebar).
3. Click **Draft a new release**.
4. Click **Choose a tag** and type a new version number (e.g., `v1.0.0`), then click **Create new tag**.
5. Give the release a title (e.g., "Version 1.0.0 Initial Release").
6. Click **Publish release**.

**What happens next:**
- Navigate to the **Actions** tab in your repository.
- You will see a workflow running titled "Build and Release Android APK".
- The workflow takes approximately **5-10 minutes** to complete. It sets up the Android environment, installs your dependencies, builds the APK locally on the runner using `eas build --local`, and uploads it.
- Once finished, go back to the Release page. The `.apk` file will appear under the **Assets** section, ready to be downloaded and installed on Android tablets!

---

## 2. Building Locally on Your Machine

If you want to build the APK directly on your Windows machine, you need Java and Android SDK installed (which you likely have if you develop Android apps). Otherwise, the GitHub Actions method is easier.

**Command Line Instructions:**

1. Open a terminal and navigate to your `mobile_app` folder:
   ```bash
   cd "d:\New folder\mobile_app"
   ```

2. Install the EAS CLI globally (if you haven't already):
   ```bash
   npm install -g eas-cli
   ```

3. Log in to your Expo account:
   ```bash
   eas login
   ```

4. Start the local build for Android using the `preview` profile:
   ```bash
   eas build --platform android --profile preview --local
   ```

5. Once the build is complete, you will find a `.apk` file generated inside the `mobile_app` folder or a specified output folder.

---

## Explaining the Configuration Files

I created the following configuration files to make this process seamless:

1. **`app.json`**: This is the core Expo configuration file. It provides the essential Android package name (`com.sudharshan.faceattend`), versioning, app name (`FaceAttend AI`), and required permissions (Camera, Audio, Location). Without this, EAS cannot generate standalone apps.
2. **`eas.json`**: This tells EAS Build *how* to build the app. I defined a `preview` profile with `"buildType": "apk"`. By default, Expo builds `.aab` (Android App Bundles) meant for the Google Play Store, but `.apk` is what you need to directly install on tablets.
3. **`.github/workflows/build-apk.yml`**: This YAML file defines the Continuous Integration (CI) process. It instructs GitHub servers to boot up an Ubuntu environment, prepare Android Java tools, log into Expo, run the build command, and upload the resulting artifact directly to your GitHub Release.
