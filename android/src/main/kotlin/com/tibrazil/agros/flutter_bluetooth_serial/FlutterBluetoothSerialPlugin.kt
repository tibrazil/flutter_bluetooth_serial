package com.tibrazil.agros.flutter_bluetooth_serial

import android.Manifest
import android.app.Activity
import android.bluetooth.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import kotlinx.coroutines.*
import kotlin.collections.HashMap

class FlutterBluetoothSerialPlugin : FlutterPlugin, ActivityAware {
    
    companion object {
        private const val NAMESPACE = "flutter_bluetooth_serial"
        private const val REQUEST_ENABLE_BLUETOOTH = 1337
        private const val REQUEST_DISCOVERABLE_BLUETOOTH = 2137
        private const val REQUEST_LOCATION_PERMISSIONS = 1451
    }
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var stateChannel: EventChannel
    private lateinit var discoveryChannel: EventChannel
    private lateinit var binaryMessenger: BinaryMessenger
    
    private var activity: Activity? = null
    private var context: Context? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    
    private var pendingResult: MethodChannel.Result? = null
    private var stateSink: EventChannel.EventSink? = null
    private var discoverySink: EventChannel.EventSink? = null
    
    private val connections = mutableMapOf<Int, BluetoothConnectionWrapper>()
    private var lastConnectionId = 0
    
