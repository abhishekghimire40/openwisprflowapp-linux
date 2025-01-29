import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:system_tray/system_tray.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'keyboard_simulator.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/rendering.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize hotkey
  await hotKeyManager.unregisterAll();
  
  await windowManager.ensureInitialized();

  // Set window manager handlers
  windowManager.setPreventClose(true);  // Prevent window from actually closing
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,  // Show in taskbar
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Set taskbar/window icon
    if (Platform.isWindows) {
      await windowManager.setIcon('assets/app_icon.ico');
    } else {
      await windowManager.setIcon('assets/app_icon.png');
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => VoiceRecognitionState(),
      child: const MyApp(),
    ),
  );
}

class VoiceRecognitionState extends ChangeNotifier {
  final _audioRecorder = AudioRecorder();
  bool _isListening = false;
  String _lastWords = '';
  String _currentRecordingPath = '';
  String? _apiKey;
  String _selectedModel = 'whisper-large-v3-turbo';  // Default model
  final SystemTray _systemTray = SystemTray();
  bool _isInitialized = false;

  bool get isListening => _isListening;
  String get lastWords => _lastWords;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;
  String get selectedModel => _selectedModel;
  String? get apiKey => _apiKey;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    // Try to load settings
    await _loadSettings();

    // Initialize system tray
    await _initSystemTray();

    // Register global hotkey (Alt + X)
    await hotKeyManager.register(
      HotKey(
        KeyCode.keyX,
        modifiers: [KeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      keyDownHandler: (_) async {
        if (!hasApiKey) {
          await windowManager.show();
          await windowManager.focus();
          return;
        }
        // Hide window when starting to listen
        await windowManager.hide();
        await toggleListening();
      },
    );

    _isInitialized = true;
  }

  Future<void> _loadSettings() async {
    final directory = await getApplicationDocumentsDirectory();
    final apiKeyFile = File('${directory.path}/api_key.txt');
    final modelFile = File('${directory.path}/model.txt');
    
    if (await apiKeyFile.exists()) {
      _apiKey = await apiKeyFile.readAsString();
    }
    
    if (await modelFile.exists()) {
      _selectedModel = await modelFile.readAsString();
    }
    
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    if (key.trim().isEmpty) return;
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/api_key.txt');
    await file.writeAsString(key.trim());
    _apiKey = key.trim();
    notifyListeners();
  }

  Future<void> setModel(String model) async {
    if (!['whisper-large-v3-turbo', 'whisper-large-v3', 'distil-whisper-large-v3-en'].contains(model)) return;
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/model.txt');
    await file.writeAsString(model);
    _selectedModel = model;
    notifyListeners();
  }

  Future<void> _initSystemTray() async {
    await _systemTray.initSystemTray(
      title: "OpenWisprFlow",
      iconPath: Platform.isWindows 
          ? 'assets/app_icon.ico'
          : 'assets/app_icon.png',
      toolTip: "OpenWisprFlow - Voice to Text (Alt+X)",
    );

    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'OpenWisprFlow',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show',
        onClicked: (menuItem) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItemLabel(
        label: isListening ? 'Stop Listening' : 'Start Listening',
        onClicked: (menuItem) async {
          await toggleListening();
          await _updateContextMenu();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) async {
          await _systemTray.destroy();
          exit(0);
        },
      ),
    ]);

    await _systemTray.setContextMenu(menu);
    
