import { useGoc } from '../../state/GocContext.jsx';
import { paper } from '../../theme.js';
import SurveyPublic from '../SurveyPublic.jsx';

/** Section 2 — a story's "Answer Survey" CTA opens the EXISTING SurveyPublic
 * screen inside a big modal floating over the current app context, never a
 * full-screen navigation destination. Mounted as an always-on-top sibling
 * in App.jsx (same pattern as StoryViewer/PulseViewer), keyed off
 * `state.storySurveyModalPublicId` rather than `state.screen` — Home and
 * StoryViewer stay mounted underneath (StoryViewer pauses itself by
 * watching this same state, see StoryViewer.jsx), so closing this modal
 * returns to the exact same story/context, not Home or another screen.
 * zIndex 28 — one above StoryViewer's own 27, so it visually floats over
 * the (now paused) story rather than beside it. */
export default function SurveyResponseModal() {
  const { state } = useGoc();
  if (!state.storySurveyModalPublicId) return null;
  return (
    <div
      data-testid="survey-response-modal"
      style={{ position: 'fixed', inset: 0, zIndex: 28, background: paper, overflowY: 'auto' }}
    >
      <SurveyPublic />
    </div>
  );
}
