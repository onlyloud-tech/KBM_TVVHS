// ApplicationLoopback.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <Windows.h>
#include <iostream>
#include <mmsystem.h>
#include "LoopbackCapture.h"
#include "MicCapture.h"

#pragma comment(lib, "winmm.lib")

void usage()
{
    std::wcout <<
        L"Usage: ApplicationLoopback <pid> <includetree|excludetree> <outputfilename> [seconds] [micfilename]\n"
        L"\n"
        L"<pid> is the process ID to capture or exclude from capture\n"
        L"includetree includes audio from that process and its child processes\n"
        L"excludetree includes audio from all processes except that process and its child processes\n"
        L"<outputfilename> is the WAV file to receive the captured audio\n"
        L"[seconds] is the capture duration, from 1 to 600 (default 10)\n"
        L"\n"
        L"Examples:\n"
        L"\n"
        L"ApplicationLoopback 1234 includetree CapturedAudio.wav\n"
        L"\n"
        L"  Captures audio from process 1234 and its children.\n"
        L"\n"
        L"ApplicationLoopback 1234 excludetree CapturedAudio.wav\n"
        L"\n"
        L"  Captures audio from all processes except process 1234 and its children.\n";
}

int wmain(int argc, wchar_t* argv[])
{
    if (argc < 4 || argc > 6)
    {
        usage();
        return 0;
    }

    DWORD processId = wcstoul(argv[1], nullptr, 0);
    if (processId == 0)
    {
        usage();
        return 0;
    }

    bool includeProcessTree;
    if (wcscmp(argv[2], L"includetree") == 0)
    {
        includeProcessTree = true;
    }
    else if (wcscmp(argv[2], L"excludetree") == 0)
    {
        includeProcessTree = false;
    }
    else
    {
        usage();
        return 0;
    }

    PCWSTR outputFile = argv[3];
    unsigned seconds = 10;
    if (argc >= 5)
    {
        wchar_t* end = nullptr;
        unsigned long parsed = wcstoul(argv[4], &end, 10);
        if (!end || *end || parsed < 1 || parsed > 600)
        {
            usage();
            return 2;
        }
        seconds = static_cast<unsigned>(parsed);
    }

    std::wcout << L"Microphone input devices: " << waveInGetNumDevs() << L"\n";
    std::wcout << L"Playback output devices: " << waveOutGetNumDevs() << L"\n";
    if (waveInGetNumDevs())
    {
        WAVEINCAPSW caps{};
        if (waveInGetDevCapsW(WAVE_MAPPER, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
            std::wcout << L"Microphone: " << caps.szPname << L" formats=0x"
                << std::hex << caps.dwFormats << std::dec << L" channels=" << caps.wChannels << L"\n";
        for (DWORD rate : { 44100UL, 48000UL, 22050UL })
            for (WORD channels : { 1, 2 })
            {
                WAVEFORMATEX format{};
                format.wFormatTag = WAVE_FORMAT_PCM;
                format.nChannels = channels;
                format.nSamplesPerSec = rate;
                format.wBitsPerSample = 16;
                format.nBlockAlign = channels * 2;
                format.nAvgBytesPerSec = rate * format.nBlockAlign;
                const auto result = waveInOpen(nullptr, WAVE_MAPPER, &format, 0, 0, WAVE_FORMAT_QUERY);
                std::wcout << L"MIC_FORMAT " << rate << L"Hz " << channels
                    << L"ch result=" << result << L"\n";
            }
    }

    CLoopbackCapture loopbackCapture;
    HRESULT hr = loopbackCapture.StartCaptureAsync(processId, includeProcessTree, outputFile);
    if (FAILED(hr))
    {
        wil::unique_hlocal_string message;
        FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_ALLOCATE_BUFFER, nullptr, hr,
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (PWSTR)&message, 0, nullptr);
        std::wcout << L"Failed to start capture\n0x" << std::hex << hr << L": " << message.get() << L"\n";
    }
    else
    {
        std::wcout << L"Capturing " << seconds << L" seconds of audio." << std::endl;
        MicCapture mic;
        if (argc == 6)
            std::wcout << (mic.Start(argv[5]) ? L"MIC_CAPTURE=STARTED\n" : L"MIC_CAPTURE=UNAVAILABLE\n");
        // Java's ProcessBuilder supplies a pipe on stdin. A newline stops an
        // early recording; otherwise the declared duration stops it.
        HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
        for (unsigned elapsed = 0; elapsed < seconds * 1000; elapsed += 20)
        {
            DWORD available = 0;
            if (input && input != INVALID_HANDLE_VALUE &&
                PeekNamedPipe(input, nullptr, 0, nullptr, &available, nullptr) && available)
            {
                char command = 0;
                DWORD read = 0;
                if (ReadFile(input, &command, 1, &read, nullptr) && read) break;
            }
            Sleep(20);
        }

        mic.Stop();
        loopbackCapture.StopCaptureAsync();

        std::wcout << L"Finished.\n";
    }

    return 0;
}
