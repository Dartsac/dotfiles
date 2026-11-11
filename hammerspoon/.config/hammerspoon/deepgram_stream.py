#!/usr/bin/env python3
"""
Record microphone audio, then transcribe the complete recording with Deepgram
Nova-3 when stopped (SIGINT) by Hammerspoon. No text is emitted while recording.

Output lines:
  {"event": "ready"}                  recording
  {"level": 0.42}                     mic loudness 0..1, ~20x/sec (for the HUD meter)
  {"text": "Some words."}             complete transcript to type after stopping
  {"event": "idle_timeout"}           auto-stopped after silence
  {"event": "error", "message": ...}  something went wrong
"""

import asyncio
import io
import json
import math
import os
import signal
import sys
import time
import wave
from array import array
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import sounddevice as sd

SAMPLE_RATE = 16000
BLOCK_MS = 50  # also the level-meter update rate
METER_FLOOR_DB = -55  # loudness shown as an empty bar
METER_CEILING_DB = -15  # loudness shown as a full bar
SPEECH_LEVEL = 0.25  # approximately -45 dB; used only for silence auto-stop
# Pauses longer than this are thinking time rather than sentence boundaries
# (sentence-final pauses are mostly 450-1000 ms), so they are shortened to this
# length before upload to save cost and upload time.
MAX_PAUSE_S = 1.0
SILENCE_DB = -50  # quieter than this counts as silence for pause shortening
SILENCE_LEVEL = (SILENCE_DB - METER_FLOOR_DB) / (METER_CEILING_DB - METER_FLOOR_DB)
IDLE_TIMEOUT_S = float(os.environ.get("DICTATION_IDLE_TIMEOUT", "60"))
KEYTERMS = [
    t.strip() for t in os.environ.get("DICTATION_KEYTERMS", "").split(",") if t.strip()
]
LANGUAGE = os.environ.get("DICTATION_LANGUAGE", "en-US")


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def level_of(chunk):
    """RMS loudness of an int16 chunk, mapped to 0..1 on a dB scale."""
    samples = array("h", chunk)
    if not samples:
        return 0.0
    rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    db = 20 * math.log10(max(rms, 1.0) / 32768)
    return max(
        0.0, min(1.0, (db - METER_FLOOR_DB) / (METER_CEILING_DB - METER_FLOOR_DB))
    )


def load_api_key():
    key = os.environ.get("DEEPGRAM_API_KEY", "").strip()
    if not key:
        path = Path.home() / ".config" / "deepgram" / "api_key"
        if path.exists():
            key = path.read_text().strip()
    if not key:
        emit({"event": "error", "message": "No API key in ~/.config/deepgram/api_key"})
        sys.exit(1)
    return key


def build_url():
    params = [
        ("model", "nova-3"),
        ("language", LANGUAGE),
        ("smart_format", "true"),
        ("punctuate", "true"),
    ]
    params += [("keyterm", t) for t in KEYTERMS]
    return "https://api.deepgram.com/v1/listen?" + urlencode(params)


def shorten_pauses(chunks, levels):
    """Cap each silent run at MAX_PAUSE_S, keeping its start and end so quiet
    word edges next to speech are never cut."""
    half = int(SAMPLE_RATE * MAX_PAUSE_S / 2) * 2  # bytes; 2 per sample

    def cap(silence):
        if len(silence) <= 2 * half:
            return bytes(silence)
        return bytes(silence[:half] + silence[-half:])

    out, silence = [], bytearray()
    for chunk, level in zip(chunks, levels):
        if level < SILENCE_LEVEL:
            silence += chunk
        else:
            out += [cap(silence), chunk]
            silence = bytearray()
    out.append(cap(silence))
    return b"".join(out)


def transcribe(chunks, levels, key):
    """Send one WAV so punctuation is based on the whole recording."""
    audio = io.BytesIO()
    with wave.open(audio, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(shorten_pauses(chunks, levels))
    request = Request(
        build_url(),
        data=audio.getvalue(),
        headers={"Authorization": f"Token {key}", "Content-Type": "audio/wav"},
        method="POST",
    )
    with urlopen(request, timeout=120) as response:
        data = json.load(response)
    return data["results"]["channels"][0]["alternatives"][0]["transcript"]


async def main():
    key = load_api_key()
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    chunks, levels = [], []
    last_speech = time.monotonic()

    def on_chunk(chunk, level):
        nonlocal last_speech
        chunks.append(chunk)
        levels.append(level)
        emit({"level": round(level, 2)})
        if level >= SPEECH_LEVEL:
            last_speech = time.monotonic()

    def on_audio(indata, frames, t, status):
        chunk = bytes(indata)
        loop.call_soon_threadsafe(on_chunk, chunk, level_of(chunk))

    async def watchdog():
        while not stop.is_set():
            await asyncio.sleep(1)
            if time.monotonic() - last_speech > IDLE_TIMEOUT_S:
                emit({"event": "idle_timeout"})
                stop.set()

    with sd.RawInputStream(
        samplerate=SAMPLE_RATE,
        blocksize=int(SAMPLE_RATE * BLOCK_MS / 1000),
        channels=1,
        dtype="int16",
        callback=on_audio,
    ):
        emit({"event": "ready"})
        wd_task = asyncio.create_task(watchdog())
        try:
            await stop.wait()
        finally:
            wd_task.cancel()
    # Drain callbacks queued by the audio thread before taking the snapshot.
    await asyncio.sleep(0)
    if chunks:
        text = await asyncio.to_thread(transcribe, chunks, levels, key)
        if text:
            emit({"text": text})


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:  # surface errors to Hammerspoon instead of dying silently
        emit({"event": "error", "message": str(e)})
        sys.exit(1)
