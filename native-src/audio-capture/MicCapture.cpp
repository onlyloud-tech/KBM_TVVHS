#include "MicCapture.h"
#include <iostream>

#pragma comment(lib, "winmm.lib")

void MicCapture::WriteHeader()
{
    if (!file_) return;
    const DWORD riffSize = bytes_ + 36;
    const DWORD fmtSize = 16;
    const WORD pcm = 1, channels = 1, align = 2, bits = 16;
    const DWORD rate = 44100, byteRate = rate * align;
    rewind(file_);
    fwrite("RIFF", 1, 4, file_);
    fwrite(&riffSize, 4, 1, file_);
    fwrite("WAVEfmt ", 1, 8, file_);
    fwrite(&fmtSize, 4, 1, file_);
    fwrite(&pcm, 2, 1, file_);
    fwrite(&channels, 2, 1, file_);
    fwrite(&rate, 4, 1, file_);
    fwrite(&byteRate, 4, 1, file_);
    fwrite(&align, 2, 1, file_);
    fwrite(&bits, 2, 1, file_);
    fwrite("data", 1, 4, file_);
    fwrite(&bytes_, 4, 1, file_);
    fflush(file_);
}

bool MicCapture::Start(const wchar_t* path)
{
    if (running_ || waveInGetNumDevs() == 0) return false;
    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 1;
    format.nSamplesPerSec = 44100;
    format.wBitsPerSample = 16;
    format.nBlockAlign = 2;
    format.nAvgBytesPerSec = 88200;
    ready_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!ready_) return false;
    MMRESULT openResult = waveInOpen(&input_, WAVE_MAPPER, &format,
        reinterpret_cast<DWORD_PTR>(ready_), 0, CALLBACK_EVENT);
    if (openResult != MMSYSERR_NOERROR)
    {
        std::wcout << L"MIC_OPEN_ERROR=" << openResult << L"\n";
        CloseHandle(ready_);
        ready_ = nullptr;
        return false;
    }
    if (_wfopen_s(&file_, path, L"wb+") != 0)
    {
        std::wcout << L"MIC_FILE_ERROR\n";
        waveInClose(input_);
        input_ = nullptr;
        CloseHandle(ready_);
        ready_ = nullptr;
        return false;
    }
    WriteHeader();
    for (size_t i = 0; i < headers_.size(); ++i)
    {
        headers_[i].lpData = buffers_[i].data();
        headers_[i].dwBufferLength = static_cast<DWORD>(buffers_[i].size());
        MMRESULT prepareResult = waveInPrepareHeader(input_, &headers_[i], sizeof(WAVEHDR));
        MMRESULT addResult = prepareResult == MMSYSERR_NOERROR
            ? waveInAddBuffer(input_, &headers_[i], sizeof(WAVEHDR)) : prepareResult;
        if (prepareResult != MMSYSERR_NOERROR || addResult != MMSYSERR_NOERROR)
        {
            std::wcout << L"MIC_BUFFER_ERROR=" << prepareResult << L"/" << addResult << L"\n";
            Stop();
            return false;
        }
    }
    MMRESULT startResult = waveInStart(input_);
    if (startResult != MMSYSERR_NOERROR)
    {
        std::wcout << L"MIC_START_ERROR=" << startResult << L"\n";
        Stop();
        return false;
    }
    running_ = true;
    thread_ = std::thread([this] { Run(); });
    return true;
}

void MicCapture::Run()
{
    while (running_)
    {
        WaitForSingleObject(ready_, 100);
        for (auto& header : headers_)
        {
            if (!(header.dwFlags & WHDR_DONE)) continue;
            if (header.dwBytesRecorded)
            {
                fwrite(header.lpData, 1, header.dwBytesRecorded, file_);
                bytes_ += header.dwBytesRecorded;
            }
            header.dwBytesRecorded = 0;
            if (running_) waveInAddBuffer(input_, &header, sizeof(WAVEHDR));
        }
    }
}

void MicCapture::Stop()
{
    running_ = false;
    if (thread_.joinable()) thread_.join();
    if (input_)
    {
        waveInStop(input_);
        waveInReset(input_);
        for (auto& header : headers_)
        {
            if (header.dwFlags & WHDR_DONE && header.dwBytesRecorded && file_)
            {
                fwrite(header.lpData, 1, header.dwBytesRecorded, file_);
                bytes_ += header.dwBytesRecorded;
                header.dwBytesRecorded = 0;
            }
            if (header.dwFlags & WHDR_PREPARED)
                waveInUnprepareHeader(input_, &header, sizeof(WAVEHDR));
        }
        waveInClose(input_);
        input_ = nullptr;
    }
    if (file_)
    {
        WriteHeader();
        fclose(file_);
        file_ = nullptr;
    }
    if (ready_)
    {
        CloseHandle(ready_);
        ready_ = nullptr;
    }
}
