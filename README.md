# Hearth — Tablet

A companion tablet for people living with dementia. Show-centric TV remote,
person recognition with shared memories, relationship-based calling,
plain-language reminders. On-device inference (Gemma) is the eventual
target; this repo is the UI prototype.

## Run

```sh
npm install
npm run dev
```

## Layout

```
src/
  main.tsx                    entry — mounts <App/>, loads CSS + Phosphor icons
  App.jsx                     tablet shell, top bar, screen switch, bottom nav
  components/primitives.jsx   Icon, Button, Photo, ContextStrip, ShowTile, ...
  screens/
    HomeScreen.jsx            "Now" card + relationship-based calling
    TVScreen.jsx              show-centric remote, intent rewind, never-lost shelf
    PersonScreen.jsx          camera viewfinder + recognized person + memories
    RemindersScreen.jsx       day-at-a-glance reminders
  styles/
    design-system.css         colors, type, fonts (@font-face → /fonts/)
    tablet.css                tablet-specific component CSS
    stage.css                 dark backdrop + tablet bezel

public/fonts/                 Atkinson Hyperlegible + Newsreader (self-hosted woff2)

reference/
  hearth-tablet-prototype.html  original Claude artifact bundle — design source of truth
```
