"""Assembles an episode MP4 with FFmpeg.

Each scene is a still image with a slow zoom (Ken Burns), the spoken line as
audio and burned-in captions. A title card opens the episode and a vote card
closes it. Segments share one format, so they are joined without re-encoding.

    title card -> scene 1 ... scene N -> "what happens next?" card
"""

import json
import subprocess
from pathlib import Path

FPS = 30
PAD = 0.35          # seconds of silence after each line
TITLE_SECS = 2.5
VOTE_SECS = 5.0


class VideoError(Exception):
    pass


def run(args, cwd):
    p = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args],
                       cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise VideoError("ffmpeg: " + p.stderr.strip()[-1200:])


def duration(path) -> float:
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "json", str(path)], capture_output=True, text=True)
    try:
        return float(json.loads(p.stdout)["format"]["duration"])
    except (KeyError, ValueError, json.JSONDecodeError):
        raise VideoError(f"could not read the length of {path}") from None


def _esc(text: str) -> str:
    """Make free text safe inside an ASS subtitle line."""
    return (" ".join(str(text).split())
            .replace("\\", "/").replace("{", "(").replace("}", ")"))


def _ass(w: int, h: int, secs: float, lines: list) -> str:
    """Subtitle file for one segment. lines = [(style, text)] shown for the whole segment."""
    big, small = round(h * 0.034), round(h * 0.018)
    margin = round(w * 0.07)
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {w}
PlayResY: {h}
WrapStyle: 0

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Caption,DejaVu Sans,{big},&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,{max(2, big // 12)},1,2,{margin},{margin},{round(h * 0.16)},1
Style: Speaker,DejaVu Sans,{round(big * 0.8)},&H0066D9FF,&H0066D9FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,{max(2, big // 12)},1,2,{margin},{margin},{round(h * 0.16) + round(big * 2.9)},1
Style: Label,DejaVu Sans,{small},&H00FFFFFF,&H00FFFFFF,&H00000000,&H60000000,0,0,0,0,100,100,0,0,3,4,0,9,{margin // 2},{margin // 2},{margin // 2},1
Style: Title,DejaVu Sans,{round(big * 1.3)},&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,{max(2, big // 10)},2,5,{margin},{margin},0,1
Style: Option,DejaVu Sans,{big},&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,{max(2, big // 12)},1,5,{margin},{margin},0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    end = f"0:{int(secs // 60):02d}:{secs % 60:05.2f}"
    events = [f"Dialogue: 0,0:00:00.00,{end},{style},,0,0,0,,{text}" for style, text in lines]
    # Every frame says the content is AI-generated (course rule: label generated media).
    events.append(f"Dialogue: 1,0:00:00.00,{end},Label,,0,0,0,,AI-generated")
    return head + "\n".join(events) + "\n"


def _zoom(i: int, frames: int, w: int, h: int, darken: bool = False) -> str:
    """Slow zoom in (even scenes) or out (odd scenes) on a still image."""
    z = (f"1+0.10*on/{frames}" if i % 2 == 0 else f"1.10-0.10*on/{frames}")
    f = (f"scale={2 * w}:{2 * h}:force_original_aspect_ratio=increase,"
         f"crop={2 * w}:{2 * h},"
         f"zoompan=z='{z}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
         f"d={frames}:s={w}x{h}:fps={FPS}")
    if darken:
        f += ",boxblur=12:2,eq=brightness=-0.25"
    return f


ENCODE = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
          "-r", str(FPS), "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2"]


def _segment(work: Path, name: str, image: str, audio, secs: float, i: int,
             w: int, h: int, lines: list, darken=False):
    frames = max(1, round(secs * FPS))
    (work / f"{name}.ass").write_text(_ass(w, h, secs, lines), encoding="utf-8")
    vf = f"{_zoom(i, frames, w, h, darken)},ass={name}.ass"
    if audio:
        ains = ["-i", audio]
        af = ["-af", "apad", "-t", f"{secs:.3f}"]
    else:
        ains = ["-f", "lavfi", "-t", f"{secs:.3f}", "-i", "anullsrc=r=44100:cl=stereo"]
        af = ["-t", f"{secs:.3f}"]
    run(["-i", image, *ains, "-vf", vf, *af, "-map", "0:v", "-map", "1:a",
         *ENCODE, f"{name}.mp4"], work)
    return f"{name}.mp4"


def assemble(work: Path, scenes: list, title: str, number: int, options: list,
             height: int = 1920) -> Path:
    """scenes: [{"image": file, "audio": file, "speaker": str, "line": str}] in work.

    Returns the path of episode.mp4 (9:16, H.264/AAC, captions burned in).
    """
    if not scenes:
        raise VideoError("no scenes to assemble")
    h = height - height % 2
    w = round(h * 9 / 16 / 2) * 2
    parts = [_segment(work, "s000", scenes[0]["image"], None, TITLE_SECS, 1, w, h,
                      [("Title", f"Episode {number}\\N{_esc(title)}")], darken=True)]
    for i, s in enumerate(scenes, start=1):
        secs = duration(work / s["audio"]) + PAD
        lines = [("Caption", _esc(s["line"]))]
        if s.get("speaker") and s["speaker"] != "Narrator":
            lines.append(("Speaker", _esc(s["speaker"])))
        parts.append(_segment(work, f"s{i:03d}", s["image"], s["audio"], secs, i,
                              w, h, lines))
    if options:
        text = "What happens next?\\N\\N" + "\\N".join(
            f"{k}. {_esc(o)}" for k, o in enumerate(options, start=1)) + "\\N\\NVote in the app"
        parts.append(_segment(work, "s999", scenes[-1]["image"], None, VOTE_SECS, 0,
                              w, h, [("Option", text)], darken=True))
    (work / "list.txt").write_text("".join(f"file '{p}'\n" for p in parts))
    run(["-f", "concat", "-safe", "0", "-i", "list.txt", "-c", "copy",
         "-movflags", "+faststart", "episode.mp4"], work)
    return work / "episode.mp4"
