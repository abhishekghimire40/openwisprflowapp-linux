# OpenWisprFlow

Your voice everywhere - A minimalist voice-to-text application powered by Groq AI.

## Features

- Instant voice-to-text transcription using Groq's Whisper models
- Global hotkey (Alt+X) for quick access from any application
- System tray integration for seamless background operation
- Multiple transcription models:
  - Whisper Large V3 Turbo (fastest)
  - Whisper Large V3 (most accurate)
  - Distil Whisper Large V3 (balanced)
- Dark mode interface with modern, minimalist design
- Built with Flutter for Windows and Linux

## Requirements

### Windows
- Windows 10 or later
- Microphone access

### Linux
- X11-based desktop environment (GNOME, KDE, XFCE, etc.)
- Required packages: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`
- Microphone access
- Groq API key (free at https://console.groq.com/keys)

## Important Note for Linux Users

When you first run the application, you'll be prompted to allow "remote desktop" access. This is normal and safe! Here's why:

- This permission is required for the global hotkey (Alt+X) to work when the app is minimized
- It's also needed for system tray integration and window management
- This is standard for Linux apps that use global shortcuts (similar to Discord, Slack, etc.)
- The app does NOT actually enable remote desktop access or share your screen
- This is a one-time prompt for X11's security system

## Installation

1. Download the latest release for your platform
2. Run the application
3. Enter your Groq API key when prompted
4. Press Alt+X anywhere to start dictating

## Development Setup

1. Install Flutter (https://flutter.dev/docs/get-started/install)
2. Clone this repository
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

## Building

### For Windows:
```bash
flutter build windows
```
The built application will be in `build/windows/runner/Release/`.

### For Linux:
```bash
flutter build linux --release
```
The built application will be in `build/linux/x64/release/bundle/`.

## Dependencies

- flutter
- window_manager
- provider
- google_fonts
- record
- path_provider
- http
- system_tray
- hotkey_manager
- url_launcher

## License

MIT License - see LICENSE file

## Credits

Built with [Flutter](https://flutter.dev) and powered by [Groq AI](https://groq.com)
