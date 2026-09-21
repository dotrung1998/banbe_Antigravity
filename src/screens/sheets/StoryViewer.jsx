import { useEffect } from 'react';
import { useGoc } from '../../state/GocContext.jsx';

// Task 3.4 (07-notifications.md) — the story progression viewer. A
// deliberately SEPARATE component/state from PhotoViewer.jsx and
// ChatPhotoViewer.jsx (14-photo-viewer.md's own instruction not to conflate
// origin/back semantics across viewer kinds) even though it shares the same
// blurred-fullscreen visual language.
const STORY_MS = 5000;

export default function StoryViewer() {
  const { state: s, T, closeStoryViewer, storyNext, storyPrev, markStoryViewedAt } = useGoc();
  const viewer = s.storyViewer;
  const index = viewer?.index ?? 0;
  const story = viewer?.stories?.[index];

  // Records the view for whichever story is currently shown, including the
  // very first one and every subsequent storyNext()/storyPrev() step.
  useEffect(() => {
    if (viewer) markStoryViewedAt(index);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewer?.organizerId, index]);

  // Auto-advance after STORY_MS, same as every other stories implementation
  // this feature is modeled on functionally (not visually/branding-wise —
  // see this ticket's own "do not copy Messenger/Instagram" instruction).
  useEffect(() => {
    if (!viewer) return undefined;
    const t = setTimeout(storyNext, STORY_MS);
    return () => clearTimeout(t);
  }, [viewer?.organizerId, index, storyNext]);

  if (!viewer || !story) return null;

  const onTap = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    if (x < rect.width / 2) storyPrev();
    else storyNext();
  };

  return (
    <div
      data-screen-label="Story viewer"
      onClick={onTap}
      style={{ position: 'absolute', inset: 0, zIndex: 27, background: '#000', display: 'flex', alignItems: 'center', justifyContent: 'center', animation: 'gocFade 0.2s ease both' }}
    >
      <img src={story.url} alt="" data-testid="story-viewer-image" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />

      {/* Progress bars — one per story in this author's set, the current one filling. */}
      <div style={{ position: 'absolute', top: 54, left: 12, right: 12, display: 'flex', gap: 4 }}>
        {viewer.stories.map((st, i) => (
          <div key={st.id} style={{ flex: 1, height: 2.5, borderRadius: 2, background: 'rgba(255,255,255,0.35)', overflow: 'hidden' }}>
            <div style={{ height: '100%', background: '#fff', width: i < index ? '100%' : '0%', animation: i === index ? `gocStoryFill ${STORY_MS}ms linear forwards` : 'none' }} />
          </div>
        ))}
      </div>

      <div onClick={(e) => { e.stopPropagation(); closeStoryViewer(); }} data-testid="story-viewer-close" style={{ position: 'absolute', top: 62, right: 16, color: '#fff', fontSize: 22, cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>×</div>

      <span style={{ position: 'absolute', bottom: 40, left: 18, color: 'rgba(255,255,255,0.75)', fontSize: 10.5, letterSpacing: '0.04em', textShadow: '0 1px 3px rgba(12,12,12,0.55)' }}>
        banbe ▪︎ {T('story', 'story')}
      </span>
    </div>
  );
}
