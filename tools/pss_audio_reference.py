"""Decode the Namco sector-interleaved movie track directly from an ISO (stdlib).

This is an independent reference, not a call into the runtime decoder. These T4
movies use MPEG-2 elementary video and SPU ADPCM blocks in a sector envelope;
they are not ordinary MPEG program streams with a private-stream audio PES.
The stream driver's 512-byte channel transfers, source offsets 512 bytes apart
and 1024-byte source stride establish the default stereo interleave independently
of the runtime's movie HLE. --interleave-bytes allows explicit comparison variants.
Supply the movie's relative sector and byte size from the local movie-open log.
No game offsets or audio data are embedded in this tool. Example:

  python -I tools/pss_audio_reference.py --iso DISC.iso --sector N --size N \
      --wav build/movie-audio/reference.wav --json build/movie-audio/reference.json

The WAV preserves the 44.1 kHz source clock. The runtime may deliberately use a
slightly faster source clock to follow its 30 Hz (rather than 30000/1001) video.
Invalid ADPCM filter indices are rejected instead of silently guessed. Predictor
history persists across sector units. Audio end flags are counted but do not
stop a streaming track. Only ISO input is opened read-only.
"""

import argparse
import array
import collections
import json
import math
from pathlib import Path
import struct
import sys
import wave


COEFFICIENTS = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))
FPS = (0, 24000 / 1001, 24, 25, 30000 / 1001, 30, 50, 60000 / 1001, 60)


