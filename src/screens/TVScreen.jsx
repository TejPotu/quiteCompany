// TVScreen — dementia-first TV remote.
//
// Designed against real pain points from dementia patients:
// - AI hides platforms (no Hulu/iPlayer/ITVX wording shown to user)
// - Each show has one canonical source — no duplicate listings
// - "Stop watching" is a plain-language button, not an X icon
// - Currently playing show has redundant focal cues (outline + badge + scale + dim others)
// - Rewind chips speak in human time, not seconds
// - Each tile reassures: "Always here" + resume point so progress isn't lost
// - "Captions: On" indicator is persistent and visible
import { useState } from 'react';
import { Icon, CircleButton, IntentChip, ContextStrip } from '../components/primitives.jsx';

const FAVOURITES = [
  {
    title: "Antiques Roadshow",
    episode: "Episode 4 — Cardiff Castle",
    resume: "12 minutes in",
    image: "https://images.unsplash.com/photo-1513519245088-0e12902e5a38?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(184,154,79,.55) 0%,rgba(42,36,28,.85) 100%)",
  },
  {
    title: "Coronation Street",
    episode: "Episode 12 — A new neighbour",
    resume: "Start of episode",
    image: "https://images.unsplash.com/photo-1444723121867-7a241cacace9?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(156,78,44,.55) 0%,rgba(58,36,26,.88) 100%)",
  },
  {
    title: "Gardeners' World",
    episode: "Episode 7 — Spring borders",
    resume: "26 minutes in",
    image: "https://images.unsplash.com/photo-1466692476868-aef1dfb1e735?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(90,107,80,.45) 0%,rgba(42,36,28,.85) 100%)",
  },
  {
    title: "Doc Martin",
    episode: "Episode 2 — Cornwall calls",
    resume: "5 minutes in",
    image: "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(122,154,179,.5) 0%,rgba(42,36,28,.85) 100%)",
  },
  {
    title: "Call the Midwife",
    episode: "Episode 5 — Poplar in winter",
    resume: "Start of episode",
    image: "https://images.unsplash.com/photo-1519741497674-611481863552?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(199,106,63,.5) 0%,rgba(58,36,26,.88) 100%)",
  },
  {
    title: "Dad's Army",
    episode: "Episode 1 — On parade",
    resume: "18 minutes in",
    image: "https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=900&q=80&auto=format&fit=crop",
    tint: "linear-gradient(160deg,rgba(123,143,110,.5) 0%,rgba(42,36,28,.85) 100%)",
  },
];

