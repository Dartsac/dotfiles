#!/usr/bin/env python3
"""
Stream microphone audio to Deepgram Nova-3 and print finalized transcript
segments to stdout as JSON lines. Launched and stopped (SIGINT) by Hammerspoon.

Output lines:
  {"event": "ready"}                  connected, listening
  {"level": 0.42}                     mic loudness 0..1, ~20x/sec (for the HUD meter)
  {"text": "Some words."}             a finalized segment to type
  {"event": "idle_timeout"}           auto-stopped after silence
  {"event": "error", "message": ...}  something went wrong
"""

import asyncio
import json
import math
import os
import signal
import sys
import time
from array import array
from pathlib import Path
from urllib.parse import urlencode

import sounddevice as sd
import websockets

SAMPLE_RATE = 16000
BLOCK_MS = 50  # also the level-meter update rate
METER_FLOOR_DB = -55  # loudness shown as an empty bar
METER_CEILING_DB = -15  # loudness shown as a full bar
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
        ("encoding", "linear16"),
        ("sample_rate", SAMPLE_RATE),
        ("channels", 1),
        ("smart_format", "true"),
        ("punctuate", "true"),
        # No "dictation": on nova-3 streaming it replaces automatic punctuation and
        # smart formatting with literal spoken-command punctuation only.
        ("interim_results", "true"),
        ("endpointing", 150),  # ms of silence before a segment is finalized
    ]
    params += [("keyterm", t) for t in KEYTERMS]
    return "wss://api.deepgram.com/v1/listen?" + urlencode(params)


async def main():
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    audio_q: asyncio.Queue = asyncio.Queue()
    state = {"last_speech": time.monotonic()}

    def on_chunk(chunk, level):
        audio_q.put_nowait(chunk)
        emit({"level": round(level, 2)})

    def on_audio(indata, frames, t, status):
        chunk = bytes(indata)
        loop.call_soon_threadsafe(on_chunk, chunk, level_of(chunk))

    async def sender(ws):
        while not stop.is_set():
            try:
                chunk = await asyncio.wait_for(audio_q.get(), 0.25)
            except asyncio.TimeoutError:
                continue
            await ws.send(chunk)
        while not audio_q.empty():  # flush what was captured before stop
            await ws.send(audio_q.get_nowait())
        await ws.send(
            json.dumps({"type": "CloseStream"})
        )  # server finalizes, then closes

    async def receiver(ws):
        async for raw in ws:
            data = json.loads(raw)
            if data.get("type") != "Results":
                continue
            text = data["channel"]["alternatives"][0].get("transcript", "")
            if text:
                state["last_speech"] = time.monotonic()
            if data.get("is_final") and text:
                emit({"text": text})

    async def watchdog():
        while not stop.is_set():
            await asyncio.sleep(1)
            if time.monotonic() - state["last_speech"] > IDLE_TIMEOUT_S:
                emit({"event": "idle_timeout"})
                stop.set()

    key = load_api_key()
    # Open the mic first so nothing is lost while the socket connects.
    with sd.RawInputStream(
        samplerate=SAMPLE_RATE,
        blocksize=int(SAMPLE_RATE * BLOCK_MS / 1000),
        channels=1,
        dtype="int16",
        callback=on_audio,
    ):
        async with websockets.connect(
            build_url(), additional_headers={"Authorization": f"Token {key}"}
        ) as ws:
            emit({"event": "ready"})
            recv_task = asyncio.create_task(receiver(ws))
            wd_task = asyncio.create_task(watchdog())
            await sender(ws)
            try:
                await asyncio.wait_for(recv_task, 5)
            except asyncio.TimeoutError:
                recv_task.cancel()
            wd_task.cancel()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:  # surface errors to Hammerspoon instead of dying silently
        emit({"event": "error", "message": str(e)})
        sys.exit(1)
