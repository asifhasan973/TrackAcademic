# TrackAcademic 🎓

**TrackAcademic** is a comprehensive academic attendance, course lifecycle, and assessment management platform engineered for universities and educational institutions. Built with Flutter, Firebase Cloud Firestore/Auth, and a secure Node.js/TypeScript backend hosted on Vercel.

---

## 🌟 Key Features

### 👨‍🏫 Teacher Workspace
- **Course Lifecycle Management**: Create, update, archive, and manage course join codes (`CSE311`, `KYFLOGOY`, etc.).
- **Smart GPS & Passcode Attendance**: Launch attendance sessions with geofence validation (custom radius & GPS accuracy safeguards) and optional numeric passcodes.
- **Attendance Register & Manual Corrections**: Review live session logs, mark manual overrides, and finalize attendance records atomically.
- **Assessments & Marks Publishing**: Record, adjust, and publish scores for midterms, quizzes, and finals with immediate sync.
- **Reporting & Unicode Exports**: Export attendance registers and student report cards directly to RFC 4180 CSV and formatted PDF documents (with Bengali & English Unicode support).
- **Class Schedules**: Set up multi-day class schedules (Theory and Sessional) with automatic room assignments.

### 👨‍🎓 Student Workspace
- **Course Enrollment**: Search and join courses using teacher-provided alphanumeric join codes.
- **Self-Attendance Submission**: One-tap attendance submission with location verification (GPS radius validation) and passcode confirmation.
- **Personal Academic Dashboard**: Real-time attendance percentage tracking, color-coded status pills, and published mark summaries.
- **Native Device Timetable Reminders**: Local alarm integration that schedules notifications before upcoming classes without draining battery.

---

## 🏗️ Architecture & Technology Stack

| Layer | Technology |
|---|---|
| **Mobile Client** | [Flutter](https://flutter.dev/) (Dart 3.x) with Material 3 responsive layouts |
| **Authentication** | [Firebase Authentication](https://firebase.google.com/products/auth) (Direct instant sign-in & role claims) |
| **Primary Database** | [Cloud Firestore](https://firebase.google.com/products/firestore) (Fine-grained security rules, real-time streams) |
| **Production Backend** | [Vercel](https://vercel.com/) Serverless Functions (Node.js 20+ / TypeScript) |
| **Backend Endpoint** | `https://trackacademic-backend.vercel.app/api` |
| **Location Services** | `geolocator` with native device GPS accuracy heuristics |
| **Background Notifications** | Firebase Cloud Messaging (FCM) & Android native `AlarmManager` |

---

## 🚀 Live Demo Credentials

The platform is 100% online in cloud production mode. You can log in immediately using the active accounts below:

| Role | Email | Password | Institution ID | Status |
|---|---|---|---|---|
| **Teacher** | `teacher.demo@trackacademic.live` | `DemoPassword123!` | `ONLINE-T01` | Active & Verified |
| **Student** | `student.demo@trackacademic.live` | `DemoPassword123!` | `ONLINE-S01` | Active & Verified |

> **Note on Registration**: 
> - **Student self-registration**: Anyone can create an account using **Create account** with immediate access (email verification is optional/bypassed).
> - **Teacher self-registration**: Requires the administrative authorization code: `TRACK-TEACH-2026-K9P4`.

---

## 📲 Installation & Running

### Option A: Install Release Android APK
A production release APK is pre-built and configured for online cloud access:
```bash
# Locate pre-built APK at project root
ls -lh trackacademic-online.apk
```
Or rebuild the release APK anytime with:
```bash
bash scripts/build_online_apk.sh
```

### Option B: Run via Flutter CLI (Development)
The Flutter application is configured with the live HTTPS backend URL by default.

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run on connected mobile device or emulator
flutter run
```

Or explicitly specify the production defines:
```bash
flutter run \
  --dart-define=USE_FIREBASE_EMULATORS=false \
  --dart-define=BACKEND_URL="https://trackacademic-backend.vercel.app/api"
```

### Option C: Run with Local Firebase Emulators (Offline Testing)
If you wish to run in a totally isolated, offline emulator environment:
```bash
# Start Auth, Firestore, and Functions emulators with seeded demo data
bash scripts/start_demo_emulators.sh

# Run Flutter pointing to emulator
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

---

## 📁 Repository Structure

```plaintext
TrackAcademic/
├── android/               # Native Android configuration (permissions, alarms, manifest)
├── backend/               # Vercel serverless backend (TypeScript, Firebase Admin SDK)
│   ├── api/index.ts       # Express/Serverless router entry
│   └── src/operations/    # Atomic backend business operations (attendance, courses, marks)
├── functions/             # Firebase Cloud Functions (mirroring backend logic)
├── lib/                   # Flutter application source code
│   ├── core/              # Network (ApiClient), Auth, Reminder, and Notification services
│   └── features/          # Authentication, Teacher, and Student feature modules
├── scripts/               # Automation scripts
│   ├── build_online_apk.sh       # Release APK build script
│   ├── start_demo_emulators.sh   # Firebase emulator launcher
│   ├── seed_demo_accounts.mjs    # Emulator seed script
│   └── verify_user_email.mjs     # Account verification utility
├── test/                  # Flutter unit and widget tests
└── tests/                 # End-to-end integration and security test suites
```

---

## 🧪 Testing

To execute all Flutter unit, model, and UI integration tests:
```bash
flutter test
```

To run backend unit and integration tests:
```bash
cd backend && npm test
```

---

## 🔒 Security & Privacy
- **Idempotency Safeguards**: Safe mutations use UUID-based idempotency keys with deduplication.
- **Fail-Closed Permissions**: Firestore security rules restrict collection reads and writes strictly to verified course owners and enrolled students.
- **Device Location**: GPS coordinates are requested strictly during attendance sessions and never logged without user consent.
