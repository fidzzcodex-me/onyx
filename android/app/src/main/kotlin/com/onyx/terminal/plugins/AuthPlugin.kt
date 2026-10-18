package com.onyx.terminal.plugins

import androidx.fragment.app.FragmentActivity
import com.onyx.terminal.auth.AuthManager
import com.onyx.terminal.auth.BiometricAuth
import com.onyx.terminal.auth.PinManager
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.MainThread
import com.onyx.terminal.util.bool
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.util.str
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class AuthPlugin(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val auth = AuthManager(activity)
    private val pin = PinManager(activity)
    private val biometric = BiometricAuth(activity)
    private val store = CredentialStore.get(activity)
    private val channel = MethodChannel(messenger, Channels.AUTH)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "register" -> scope.reply(result) {
                auth.register(call.requireStr("name"), call.requireStr("email"), call.requireStr("password")).toMap()
            }
            "login" -> scope.reply(result) {
                auth.login(call.requireStr("email"), call.requireStr("password"), call.bool("remember", true)).toMap()
            }
            "loginGuest" -> scope.reply(result) { auth.loginGuest().toMap() }
            "logout" -> scope.reply(result) { auth.logout() }
            "currentUser" -> scope.reply(result) { auth.current()?.toMap() }
            "hasAccounts" -> scope.reply(result) { auth.hasAccounts() }
            "updateProfile" -> scope.reply(result) {
                auth.updateProfile(call.requireStr("name"), call.requireStr("email")).toMap()
            }
            "changePassword" -> scope.reply(result) {
                auth.changePassword(call.requireStr("oldPassword"), call.requireStr("newPassword"))
            }
            "resetPassword" -> scope.reply(result) {
                auth.resetPassword(call.requireStr("email"), call.requireStr("newPassword"))
            }
            "deleteAccount" -> scope.reply(result) { auth.deleteAccount() }
            "hasPin" -> scope.reply(result) { pin.hasPin() }
            "setPin" -> scope.reply(result) { pin.set(call.requireStr("pin")) }
            "clearPin" -> scope.reply(result) { pin.clear() }
            "verifyPin" -> scope.reply(result) {
                val outcome = pin.verify(call.requireStr("pin"))
                if (outcome["ok"] == true) auth.markVerified()
                outcome
            }
            "biometricAvailability" -> result.success(biometric.availability())
            "isBiometricEnabled" -> scope.reply(result) { store.get("biometric.enabled") == "1" }
            "setBiometricEnabled" -> scope.reply(result) {
                if (call.bool("enabled")) store.put("biometric.enabled", "1") else store.remove("biometric.enabled")
            }
            "biometricAuthenticate" -> {
                biometric.authenticate(call.str("title"), call.str("subtitle")) { ok, message ->
                    if (ok) auth.markVerified()
                    MainThread.post {
                        result.success(mapOf("ok" to ok, "message" to message))
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}
