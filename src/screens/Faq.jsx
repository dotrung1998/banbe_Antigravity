import { useBanBe } from '../state/BanBeContext.jsx';
import HelpReader from './HelpReader.jsx';
import { FAQ_SECTIONS } from '../data/help/index.js';
import { filterHelpSections } from '../lib/contentFlags.js';

// Help & Legal > Q&A (frequently asked questions), grouped by topic.
export default function Faq() {
  const { T, set, state: s } = useBanBe();
  return (
    <HelpReader
      testId="faq"
      title={T('Hỏi & Đáp', 'Q&A')}
      intro={T('Câu hỏi thường gặp. Dùng ô tìm kiếm để lọc nhanh.', 'Frequently asked questions. Use the search box to filter.')}
      sections={filterHelpSections(FAQ_SECTIONS, s.featureFlags)}
      onBack={() => set({ screen: 'accountGroup', accountGroupKey: 'helpLegal' })}
      backLabel={T('Trợ Giúp & Pháp Lý', 'Help & Legal')}
    />
  );
}
