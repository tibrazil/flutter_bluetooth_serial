part of flutter_bluetooth_serial;

class FlutterBluetoothSerial {
  static const String namespace = 'flutter_bluetooth_serial';

  static final FlutterBluetoothSerial _instance = FlutterBluetoothSerial._();
  static FlutterBluetoothSerial get instance => _instance;

  static const MethodChannel _methodChannel =
      MethodChannel('$namespace/methods');
  static const EventChannel _stateChannel = EventChannel('$namespace/state');
  static const EventChannel _discoveryChannel =
      EventChannel('$namespace/discovery');

  FlutterBluetoothSerial._() {
    _methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'handlePairingRequest':
          if (_pairingRequestHandler != null) {
            return _pairingRequestHandler!(
                BluetoothPairingRequest.fromMap(call.arguments));
          }
          break;
        default:
          throw 'Unknown method: ${call.method}';
      }
    });
  }

  Future<bool?> get isAvailable => _methodChannel.invokeMethod('isAvailable');
  Future<bool?> get isEnabled => _methodChannel.invokeMethod('isEnabled');

  @Deprecated('Use `isEnabled` instead')
  Future<bool?> get isOn => isEnabled;

  Stream<BluetoothState> onStateChanged() => _stateChannel
      .receiveBroadcastStream()
      .map((data) => BluetoothState.fromUnderlyingValue(data));

  Future<BluetoothState> get state async => BluetoothState.fromUnderlyingValue(
      await _methodChannel.invokeMethod('getState'));

  Future<String?> get address => _methodChannel.invokeMethod("getAddress");
  Future<String?> get name => _methodChannel.invokeMethod("getName");

  Future<bool?> changeName(String name) =>
      _methodChannel.invokeMethod("setName", {"name": name});

  Future<bool?> requestEnable() => _methodChannel.invokeMethod('requestEnable');
  Future<bool?> requestDisable() =>
      _methodChannel.invokeMethod('requestDisable');
  Future<void> openSettings() => _methodChannel.invokeMethod('openSettings');

  Future<BluetoothBondState> getBondStateForAddress(String address) async {
    final state = await _methodChannel
        .invokeMethod('getDeviceBondState', {"address": address});
    return BluetoothBondState.fromUnderlyingValue(state);
  }

  Future<bool?> bondDeviceAtAddress(String address,
      {String? pin, bool? passkeyConfirm}) async {
    if (pin != null || passkeyConfirm != null) {
      if (_pairingRequestHandler != null) {
        throw "Pairing request handler already registered";
      }

      setPairingRequestHandler((request) async {
        Future.delayed(const Duration(seconds: 1), () {
          setPairingRequestHandler(null);
        });

        if (pin != null && request.pairingVariant == PairingVariant.Pin) {
          return pin;
        }

        if (passkeyConfirm != null &&
            (request.pairingVariant == PairingVariant.Consent ||
                request.pairingVariant == PairingVariant.PasskeyConfirmation)) {
          return passkeyConfirm;
        }

        return null;
      });
    }

    return _methodChannel.invokeMethod('bondDevice', {"address": address});
  }

  Future<bool?> removeDeviceBondWithAddress(String address) =>
      _methodChannel.invokeMethod('removeDeviceBond', {'address': address});

  Function? _pairingRequestHandler;

  void setPairingRequestHandler(
      Future<dynamic> Function(BluetoothPairingRequest request)? handler) {
    if (handler == null) {
      _pairingRequestHandler = null;
      _methodChannel.invokeMethod('pairingRequestHandlingDisable');
      return;
    }

    if (_pairingRequestHandler == null) {
      _methodChannel.invokeMethod('pairingRequestHandlingEnable');
    }
    _pairingRequestHandler = handler;
  }

  Future<List<BluetoothDevice>> getBondedDevices() async {
    final List list = await _methodChannel.invokeMethod('getBondedDevices');
    return list.map((map) => BluetoothDevice.fromMap(map)).toList();
  }

  Future<bool?> get isDiscovering =>
      _methodChannel.invokeMethod('isDiscovering');

  Stream<BluetoothDiscoveryResult> startDiscovery() async* {
    late StreamSubscription subscription;
    late StreamController controller;

    controller = StreamController(
      onCancel: () => subscription.cancel(),
    );

    await _methodChannel.invokeMethod('startDiscovery');

    subscription = _discoveryChannel.receiveBroadcastStream().listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );

    yield* controller.stream
        .map((map) => BluetoothDiscoveryResult.fromMap(map));
  }

  Future<void> cancelDiscovery() =>
      _methodChannel.invokeMethod('cancelDiscovery');

  Future<bool?> get isDiscoverable =>
      _methodChannel.invokeMethod("isDiscoverable");

  Future<int?> requestDiscoverable(int durationInSeconds) => _methodChannel
      .invokeMethod("requestDiscoverable", {"duration": durationInSeconds});

  // Deprecated methods for backward compatibility
  BluetoothConnection? _defaultConnection;

  @Deprecated('Use `BluetoothConnection.isConnected` instead')
  Future<bool> get isConnected async =>
      _defaultConnection?.isConnected ?? false;

  @Deprecated('Use `BluetoothConnection.toAddress(device.address)` instead')
  Future<void> connect(BluetoothDevice device) =>
      connectToAddress(device.address);

  @Deprecated('Use `BluetoothConnection.toAddress(address)` instead')
  Future<void> connectToAddress(String? address) async {
    _defaultConnection = await BluetoothConnection.toAddress(address);
  }

  @Deprecated(
      'Use `BluetoothConnection.finish` or `BluetoothConnection.close` instead')
  Future<void> disconnect() => _defaultConnection!.finish();

  @Deprecated('Use `BluetoothConnection.input` instead')
  Stream<Uint8List>? onRead() => _defaultConnection!.input;

  @Deprecated('Use `BluetoothConnection.output` with encoding instead')
  Future<void> write(String message) {
    _defaultConnection!.output.add(utf8.encode(message));
    return _defaultConnection!.output.allSent;
  }

  @Deprecated('Use `BluetoothConnection.output` instead')
  Future<void> writeBytes(Uint8List message) {
    _defaultConnection!.output.add(message);
    return _defaultConnection!.output.allSent;
  }
}
