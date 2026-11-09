import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool appLockEnabled;
  final ThemeMode themeMode;

  SettingsState({
    this.appLockEnabled = false,
    this.themeMode = ThemeMode.system,
  });

  SettingsState copyWith({
    bool? appLockEnabled,
    ThemeMode? themeMode,
  }) {
    return SettingsState(
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  late final SharedPreferences _prefs;

  @override
  SettingsState build() {
    _initPrefs();
    return SettingsState();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final lockEnabled = _prefs.getBool('app_lock_enabled') ?? false;
    final isDark = _prefs.getBool('is_dark_mode');
    
    ThemeMode mode = ThemeMode.system;
    if (isDark != null) {
      mode = isDark ? ThemeMode.dark : ThemeMode.light;
    }

    state = state.copyWith(
      appLockEnabled: lockEnabled,
      themeMode: mode,
    );
  }

  Future<void> toggleAppLock() async {
    final newValue = !state.appLockEnabled;
    await _prefs.setBool('app_lock_enabled', newValue);
    state = state.copyWith(appLockEnabled: newValue);
  }

  Future<void> toggleThemeMode() async {
    final isCurrentlyDark = state.themeMode == ThemeMode.dark || 
        (state.themeMode == ThemeMode.system && 
         WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    
    final newMode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    await _prefs.setBool('is_dark_mode', !isCurrentlyDark);
    state = state.copyWith(themeMode: newMode);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
