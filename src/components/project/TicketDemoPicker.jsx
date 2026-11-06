// Admin "Ticket demo" picker (migration 217, switch ticket_demo). Opened from Account > Review & moderation, admins only:
// pick a ticket status (Hold, Pay, Review, ticket, ended, cancelled, expired), optionally 3 named tickets or a gifted ticket,
// then open the real ticket screen on a sample booking. Same picker on iOS.
import { useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { TICKET_DEMO_CASES, TICKET_DEMO_LABELS, ticketDemoAllowed, ticketDemoState } from '../../lib/ticketDemo.js';
import { Sheet, Chip, ChipRow, FieldLabel, Note, pillButton } from './ProjectUI.jsx';
import { ink2 } from '../../theme.js';

export default function TicketDemoPicker({ close }) {
  const { T, set } = useBanBe();
  const [key, setKey] = useState('upcoming');
  const [variant, setVariant] = useState('single'); // single | named | gifted
  const label = (k) => T(...TICKET_DEMO_LABELS[k]);
  const open = () => {
    set(prev => (ticketDemoAllowed(prev) ? ticketDemoState(key, { named: variant === 'named', gifted: variant === 'gifted', prevEventKey: prev.ticketDemoPrev || prev.eventKey }) : {}));
    close();
  };
  const variants = [['single', T('1 vé', '1 ticket')], ['named', T('3 vé có tên', '3 named tickets')], ['gifted', T('Vé đã tặng', 'Gifted ticket')]];
  const paidKey = !['holding', 'awaiting', 'review', 'expired'].includes(key);
  return (
    <Sheet title={T('Bản demo vé', 'Ticket demo')} onClose={close} testId="ticket-demo-picker" closeTestId="ticket-demo-picker-close">
      <Note tone="ink2">{T('Dữ liệu mẫu. Không lưu gì.', 'Sample data. Nothing is saved.')}</Note>
      <FieldLabel>{T('Trạng thái vé', 'Ticket status')}</FieldLabel>
      <ChipRow>
        {TICKET_DEMO_CASES.map(k => <Chip key={k} title={label(k)} selected={key === k} onClick={() => setKey(k)} testId={`ticket-demo-case-${k}`} />)}
      </ChipRow>
      {paidKey && (
        <>
          <FieldLabel>{T('Loại vé', 'Ticket type')}</FieldLabel>
          <ChipRow>
            {variants.map(([v, t]) => <Chip key={v} title={t} selected={variant === v} onClick={() => setVariant(v)} testId={`ticket-demo-variant-${v}`} />)}
          </ChipRow>
        </>
      )}
      <span style={{ fontSize: 13, color: ink2 }}>{T('Mở màn hình vé thật trên dữ liệu mẫu. Các nút ghi dữ liệu hoặc rời màn hình hiện "Không có trong bản demo".', 'Opens the real ticket screen on sample data. Buttons that write data or leave the screen say "Not available in the demo".')}</span>
      <button type="button" data-testid="ticket-demo-open" style={pillButton(true)} onClick={open}>{T('Mở bản demo', 'Open demo')}</button>
    </Sheet>
  );
}
