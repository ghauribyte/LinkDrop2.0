import 'package:flutter/material.dart';

import 'screens/device_list_screen.dart';

void main() {
  runApp(const LinkDropApp());
}

class LinkDropApp extends StatelessWidget {
  const LinkDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkDrop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const DeviceListScreen(),
    );
  }
}
