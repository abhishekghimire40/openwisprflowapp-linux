import 'keyboard_simulator_linux.dart';

class KeyboardSimulator {
  static void sendText(String text) {
    LinuxKeyboardSimulator.sendText(text);
  }

  static void simulateCtrlV() {
    LinuxKeyboardSimulator.simulateCtrlV();
  }
}