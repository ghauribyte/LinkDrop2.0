import 'dart:io';
import 'lib/engine/cert_exchange.dart';

/// Quick manual test for the cert exchange client.
/// Usage: dart fetch_cert_test.dart <receiver_ip> [port]
///
/// Run this against a receiver that's already running (receiver.dart),
/// which now also starts a CertServer automatically. Confirms the
/// fetched cert is valid PEM before trusting it in the real send flow.
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart fetch_cert_test.dart <receiver_ip> [port]');
    exit(1);
  }

  final ip = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 7980;

  print('Fetching cert from $ip:$port...');
  final cert = await fetchCert(ip: ip, port: port);

  if (cert == null) {
    print('Failed to fetch cert — no response, timeout, or invalid PEM.');
    exit(1);
  }

  print('Got cert (${cert.length} chars):');
  print(cert);
}
