import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'package:characters/characters.dart';

// FFI bindings for X11
final DynamicLibrary x11 = DynamicLibrary.open('libX11.so.6');
final DynamicLibrary xtst = DynamicLibrary.open('libXtst.so.6');

// X11 function bindings
typedef XOpenDisplayNative = Pointer<Void> Function(Pointer<Utf8>);
typedef XOpenDisplayDart = Pointer<Void> Function(Pointer<Utf8>);

typedef XStringToKeysymNative = Int32 Function(Pointer<Utf8>);
typedef XStringToKeysymDart = int Function(Pointer<Utf8>);

typedef XKeysymToKeycodesNative = Int32 Function(Pointer<Void>, Int32);
typedef XKeysymToKeycodesDart = int Function(Pointer<Void>, int);

typedef XTestFakeKeyEventNative = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef XTestFakeKeyEventDart = int Function(Pointer<Void>, int, int, int);

typedef XFlushNative = Int32 Function(Pointer<Void>);
typedef XFlushDart = int Function(Pointer<Void>);

class LinuxKeyboardSimulator {
  static final _xOpenDisplay = x11.lookupFunction<XOpenDisplayNative, XOpenDisplayDart>('XOpenDisplay');
  static final _xStringToKeysym = x11.lookupFunction<XStringToKeysymNative, XStringToKeysymDart>('XStringToKeysym');
  static final _xKeysymToKeycode = x11.lookupFunction<XKeysymToKeycodesNative, XKeysymToKeycodesDart>('XKeysymToKeycode');
  static final _xTestFakeKeyEvent = xtst.lookupFunction<XTestFakeKeyEventNative, XTestFakeKeyEventDart>('XTestFakeKeyEvent');
  static final _xFlush = x11.lookupFunction<XFlushNative, XFlushDart>('XFlush');

  static Pointer<Void>? _display;

  static void initialize() {
    if (_display == null) {
      _display = _xOpenDisplay(nullptr);
      if (_display == nullptr) {
        throw Exception('Failed to open X11 display');
      }
    }
  }

  static void sendText(String text) {
    initialize();
    
    for (var char in text.characters) {
      final charPtr = char.toNativeUtf8();
      final keysym = _xStringToKeysym(charPtr);
      final keycode = _xKeysymToKeycode(_display!, keysym);
      
      // Press key
      _xTestFakeKeyEvent(_display!, keycode, 1, 0);
      // Release key
      _xTestFakeKeyEvent(_display!, keycode, 0, 0);
      _xFlush(_display!);
      
      malloc.free(charPtr);
      sleep(const Duration(milliseconds: 5));
    }
  }

  static void simulateCtrlV() {
    initialize();
    
    // Control key codes
    final controlPtr = 'Control_L'.toNativeUtf8();
    final controlKeysym = _xStringToKeysym(controlPtr);
    final controlKeycode = _xKeysymToKeycode(_display!, controlKeysym);
    malloc.free(controlPtr);
    
    // V key codes
    final vPtr = 'v'.toNativeUtf8();
    final vKeysym = _xStringToKeysym(vPtr);
    final vKeycode = _xKeysymToKeycode(_display!, vKeysym);
    malloc.free(vPtr);
    
    // Press Control
    _xTestFakeKeyEvent(_display!, controlKeycode, 1, 0);
    // Press V
    _xTestFakeKeyEvent(_display!, vKeycode, 1, 0);
    // Release V
    _xTestFakeKeyEvent(_display!, vKeycode, 0, 0);
    // Release Control
    _xTestFakeKeyEvent(_display!, controlKeycode, 0, 0);
    
    _xFlush(_display!);
  }
}
