package com.hackathon.SafeSakhi

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.safesakhi/calls"
    private val EVENT_CHANNEL = "com.safesakhi/call_state"
    private val REQUEST_CALL_PHONE = 1001

    private var callStateSink: EventChannel.EventSink? = null
    private var permissionResultSink: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private var telephonyManager: TelephonyManager? = null

    @Suppress("DEPRECATION")
    private val phoneStateListenerCompat = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            val stateStr = when (state) {
                TelephonyManager.CALL_STATE_IDLE -> "IDLE"
                TelephonyManager.CALL_STATE_RINGING -> "RINGING"
                TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
                else -> "UNKNOWN"
            }
            Log.d("SafeSakhi", "Call state: $stateStr")
            handler.post {
                callStateSink?.success(stateStr)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "makeDirectCall" -> {
                        val number = call.argument<String>("number") ?: ""
                        makeDirectCall(number, result)
                    }
                    "requestCallPhonePermission" -> {
                        requestCallPhonePermission(result)
                    }
                    "setSpeakerphone" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setSpeakerphone(enabled, result)
                    }
                    "bringAppToForeground" -> {
                        bringAppToForeground()
                        result.success(true)
                    }
                    "startCallStateListener" -> {
                        startCallStateListener()
                        result.success(true)
                    }
                    "stopCallStateListener" -> {
                        stopCallStateListener()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    callStateSink = events
                    startCallStateListener()
                }

                override fun onCancel(arguments: Any?) {
                    callStateSink = null
                    stopCallStateListener()
                }
            })
    }

    private fun makeDirectCall(number: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(false)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$number")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e("SafeSakhi", "Direct call failed: ${e.message}")
            try {
                val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$number")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(dialIntent)
                result.success(true)
            } catch (e2: Exception) {
                result.success(false)
            }
        }
    }

    private fun requestCallPhonePermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
        } else {
            permissionResultSink?.success(false)
            permissionResultSink = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE),
                REQUEST_CALL_PHONE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALL_PHONE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d("SafeSakhi", "CALL_PHONE permission granted: $granted")
            permissionResultSink?.success(granted)
            permissionResultSink = null
        }
    }

    private fun setSpeakerphone(enabled: Boolean, result: MethodChannel.Result) {
        try {
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = enabled
            result.success(true)
        } catch (e: Exception) {
            Log.e("SafeSakhi", "Speaker error: ${e.message}")
            result.success(false)
        }
    }

    private fun bringAppToForeground() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("SafeSakhi", "Bring to foreground failed: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun startCallStateListener() {
        try {
            telephonyManager?.listen(
                phoneStateListenerCompat,
                PhoneStateListener.LISTEN_CALL_STATE
            )
        } catch (e: Exception) {
            Log.e("SafeSakhi", "Phone state listener error: ${e.message}")
        }
    }

    private fun stopCallStateListener() {
        try {
            telephonyManager?.listen(phoneStateListenerCompat, PhoneStateListener.LISTEN_NONE)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopCallStateListener()
        super.onDestroy()
    }
}
