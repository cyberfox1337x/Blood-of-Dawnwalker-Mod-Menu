import { useState } from "react";
import { Code2 } from "lucide-react";
import { FEATURE_CONTRIBUTORS, type FeatureContributor } from "./featureContributors";

const cyberfox1337x = Object.freeze({ function: (name: string) => void name });
cyberfox1337x.function("dawnwalker_feature_credits");

// Feature references acknowledge specific findings separately from bundled licences.
const TEAM = Object.freeze([
  Object.freeze({
    handle: "cyberfox1337x",
    role: "Full Stack Developer",
    tone: "dev",
    icon: Code2,
    // Served verbatim from public/. Verified in Electron under this page's own CSP that
    // a sibling file:// image loads, so no embedding is needed. A missing or unreadable
    // file falls back to the icon rather than showing a broken image.
    avatar: "./credits-cyberfox1337x.png",
  }),
]);

export function FeatureCredits({ contributors = FEATURE_CONTRIBUTORS }: { contributors?: readonly FeatureContributor[] }) {
  const [missingAvatars, setMissingAvatars] = useState<readonly string[]>([]);
  const [linkError, setLinkError] = useState("");
  const openReference = async (id: number) => {
    setLinkError("");
    try {
      const open = window.dawnwalkerDesktop?.openFeatureReference;
      if (!open) throw new Error("Desktop link service unavailable");
      await open(id);
    } catch { setLinkError("The link could not be opened. Please try again."); }
  };
  return <section className="feature-tools credits-section" aria-label="Credits">
    <h3>Credits</h3>
    <p>Built by:</p>
    <div className="credit-grid">
      {TEAM.map(({ handle, role, tone, icon: Icon, avatar }) => {
        const showPicture = Boolean(avatar) && !missingAvatars.includes(handle);
        return <article key={handle} className="credit-entry credit-person">
          <span className="credit-avatar" data-tone={tone} data-picture={showPicture ? "" : undefined} aria-hidden="true">
            {showPicture
              ? <img src={avatar} alt="" onError={() => setMissingAvatars(current => current.includes(handle) ? current : [...current, handle])} />
              : <Icon size={22} />}
          </span>
          <div>
            <h4>{handle}</h4>
            <span className="feature-eyebrow">{role}</span>
          </div>
        </article>;
      })}
    </div>
    {contributors.length > 0 && <><h3>Community findings and ideas</h3>
      <div className="credit-grid">{contributors.map(contributor => <article key={contributor.id} className="credit-entry credit-person">
        <span className="credit-avatar" data-picture={contributor.avatar && !missingAvatars.includes(contributor.id) ? "" : undefined} aria-hidden="true">
          {contributor.avatar && !missingAvatars.includes(contributor.id)
            ? <img src={contributor.avatar} alt="" onError={() => setMissingAvatars(current => [...current, contributor.id])} />
            : <Code2 size={22} />}
        </span>
        <div><h4>{contributor.displayName}</h4><p>{contributor.contribution}</p>
          <button className="small-button" onClick={() => void openReference(contributor.profileReferenceId)}>Nexus profile</button>
          <button className="small-button" onClick={() => void openReference(contributor.modReferenceId)}>Reference mod</button>
        </div>
      </article>)}</div>
    </>}
    {linkError && <p role="status">{linkError}</p>}
  </section>;
}