export const TVScreen = () => {
  const [paused, setPaused]     = useState(false);
  const [stopped, setStopped]   = useState(false);
  const [playing, setPlaying]   = useState(FAVOURITES[0]);
  const [says, setSays]         = useState(
    `Now playing ${FAVOURITES[0].title}. ${FAVOURITES[0].episode}. You're ${FAVOURITES[0].resume}.`
  );
  const [heard, setHeard]       = useState("");

  const setIntent = (label, narration) => {
    setHeard(label);
    setSays(narration);
  };

  const togglePause = () => {
    const wasPaused = paused;
    setPaused(p => !p);
    setHeard(wasPaused ? "play" : "pause");
    setSays(wasPaused
      ? `Playing again. You're back where you left off in ${playing.title}.`
      : `Paused. We can come back any time.`);
  };

  const stopWatching = () => {
    const wasTitle = playing.title;
    setStopped(true);
    setPaused(false);
    setHeard("stop watching");
    setSays(`All done with ${wasTitle}. It's saved right where you left off.`);
  };

  const playShow = (show) => {
    setPlaying(show);
    setPaused(false);
    setStopped(false);
    setHeard(`watch ${show.title}`);
    setSays(`Putting on ${show.title}. ${show.episode}. ${show.resume === "Start of episode" ? "Starting from the beginning." : `You're ${show.resume}.`}`);
  };

  return (
    <div className="page watch-page">
      <ContextStrip says={says} heard={heard} />

      {/* Now playing — the unmistakable focal point */}
      {!stopped ? (
        <div className="now-playing">
          <div
            className="now-playing-poster"
            style={{ backgroundImage: `${playing.tint}, url(${playing.image})` }}
          >
            <div className="now-playing-badge">
              <span className="now-playing-badge-dot" />
              {paused ? "Paused" : "Now playing"}
            </div>
            <div className="now-playing-captions">
              <Icon name="closed-captioning" weight="fill" size={18} color="#FAF6EF" />
              Captions on
            </div>
            <span className="now-playing-poster-title">{playing.title}</span>
          </div>

          <div className="now-playing-info">
            <div className="now-playing-label">You are watching</div>
            <div className="now-playing-title">{playing.title}</div>
            <div className="now-playing-episode">
              <Icon name="television-simple" weight="fill" size={28} color="var(--ember)" />
              {playing.episode}
            </div>
            <div className="now-playing-resume">
              <Icon name="bookmark-simple" weight="fill" size={22} color="var(--sage-deep)" />
              You're {playing.resume}
            </div>

            <div className="now-playing-controls">
              <CircleButton
                icon="arrow-counter-clockwise"
                onClick={() => setIntent("go back a little",
                  "I went back about ten seconds. Nothing was lost.")}
                ariaLabel="Go back"
              />
              <CircleButton
                icon={paused ? "play" : "pause"}
                kind="primary"
                big
                onClick={togglePause}
                ariaLabel={paused ? "Play" : "Pause"}
              />
              <CircleButton
                icon="speaker-high"
                onClick={() => setIntent("louder", "A little louder.")}
                ariaLabel="Volume"
              />
            </div>

            <button className="stop-watching" onClick={stopWatching}>
              <Icon name="x-circle" weight="fill" size={28} />
              Stop watching
            </button>
          </div>
        </div>
      ) : (
        <div className="watch-confirmation" role="status">
          <Icon name="check-circle" weight="fill" size={32} color="var(--sage-deep)" />
          <div>
            <div className="watch-confirmation-title">Saved your place in {playing.title}.</div>
            <div className="watch-confirmation-sub">Pick another show below whenever you'd like.</div>
          </div>
        </div>
      )}

      {/* Plain-language navigation chips — only meaningful when watching */}
      {!stopped && (
        <div className="watch-intents">
          <div className="watch-intents-label">If you missed something</div>
          <div className="intent-row">
            <IntentChip icon="arrow-counter-clockwise"
              onClick={() => setIntent("I missed that",
                "I went back about thirty seconds. You haven't lost anything.")}>
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
              onClick={() => setIntent("what's happening?",
                `You're watching ${playing.title}. ${playing.episode}. You're ${playing.resume}.`)}>
              What's happening?
            </IntentChip>
          </div>
        </div>
      )}

      {/* Favourite shows */}
      <div className="favourites-heading">Your shows</div>
      <div className={`favourites-grid ${!stopped ? "has-playing" : ""}`}>
        {FAVOURITES.map((show) => {
          const isPlaying = !stopped && show.title === playing.title;
          return (
            <button
              key={show.title}
              className={`favourite-tile ${isPlaying ? "is-playing" : ""}`}
              onClick={() => playShow(show)}
            >
              <div
                className="favourite-poster"
                style={{ backgroundImage: `${show.tint}, url(${show.image})` }}
              >
                {isPlaying && (
                  <div className="favourite-playing-badge">
                    <span className="favourite-playing-badge-dot" />
                    Playing now
                  </div>
                )}
                <div className="favourite-resume">
                  <Icon name="bookmark-simple" weight="fill" size={14} color="#FAF6EF" />
                  {show.resume}
                </div>
              </div>
              <div className="favourite-title">{show.title}</div>
              <div className="favourite-episode">{show.episode}</div>
            </button>
          );
        })}
      </div>

      <div className="watch-reassurance">
        <Icon name="heart" weight="fill" size={22} color="var(--ember)" />
        Your shows are always here. Hearth keeps your place — nothing is ever lost.
      </div>
    </div>
  );
};
