// A CLI harness: stdout is its entire user interface.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Samples the phone's Dart isolate during a receive and reports where the
/// time actually goes.
///
/// The receive path reached 8.9 MiB/s on a link with roughly 20 MB/s of
/// headroom, while the same code does 45 MB/s over loopback on x86 and the
/// phone's storage writes at 251 MB/s. So neither the link nor the disk
/// explains it, which leaves the Dart path on ARM — and guessing which part
/// has already been wrong twice in this work, hence sampling it.
///
/// Usage:
///   `dart profile_receive.dart <vm-service-uri> [seconds]`
///
/// The URI is what `flutter run --profile` prints; it is already forwarded to
/// localhost by the flutter tool.
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart profile_receive.dart <vm-service-uri> [seconds]');
    exit(1);
  }

  final seconds = args.length > 1 ? int.parse(args[1]) : 30;

  // http://127.0.0.1:PORT/AUTH=/ -> ws://127.0.0.1:PORT/AUTH=/ws
  var uri = args[0].replaceFirst('http://', 'ws://');
  if (!uri.endsWith('/')) uri += '/';
  uri += 'ws';

  print('Connecting to $uri ...');
  final VmService service;
  try {
    service = await vmServiceConnectUri(uri);
  } catch (e) {
    print('Could not connect: $e');
    exit(1);
  }

  final vm = await service.getVM();
  final isolates = vm.isolates ?? [];
  if (isolates.isEmpty) {
    print('No isolates.');
    exit(1);
  }

  // The main isolate runs the receive path; the others are plugin workers.
  final isolateId = isolates.first.id!;
  print('Isolate: ${isolates.first.name} ($isolateId)');

  await service.clearCpuSamples(isolateId);
  print('Sampling for ${seconds}s — start the transfer now.');
  await Future<void>.delayed(Duration(seconds: seconds));

  final samples = await service.getCpuSamples(
    isolateId,
    0,
    DateTime.now().microsecondsSinceEpoch,
  );

  final functions = samples.functions ?? [];
  final sampleList = samples.samples ?? [];
  print('Collected ${sampleList.length} samples.');

  if (sampleList.isEmpty) {
    print('Nothing sampled — was the transfer running?');
    await service.dispose();
    return;
  }

  // Attribute each sample to the leaf frame: where the CPU actually was,
  // rather than everything on the stack beneath it.
  final leafCounts = <String, int>{};
  // And to every frame on the stack, which shows which subsystem the time
  // sits under even when the leaf is a generic primitive.
  final inclusiveCounts = <String, int>{};

  String nameFor(int index) {
    if (index < 0 || index >= functions.length) return '<unknown>';
    final fn = functions[index].function;
    if (fn is FuncRef) {
      final owner = fn.owner;
      final ownerName = owner is ClassRef
          ? '${owner.name}.'
          : owner is LibraryRef
              ? ''
              : '';
      return '$ownerName${fn.name}';
    }
    return functions[index].function?.toString() ?? '<unknown>';
  }

  for (final sample in sampleList) {
    final stack = sample.stack ?? [];
    if (stack.isEmpty) continue;

    leafCounts.update(nameFor(stack.first), (v) => v + 1, ifAbsent: () => 1);

    final seen = <String>{};
    for (final frame in stack) {
      final name = nameFor(frame);
      if (seen.add(name)) {
        inclusiveCounts.update(name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  void report(String title, Map<String, int> counts, int total) {
    print('\n=== $title ===');
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries.take(20)) {
      final pct = (e.value / total * 100).toStringAsFixed(1);
      print('${pct.padLeft(5)}%  ${e.key}');
    }
  }

  report('Self time (leaf frame)', leafCounts, sampleList.length);
  report('Inclusive (anywhere on stack)', inclusiveCounts, sampleList.length);

  await service.dispose();
}
