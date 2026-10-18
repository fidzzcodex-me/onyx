package com.onyx.terminal.auth

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.onyx.terminal.R

class BiometricAuth(private val activity: FragmentActivity) {
    private val allowed =
        BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.BIOMETRIC_WEAK

    fun availability(): String =
        when (BiometricManager.from(activity).canAuthenticate(allowed)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none_enrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "no_hardware"
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "hw_unavailable"
            else -> "unavailable"
        }

    fun authenticate(title: String?, subtitle: String?, done: (Boolean, String?) -> Unit) {
        activity.runOnUiThread {
            val executor = ContextCompat.getMainExecutor(activity)
            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    done(true, null)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    done(false, errString.toString())
                }
            }
            val prompt = BiometricPrompt(activity, executor, callback)
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle(title ?: activity.getString(R.string.biometric_title))
                .setSubtitle(subtitle ?: activity.getString(R.string.biometric_subtitle))
                .setAllowedAuthenticators(allowed)
                .setNegativeButtonText(activity.getString(R.string.biometric_cancel))
                .build()
            try {
                prompt.authenticate(info)
            } catch (error: Exception) {
                done(false, error.message)
            }
        }
    }
}