    private val pluginScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                connections.values.forEach { it.disconnect() }
                connections.clear()
                
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothDevice.ERROR)
                stateSink?.success(state)
            }
        }
    }
    
    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    
                    device?.let {
                        val result = mapOf(
                            "address" to it.address,
                            "name" to it.name,
                            "type" to it.type,
                            "isConnected" to isDeviceConnected(it),
                            "bondState" to it.bondState,
                            "rssi" to rssi.toInt()
                        )
                        discoverySink?.success(result)
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    context?.unregisterReceiver(this)
                    bluetoothAdapter?.cancelDiscovery()
                    discoverySink?.endOfStream()
                    discoverySink = null
                }
            }
        }
    }
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binaryMessenger = binding.binaryMessenger
        
        methodChannel = MethodChannel(binaryMessenger, "$NAMESPACE/methods")
        methodChannel.setMethodCallHandler(::onMethodCall)
        
        stateChannel = EventChannel(binaryMessenger, "$NAMESPACE/state")
        stateChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                stateSink = events
                context?.registerReceiver(stateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
            }
            
            override fun onCancel(arguments: Any?) {
                stateSink = null
                context?.runCatching { unregisterReceiver(stateReceiver) }
            }
        })
        
        discoveryChannel = EventChannel(binaryMessenger, "$NAMESPACE/discovery")
        discoveryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                discoverySink = events
            }
            
            override fun onCancel(arguments: Any?) {
                context?.runCatching { unregisterReceiver(discoveryReceiver) }
                bluetoothAdapter?.cancelDiscovery()
                discoverySink?.endOfStream()
                discoverySink = null
            }
        })
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        pluginScope.cancel()
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        context = binding.activity.applicationContext
        
        val bluetoothManager = activity?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            when (requestCode) {
                REQUEST_ENABLE_BLUETOOTH -> {
                    pendingResult?.success(resultCode != Activity.RESULT_CANCELED)
                    pendingResult = null
                    true
                }
                REQUEST_DISCOVERABLE_BLUETOOTH -> {
                    pendingResult?.success(if (resultCode == Activity.RESULT_CANCELED) -1 else resultCode)
                    pendingResult = null
                    true
                }
                else -> false
            }
        }
        
        binding.addRequestPermissionsResultListener { requestCode, _, grantResults ->
            if (requestCode == REQUEST_LOCATION_PERMISSIONS) {
                pendingResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
                pendingResult = null
                true
            } else false
        }
    }
    
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {
        activity = null
        context = null
    }
    
    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (bluetoothAdapter == null && call.method != "isAvailable") {
            result.error("bluetooth_unavailable", "Bluetooth is not available", null)
            return
        }
        
        when (call.method) {
            "isAvailable" -> result.success(bluetoothAdapter != null)
            "isEnabled" -> result.success(bluetoothAdapter?.isEnabled ?: false)
            "getState" -> result.success(bluetoothAdapter?.state ?: BluetoothAdapter.ERROR)
            "requestEnable" -> requestEnable(result)
            "requestDisable" -> requestDisable(result)
            "openSettings" -> openSettings(result)
            "getBondedDevices" -> getBondedDevices(result)
            "startDiscovery" -> startDiscovery(result)
            "cancelDiscovery" -> cancelDiscovery(result)
            "connect" -> connect(call, result)
            "write" -> write(call, result)
            "isDiscovering" -> result.success(bluetoothAdapter?.isDiscovering ?: false)
            "isDiscoverable" -> result.success(bluetoothAdapter?.scanMode == BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE)
            "requestDiscoverable" -> requestDiscoverable(call, result)
            else -> result.notImplemented()
        }
    }
    
    private fun requestEnable(result: MethodChannel.Result) {
        bluetoothAdapter?.let { adapter ->
            if (!adapter.isEnabled) {
                pendingResult = result
                val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                activity?.startActivityForResult(intent, REQUEST_ENABLE_BLUETOOTH)
            } else {
                result.success(true)
            }
        } ?: result.error("bluetooth_unavailable", "Bluetooth adapter not available", null)
    }
    
    private fun requestDisable(result: MethodChannel.Result) {
        bluetoothAdapter?.let { adapter ->
            if (adapter.isEnabled) {
                adapter.disable()
                result.success(true)
            } else {
                result.success(false)
            }
        } ?: result.error("bluetooth_unavailable", "Bluetooth adapter not available", null)
    }
    
    private fun openSettings(result: MethodChannel.Result) {
        val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
        activity?.startActivity(intent)
        result.success(null)
    }
    
    private fun getBondedDevices(result: MethodChannel.Result) {
        ensurePermissions { granted ->
            if (!granted) {
                result.error("no_permissions", "Location permission required for device discovery", null)
                return@ensurePermissions
            }
            
            bluetoothAdapter?.bondedDevices?.let { devices ->
                val deviceList = devices.map { device ->
                    mapOf(
                        "address" to device.address,
                        "name" to device.name,
                        "type" to device.type,
                        "isConnected" to isDeviceConnected(device),
                        "bondState" to BluetoothDevice.BOND_BONDED
                    )
                }
                result.success(deviceList)
            } ?: result.error("bluetooth_unavailable", "Bluetooth adapter not available", null)
        }
    }
    
    private fun startDiscovery(result: MethodChannel.Result) {
        ensurePermissions { granted ->
            if (!granted) {
                result.error("no_permissions", "Location permission required for device discovery", null)
                return@ensurePermissions
            }
            
            val filter = IntentFilter().apply {
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                addAction(BluetoothDevice.ACTION_FOUND)
            }
            context?.registerReceiver(discoveryReceiver, filter)
            bluetoothAdapter?.startDiscovery()
            result.success(null)
        }
    }
    
    private fun cancelDiscovery(result: MethodChannel.Result) {
        context?.runCatching { unregisterReceiver(discoveryReceiver) }
        bluetoothAdapter?.cancelDiscovery()
        discoverySink?.endOfStream()
        discoverySink = null
        result.success(null)
    }
    
    private fun requestDiscoverable(call: MethodCall, result: MethodChannel.Result) {
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
        call.argument<Int>("duration")?.let { duration ->
            intent.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, duration)
        }
        pendingResult = result
        activity?.startActivityForResult(intent, REQUEST_DISCOVERABLE_BLUETOOTH)
    }
    
    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        if (address == null) {
            result.error("invalid_argument", "Address argument not found", null)
            return
        }
        
        bluetoothAdapter?.let { adapter ->
            val id = ++lastConnectionId
            val connection = BluetoothConnectionWrapper(id, adapter)
            connections[id] = connection
            
            pluginScope.launch {
                try {
                    connection.connect(address)
                    result.success(id)
                } catch (e: Exception) {
                    connections.remove(id)
                    result.error("connect_error", e.message, null)
                }
            }
        } ?: result.error("bluetooth_unavailable", "Bluetooth adapter not available", null)
    }
    
    private fun write(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id")
        if (id == null) {
            result.error("invalid_argument", "ID argument not found", null)
            return
        }
        
        val connection = connections[id]
        if (connection == null) {
            result.error("invalid_argument", "Connection with provided ID not found", null)
            return
        }
        
        val data = when {
            call.hasArgument("string") -> call.argument<String>("string")?.toByteArray()
            call.hasArgument("bytes") -> call.argument<ByteArray>("bytes")
            else -> null
        }
        
        if (data == null) {
            result.error("invalid_argument", "Either 'string' or 'bytes' argument required", null)
            return
        }
        
        pluginScope.launch {
            try {
                connection.write(data)
                result.success(null)
            } catch (e: Exception) {
                result.error("write_error", e.message, null)
            }
        }
    }
    
    private fun ensurePermissions(callback: (Boolean) -> Unit) {
        val activity = this.activity ?: return callback(false)
        
        val requiredPermissions = mutableListOf<String>().apply {
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        }
        
        val missingPermissions = requiredPermissions.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        
        if (missingPermissions.isEmpty()) {
            callback(true)
        } else {
            pendingResult = object : MethodChannel.Result {
                override fun success(result: Any?) {
                    callback(result as? Boolean ?: false)
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    callback(false)
                }
                override fun notImplemented() {
                    callback(false)
                }
            }
            ActivityCompat.requestPermissions(activity, missingPermissions.toTypedArray(), REQUEST_LOCATION_PERMISSIONS)
        }
    }
    
    private fun isDeviceConnected(device: BluetoothDevice): Boolean {
        return try {
            val method = device.javaClass.getMethod("isConnected")
            method.invoke(device) as Boolean
        } catch (e: Exception) {
            false
        }
    }
    
    private inner class BluetoothConnectionWrapper(
        private val id: Int,
        adapter: BluetoothAdapter
    ) : BluetoothConnection(adapter) {
        
        private val readChannel = EventChannel(binaryMessenger, "$NAMESPACE/read/$id")
        private var readSink: EventChannel.EventSink? = null
        
        init {
            readChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    readSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    disconnect()
                    pluginScope.launch {
                        readChannel.setStreamHandler(null)
                        connections.remove(id)
                    }
                }
            })
        }
        
        override fun onRead(data: ByteArray) {
            activity?.runOnUiThread {
                readSink?.success(data)
            }
        }
        
        override fun onDisconnected(byRemote: Boolean) {
            activity?.runOnUiThread {
                if (byRemote) {
                    readSink?.endOfStream()
                    readSink = null
                }
            }
        }
    }
}