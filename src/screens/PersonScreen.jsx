// PersonScreen — dementia-first face recognition.
// After a successful scan: one calm identity card (name, relationship,
// where from, age, photo) and a scrollable strip of shared photos.
// No story paragraphs, no factoid stacks — minimal text, low anxiety.
import { ContextStrip, Eyebrow, Icon } from '../components/primitives.jsx';

const PERSON = {
  name: "Sarah",
  relationship: "Your daughter",
  from: "Brighton",
  age: 52,
  portrait: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=900&q=80&auto=format&fit=crop",
};

const PHOTOS = [
  { src: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=900&q=80&auto=format&fit=crop", caption: "The beach, last summer" },
  { src: "https://images.unsplash.com/photo-1543589077-47d81606c1bf?w=900&q=80&auto=format&fit=crop", caption: "Christmas 2024" },
  { src: "https://images.unsplash.com/photo-1519225421980-715cb0215aed?w=900&q=80&auto=format&fit=crop", caption: "Sarah's wedding, 2010" },
  { src: "https://images.unsplash.com/photo-1502331538081-041522531548?w=900&q=80&auto=format&fit=crop", caption: "Garden, spring" },
  { src: "https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=900&q=80&auto=format&fit=crop", caption: "Tea together" },
  { src: "https://images.unsplash.com/photo-1502323777036-f29e3972d82f?w=900&q=80&auto=format&fit=crop", caption: "Walk by the sea" },
];

export const PersonScreen = () => (
  <div className="page people-page">
    <ContextStrip
      says={`This is ${PERSON.name}, ${PERSON.relationship.toLowerCase()}.`}
      heard="who is this?"
    />

    {/* Identity card — the one focal point */}
    <div className="person-card">
      <div
        className="person-portrait"
        style={{ backgroundImage: `url(${PERSON.portrait})` }}
        aria-label={`Photo of ${PERSON.name}`}
      />
      <div className="person-info">
        <div className="person-eyebrow">This is</div>
        <div className="person-name">{PERSON.name}</div>
        <div className="person-relationship">{PERSON.relationship}</div>
        <div className="person-meta">
          <span className="person-meta-item">
            <Icon name="map-pin" weight="fill" size={22} color="var(--ember)" />
            From {PERSON.from}
          </span>
          <span className="person-meta-dot" />
          <span className="person-meta-item">
            <Icon name="cake" weight="fill" size={22} color="var(--ember)" />
            {PERSON.age} years old
          </span>
        </div>
      </div>
    </div>

    {/* Scrollable photos strip */}
    <div className="people-photos">
      <Eyebrow>Photos with {PERSON.name}</Eyebrow>
      <div className="people-photos-row">
        {PHOTOS.map((p, i) => (
          <figure key={i} className="people-photo">
            <div
              className="people-photo-img"
              style={{ backgroundImage: `url(${p.src})` }}
              aria-label={p.caption}
            />
            <figcaption className="people-photo-caption">{p.caption}</figcaption>
          </figure>
        ))}
      </div>
    </div>
  </div>
);
