# 🎸 Riffline

**Turn any rhythm-game chart into a mobile performance — instantly.**

Riffline transforms Clone Hero, Rock Band, and custom song charts into a fast, fluid tap experience on your phone. No controllers. No cables. Just you, your music, and your reflexes.

---

## ✨ Features

### 🎵 Play Any Song
- **Clone Hero (.chart, .mid, .sng)** — drop in your existing library
- **Rock Band 3 (Xbox 360 CON/LIVE)** — full STFS container support with auto-extraction
- **ZIP bundles** — download community packs and import directly
- **Multi-stem mixing** — all instruments blended into one crystal-clear audio track

### 🎮 Multiple Play Modes
| Preset | Style |
|--------|-------|
| **Tiles** | Simplified for mobile — pure rhythm, no chords |
| **Tiles Akıcı** | Tiles density with assisted lane flow and timing |
| **Rahat** | Relaxed — slightly more notes, still comfortable |
| **Rahat Akıcı** | Relaxed density with assisted lane flow and timing |
| **Normal** | More chart detail with chords |
| **Normal Akıcı** | Normal density with assisted lane flow and timing |
| **Sadık** | 100% original — every note, every chord, no mercy |
| **Sadık Akıcı** | Full original density with mobile playability assists |

### 🎸 Full Instrument Support
- Guitar / Bass / Keys / Drums
- All difficulty levels: Easy → Expert
- Automatic instrument detection from chart files

### 📱 Designed for Mobile
- Portrait-first phone and tablet layout
- Touch-optimized highway with invisible edge padding
- Smooth alpha-fade note approach
- Hit ring animations & miss flash feedback
- Combo multiplier system with tier-based glow effects (up to 20x!)

### 🏆 Progress Tracking
- 5-star rating system
- Per-song score persistence
- Best score saved per instrument/difficulty/preset combo
- Combo milestone celebrations (25, 50, 100, 200, 300, 500)

### ⚡ Performance
- Pre-decoded audio cache — zero lag on replay
- Native Android audio pipeline (MediaCodec) — no external dependencies
- Memory-mapped mixing — plays 11-channel Rock Band stems without breaking a sweat
- Peak normalization prevents clipping across any number of stems

---

## 📲 Getting Started

1. **Download** the latest APK from [Releases](../../releases)
2. **Add songs** — tap the "+" button and import .sng, .chart, .mid, .zip, or .con files
3. **Pick your instrument**, difficulty, and play style
4. **Hit BAŞLAT** and shred

---

## 🎶 Supported Formats

| Format | Source | Notes |
|--------|--------|-------|
| `.sng` | Clone Hero | Single-file package, plug & play |
| `.chart` | Moonscraper / CH | + audio files in same folder |
| `.mid` | Rock Band / FoF | MIDI chart + stems |
| `.zip` | Community packs | Auto-extracts chart + audio + art |
| `.con` / `.live` | Xbox 360 RB3 | Full STFS parsing, MOGG decoding |

---

## 🛠 Tech Stack

- **Engine**: Godot 4.7 (GDScript)
- **Android Audio**: Custom Kotlin plugin using MediaCodec API
- **Architecture**: MappedByteBuffer accumulator for unlimited stem mixing
- **Rendering**: Mobile renderer, optimized for 60fps on mid-range devices
- **Zero dependencies**: No ffmpeg-kit, no native .so libs — pure platform APIs

---

## 🏗 Building from Source

```bash
# Build the Android audio plugin
cd native_audio_decoder
./gradlew assembleRelease

# AAR is output to:
# native_audio_decoder/build/outputs/aar/NativeAudioDecoder-release.aar
# Copy to addons/NativeAudioDecoder/

# Open project in Godot 4.7 and export to Android
```

---

## 📸 Screenshots

*Coming soon*

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <b>Your charts. Your phone. Your stage.</b><br>
  <i>Riffline — rhythm gaming, unchained.</i>
</p>