def find_extent(disc, path):
    """Resolve an ISO9660 path, avoiding assumptions about DATA.BIN's LBA."""
    disc.seek(16 * 2048)
    pvd = disc.read(2048)
    if pvd[:7] != b"\x01CD001\x01":
        raise ValueError("expected a plain 2048-byte-sector ISO9660 image")
    lba, size = struct.unpack_from("<I", pvd, 158)[0], struct.unpack_from("<I", pvd, 166)[0]
    for part in path.replace("\\", "/").strip("/").split("/"):
        disc.seek(lba * 2048)
        directory = disc.read(size)
        pos, found = 0, None
        while pos < len(directory):
            length = directory[pos]
            if not length:
                pos = (pos // 2048 + 1) * 2048
                continue
            record = directory[pos:pos + length]
            name = record[33:33 + record[32]].decode("ascii", "replace").split(";")[0]
            if name.upper() == part.upper():
                found = struct.unpack_from("<I", record, 2)[0], struct.unpack_from("<I", record, 10)[0]
                break
            pos += length
        if found is None:
            raise ValueError("ISO file not found: " + path)
        lba, size = found
    return lba, size


def decode_block(block, history):
    if len(block) != 16:
        raise ValueError("an SPU ADPCM block must contain exactly 16 bytes")
    predictor, shift = block[0] >> 4, block[0] & 15
    if predictor >= len(COEFFICIENTS):
        raise ValueError("invalid ADPCM predictor: %d" % predictor)
    if shift > 12:
        shift = 9
    c1, c2 = COEFFICIENTS[predictor]
    previous, older = history
    result = []
    for packed in block[2:]:
        for code in (packed & 15, packed >> 4):
            signed = code if code < 8 else code - 16
            residual = (signed * 4096) >> shift
            prediction = (previous * c1 + older * c2 + 32) // 64
            sample = max(-32768, min(32767, residual + prediction))
            result.append(sample)
            older, previous = previous, sample
    history[:] = previous, older
    return result


def decode_stereo(data, histories, interleave=512):
    if interleave <= 0 or interleave % 16 or len(data) % (2 * interleave):
        raise ValueError("stereo ADPCM must contain whole channel interleave pairs")
    result = array.array("h")
    for offset in range(0, len(data), 2 * interleave):
        left, right = [], []
        for block in range(0, interleave, 16):
            left.extend(decode_block(data[offset + block:offset + block + 16], histories[0]))
            right.extend(decode_block(data[offset + interleave + block:offset + interleave + block + 16], histories[1]))
        for l, r in zip(left, right):
            result.extend((l, r))
    return result


def self_test():
    # Hand-computed vectors exercise nibble sign/order, prediction, rounding,
    # saturation and independent channel histories; no copyrighted fixtures.
    assert decode_block(bytes([0, 0, 0x87]) + bytes(13), [0, 0])[:2] == [28672, -32768]
    assert decode_block(bytes([12, 0, 0xF1]) + bytes(13), [0, 0])[:4] == [1, -1, 0, 0]
    assert decode_block(bytes([0x1C, 0]) + bytes(14), [64, 0])[:4] == [60, 56, 53, 50]
    assert decode_block(bytes([0x2C, 0]) + bytes(14), [64, 0])[:4] == [115, 155, 185, 206]
    assert decode_block(bytes([0x1C, 0]) + bytes(14), [-1, 0])[0] == -1
    assert decode_block(bytes([0x10, 0, 7]) + bytes(13), [32767, 32767])[0] == 32767
    assert decode_block(bytes([13, 0, 1]) + bytes(13), [0, 0])[0] == 8
    pair = bytes([12, 0, 0x11]) + bytes(13) + bytes([12, 0, 0xEE]) + bytes(13)
    histories = [[0, 0], [0, 0]]
    assert list(decode_stereo(pair, histories, 16)[:4]) == [1, -2, 1, -2]
    blocks = (bytes([0x1C, 0, 0x11]) + bytes(13)) * 2
    h1, h2 = [[0, 0], [0, 0]], [[0, 0], [0, 0]]
    assert decode_stereo(blocks * 2, h1, 16) == decode_stereo(blocks, h2, 16) + decode_stereo(blocks, h2, 16)
    left_block = bytes([12, 0]) + bytes([0x11] * 14)
    right_block = bytes([12, 0]) + bytes([0xEE] * 14)
    sector_pair = left_block * 32 + right_block * 32
    pcm = decode_stereo(sector_pair, [[0, 0], [0, 0]])
    assert len(pcm) == 2 * 32 * 28
    assert set(pcm[::2]) == {1} and set(pcm[1::2]) == {-2}
    try:
        decode_block(bytes([0x50]) + bytes(15), [0, 0])
    except ValueError:
        pass
    else:
        raise AssertionError("invalid predictor was accepted")
    return 12


def extract(args):
    video_bytes, audio_bytes = args.video_sectors * 2048, args.audio_sectors * 2048
    unit_bytes = video_bytes + audio_bytes
    units = args.size // unit_bytes
    if args.units is not None:
        units = min(units, args.units)
    if args.wav:
        args.wav.parent.mkdir(parents=True, exist_ok=True)
    output = wave.open(str(args.wav), "wb") if args.wav else None
    if output:
        output.setparams((2, 2, args.rate, 0, "NONE", "not compressed"))
    histories = [[0, 0], [0, 0]]
    filters, shifts, flags = (collections.Counter() for _ in range(3))
    sequence_headers = set()
    pictures, carry = 0, b""
    total, rail, peak, energy, sum_l, sum_r, energy_l, energy_r, cross = (0,) * 9
    max_steps = [0, 0]
    last = [0, 0]
    last_nonzero_unit = None
    try:
        with open(args.iso, "rb") as disc:
            lba, data_size = find_extent(disc, args.file)
            if args.sector * 2048 + args.size > data_size:
                raise ValueError("movie extent exceeds its container file")
            for unit in range(units):
                disc.seek((lba + args.sector) * 2048 + unit * unit_bytes)
                video, audio = disc.read(video_bytes), disc.read(audio_bytes)
                if len(audio) != audio_bytes:
                    raise ValueError("truncated movie unit")
                scan = carry + video
                pictures += scan.count(b"\x00\x00\x01\x00")
                start = 0
                while True:
                    pos = scan.find(b"\x00\x00\x01\xb3", start)
                    if pos < 0:
                        break
                    if pos + 8 <= len(scan):
                        width = (scan[pos + 4] << 4) | (scan[pos + 5] >> 4)
                        height = ((scan[pos + 5] & 15) << 8) | scan[pos + 6]
                        sequence_headers.add((width, height, scan[pos + 7] & 15))
                    start = pos + 4
                # Only retain a possible split start code, not complete headers.
                carry = video[-3:]
                for i in range(0, len(audio), 16):
                    filters[audio[i] >> 4] += 1
                    shifts[audio[i] & 15] += 1
                    flags[audio[i + 1]] += 1
                pcm = decode_stereo(audio, histories, args.interleave_bytes)
                if any(abs(v) > 8 for v in pcm):
                    last_nonzero_unit = unit
                for i in range(0, len(pcm), 2):
                    l, r = pcm[i:i + 2]
                    sum_l += l
                    sum_r += r
                    energy_l += l * l
                    energy_r += r * r
                    cross += l * r
                    max_steps[0] = max(max_steps[0], abs(l - last[0]))
                    max_steps[1] = max(max_steps[1], abs(r - last[1]))
                    last[:] = l, r
                total += len(pcm)
                rail += sum(v <= -32768 or v >= 32767 for v in pcm)
                peak = max(peak, max(abs(v) for v in pcm))
                energy += sum(v * v for v in pcm)
                if output:
                    if sys.byteorder != "little":
                        pcm.byteswap()
                    output.writeframesraw(pcm.tobytes())
    finally:
        if output:
            output.close()
    frames = total // 2
    correlation = ((cross - sum_l * sum_r / frames) /
                   math.sqrt((energy_l - sum_l * sum_l / frames) * (energy_r - sum_r * sum_r / frames))) if frames and energy_l and energy_r else 0
    return {
        "format": "Namco sector-interleaved MPEG-2 + stereo SPU ADPCM",
        "container_lba": lba, "units": units, "unit_bytes": unit_bytes,
        "interleave_bytes": args.interleave_bytes,
        "source_rate_hz": args.rate, "frames": frames, "duration_s": frames / args.rate,
        "last_nonzero_unit": last_nonzero_unit, "mpeg_pictures": pictures,
        "mpeg_sequences": [{"width": w, "height": h, "frame_rate_code": c,
                            "fps": FPS[c] if c < len(FPS) else None}
                           for w, h, c in sorted(sequence_headers)],
        "filter_counts": dict(filters), "shift_counts": dict(shifts), "flag_counts": dict(flags),
        "peak": peak, "rail_samples": rail, "rail_percent": 100 * rail / total,
        "rms": math.sqrt(energy / total) / 32768, "channel_correlation": correlation,
        "maximum_channel_steps": max_steps,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--iso", type=Path)
    parser.add_argument("--file", default="TEKKEN/DATA.BIN")
    parser.add_argument("--sector", type=lambda v: int(v, 0))
    parser.add_argument("--size", type=lambda v: int(v, 0))
    parser.add_argument("--units", type=int)
    parser.add_argument("--video-sectors", type=int, default=39)
    parser.add_argument("--audio-sectors", type=int, default=2)
    parser.add_argument("--interleave-bytes", type=int, default=512)
    parser.add_argument("--rate", type=int, default=44100)
    parser.add_argument("--wav", type=Path)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps({"self_tests_passed": self_test()}))
        return
    if args.iso is None or args.sector is None or args.size is None:
        parser.error("--iso, --sector, and --size are required")
    if args.sector < 0 or args.size <= 0 or args.rate <= 0 or args.video_sectors <= 0 or args.audio_sectors <= 0:
        parser.error("sector must be nonnegative and size/rate/sector counts must be positive")
    if args.units is not None and args.units <= 0:
        parser.error("--units must be positive")
    if args.size < (args.video_sectors + args.audio_sectors) * 2048:
        parser.error("movie size must contain at least one complete interleave unit")
    if args.interleave_bytes <= 0 or args.interleave_bytes % 16 or args.audio_sectors * 2048 % (2 * args.interleave_bytes):
        parser.error("audio sectors must contain whole pairs of ADPCM channel interleaves")
    if any(path and path.resolve() == args.iso.resolve() for path in (args.wav, args.json)):
        parser.error("outputs must not overwrite the input ISO")
    result = extract(args)
    encoded = json.dumps(result, indent=2, sort_keys=True)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)


if __name__ == "__main__":
    main()
