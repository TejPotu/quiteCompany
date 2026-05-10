// PersonScreen — VISION ONLY. Camera viewfinder + recognized person with rich detail.
// No call button here — calling lives on Home.
import { ContextStrip, Eyebrow, Photo, Icon } from '../components/primitives.jsx';

export const PersonScreen = () => (
  <div className="page" style={{ gap: 20 }}>
    <ContextStrip
      says="This is your daughter, Sarah. You saw her at the beach last summer."
      heard="who is this?"
    />

    <div style={{ display: "grid", gridTemplateColumns: "1fr 1.1fr", gap: 22, flex: 1, minHeight: 0 }}>
      {/* LEFT — camera viewfinder, larger */}
      <div style={{ position: "relative", minWidth: 0, display: "flex" }}>
        <div style={{
            width: "100%", borderRadius: 28, overflow: "hidden",
            background: "radial-gradient(circle at 50% 40%, #C9D7E2 0%, #7A9AB3 60%, #4F708A 100%)",
            position: "relative", boxShadow: "var(--shadow-3)" }}>
          {/* Soft silhouette */}
          <div style={{ position: "absolute", left: "50%", top: "60%", transform: "translate(-50%, -50%)",
                        width: 280, height: 280, borderRadius: "50%",
                        background: "rgba(250,246,239,0.42)", filter: "blur(12px)" }}></div>
          <div style={{ position: "absolute", left: "50%", top: "92%", transform: "translateX(-50%)",
                        width: 460, height: 240, borderRadius: "50% 50% 0 0",
                        background: "rgba(250,246,239,0.36)", filter: "blur(16px)" }}></div>
          {/* Detection box */}
          <div style={{ position: "absolute", left: "30%", top: "20%", width: "40%", height: "50%",
                        border: "3px solid #FAF6EF", borderRadius: 28,
                        boxShadow: "0 0 0 6px rgba(250,246,239,0.15)" }}>
            {/* Identity tag */}
            <div style={{ position: "absolute", top: -36, left: 0,
                          padding: "6px 16px", borderRadius: 8,
                          background: "var(--ember)", color: "#fff",
                          fontSize: 16, letterSpacing: "0.06em",
                          textTransform: "uppercase", fontWeight: 700 }}>
              Sarah · your daughter
            </div>
          </div>
          {/* Confidence note */}
          <div style={{ position: "absolute", bottom: 18, left: 18, right: 18,
                        padding: "10px 16px", borderRadius: 14,
                        background: "rgba(42,36,28,0.55)", backdropFilter: "blur(10px)",
                        color: "#FAF6EF", fontFamily: "var(--font-sans)",
                        fontSize: 17, display: "flex", alignItems: "center", gap: 10 }}>
            <Icon name="eye" weight="fill" size={20} />
            Looking. Hold steady — I'm sure of it.
          </div>
        </div>
      </div>

      {/* RIGHT — recognized person detail */}
      <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
        {/* Identity card */}
        <div className="card-hero" style={{ padding: 22, display: "flex", gap: 22, alignItems: "center" }}>
          <Photo initial="S" tone="ember" size={170} radius={26} />
          <div style={{ minWidth: 0 }}>
            <Eyebrow>This is</Eyebrow>
            <div style={{ fontFamily: "var(--font-serif)", fontSize: 64, fontWeight: 500,
                          letterSpacing: "-0.02em", lineHeight: 0.95, color: "var(--ink)",
                          margin: "6px 0 6px" }}>
              Sarah
            </div>
            <div style={{ fontSize: 22, color: "var(--ink-soft)" }}>your daughter</div>
            <div style={{ fontSize: 19, color: "var(--ink-mute)", marginTop: 8 }}>
              Lives in Brighton · 52 years old
            </div>
          </div>
        </div>

        {/* Story / memory */}
        <div className="card" style={{ background: "var(--card-warm)" }}>
          <Eyebrow>You and Sarah</Eyebrow>
          <div style={{ fontFamily: "var(--font-serif)", fontStyle: "italic", fontSize: 24,
                        color: "var(--ink)", lineHeight: 1.3, marginTop: 8 }}>
            "You went to the beach together last summer. Sarah brought a picnic and the two of you collected shells."
          </div>
          <div style={{ display: "flex", gap: 14, marginTop: 14, fontSize: 17, color: "var(--ink-mute)" }}>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <Icon name="clock" size={18} /> Last visit · 2 weeks ago
            </span>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <Icon name="cake" size={18} /> Birthday · March 14
            </span>
          </div>
        </div>

        {/* Photo strip — three memories with captions */}
        <div>
          <Eyebrow>Photos together</Eyebrow>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginTop: 10 }}>
            {[
              { tone: "sky",   caption: "The beach,\nlast summer" },
              { tone: "sage",  caption: "Christmas\n2024" },
              { tone: "honey", caption: "Sarah's wedding,\n2010" },
            ].map((m, i) => (
              <div key={i} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                <div className={`photo ${m.tone}`}
                     style={{ height: 110, borderRadius: 16 }}></div>
                <div style={{ fontSize: 15, color: "var(--ink-soft)", lineHeight: 1.25,
                              whiteSpace: "pre-line", textAlign: "center", fontWeight: 700 }}>
                  {m.caption}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  </div>
);