    // Handle system tray click events
    _systemTray.registerSystemTrayEventHandler((eventName) {
      debugPrint("System tray event: $eventName");
      if (eventName == kSystemTrayEventClick) {
        // Left click - always show window
        windowManager.show();
        windowManager.focus();
      } else if (eventName == kSystemTrayEventRightClick) {
        // Right click - show menu
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _updateContextMenu() async {
    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'OpenWisprFlow',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show',
        onClicked: (menuItem) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItemLabel(
        label: isListening ? 'Stop Listening' : 'Start Listening',
        onClicked: (menuItem) async {
          await toggleListening();
          await _updateContextMenu();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) async {
          await _systemTray.destroy();
          exit(0);
        },
      ),
    ]);

    await _systemTray.setContextMenu(menu);
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
    // Update the context menu to reflect the new state
    await _updateContextMenu();
    notifyListeners();
  }

  Future<void> _startListening() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath = '${tempDir.path}/temp_audio.wav';
      
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 16 * 1000,
        ),
        path: _currentRecordingPath,
      );

      _isListening = true;
      notifyListeners();

    } catch (e) {
      print('Error starting recording: $e');
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> _stopListening() async {
    try {
      await _audioRecorder.stop();
      _isListening = false;
      notifyListeners();

      await _transcribeAudio(_currentRecordingPath);
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> _transcribeAudio(String audioPath) async {
    if (!hasApiKey) {
      _lastWords = 'Please set up your Groq API key first';
      notifyListeners();
      await windowManager.show();  // Only show for API key setup
      return;
    }

    try {
      final url = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $_apiKey'
        ..fields['model'] = _selectedModel
        ..fields['response_format'] = 'verbose_json'
        ..fields['language'] = 'en'  // Set language to English
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            audioPath,
            contentType: MediaType('audio', 'wav'),
          ),
        );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        _lastWords = data['text'];
        notifyListeners();
        
        // Copy to clipboard and simulate Ctrl+V
        await Clipboard.setData(ClipboardData(text: _lastWords));
        // Small delay to ensure clipboard is ready
        await Future.delayed(const Duration(milliseconds: 50));
        // Simulate Ctrl+V
        KeyboardSimulator.simulateCtrlV();
      } else {
        print('Error from Groq API: $responseBody');
        _lastWords = 'Error transcribing audio';
        notifyListeners();
        await windowManager.show();  // Show window on error
      }
    } catch (e) {
      print('Error sending request to Groq: $e');
      _lastWords = 'Error connecting to transcription service';
      notifyListeners();
      await windowManager.show();  // Show window on error
    }
  }

  @override
  void dispose() {
    _stopListening();
    hotKeyManager.unregisterAll();
    super.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenWisprFlow',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white,
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF1E1E1E),
          onSurface: Colors.white,
          onBackground: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        useMaterial3: true,
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(ThemeData.dark().textTheme),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: const Color(0xFF1E1E1E),
            backgroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1E1E1E),
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WindowListener {
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    context.read<VoiceRecognitionState>().initialize().then((_) {
      if (!context.read<VoiceRecognitionState>().hasApiKey) {
        _showApiKeyDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Column(
        children: [
          WindowCaption(
            brightness: Brightness.dark,
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 16,
                    height: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'OpenWisprFlow',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: Consumer<VoiceRecognitionState>(
                    builder: (context, state, child) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/app_icon.png',
                              width: 96,
                              height: 96,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Your voice everywhere',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 28,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!state.hasApiKey)
                            TextButton(
                              onPressed: _showApiKeyDialog,
                              child: const Text('Set up Groq API Key'),
                            ),
                          if (state.hasApiKey)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                state.lastWords.isEmpty
                                    ? 'Press Alt+X to start speaking'
                                    : state.lastWords,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 30),
                          if (state.hasApiKey)
                            FloatingActionButton(
                              onPressed: () => state.toggleListening(),
                              backgroundColor: Colors.white12,
                              child: Icon(
                                state.isListening ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: _showSettingsDialog,
                    color: Colors.white30,
                    hoverColor: Colors.white12,
                    tooltip: 'Settings',
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Press Alt+X anywhere to start',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiKeyDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          'Welcome to OpenWisprFlow',
          style: GoogleFonts.jetBrainsMono(
            fontWeight: FontWeight.w500,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To get started, you\'ll need a Groq API key:',
              style: GoogleFonts.jetBrainsMono(),
            ),
            const SizedBox(height: 16),
            Text(
              '1. Visit https://console.groq.com/keys\n' +
              '2. Log in or sign up (it\'s free)\n' +
              '3. Create a new API key\n' +
              '4. Copy and paste it below',
              style: GoogleFonts.jetBrainsMono(
                height: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiKeyController,
              style: GoogleFonts.jetBrainsMono(),
              decoration: InputDecoration(
                labelText: 'API Key',
                labelStyle: GoogleFonts.jetBrainsMono(color: Colors.white70),
                hintText: 'Paste your Groq API key here',
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white30),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await windowManager.show();
              await windowManager.focus();
              await launchUrl(
                Uri.parse('https://console.groq.com/keys'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              'Open Groq Console',
              style: GoogleFonts.jetBrainsMono(),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (_apiKeyController.text.trim().isNotEmpty) {
                context.read<VoiceRecognitionState>().setApiKey(_apiKeyController.text);
                Navigator.of(context).pop();
              }
            },
            child: Text(
              'Save API Key',
              style: GoogleFonts.jetBrainsMono(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final state = context.read<VoiceRecognitionState>();
    final apiKeyController = TextEditingController(text: state.apiKey);
    String selectedModel = state.selectedModel;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(
              'Settings',
              style: GoogleFonts.jetBrainsMono(
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/groq-logo.png',
              height: 24,
              color: Colors.white70,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Groq API Key',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: apiKeyController,
              style: GoogleFonts.jetBrainsMono(),
              decoration: InputDecoration(
                hintText: 'Enter your Groq API key',
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white30),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Transcription Model',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedModel,
              style: GoogleFonts.jetBrainsMono(),
              dropdownColor: const Color(0xFF1E1E1E),
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'whisper-large-v3-turbo',
                  child: Text(
                    'Whisper Large V3 Turbo',
                    style: GoogleFonts.jetBrainsMono(),
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-large-v3',
                  child: Text(
                    'Whisper Large V3',
                    style: GoogleFonts.jetBrainsMono(),
                  ),
                ),
                DropdownMenuItem(
                  value: 'distil-whisper-large-v3-en',
                  child: Text(
                    'Distil Whisper Large V3',
                    style: GoogleFonts.jetBrainsMono(),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  selectedModel = value;
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Language: English',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white30,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await launchUrl(
                Uri.parse('https://console.groq.com/keys'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              'Get API Key',
              style: GoogleFonts.jetBrainsMono(),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (apiKeyController.text.trim().isNotEmpty) {
                state.setApiKey(apiKeyController.text);
              }
              state.setModel(selectedModel);
              Navigator.of(context).pop();
            },
            child: Text(
              'Save Settings',
              style: GoogleFonts.jetBrainsMono(),
            ),
          ),
        ],
      ),
    );
    
    apiKeyController.dispose();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }
}

class WindowCaption extends StatelessWidget {
  final Widget? title;
  final Color backgroundColor;
  final Brightness brightness;

  const WindowCaption({
    super.key,
    this.title,
    this.backgroundColor = Colors.transparent,
    this.brightness = Brightness.light,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: brightness == Brightness.light
                ? Colors.grey[300]!
                : Colors.grey[800]!,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (title != null) 
            Expanded(child: DefaultTextStyle(
              style: TextStyle(
                color: brightness == Brightness.light ? Colors.black87 : Colors.white,
                fontSize: 14,
              ),
              child: title!,
            )),
          const WindowCaptionButtons(),
        ],
      ),
    );
  }
}

class WindowCaptionButtons extends StatelessWidget {
  const WindowCaptionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CaptionButton(
          icon: Icons.remove,
          onPressed: () async => await windowManager.minimize(),
        ),
        _CaptionButton(
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _CaptionButton(
          icon: Icons.close,
          onPressed: () async => await windowManager.hide(),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CaptionButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      onPressed: onPressed,
      iconSize: 16,
      padding: const EdgeInsets.all(8),
      splashRadius: 16,
    );
  }
}
