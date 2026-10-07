import { useEffect } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import HelpReader from './HelpReader.jsx';
import { GUIDES } from '../data/help/index.js';

// Help & Legal > Guides. `s.guideKey` picks the guide (personal | host |
// admin). The admin guide is only for admin accounts — anyone else asking for
// it (stale link, role change) is sent back to Help & Legal.
export default function Guide() {
  const { state: s, T, set } = useBanBe();
  const guide = GUIDES[s.guideKey];
  const allowed = !!guide && (!guide.adminOnly || s.accountType === 'admin');
  const back = () => set({ screen: 'accountGroup', accountGroupKey: 'helpLegal' });
  useEffect(() => { if (!allowed) set({ screen: 'accountGroup', accountGroupKey: 'helpLegal' }); }, [allowed, set]);
  if (!allowed) return null;
  return (
    <HelpReader
      testId={`guide-${s.guideKey}`}
      title={T(guide.vi, guide.en)}
      intro={T(guide.introVi, guide.introEn)}
      sections={guide.sections}
      onBack={back}
      backLabel={T('Trợ Giúp & Pháp Lý', 'Help & Legal')}
    />
  );
}
