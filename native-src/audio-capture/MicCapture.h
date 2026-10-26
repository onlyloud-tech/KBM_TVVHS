#pragma once

#include <Windows.h>
#include <mmsystem.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <thread>

// Diagnostic microphone recorder. PCM16 mono 44.1 kHz, independent of the
// process-loopback capture; the two tracks are intentionally kept separate.
class MicCapture {
public:
    ~MicCapture() { Stop(); }
    bool Start(const wchar_t* path);
    void Stop();

private:
    void Run();
    void WriteHeader();
    HWAVEIN input_ = nullptr;
    HANDLE ready_ = nullptr;
    FILE* file_ = nullptr;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::array<std::array<char, 17640>, 4> buffers_{};
    std::array<WAVEHDR, 4> headers_{};
    DWORD bytes_ = 0;
};
