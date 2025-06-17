# Bluetooth Serial Example

Example app demonstrating the usage of `agros_flutter_bluetooth_serial` plugin.

## Features Demonstrated

- ✅ Bluetooth adapter status monitoring
- ✅ Device discovery and bonding
- ✅ Connection management
- ✅ Real-time data communication
- ✅ Multiple device handling
- ✅ Error handling and recovery

## Installing
```yaml
dependencies:
  agros_flutter_bluetooth_serial:
    git:
      url: https://github.com/tibrazil/flutter_bluetooth_serial.git
      ref: master # ou tag específica como v1.0.0
```

## Running the Example

```bash
cd example
flutter pub get
flutter run
```

## Testing with Hardware

### HC-05 Bluetooth Module
1. Pair with HC-05 (default PIN: 1234 or 0000)
2. Connect via the app
3. Send AT commands:
   - `AT` → Should respond `OK`
   - `AT+VERSION` → Returns firmware version
   - `AT+NAME?` → Returns device name

### ESP32 Bluetooth
1. Use ESP32 with Bluetooth Classic enabled
2. Implement Serial Port Profile (SPP)
3. Test data exchange

## Code Structure

```dart
// Initialize Bluetooth
final bluetooth = FlutterBluetoothSerial.instance;

// Connect to device
final connection = await BluetoothConnection.toAddress(deviceAddress);

// Listen for data
connection.input?.listen((data) {
  final message = String.fromCharCodes(data);
  print('Received: $message');
});

// Send data
connection.output.add(utf8.encode('Hello Device!'));

// Cleanup
await connection.finish();
```

## Troubleshooting

### Common Issues

1. **Permissions**: Ensure location permissions are granted
2. **Pairing**: Device must be paired before connection
3. **Discovery**: May take time to find devices
4. **Connection**: Check if device is in range and not connected elsewhere

### Android 12+ Notes

The app automatically handles new Bluetooth permissions for Android 12+:
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_ADVERTISE`