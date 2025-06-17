part of flutter_bluetooth_serial;

class BluetoothDevice {
  final String? name;
  final String address;
  final BluetoothDeviceType type;
  final bool isConnected;
  final BluetoothBondState bondState;

  @Deprecated('Use `isBonded` instead')
  bool get bonded => bondState.isBonded;

  bool get isBonded => bondState.isBonded;

  const BluetoothDevice({
    this.name,
    required this.address,
    this.type = BluetoothDeviceType.unknown,
    this.isConnected = false,
    this.bondState = BluetoothBondState.unknown,
  });

  factory BluetoothDevice.fromMap(Map map) {
    return BluetoothDevice(
      name: map["name"],
      address: map["address"]!,
      type: map["type"] != null
          ? BluetoothDeviceType.fromUnderlyingValue(map["type"])
          : BluetoothDeviceType.unknown,
      isConnected: map["isConnected"] ?? false,
      bondState: map["bondState"] != null
          ? BluetoothBondState.fromUnderlyingValue(map["bondState"])
          : BluetoothBondState.unknown,
    );
  }

  Map<String, dynamic> toMap() => {
        "name": name,
        "address": address,
        "type": type.toUnderlyingValue(),
        "isConnected": isConnected,
        "bondState": bondState.toUnderlyingValue(),
      };

  BluetoothDevice copyWith({
    String? name,
    String? address,
    BluetoothDeviceType? type,
    bool? isConnected,
    BluetoothBondState? bondState,
  }) {
    return BluetoothDevice(
      name: name ?? this.name,
      address: address ?? this.address,
      type: type ?? this.type,
      isConnected: isConnected ?? this.isConnected,
      bondState: bondState ?? this.bondState,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BluetoothDevice && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() {
    return 'BluetoothDevice{name: $name, address: $address, type: $type, isConnected: $isConnected, bondState: $bondState}';
  }
}
