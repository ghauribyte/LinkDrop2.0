/// Represents a device discovered on the local network.
class Device {
  final String id;
  final String name;
  final String ipAddress;
  final DateTime lastSeen;

  Device({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.lastSeen,
  });

  Device copyWith({DateTime? lastSeen}) {
    return Device(
      id: id,
      name: name,
      ipAddress: ipAddress,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() => 'Device($name, id: $id, ip: $ipAddress)';
}
