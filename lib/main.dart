import 'package:flutter/material.dart';

import 'screens/device_list_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/send_screen.dart';
import 'screens/wifi_direct_screen.dart';

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
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LinkDrop')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SendScreen()),
              ),
              icon: const Icon(Icons.send),
              label: const Text('Send a File'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiveScreen()),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Receive Files'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceListScreen()),
              ),
              icon: const Icon(Icons.devices),
              label: const Text('Nearby Devices'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WifiDirectScreen()),
              ),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Wi-Fi Direct'),
            ),
          ],
        ),
      ),
    );
  }
}
