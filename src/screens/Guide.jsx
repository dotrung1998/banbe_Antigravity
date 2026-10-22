import { useEffect } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import HelpReader from './HelpReader.jsx';
import { GUIDES } from '../data/help/index.js';
import { filterHelpSections } from '../lib/contentFlags.js';

// Help & Legal > Guides. `s.guideKey` picks the guide (personal | host |
// admin). The admin guide is only for admin accounts — anyone else asking for
// it (stale link, role change) is sent back to Help & Legal.
export default function Guide() {
  const { state: s, T, set } = useBanBe();
  const guide = GUIDES[s.guideKey];
  const allowed = !!guide && (!guide.adminOnly || s.accountType === 'admin');
  // The admin guide is opened from the Admin tab, so it returns there.
  const fromAdmin = s.guideKey === 'admin';
  const back = () => set(fromAdmin ? { screen: 'profile' } : { screen: 'accountGroup', accountGroupKey: 'helpLegal' });
  useEffect(() => { if (!allowed) set({ screen: 'accountGroup', accountGroupKey: 'helpLegal' }); }, [allowed, set]);
  if (!allowed) return null;
  return (
    <HelpReader
      testId={`guide-${s.guideKey}`}
      title={T(guide.vi, guide.en)}
      intro={T(guide.introVi, guide.introEn)}
      sections={filterHelpSections(guide.sections, s.featureFlags)}
      onBack={back}
      backLabel={fromAdmin ? T('Tài khoản', 'Account') : T('Trợ Giúp & Pháp Lý', 'Help & Legal')}
    />
  );
}
