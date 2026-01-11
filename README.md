# AI Timetable Tool (Flutter)

This project is a **mobile AI timetable application** built using **Flutter (Dart)**.  
It is designed to run on **Android** and will later integrate AI features (e.g. OpenAI), OCR, and smart scheduling.

---

## 👥 Collab (Teammate Setup)

If you are joining the project:

1. **Pull the development branch:**
   ```bash
   git checkout main
   git pull origin main
   ```

---

## 📦 Requirements

Before running this project, make sure you have the following installed:

- **Flutter SDK**
- **Dart** (comes with Flutter)
- **Android Studio** (for Android SDK & Emulator)
- **VS Code** (recommended editor)
- **Git**

---

## 🛠️ Flutter App Setup (Frontend)

1️⃣ Install Flutter (VS Code – Recommended)
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
    ```
6. Follow the prompts to install Flutter SDK automatically
    Verify installation:
    ```bash
    flutter doctor
    ```


2️⃣ Android Studio Setup
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



3️⃣ Create Emulator
1. Open Android Studio
2. Go to More Actions → Virtual Device Manager
3. Create a device (e.g. Pixel 5)
4. Choose Android 14 system image
5. Finish and press ▶️ to start the emulator



4️⃣ Accept Android Licenses
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



5️⃣ Run the App
Make sure the Android emulator is running.

Then in VS Code terminal:
 ```bash
    flutter clean
    flutter pub get
    flutter run
```

The app will build and launch on the emulator

---

🔐 Environment Variables (.env)
⚠️ DO NOT COMMIT API KEYS

This project uses .env files.

Add this to .gitignore:
```bash
    .env
```

---

🗺️ OpenRouteService (ORS) API Key (Frontend)
Used for ETA calculation and leave-time reminders.

1️⃣ Get ORS API Key
1. Go to https://openrouteservice.org/
2. Create an account
3. Generate an API key


2️⃣ Create .env (Frontend)
Create .env in the project root (same level as pubspec.yaml):
```bash
    ORS_API_KEY=your_ors_key_here
```

---

## 🤖 Backend Setup

1️⃣ Backend Folder
```bash
    cd backend
```


2️⃣ Create Backend .env
Inside backend/:
```bash
    GEMINI_API_KEY=your_gemini_api_key_here
```


3️⃣ Get Gemini API Key
1. Visit: https://aistudio.google.com/
2. Create a project
3. Generate API key
4. Copy key into .env


4️⃣ Install Backend Dependencies
```bash
    pip install -r requirements.txt
```


5️⃣ Run Backend
```bash
    uvicorn main:app --reload --host 127.0.0.1 --port 8000
```
Make sure the backend is running before using AI features in the app.

---

## 🔔 Notifications & Time-Based Features
1. Notifications depend on emulator time
2. Always ensure emulator time matches real time:
    Settings → System → Date & time
    Enable Network-provided time
4. Avoid wiping emulator data (resets time)

---

## 📂 Project Structure
```bash
    lib/                → Flutter source
    android/            → Android config
    backend/            → AI backend
    ios/                → iOS config (future)
    pubspec.yaml        → Flutter dependencies
    .env                → API keys (NOT committed)
    .env.example        → Example env file
```

---

## 🧹 Useful Commands
Clean & rebuild:
```bash
    flutter clean
    flutter pub get
    flutter run
```

Check devices
```bash
    flutter devices
```

---

### ⚠️ Common Issues
1. App crashes on startup
    .env missing or not registered in pubspec.yaml
2. No notifications
    Emulator time incorrect

    Notification permission not granted

    Event scheduled in the past

---

## 📄 License

This project is for educational and development purposes.
