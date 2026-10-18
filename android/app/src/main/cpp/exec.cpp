#include <jni.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern "C" JNIEXPORT jint JNICALL
Java_com_onyx_terminal_terminal_NativeExec_waitFor(JNIEnv*, jobject, jint pid) {
    int status = 0;
    pid_t result;
    do {
        result = waitpid(static_cast<pid_t>(pid), &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return -WTERMSIG(status);
    return -1;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_onyx_terminal_terminal_NativeExec_signal(JNIEnv*, jobject, jint pid, jint sig, jboolean group) {
    if (pid <= 1) return -1;
    if (group == JNI_TRUE) {
        return killpg(static_cast<pid_t>(pid), sig);
    }
    return kill(static_cast<pid_t>(pid), sig);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_onyx_terminal_terminal_NativeExec_isAlive(JNIEnv*, jobject, jint pid) {
    if (pid <= 1) return 0;
    return kill(static_cast<pid_t>(pid), 0) == 0 ? 1 : 0;
}
