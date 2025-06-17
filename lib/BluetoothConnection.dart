// lib/BluetoothConnection.dart
part of flutter_bluetooth_serial;

class BluetoothConnection {
  final int? _id;
  final EventChannel _readChannel;
  late StreamSubscription<Uint8List> _readSubscription;
  late StreamController<Uint8List> _readController;

  Stream<Uint8List>? input;
  late _BluetoothStreamSink output;

  bool get isConnected => output.isConnected;

  BluetoothConnection._consumeConnectionID(int? id)
      : _id = id,
        _readChannel =
            EventChannel('${FlutterBluetoothSerial.namespace}/read/$id') {
    _readController = StreamController<Uint8List>();

    _readSubscription =
        _readChannel.receiveBroadcastStream().cast<Uint8List>().listen(
              _readController.add,
              onError: _readController.addError,
              onDone: close,
            );

    input = _readController.stream;
    output = _BluetoothStreamSink<Uint8List>(_id);
  }

  static Future<BluetoothConnection> toAddress(String? address) async {
    final id = await FlutterBluetoothSerial._methodChannel
        .invokeMethod('connect', {"address": address});
    return BluetoothConnection._consumeConnectionID(id);
  }

  void dispose() => finish();

  Future<void> close() async {
    await Future.wait([
      output.close(),
      _readSubscription.cancel(),
      if (!_readController.isClosed)
        _readController.close()
      else
        Future.value(),
    ], eagerError: true);
  }

  @Deprecated('Use `close` instead')
  Future<void> cancel() => close();

  Future<void> finish() async {
    await output.allSent;
    return close();
  }
}

class _BluetoothStreamSink<T> implements StreamSink<T> {
  final int? _id;
  bool isConnected = true;
  Future<void> _chainedFutures = Future.value();
  late Future<dynamic> _doneFuture;
  dynamic exception;

  _BluetoothStreamSink(this._id) {
    _doneFuture = Future(() async {
      while (isConnected) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (exception != null) throw exception;
    });
  }

  @override
  void add(T data) {
    if (!isConnected) throw StateError("Not connected!");

    _chainedFutures = _chainedFutures.then((_) async {
      if (!isConnected) throw StateError("Not connected!");

      await FlutterBluetoothSerial._methodChannel.invokeMethod('write', {
        'id': _id,
        'bytes': data,
      });
    }).catchError((e) {
      exception = e;
      close();
    });
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    throw UnsupportedError(
        "BluetoothConnection output sink cannot receive errors!");
  }

  @override
  Future addStream(Stream<T> stream) async {
    final completer = Completer<void>();
    stream.listen(add).onDone(completer.complete);
    await completer.future;
    await _chainedFutures;
  }

  @override
  Future close() {
    isConnected = false;
    return done;
  }

  @override
  Future get done => _doneFuture;

  Future get allSent async {
    Future lastFuture;
    do {
      lastFuture = _chainedFutures;
      await lastFuture;
    } while (lastFuture != _chainedFutures);

    if (exception != null) throw exception;
    _chainedFutures = Future.value();
  }
}
