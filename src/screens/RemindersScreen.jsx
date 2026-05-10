// RemindersScreen — visual-heavy list + ContextStrip caption.
import { ContextStrip, Icon, Button } from '../components/primitives.jsx';

export const RemindersScreen = () => {
  const items = [
    { state: "done", time: "8:00", ampm: "AM", icon: "coffee",      title: "Breakfast" },
    { state: "now",  time: "9:00", ampm: "AM", icon: "pill",        title: "Medicine" },
    { state: "next", time: "12:30", ampm: "PM", icon: "fork-knife", title: "Lunch" },
    { state: "next", time: "4:00", ampm: "PM", icon: "user",        title: "Tom is visiting" },
    { state: "next", time: "8:00", ampm: "PM", icon: "moon",        title: "Evening medicine" },
  ];

  const tone = {
    done: { bg: "var(--card)", border: "var(--border-soft)", iconBg: "var(--paper-deep)", iconColor: "var(--ink-mute)",  text: "var(--ink-mute)", opacity: 0.55 },
    now:  { bg: "#FFFBF4",     border: "var(--honey)",        iconBg: "var(--honey)",      iconColor: "#fff",             text: "var(--ink)",      opacity: 1     },
    next: { bg: "var(--card)", border: "var(--border-soft)", iconBg: "var(--paper-deep)", iconColor: "var(--ink-soft)", text: "var(--ink)",      opacity: 1     },
  };

  return (
    <div className="page" style={{ gap: 14 }}>
      <ContextStrip
        says="You have five things today. One is right now — your medicine."
        heard=""
      />
      {items.map((r, i) => {
        const t = tone[r.state];
        const isDone = r.state === "done";
        return (
          <div key={i} style={{
              background: t.bg,
              border: `2px solid ${t.border}`,
              borderRadius: 24, padding: "16px 24px",
              display: "flex", alignItems: "center", gap: 24,
              opacity: t.opacity,
              boxShadow: r.state === "now" ? "var(--shadow-2)" : "var(--shadow-1)" }}>
            <div style={{ flex: "0 0 110px", textAlign: "center" }}>
              <div style={{ fontFamily: "var(--font-serif)", fontSize: 38, fontWeight: 500,
                            color: t.text, letterSpacing: "-0.02em", lineHeight: 1 }}>
                {r.time}
              </div>
              <div style={{ fontSize: 14, color: "var(--ink-mute)", letterSpacing: "0.08em",
                            textTransform: "uppercase", fontWeight: 700, marginTop: 4 }}>
                {r.ampm}
              </div>
            </div>
            <div style={{ width: 80, height: 80, borderRadius: 20, background: t.iconBg,
                          display: "flex", alignItems: "center", justifyContent: "center",
                          flex: "0 0 80px" }}>
              <Icon name={r.icon} weight={r.state === "now" ? "fill" : "duotone"} size={44} color={t.iconColor} />
            </div>
            <div style={{ fontFamily: "var(--font-serif)", fontSize: 34, fontWeight: 500,
                          color: t.text, lineHeight: 1.0, flex: 1, minWidth: 0,
                          textDecoration: isDone ? "line-through" : "none",
                          textDecorationColor: "var(--ink-faint)" }}>
              {r.title}
            </div>
            {r.state === "now" && (
              <Button kind="confirm" icon="check">I took it</Button>
            )}
            {isDone && (
              <Icon name="check-circle" weight="fill" size={36} color="var(--sage)" />
            )}
          </div>
        );
      })}
    </div>
  );
};
