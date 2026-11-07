// Admin "Project hub demo" picker (note 76, migration 216, switch project_hub_demo). Opened from Account > Review &
// moderation, admins only: pick who to view the sample project as and whether the demo clock sits on the event day,
// then open the hub on sample data. Same picker on iOS.
import { useState } from 'react';
import { useEventProject } from '../../state/useEventProject.js';
import { DEMO_ROLES } from '../../lib/projectDemo.js';
import { Sheet, Chip, ChipRow, FieldLabel, Note, pillButton } from './ProjectUI.jsx';
import { ink, ink2 } from '../../theme.js';

export default function ProjectDemoPicker({ close }) {
  const p = useEventProject();
  const { T } = p;
  const [as, setAs] = useState('host');
  const [eventDay, setEventDay] = useState(false);
  const [busy, setBusy] = useState(false);
  return (
    <Sheet title={T('Bản demo dự án sự kiện', 'Project hub demo')} onClose={close} testId="project-demo-picker" closeTestId="project-demo-picker-close">
      <Note tone="ink2">{T('Dữ liệu mẫu. Không lưu gì.', 'Sample data. Nothing is saved.')}</Note>
      <FieldLabel>{T('Xem với vai trò', 'View as')}</FieldLabel>
      <ChipRow>
        {DEMO_ROLES.map(r => <Chip key={r} title={p.roleName(r)} selected={as === r} onClick={() => setAs(r)} testId={`project-demo-as-${r}`} />)}
      </ChipRow>
      <label style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 44, color: ink, cursor: 'pointer' }}>
        <input type="checkbox" role="switch" checked={eventDay} onChange={e => setEventDay(e.target.checked)} data-testid="project-demo-event-day" style={{ width: 22, height: 22 }} />
        <span style={{ flex: 1 }}>
          <strong style={{ display: 'block' }}>{T('Ngày diễn ra', 'Event day')}</strong>
          <span style={{ fontSize: 13, color: ink2 }}>{T('Đặt đồng hồ demo vào ngày sự kiện để xem chế độ trực tiếp của Ngày G.', 'Puts the demo clock on the event day to show Day-of live mode.')}</span>
        </span>
      </label>
      <button type="button" disabled={busy} data-testid="project-demo-open" style={pillButton(true)}
        onClick={async () => { setBusy(true); const ok = await p.openProjectDemo({ as, eventDay }); setBusy(false); if (!ok) close(); }}>
        {T('Mở bản demo', 'Open demo')}
      </button>
    </Sheet>
  );
}
