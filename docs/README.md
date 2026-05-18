# `docs/` — submission assets

Files in this folder are referenced from the top-level `README.md`. Drop the
right artifact in the right spot and the README renders automatically.

## What goes here

```
docs/
├── architecture.png            ← exported from QuiteCompany-architecture.excalidraw
└── screenshots/
    ├── watch.png               ← Watch tab — now-playing + favourites grid
    ├── watch-voice.png         ← Watch tab — tap-to-talk active state
    ├── people.png              ← People tab — recognised person card + photos
    ├── cues.png                ← Cues tab — caregiver indexing view
    ├── wellness.png            ← Wellness / setup sheets (Gemma + Telegram)
    ├── telegram-alert.png      ← Caregiver-side: absence alert in Telegram
    └── web-home.png            ← Web prototype — Home screen (Vite)
```

## How to export

### Architecture diagram (`architecture.png`)

1. Open [excalidraw.com](https://excalidraw.com)
2. **Menu → Open** → `../QuiteCompany-architecture.excalidraw`
3. **Menu → Export image → PNG**, white background, scale 2×
4. Save as `docs/architecture.png`

### iPad screenshots

On the iPad while the app is running: hold Top + Volume Up. The image lands
in Photos — AirDrop to your Mac, save to `docs/screenshots/<name>.png`.

For the Telegram alert screenshot, take it from your phone (the caregiver
device) when the absence alert fires.

### Web prototype screenshot

```sh
npm run dev
```

Open the Vite URL in a browser, hit `Cmd-Shift-4` on macOS (or your OS
equivalent), drag a tight window-sized rectangle, save to `docs/screenshots/`.
