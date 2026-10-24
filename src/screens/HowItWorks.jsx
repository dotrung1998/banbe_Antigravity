// Help & Legal > How banbe works (note 63): the same story as the public Welcome screen, replayable when signed in.
// Version 1 or 2 follows the admin switch `onboarding_v2`; the last page ends with Done instead of the sign-up CTAs.
// iOS twin: HowItWorksScreen in apps/ios/BanbeApp/Views/HowBanbeWorksView.swift.
import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink } from '../theme.js';
import { track } from '../lib/analytics.js';
import { flagOn } from '../lib/featureFlags.js';
import { HowBanbeWorksV1, HowBanbeWorksV2, HowBanbeWorksThanks, HIW_PAGE_COUNT } from '../components/HowBanbeWorks.jsx';

const plain = { border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontWeight: 600, minHeight: 44, cursor: 'pointer' };
const doneBtn = { width: '100%', minHeight: 56, borderRadius: 18, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 17, fontWeight: 700, cursor: 'pointer' };

export default function HowItWorks() {
  const { state: s, T, set } = useBanBe();
  const v2 = flagOn(s.featureFlags, 'onboarding_v2');
  const [page, setPage] = useState(0);
  // Done (or the swipe past the very last screen) thanks the person before going back (owner, 2026-10-24).
  const [finished, setFinished] = useState(false);
  const close = () => set({ screen: 'accountGroup', accountGroupKey: 'helpLegal' });
  useEffect(() => { track('public_story_opened'); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (page === HIW_PAGE_COUNT - 1) track('public_story_completed'); }, [page]);
  const Story = v2 ? HowBanbeWorksV2 : HowBanbeWorksV1;
  return (
    <div data-screen-label="How banbe works" style={{ minHeight: '100%', background: paper, color: ink, display: 'flex', justifyContent: 'center', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
      <div style={{ width: '100%', maxWidth: 480, padding: '56px 24px 120px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button type="button" data-testid="hiw-back" aria-label={T('Quay lại', 'Back')} onClick={() => (finished ? setFinished(false) : page > 0 ? setPage(page - 1) : close())} style={{ ...plain, fontSize: 22, padding: '0 10px' }}>‹</button>
          <span data-testid="welcome-story-progress" style={{ fontSize: 13, fontWeight: 600, opacity: 0.7 }}>{page + 1}/{HIW_PAGE_COUNT}</span>
          <span style={{ flex: 1 }} />
          {page < HIW_PAGE_COUNT - 1 && (
            <button type="button" data-testid="welcome-story-skip" onClick={() => { track('public_story_skipped', { step: page }); close(); }} style={{ ...plain, fontSize: 15 }}>{T('Bỏ qua', 'Skip')}</button>
          )}
        </div>
        {finished ? (
          <HowBanbeWorksThanks T={T}>
            <button type="button" data-testid="hiw-close" className="bb-press" onClick={close} style={doneBtn}>{T('Về Trợ giúp', 'Back to Help')}</button>
          </HowBanbeWorksThanks>
        ) : (
          <Story T={T} page={page} onNext={() => setPage(page + 1)} onFinish={() => setFinished(true)}
            finale={<button type="button" data-testid="hiw-done" className="bb-press" onClick={() => setFinished(true)} style={doneBtn}>{T('Xong', 'Done')}</button>} />
        )}
      </div>
    </div>
  );
}
