// TVScreen — the deep TV remote.
// Show-centric · plain-language · intent-based rewind · platform-as-secondary · never-lost shelf.
import { useState } from 'react';
import {
  ContextStrip, Eyebrow, Icon, CircleButton, IntentChip, ShowTile, PlatformPill,
} from '../components/primitives.jsx';

export const TVScreen = () => {
  const [paused, setPaused] = useState(false);
  const [says, setSays]     = useState("Now playing your news. You're on Hulu.");
  const [heard, setHeard]   = useState("");

  const setIntent = (label, narration) => {
    setHeard(label);
    setSays(narration);
  };

  const togglePause = () => {
    const wasPaused = paused;
    setPaused(p => !p);
    setHeard(wasPaused ? "play" : "pause");
    setSays(wasPaused
      ? "Playing again. You're back where you left off."
      : "Paused. We can come back any time.");
  };

  // Real-name examples per spec; brand-neutral colored chips (no logos).
  const continueWatching = [
    { title: "The Evening News",  platform: "Hulu",       progress: 38,
      gradient: "linear-gradient(160deg,#4F708A 0%,#2A241C 100%)" },
    { title: "Antiques\nRoadshow", platform: "BBC iPlayer", progress: 64,
      gradient: "linear-gradient(160deg,#B89A4F 0%,#5A4828 100%)" },
    { title: "Coronation\nStreet", platform: "ITVX",       progress: 12,
      gradient: "linear-gradient(160deg,#9C4E2C 0%,#3a241a 100%)" },
    { title: "Gardeners'\nWorld",  platform: "BBC iPlayer", progress: 88,
      gradient: "linear-gradient(160deg,#5A6B50 0%,#2A241C 100%)" },
  ];

  const showsYouLike = [
    { title: "Doc Martin",   gradient: "linear-gradient(160deg,#7A9AB3,#4F708A)" },
    { title: "Call the\nMidwife", gradient: "linear-gradient(160deg,#C76A3F,#9C4E2C)" },
    { title: "Last of the\nSummer Wine", gradient: "linear-gradient(160deg,#B89A4F,#5A4828)" },
    { title: "Dad's Army",   gradient: "linear-gradient(160deg,#7B8F6E,#5A6B50)" },
  ];

  return (
    <div className="page" style={{ gap: 22 }}>
      <ContextStrip says={says} heard={heard} />

      {/* Now playing hero */}
      <div className="card-hero" style={{ padding: 0, overflow: "hidden",
                                          display: "grid", gridTemplateColumns: "300px 1fr",
                                          minHeight: 300 }}>
        <div className="show-poster" style={{
            height: "100%", borderRadius: 0,
            background: "linear-gradient(160deg,#4F708A 0%,#2A241C 100%)",
            fontSize: 36, padding: 20, alignItems: "flex-end" }}>
          <PlatformPill>Hulu · live</PlatformPill>
          <span style={{ position: "relative", zIndex: 1 }}>The Evening<br/>News</span>
        </div>

        <div style={{ padding: "26px 28px", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
          <div>
            <Eyebrow color="var(--ember-deep)">{paused ? "Paused" : "Now playing"}</Eyebrow>
            <div style={{ fontFamily: "var(--font-serif)", fontSize: 44, fontWeight: 500,
                          letterSpacing: "-0.01em", lineHeight: 1.0,
                          color: "var(--ink)", margin: "8px 0 6px" }}>
              The Evening News
            </div>
            <div style={{ fontSize: 22, color: "var(--ink-soft)" }}>
              Tuesday — 6:00 PM
            </div>

            {/* Plain-language platform & duplicate-show line */}
            <div style={{ marginTop: 14, display: "flex", alignItems: "center", gap: 10,
                          fontSize: 18, color: "var(--ink-mute)" }}>
              <Icon name="info" size={20} color="var(--sky-deep)" />
              <span>You usually watch this on Hulu. Also on BBC iPlayer.</span>
            </div>
          </div>

          {/* Big controls */}
          <div style={{ display: "flex", alignItems: "center", gap: 22, marginTop: 18 }}>
            <CircleButton icon="arrow-counter-clockwise"
                          onClick={() => setIntent("go back a little",
                            "I went back about ten seconds. You're still on Hulu. Nothing was lost.")}
                          ariaLabel="Go back" />
            <CircleButton icon={paused ? "play" : "pause"} kind="primary" big
                          onClick={togglePause}
                          ariaLabel={paused ? "Play" : "Pause"} />
            <CircleButton icon="speaker-high"
                          onClick={() => setIntent("louder", "A little louder.")}
                          ariaLabel="Volume" />
          </div>
        </div>
      </div>

      {/* Intent-based rewind */}
      <div>
        <Eyebrow>If you missed something</Eyebrow>
        <div className="intent-row" style={{ marginTop: 10 }}>
          <IntentChip icon="arrow-counter-clockwise"
            onClick={() => setIntent("I missed that",
              "I went back about thirty seconds. You're still on Hulu.")}>
            I missed that
          </IntentChip>
          <IntentChip icon="rewind"
            onClick={() => setIntent("go back a little",
              "I went back about ten seconds. Nothing was lost.")}>
            Go back a little
          </IntentChip>
          <IntentChip icon="arrow-clockwise"
            onClick={() => setIntent("too far",
              "Coming forward a little. You're back where you wanted.")}>
            Too far
          </IntentChip>
          <IntentChip icon="question"
            onClick={() => setIntent("what just happened?",
              "You're watching the Evening News on Hulu. The newsreader was talking about the weather.")}>
            What just happened?
          </IntentChip>
        </div>
      </div>

      {/* Continue watching */}
      <div>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
          <Eyebrow>Shows you're in the middle of</Eyebrow>
          <div style={{ fontSize: 16, color: "var(--ink-mute)" }}>
            Pick up where you left off
          </div>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 14, marginTop: 12 }}>
          {continueWatching.map((s, i) => (
            <ShowTile key={i} title={s.title} platform={s.platform}
                      progress={s.progress} gradient={s.gradient}
                      height={150} fontSize={26}
                      onClick={() => setIntent(`play ${s.title.replace("\n"," ")}`,
                        `Putting on ${s.title.replace("\n"," ")} on ${s.platform}. You're at ${s.progress} percent.`)} />
          ))}
        </div>
      </div>

      {/* Never-lost shelf */}
      <div>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
          <Eyebrow>Shows you like</Eyebrow>
          <div style={{ fontSize: 16, color: "var(--ink-mute)" }}>
            You can come back to these any time.
          </div>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 14, marginTop: 12 }}>
          {showsYouLike.map((s, i) => (
            <ShowTile key={i} title={s.title} gradient={s.gradient}
                      height={150} fontSize={26}
                      onClick={() => setIntent(`watch ${s.title.replace("\n"," ")}`,
                        `Putting on ${s.title.replace("\n"," ")}. You haven't lost it — it's always here.`)} />
          ))}
        </div>
      </div>
    </div>
  );
};
