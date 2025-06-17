package com.tibrazil.agros.flutter_bluetooth_serial

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import kotlinx.coroutines.*
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.*
import java.util.concurrent.atomic.AtomicBoolean

abstract class BluetoothConnection(private val bluetoothAdapter: BluetoothAdapter) {
    
    companion object {
        private val DEFAULT_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val BUFFER_SIZE = 1024
    }
    
    private var connectionJob: Job? = null
    private var socket: BluetoothSocket? = null
    private val isConnectedFlag = AtomicBoolean(false)
    
    val isConnected: Boolean get() = isConnectedFlag.get()
    
    @Throws(IOException::class)
    suspend fun connect(address: String, uuid: UUID = DEFAULT_UUID) = withContext(Dispatchers.IO) {
        if (isConnected) throw IOException("Already connected")
        
        val device = bluetoothAdapter.getRemoteDevice(address)
            ?: throw IOException("Device not found")
        
        val bluetoothSocket = device.createRfcommSocketToServiceRecord(uuid)
            ?: throw IOException("Socket connection not established")
        
        bluetoothAdapter.cancelDiscovery()
        bluetoothSocket.connect()
        
        socket = bluetoothSocket
        isConnectedFlag.set(true)
        
        connectionJob = CoroutineScope(Dispatchers.IO + SupervisorJob()).launch {
            handleConnection(bluetoothSocket)
        }
    }
    
    fun disconnect() {
        isConnectedFlag.set(false)
        connectionJob?.cancel()
        socket?.runCatching { close() }
        socket = null
    }
    
    @Throws(IOException::class)
    suspend fun write(data: ByteArray) = withContext(Dispatchers.IO) {
        if (!isConnected) throw IOException("Not connected")
        socket?.outputStream?.write(data) ?: throw IOException("Output stream unavailable")
    }
    
    private suspend fun handleConnection(socket: BluetoothSocket) {
        val buffer = ByteArray(BUFFER_SIZE)
        
        try {
            val inputStream = socket.inputStream
            
            while (isConnected && !currentCoroutineContext().job.isCancelled) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead > 0) {
                    onRead(buffer.copyOf(bytesRead))
                }
            }
        } catch (e: IOException) {
            if (isConnected) {
                onDisconnected(true)
            }
        } finally {
            cleanup()
        }
    }
    
    private fun cleanup() {
        runCatching {
            socket?.inputStream?.close()
            socket?.outputStream?.close()
            socket?.close()
        }
        
        if (isConnected) {
            isConnectedFlag.set(false)
            onDisconnected(false)
        }
    }
    
    protected abstract fun onRead(data: ByteArray)
    protected abstract fun onDisconnected(byRemote: Boolean)
}