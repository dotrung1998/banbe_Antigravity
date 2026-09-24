import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton, alert } from '../theme.js';

function maskAccountNumber(number) {
  const s = String(number || '');
  if (s.length <= 4) return s;
  return '•'.repeat(Math.max(0, s.length - 4)) + s.slice(-4);
}

// Refund MVP (product rule B) — Account > "Tài khoản thanh toán & nhận hoàn
// tiền": the goer's own saved bank accounts, used as refund destinations.
// Reachable on its own (Account.jsx), and also opened mid-flow from a
// refund claim's "Thêm tài khoản mới" (returnToClaimId set by the caller),
// in which case saving returns straight back to that claim with the new
// account selected.
export default function RefundAccounts() {
  const {
    state, T, backFromRefundAccounts, loadRefundDestinations, saveRefundDestination, deleteRefundDestination, setDefaultRefundDestination,
    selectRefundDestinationForClaim, openPaymentDetails, reorderRefundDestinations,
  } = useGoc();
  const s = state;

  useEffect(() => { loadRefundDestinations(); }, [loadRefundDestinations]);

  // TASK B — native HTML5 drag-and-drop reorder (this app's own "web can
  // use its native accessible drag/reorder behavior" allowance), scoped to
  // the leading three-line handle only.
  const [dragId, setDragId] = useState(null);
  const [dragOverId, setDragOverId] = useState(null);
  const [openMenuId, setOpenMenuId] = useState(null);
  const handleDrop = (targetId) => {
    if (dragId && dragId !== targetId) {
      const ids = s.refundDestinations.map(d => d.id);
      const from = ids.indexOf(dragId);
      const to = ids.indexOf(targetId);
      if (from !== -1 && to !== -1) {
        ids.splice(to, 0, ids.splice(from, 1)[0]);
        reorderRefundDestinations(ids);
      }
    }
    setDragId(null); setDragOverId(null);
  };

  const [formOpen, setFormOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [label, setLabel] = useState('');
  const [bank, setBank] = useState('');
  const [account, setAccount] = useState('');
  const [holder, setHolder] = useState('');
  const [note, setNote] = useState('');
  const [setDefault, setSetDefault] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [revealedId, setRevealedId] = useState(null);
  const [copiedId, setCopiedId] = useState(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState(null);
  const [savedFlash, setSavedFlash] = useState(false);

  const openAddForm = () => {
    setFormOpen(true); setEditingId(null); setLabel(''); setBank(''); setAccount(''); setHolder(''); setNote('');
    setSetDefault(s.refundDestinations.length === 0); setConfirmed(false);
  };
  const openEditForm = (d) => {
    setFormOpen(true); setEditingId(d.id); setLabel(d.label || ''); setBank(d.bank_name); setAccount(d.account_number);
    setHolder(d.account_holder_name); setNote(d.transfer_note || ''); setSetDefault(!!d.is_default); setConfirmed(false);
  };

  const canSave = bank.trim() && account.trim() && holder.trim() && confirmed && !s.refundDestinationBusy;

  const doSave = async () => {
    if (!canSave) return;
    const newId = await saveRefundDestination({
      id: editingId, label: label.trim(), bankName: bank.trim(), accountNumber: account.trim(),
      accountHolderName: holder.trim(), transferNote: note.trim(), setDefault, confirmed,
    });
    if (!newId) return;
    setFormOpen(false);
    setSavedFlash(true);
    setTimeout(() => setSavedFlash(false), 2200);
    // "On successful Save, automatically return to the exact refund claim
    // and select the newly created account." — only when we actually got
    // here from one (returnToClaimId), and only for a genuinely NEW
    // account (editingId null); editing an existing one just stays here.
    if (s.refundAccountsReturnToClaimId && !editingId) {
      const claimId = s.refundAccountsReturnToClaimId;
      const bookingId = s.refundAccountsReturnToBookingId;
      await selectRefundDestinationForClaim(claimId, newId);
      if (bookingId) {
        openPaymentDetails(bookingId);
        // TASK A point 7/8 — this leaves 'refundAccounts' just as surely as
        // the in-view back link does, so the history entry openRefundAccounts()
        // pushed needs the same cleanup backFromRefundAccounts() gives it
        // (never leave a stray forward-navigable "refundAccounts" entry a
        // later swipe could resurrect).
        try { localStorage.removeItem('banbe.lastScreen'); } catch { /* private browsing */ }
        try { if (window.history.state?.bbScreen === 'refundAccounts') window.history.back(); } catch { /* unsupported */ }
      }
    }
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="RefundAccounts">
      <div onClick={backFromRefundAccounts} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="refund-accounts-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>{T('Tài khoản nhận hoàn tiền', 'Refund accounts')}</h1>
        {s.refundDestinations.length > 1 && (
          <p style={{ fontSize: 11.5, color: ink, opacity: 0.6, margin: '6px 0 0' }}>{T('Kéo để sắp xếp', 'Drag to reorder')}</p>
        )}
      </div>

      {savedFlash && (
        <p style={{ margin: '14px 22px 0', fontSize: 12.5, color: ink }} data-testid="refund-account-saved-flash">
          {T('Tài khoản nhận hoàn đã được lưu', 'Refund account saved')}
        </p>
      )}
      {!formOpen && s.refundDestinationsReordering && (
        <p style={{ margin: '14px 22px 0', fontSize: 11.5, color: ink, opacity: 0.6 }} data-testid="refund-account-reorder-saving">
          {T('Đang lưu thứ tự…', 'Saving order…')}
        </p>
      )}
      {!formOpen && !s.refundDestinationsReordering && s.refundDestinationError && (
        <p style={{ margin: '14px 22px 0', fontSize: 12.5, color: alert }} data-testid="refund-account-reorder-error">
          {s.refundDestinationError}
        </p>
      )}

      {!formOpen && (
        <div style={{ margin: '18px 22px 0' }}>
          {s.refundDestinations.length === 0 ? (
            <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
              <p style={{ fontSize: 13, color: ink, margin: 0, padding: '20px 16px', textAlign: 'center' }}>{T('Chưa có tài khoản nhận hoàn tiền', 'No refund accounts saved yet')}</p>
              <div style={{ borderTop: `1px solid ${rule}` }} />
              <div onClick={openAddForm} style={{ padding: '13px 14px', fontSize: 13, color: ink, cursor: 'pointer' }} data-testid="refund-account-add">
                {T('+ Thêm tài khoản', '+ Add account')}
              </div>
            </div>
          ) : (
            // TASK B — compact iOS Settings-style grouped list: one thin
            // row per account (no card padding/shadow), a leading drag
            // handle, main label + secondary bank/masked-number line, and
            // a trailing "Mặc định" tag or chevron — Edit/Delete live
            // behind a tap on that chevron instead of always-visible links.
            <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
              {s.refundDestinations.map((d, i, arr) => (
                <div key={d.id}>
                  <div
                    draggable
                    onDragStart={() => setDragId(d.id)}
                    onDragOver={(e) => { e.preventDefault(); setDragOverId(d.id); }}
                    onDrop={() => handleDrop(d.id)}
                    onDragEnd={() => { setDragId(null); setDragOverId(null); }}
                    data-testid="refund-account-row"
                    style={{
                      display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px',
                      borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none',
                      background: dragOverId === d.id && dragId !== d.id ? 'rgba(27,25,22,0.05)' : 'transparent',
                      opacity: dragId === d.id ? 0.5 : 1,
                    }}
                  >
                    <span aria-hidden style={{ flex: 'none', width: 18, height: 18, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'grab', opacity: 0.45 }} data-testid="refund-account-drag-handle">
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth="1.8" strokeLinecap="round">
                        <path d="M4 6.5h16M4 12h16M4 17.5h16" />
                      </svg>
                    </span>
                    <div
                      onClick={() => setOpenMenuId(openMenuId === d.id ? null : d.id)}
                      style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', cursor: 'pointer' }}
                    >
                      <span style={{ ...display(14) }}>{d.label || T('Tài khoản', 'Account')}</span>
                      <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }}>
                        {d.bank_name} ▪︎ {maskAccountNumber(d.account_number)}
                      </span>
                    </div>
                    {d.is_default ? (
                      <span style={{ flex: 'none', fontSize: 11, fontWeight: 600, color: ink, opacity: 0.55 }}>{T('Mặc định', 'Default')}</span>
                    ) : (
                      <span
                        onClick={() => setOpenMenuId(openMenuId === d.id ? null : d.id)}
                        aria-hidden
                        style={{ flex: 'none', fontSize: 15, color: ink, opacity: 0.35, cursor: 'pointer' }}
                      >
                        ›
                      </span>
                    )}
                  </div>
                  {openMenuId === d.id && (
                    <div style={{ padding: '10px 14px 14px 42px', display: 'flex', flexDirection: 'column', gap: 8, borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
                      <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>
                        {revealedId === d.id ? d.account_number : maskAccountNumber(d.account_number)} ▪︎ {d.account_holder_name}
                      </span>
                      <div style={{ display: 'flex', gap: 14 }}>
                        <span onClick={() => setRevealedId(revealedId === d.id ? null : d.id)} style={{ fontSize: 11.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>
                          {revealedId === d.id ? T('Ẩn', 'Hide') : T('Hiện số TK', 'Reveal')}
                        </span>
                        <span
                          onClick={async () => {
                            try {
                              await navigator.clipboard.writeText(d.account_number);
                              setCopiedId(d.id);
                              setTimeout(() => setCopiedId(cur => (cur === d.id ? null : cur)), 1500);
                            } catch { /* clipboard unavailable */ }
                          }}
                          style={{ fontSize: 11.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
                        >
                          {copiedId === d.id ? T('Đã sao chép', 'Copied') : T('Sao chép', 'Copy')}
                        </span>
                        <span onClick={() => openEditForm(d)} style={{ fontSize: 11.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Sửa', 'Edit')}</span>
                        {!d.is_default && (
                          <span onClick={() => setDefaultRefundDestination(d.id)} style={{ fontSize: 11.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Đặt mặc định', 'Set default')}</span>
                        )}
                        <span onClick={() => setConfirmDeleteId(d.id)} style={{ fontSize: 11.5, color: alert, textDecoration: 'underline', cursor: 'pointer' }}>{T('Xoá', 'Delete')}</span>
                      </div>
                      {confirmDeleteId === d.id && (
                        <div style={{ display: 'flex', gap: 10 }}>
                          <span style={{ fontSize: 11.5, color: ink, flex: 1 }}>{T('Xoá tài khoản này?', 'Delete this account?')}</span>
                          <span onClick={() => setConfirmDeleteId(null)} style={{ fontSize: 11.5, color: ink, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</span>
                          <span onClick={async () => { await deleteRefundDestination(d.id); setConfirmDeleteId(null); }} style={{ fontSize: 11.5, color: alert, cursor: 'pointer' }}>{T('Xoá', 'Delete')}</span>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              ))}
              <div
                onClick={openAddForm}
                style={{ padding: '13px 14px', fontSize: 13, color: ink, cursor: 'pointer' }}
                data-testid="refund-account-add"
              >
                {T('+ Thêm tài khoản', '+ Add account')}
              </div>
            </div>
          )}
        </div>
      )}

      {formOpen && (
        <div style={{ ...cardGlass({ margin: '18px 22px 40px', padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 8 }) }}>
          <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder={T('Nhãn (VD: Tài khoản chính)', 'Label (e.g. Main account)')}
                 style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
          <input value={bank} onChange={(e) => setBank(e.target.value)} placeholder={T('Tên ngân hàng', 'Bank name')}
                 style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
          <input value={account} onChange={(e) => setAccount(e.target.value)} placeholder={T('Số tài khoản', 'Account number')}
                 style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
          <input value={holder} onChange={(e) => setHolder(e.target.value)} placeholder={T('Tên chủ tài khoản', 'Account holder name')}
                 style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder={T('Ghi chú (không bắt buộc)', 'Note (optional)')}
                 style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: ink, cursor: 'pointer' }}>
            <input type="checkbox" checked={setDefault} onChange={(e) => setSetDefault(e.target.checked)} />
            {T('Đặt làm tài khoản mặc định', 'Set as default account')}
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: ink, cursor: 'pointer' }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} data-testid="refund-account-confirm-checkbox" />
            {T('Tôi xác nhận thông tin tài khoản trên là chính xác.', 'I confirm this account information is correct.')}
          </label>
          {s.refundDestinationError && <p style={{ fontSize: 12, color: alert, margin: 0 }}>{s.refundDestinationError}</p>}
          <div style={{ display: 'flex', gap: 10, marginTop: 4 }}>
            <div onClick={() => setFormOpen(false)} style={{ flex: 1, textAlign: 'center', padding: 12, borderRadius: 12, border: `1px solid ${rule}`, fontSize: 13, color: ink, cursor: 'pointer' }}>
              {T('Huỷ', 'Cancel')}
            </div>
            <div onClick={doSave} style={{ ...inkButton({ flex: 1, borderRadius: 12, padding: 12, fontSize: 13, opacity: canSave ? 1 : 0.5 }) }} data-testid="refund-account-save">
              {s.refundDestinationBusy ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
