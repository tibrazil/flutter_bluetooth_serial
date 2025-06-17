import 'package:flutter/material.dart';
import 'package:agros_flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:convert';

void main() {
  runApp(const BluetoothTestApp());
}

class BluetoothTestApp extends StatelessWidget {
  const BluetoothTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BluetoothTestScreen(),
    );
  }
}

class BluetoothTestScreen extends StatefulWidget {
  const BluetoothTestScreen({super.key});

  @override
  State<BluetoothTestScreen> createState() => _BluetoothTestScreenState();
}

class _BluetoothTestScreenState extends State<BluetoothTestScreen> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? _connection;
  List<BluetoothDevice> _bondedDevices = [];
  final List<BluetoothDiscoveryResult> _discoveredDevices = [];
  bool _isDiscovering = false;
  String _connectionStatus = 'Disconnected';
  final List<String> _messages = [];
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    final bluetoothSerial = FlutterBluetoothSerial.instance;

    final isAvailable = await bluetoothSerial.isAvailable;
    if (isAvailable != true) {
      _showSnackBar('Bluetooth not available');
      return;
    }

    final state = await bluetoothSerial.state;
    setState(() => _bluetoothState = state);

    bluetoothSerial.onStateChanged().listen((state) {
      setState(() => _bluetoothState = state);
    });

    _getBondedDevices();
  }

  Future<void> _getBondedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() => _bondedDevices = devices);
    } catch (e) {
      _showSnackBar('Error getting bonded devices: $e');
    }
  }

  Future<void> _enableBluetooth() async {
    try {
      final result = await FlutterBluetoothSerial.instance.requestEnable();
      if (result == true) {
        _showSnackBar('Bluetooth enabled');
      }
    } catch (e) {
      _showSnackBar('Error enabling Bluetooth: $e');
    }
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _discoveredDevices.clear();
      _isDiscovering = true;
    });

    try {
      final discovery = FlutterBluetoothSerial.instance.startDiscovery();
      discovery.listen(
        (result) {
          setState(() {
            final existingIndex = _discoveredDevices.indexWhere(
              (device) => device.device.address == result.device.address,
            );
            if (existingIndex >= 0) {
              _discoveredDevices[existingIndex] = result;
            } else {
              _discoveredDevices.add(result);
            }
          });
        },
        onDone: () {
          setState(() => _isDiscovering = false);
        },
        onError: (e) {
          setState(() => _isDiscovering = false);
          _showSnackBar('Discovery error: $e');
        },
      );
    } catch (e) {
      setState(() => _isDiscovering = false);
      _showSnackBar('Error starting discovery: $e');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_connection?.isConnected == true) {
      await _connection!.close();
    }

    setState(() => _connectionStatus = 'Connecting...');

    try {
      final connection = await BluetoothConnection.toAddress(device.address);

      connection.input?.listen(
        (data) {
          final message = String.fromCharCodes(data);
          setState(() {
            _messages.add('📨 Received: $message');
          });
        },
        onDone: () {
          setState(() => _connectionStatus = 'Disconnected');
          _showSnackBar('Connection closed');
        },
      );

      setState(() {
        _connection = connection;
        _connectionStatus = 'Connected to ${device.name ?? device.address}';
      });

      _showSnackBar('Connected successfully');
    } catch (e) {
      setState(() => _connectionStatus = 'Connection failed');
      _showSnackBar('Connection error: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_connection?.isConnected != true) {
      _showSnackBar('Not connected');
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      _connection!.output.add(utf8.encode(message));
      await _connection!.output.allSent;

      setState(() {
        _messages.add('📤 Sent: $message');
      });

      _messageController.clear();
    } catch (e) {
      _showSnackBar('Send error: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_connection?.isConnected == true) {
      await _connection!.close();
      setState(() {
        _connection = null;
        _connectionStatus = 'Disconnected';
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AGROs Bluetooth Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildControlsCard(),
            const SizedBox(height: 16),
            _buildDevicesCard(),
            const SizedBox(height: 16),
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildMessagesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bluetooth Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _bluetoothState.isEnabled
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _bluetoothState.isEnabled ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(_bluetoothState.toString()),
              ],
            ),
            const SizedBox(height: 8),
            Text('Connection: $_connectionStatus'),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Controls',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      _bluetoothState.isEnabled ? null : _enableBluetooth,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Enable BT'),
                ),
                ElevatedButton.icon(
                  onPressed: _bluetoothState.isEnabled && !_isDiscovering
                      ? _startDiscovery
                      : null,
                  icon: Icon(_isDiscovering ? Icons.search_off : Icons.search),
                  label: Text(_isDiscovering ? 'Searching...' : 'Discover'),
                ),
                ElevatedButton.icon(
                  onPressed:
                      _connection?.isConnected == true ? _disconnect : null,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_bondedDevices.isNotEmpty) ...[
              const Text('Bonded Devices:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ..._bondedDevices.map((device) => _buildDeviceTile(device, true)),
              const SizedBox(height: 16),
            ],
            if (_discoveredDevices.isNotEmpty) ...[
              const Text('Discovered Devices:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ..._discoveredDevices.map((result) =>
                  _buildDeviceTile(result.device, false, result.rssi)),
            ],
            if (_bondedDevices.isEmpty &&
                _discoveredDevices.isEmpty &&
                !_isDiscovering)
              const Text('No devices found. Try discovering devices.'),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(BluetoothDevice device, bool isBonded, [int? rssi]) {
    return ListTile(
      dense: true,
      leading: Icon(
        isBonded ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isBonded ? Colors.blue : Colors.grey,
      ),
      title: Text(device.name ?? 'Unknown Device'),
      subtitle:
          Text('${device.address}${rssi != null ? ' (RSSI: $rssi)' : ''}'),
      trailing: _connection?.isConnected == true
          ? null
          : IconButton(
              icon: const Icon(Icons.connect_without_contact),
              onPressed: () => _connectToDevice(device),
            ),
    );
  }

  Widget _buildConnectionCard() {
    if (_connection?.isConnected != true) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send Message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesCard() {
    if (_messages.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Messages',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _messages.clear()),
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      _messages[index],
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disconnect();
    _messageController.dispose();
    super.dispose();
  }
}
