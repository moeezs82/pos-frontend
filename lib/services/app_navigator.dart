import 'package:flutter/material.dart';

/// Global navigation hooks used by app-wide keyboard shortcuts.
///
/// Keeping this in one file prevents passing BuildContext through every screen
/// and makes shortcut navigation work from dialogs, lists, and nested pages.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
