# AI Timetable Tool (Flutter)

This project is a **mobile AI timetable application** built using **Flutter (Dart)**.  
It is designed to run on **Android** and will later integrate AI features (e.g. OpenAI), OCR, and smart scheduling.

---

## 📦 Requirements

Before running this project, make sure you have the following installed:

- **Flutter SDK**
- **Dart** (comes with Flutter)
- **Android Studio** (for Android SDK & Emulator)
- **VS Code** (recommended editor)
- **Git**

---

## 🛠️ Step 1: Install Flutter (via VS Code – Recommended)

1. Install **VS Code**
2. Open VS Code → Extensions
3. Install:
   - **Flutter**
   - **Dart**
4. Press `Ctrl + Shift + P`
5. Run:
    ```bash
    Flutter: New Project
    Flutter: Run Flutter Doctor
6. Follow the prompts to install Flutter SDK automatically
    Verify installation:
    ```bash
    flutter doctor

---

## 🤖 Step 2: Install Android Studio

1. Download Android Studio:
    https://developer.android.com/studio

2. Install using Standard setup

3. Open Android Studio → More Actions → SDK Manager

**SDK Platforms**
✅ Android 14 (or latest)

**SDK Tools**
Ensure these are checked:
1. Android SDK Platform-Tools
2. Android SDK Build-Tools
3. Android Emulator
4. Android SDK Command-line Tools (latest)

Click **Apply** and wait for installation.

---

## 📱 Step 3: Create an Android Emulator

1. Open Android Studio
2. Go to More Actions → Virtual Device Manager
3. Create a device (e.g. Pixel 5)
4. Choose Android 14 system image
5. Finish and press ▶️ to start the emulator

---

## 🧪 Step 4: Accept Android Licenses

In VS Code Terminal:
 ```bash
 flutter doctor --android-licenses
```
type y for all prompts.

Re-check:
 ```bash
 flutter doctor
```

You should now see
 ```bash
 [✓] Android toolchain - develop for Android devices
```
---

## 🚀 Step 5: Create the Flutter Project

Open the project folder in VS Code and run:
 ```bash
 flutter create .
```

This generates
 ```bash
 lib/
 android/
 ios/
 windows/
 pubspec.yaml
```
---

## ▶️ Step 6: Run the App

Make sure the Android emulator is running.

Then in VS Code terminal:
 ```bash
 flutter run
```

The app will build and launch on the emulator

---

## 🧩 Step 7: Main Entry File

The app starts from:
 ```bash
 lib/main.dart
```

Any UI or logic changes should be made in this file or files inside the lib/ directory.

After editing code:

Press Save → hot reload happens automatically

Or press R in terminal for full restart

---

## 🧹 Useful Commands

Clean and rebuild:
 ```bash
 flutter clean
 flutter pub get
 flutter run
```

Check devices:
 ```bash
 flutter devices
```

---

## 📂 Project Structure (Important)
    lib/          → Dart source code
    android/      → Android-specific files
    ios/          → iOS-specific files
    windows/      → Windows desktop support
    pubspec.yaml  → Dependencies & project config

---

## ✅ Troubleshooting

If flutter command is not found:
1. Use VS Code terminal
2. Or add Flutter bin folder to system PATH

If app does not update:

1. Press R for hot restart
2. Or stop (q) and rerun flutter run

---

## 📄 License

This project is for educational and development purposes.
