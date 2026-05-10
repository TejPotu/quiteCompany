// Shared primitives for the Hearth tablet UI kit.

export const Icon = ({ name, weight = "duotone", size = 32, color }) => (
  <i className={`ph-${weight} ph-${name}`} style={{ fontSize: size, color, lineHeight: 1 }}></i>
);

export const Eyebrow = ({ children, color }) => (
  <div className="eyebrow" style={{ color }}>{children}</div>
);

export const Photo = ({ initial, tone = "ember", size = 96, radius = 20 }) => (
  <div className={`photo ${tone}`}
       style={{ width: size, height: size, borderRadius: radius, fontSize: size * 0.42 }}>
    {initial}
  </div>
);

export const Button = ({ kind = "primary", icon, children, onClick, style }) => (
  <button className={`btn btn-${kind}`} onClick={onClick} style={style}>
    {icon && <Icon name={icon} weight="bold" size={24} />}
    {children}
  </button>
);

export const CircleButton = ({ icon, kind = "secondary", big, onClick, ariaLabel }) => (
  <button className={`btn btn-${kind} btn-circle ${big ? "big" : ""}`}
          onClick={onClick} aria-label={ariaLabel}>
    <Icon name={icon} weight="bold" size={big ? 56 : 44} />
  </button>
);

export const ListeningIndicator = ({ active = true }) => (
  <div className="listening">
    <span className="listening-dot" style={{ animationPlayState: active ? "running" : "paused" }}></span>
    Hearth is listening
  </div>
);

export const TopBar = ({ greeting, time, day, listening = true }) => (
  <div className="topbar">
    <div className="topbar-greeting">{greeting}</div>
    {listening && <ListeningIndicator />}
    <div className="topbar-spacer"></div>
    <div className="topbar-time">{time}</div>
    <div className="topbar-day">{day}</div>
  </div>
);

export const NavTab = ({ icon, label, active, onClick }) => (
  <button className={`nav-tab ${active ? "active" : ""}`} onClick={onClick}>
    <Icon name={icon} weight={active ? "fill" : "duotone"} size={36}
          color={active ? "var(--paper)" : "var(--ink-soft)"} />
    <span>{label}</span>
  </button>
);

export const BottomNav = ({ current, onChange }) => (
  <div className="nav">
    <NavTab icon="house"             label="Home"      active={current === "home"}      onClick={() => onChange("home")} />
    <NavTab icon="television-simple" label="Watch"     active={current === "tv"}        onClick={() => onChange("tv")} />
    <NavTab icon="users-three"       label="People"    active={current === "people"}    onClick={() => onChange("people")} />
    <NavTab icon="bell"              label="Reminders" active={current === "reminders"} onClick={() => onChange("reminders")} />
  </div>
);

export const VoiceBar = ({ said, hint = "Try saying: “Play my news” or “Go back a little.”" }) => (
  <div className="voice-bar">
    <Icon name="microphone" weight="fill" size={32} color="var(--ember)" />
    {said
      ? <div className="said">"{said}"</div>
      : <div className="hint">{hint}</div>}
  </div>
);

export const ContextStrip = ({ says, heard }) => (
  <div className="context-strip">
    <div className="context-says">
      <span className="context-says-dot"></span>
      <div style={{ minWidth: 0 }}>
        <div className="context-eyebrow">Hearth says</div>
        <div className="context-says-text">{says}</div>
      </div>
    </div>
    <div className="context-heard">
      <div className="context-eyebrow">Heard</div>
      {heard
        ? <div className="context-heard-text">"{heard}"</div>
        : <div className="context-heard-empty">Listening…</div>}
    </div>
  </div>
);

export const PlatformPill = ({ children }) => (
  <span className="platform-pill">{children}</span>
);

export const ShowTile = ({ title, gradient, platform, progress, height = 180, fontSize = 28, onClick }) => (
  <button className="show-tile" onClick={onClick}>
    <div className="show-poster" style={{ height, fontSize, background: gradient }}>
      {platform && <PlatformPill>{platform}</PlatformPill>}
      <span style={{ position: "relative", zIndex: 1 }}>{title}</span>
      {progress != null && (
        <div className="progress-bar">
          <div className="progress-bar-fill" style={{ width: `${progress}%` }}></div>
        </div>
      )}
    </div>
  </button>
);

export const IntentChip = ({ icon, children, onClick }) => (
  <button className="intent-chip" onClick={onClick}>
    <Icon name={icon} weight="bold" size={22} />
    {children}
  </button>
);
