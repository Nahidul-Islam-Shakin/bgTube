package com.shakin.bgtube

/**
 * Tiny in-process bridge: the service (notification / headset buttons)
 * -> MainActivity -> Flutter (MethodChannel).
 */
object PlayerBridge {
    @Volatile
    var listener: ((String) -> Unit)? = null

    /** Returns false when nobody is listening (the Activity/Flutter engine is gone). */
    fun send(command: String): Boolean {
        val l = listener ?: return false
        l(command)
        return true
    }
}
