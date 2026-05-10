// HomeScreen — visual-heavy. Now card + Call someone (this is where calls live).
import { useState } from 'react';
import { ContextStrip, Eyebrow, Photo, Icon, Button } from '../components/primitives.jsx';

export const HomeScreen = ({ goTo }) => {
  const [calling, setCalling] = useState(null);

  return (
    <div className="page" style={{ gap: 22 }}>
      <ContextStrip
        says={calling
          ? `Calling ${calling}. You'll see her face when she picks up.`
          : "Good morning. It's time for your medicine."}
        heard={calling ? `call my ${calling === "Sarah" ? "daughter" : "son"}` : ""}
      />

      {/* Giant Now card */}
      <div className="card-hero" style={{
          background: "#FFFBF4", border: "2px solid var(--honey)",
          padding: 0, overflow: "hidden",
          display: "grid", gridTemplateColumns: "320px 1fr",
          minHeight: 220 }}>
        <div style={{
            background: "linear-gradient(135deg, #F4E4B8 0%, #E8C77B 100%)",
            display: "flex", alignItems: "center", justifyContent: "center",
            position: "relative" }}>
          <Icon name="pill" weight="fill" size={150} color="#9C4E2C" />
          <div style={{ position: "absolute", top: 18, left: 18,
                        padding: "5px 14px", borderRadius: 999,
                        background: "var(--honey-deep)", color: "#fff",
                        fontSize: 14, fontWeight: 700, letterSpacing: "0.08em",
                        textTransform: "uppercase" }}>Now</div>
        </div>
        <div style={{ padding: 28, display: "flex", flexDirection: "column", justifyContent: "center", gap: 18 }}>
          <div style={{ fontFamily: "var(--font-serif)", fontSize: 46, fontWeight: 500,
                        letterSpacing: "-0.01em", lineHeight: 1.0, color: "var(--ink)" }}>
            Time for your medicine.
          </div>
          <div style={{ display: "flex", gap: 14 }}>
            <Button kind="confirm" icon="check">I took it</Button>
            <Button kind="secondary" onClick={() => goTo("reminders")}>Later</Button>
          </div>
        </div>
      </div>

      {/* Call someone — relationship-based calling */}
      <div>
        <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
          <Eyebrow>Call someone</Eyebrow>
          <div style={{ fontSize: 16, color: "var(--ink-mute)" }}>
            Just say "call my daughter" — or tap a face below.
          </div>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 14, marginTop: 12 }}>
          {[
            { name: "Sarah",    relation: "your daughter", initial: "S", tone: "ember" },
            { name: "Tom",      relation: "your son",      initial: "T", tone: "sage"  },
            { name: "Margaret", relation: "your wife",     initial: "M", tone: "sky"   },
            { name: "Henry",    relation: "your brother",  initial: "H", tone: "honey" },
          ].map(p => (
            <button key={p.name} onClick={() => setCalling(p.name)}
                    style={{ all: "unset", cursor: "pointer",
                             display: "flex", flexDirection: "column", alignItems: "center", gap: 10,
                             background: "var(--card)", padding: 18, borderRadius: 24,
                             border: calling === p.name ? "2px solid var(--ember)" : "1px solid var(--border-soft)",
                             boxShadow: calling === p.name ? "var(--shadow-2)" : "none" }}>
              <div style={{ position: "relative" }}>
                <Photo initial={p.initial} tone={p.tone} size={130} radius={22} />
                {calling === p.name && (
                  <div style={{ position: "absolute", inset: -6, borderRadius: 26,
                                border: "3px solid var(--ember)",
                                animation: "pulse 2.4s var(--ease) infinite" }}></div>
                )}
              </div>
              <div style={{ fontFamily: "var(--font-serif)", fontSize: 30, fontWeight: 500,
                            color: "var(--ink)", letterSpacing: "-0.01em" }}>
                {p.name}
              </div>
              <div style={{ fontSize: 16, color: "var(--ink-mute)" }}>{p.relation}</div>
              <div style={{ display: "inline-flex", alignItems: "center", gap: 8,
                            padding: "8px 18px", borderRadius: 999,
                            background: calling === p.name ? "var(--ember)" : "var(--paper-deep)",
                            color: calling === p.name ? "#fff" : "var(--ink)",
                            fontFamily: "var(--font-sans)", fontWeight: 700, fontSize: 18 }}>
                <Icon name="phone" weight="fill" size={20}
                      color={calling === p.name ? "#fff" : "var(--sage-deep)"} />
                {calling === p.name ? "Calling…" : "Call"}
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
