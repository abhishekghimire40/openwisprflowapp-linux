import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:characters/characters.dart';

class KeyboardSimulator {
  static void sendText(String text) {
    for (var char in text.characters) {
      // Convert character to virtual key code
      final scanCode = VkKeyScan(char.codeUnitAt(0));
      final vkCode = scanCode & 0xFF;
      
      // Press key
      final input1 = calloc<INPUT>();
      input1.ref.type = INPUT_KEYBOARD;
      input1.ref.ki.wVk = vkCode;
      
      // Release key
      final input2 = calloc<INPUT>();
      input2.ref.type = INPUT_KEYBOARD;
      input2.ref.ki.wVk = vkCode;
      input2.ref.ki.dwFlags = KEYEVENTF_KEYUP;
      
      final inputs = <INPUT>[input1.ref, input2.ref];
      final pInputs = calloc<INPUT>(inputs.length);
      
      for (var i = 0; i < inputs.length; i++) {
        pInputs[i] = inputs[i];
      }
      
      SendInput(inputs.length, pInputs, sizeOf<INPUT>());
      
      free(input1);
      free(input2);
      free(pInputs);
      
      // Small delay between characters
      Sleep(5);
    }
  }

  static void simulateCtrlV() {
    // Press Ctrl
    final input1 = calloc<INPUT>();
    input1.ref.type = INPUT_KEYBOARD;
    input1.ref.ki.wVk = VK_CONTROL;
    
    // Press V
    final input2 = calloc<INPUT>();
    input2.ref.type = INPUT_KEYBOARD;
    input2.ref.ki.wVk = 0x56; // V key
    
    // Release V
    final input3 = calloc<INPUT>();
    input3.ref.type = INPUT_KEYBOARD;
    input3.ref.ki.wVk = 0x56;
    input3.ref.ki.dwFlags = KEYEVENTF_KEYUP;
    
    // Release Ctrl
    final input4 = calloc<INPUT>();
    input4.ref.type = INPUT_KEYBOARD;
    input4.ref.ki.wVk = VK_CONTROL;
    input4.ref.ki.dwFlags = KEYEVENTF_KEYUP;
    
    final inputs = <INPUT>[
      input1.ref,
      input2.ref,
      input3.ref,
      input4.ref,
    ];
    final pInputs = calloc<INPUT>(inputs.length);
    
    for (var i = 0; i < inputs.length; i++) {
      pInputs[i] = inputs[i];
    }
    
    SendInput(inputs.length, pInputs, sizeOf<INPUT>());
    
    free(input1);
    free(input2);
    free(input3);
    free(input4);
    free(pInputs);
  }
} 