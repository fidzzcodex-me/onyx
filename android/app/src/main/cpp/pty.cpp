#include <jni.h>
#include <android/log.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <string>
#include <vector>

#define LOG_TAG "OnyxPty"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

std::string toStdString(JNIEnv* env, jstring value) {
    if (value == nullptr) return std::string();
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return std::string();
    std::string out(chars);
    env->ReleaseStringUTFChars(value, chars);
    return out;
}

std::vector<std::string> toStringVector(JNIEnv* env, jobjectArray array) {
    std::vector<std::string> out;
    if (array == nullptr) return out;
    jsize length = env->GetArrayLength(array);
    out.reserve(static_cast<size_t>(length));
    for (jsize i = 0; i < length; ++i) {
        jstring item = static_cast<jstring>(env->GetObjectArrayElement(array, i));
        out.push_back(toStdString(env, item));
        if (item != nullptr) env->DeleteLocalRef(item);
    }
    return out;
}

std::vector<char*> toPointers(std::vector<std::string>& storage) {
    std::vector<char*> out;
    out.reserve(storage.size() + 1);
    for (auto& entry : storage) out.push_back(const_cast<char*>(entry.c_str()));
    out.push_back(nullptr);
    return out;
}

void closeInheritedDescriptors() {
    DIR* dir = opendir("/proc/self/fd");
    if (dir == nullptr) {
        for (int fd = 3; fd < 256; ++fd) close(fd);
        return;
    }
    int dirFd = dirfd(dir);
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
        int fd = atoi(entry->d_name);
        if (fd > 2 && fd != dirFd) close(fd);
    }
    closedir(dir);
}

}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_onyx_terminal_terminal_NativePty_open(JNIEnv* env, jobject, jstring cmd, jobjectArray args,
                                               jobjectArray envp, jstring cwd, jint rows, jint cols) {
    std::string command = toStdString(env, cmd);
    std::string workdir = toStdString(env, cwd);
    std::vector<std::string> argStorage = toStringVector(env, args);
    std::vector<std::string> envStorage = toStringVector(env, envp);
    std::vector<char*> argv = toPointers(argStorage);
    std::vector<char*> environment = toPointers(envStorage);

    int master = open("/dev/ptmx", O_RDWR | O_CLOEXEC);
    if (master < 0) {
        LOGE("open ptmx failed: %s", strerror(errno));
        return nullptr;
    }

    char slaveName[64];
    if (grantpt(master) != 0 || unlockpt(master) != 0 || ptsname_r(master, slaveName, sizeof(slaveName)) != 0) {
        LOGE("pty setup failed: %s", strerror(errno));
        close(master);
        return nullptr;
    }

    struct termios tios;
    if (tcgetattr(master, &tios) == 0) {
        tios.c_iflag |= IUTF8;
        tios.c_iflag &= ~(IXON | IXOFF);
        tcsetattr(master, TCSANOW, &tios);
    }

    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = static_cast<unsigned short>(rows);
    size.ws_col = static_cast<unsigned short>(cols);
    ioctl(master, TIOCSWINSZ, &size);

    pid_t pid = fork();
    if (pid < 0) {
        LOGE("fork failed: %s", strerror(errno));
        close(master);
        return nullptr;
    }

    if (pid == 0) {
        sigset_t mask;
        sigemptyset(&mask);
        sigprocmask(SIG_SETMASK, &mask, nullptr);
        signal(SIGHUP, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGQUIT, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGCHLD, SIG_DFL);

        setsid();

        int slave = open(slaveName, O_RDWR);
        if (slave < 0) _exit(1);
        ioctl(slave, TIOCSCTTY, 0);

        dup2(slave, 0);
        dup2(slave, 1);
        dup2(slave, 2);
        if (slave > 2) close(slave);

        closeInheritedDescriptors();

        if (!workdir.empty()) {
            if (chdir(workdir.c_str()) != 0) chdir("/");
        }

        execve(command.c_str(), argv.data(), environment.data());
        _exit(127);
    }

    jintArray out = env->NewIntArray(2);
    if (out == nullptr) {
        kill(pid, SIGKILL);
        close(master);
        return nullptr;
    }
    jint values[2] = {master, static_cast<jint>(pid)};
    env->SetIntArrayRegion(out, 0, 2, values);
    return out;
}

extern "C" JNIEXPORT void JNICALL
Java_com_onyx_terminal_terminal_NativePty_setSize(JNIEnv*, jobject, jint fd, jint rows, jint cols,
                                                  jint pixelWidth, jint pixelHeight) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = static_cast<unsigned short>(rows);
    size.ws_col = static_cast<unsigned short>(cols);
    size.ws_xpixel = static_cast<unsigned short>(pixelWidth);
    size.ws_ypixel = static_cast<unsigned short>(pixelHeight);
    ioctl(fd, TIOCSWINSZ, &size);
}
