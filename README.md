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
- Built with Flutter for Windows

## Requirements

- Windows 10 or later
- Microphone access
- Groq API key (free at https://console.groq.com/keys)

## Installation

1. Download the latest release
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

To build the application:

```bash
flutter build windows
```

The built application will be in `build/windows/runner/Release/`.

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
