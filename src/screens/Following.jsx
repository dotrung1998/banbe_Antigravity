import { useEffect, useMemo, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { filterFollowedHosts } from '../lib/follows.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';
import { RowIcon } from './Account.jsx';

// Account > Following. Reads ONLY the signed-in user's own `follows` rows (owner-only RLS) —
// the list is never published or shown to anyone else. Each row links to the host's real
// profile; Unfollow always asks first and reports a failed write honestly.
export default function Following() {
  const { state: s, T, set, loadFollowedHosts, setFollowing, openOrganizerProfile, goHome } = useBanBe();
  const [query, setQuery] = useState('');
  const [confirmId, setConfirmId] = useState(null);
  const [busyId, setBusyId] = useState(null);

  useEffect(() => { if (s.user?.id) loadFollowedHosts(); }, [s.user?.id, loadFollowedHosts]);

  const rows = s.followedHosts;
  const shown = useMemo(() => filterFollowedHosts(rows, query), [rows, query]);
  const confirmRow = rows.find(r => r.organizerId === confirmId) || null;
  const loading = s.followedStatus === 'loading' || s.followedStatus === 'idle';

  const doUnfollow = async () => {
    const id = confirmId;
    if (!id) return;
    setBusyId(id);
    await setFollowing(id, false); // failure reverts the row and sets s.followWriteError
    setBusyId(null);
    setConfirmId(null);
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Following">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="following-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0, display: 'flex', alignItems: 'center', gap: 10 }) }}>
          <RowIcon kind="heart" size={26} />{T('Đang theo dõi', 'Following')}
        </h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Danh sách này chỉ mình bạn thấy.', 'Only you can see this list.')}
        </p>
      </div>

      <div style={{ margin: '16px 22px 40px' }}>
        {s.followedError && s.followedStatus === 'error' && (
          <div role="alert" data-testid="following-error" style={{ ...fieldGlass({ padding: 16, borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 8 }) }}>
            <span style={{ fontSize: 13, color: alert }}>{s.followedError}</span>
            <span onClick={() => loadFollowedHosts()} data-testid="following-retry" role="button" style={{ fontSize: 13, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Thử lại', 'Retry')}</span>
          </div>
        )}
        {s.followWriteError && (
          <div role="alert" data-testid="following-write-error" style={{ fontSize: 12.5, color: alert, margin: '0 0 10px' }}>{s.followWriteError}</div>
        )}

        {loading && rows.length === 0 && (
          <div data-testid="following-loading" style={{ ...fieldGlass({ padding: 20, textAlign: 'center', borderRadius: 14 }), fontSize: 13, color: ink }}>{T('Đang tải…', 'Loading…')}</div>
        )}

        {!loading && s.followedStatus !== 'error' && rows.length === 0 && (
          <div data-testid="following-empty" style={{ ...fieldGlass({ padding: 22, textAlign: 'center', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 10, alignItems: 'center' }) }}>
            <span style={{ fontSize: 14, fontWeight: 600, color: ink }}>{T('Bạn chưa theo dõi tổ chức nào', "You're not following any hosts yet")}</span>
            <span style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, opacity: 0.75 }}>
              {T('Mở trang của một tổ chức và nhấn Theo dõi để thấy họ ở đây.', "Open a host's page and tap Follow to see them here.")}
            </span>
            <span onClick={goHome} data-testid="following-browse" role="button" style={{ fontSize: 13, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 18px', cursor: 'pointer' }}>{T('Khám phá sự kiện', 'Browse events')}</span>
          </div>
        )}

        {rows.length > 0 && (
          <>
            <div style={{ ...fieldGlass({ borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px' }) }}>
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={T('Tìm tổ chức bạn theo dõi…', 'Search hosts you follow…')}
                aria-label={T('Tìm tổ chức bạn theo dõi', 'Search hosts you follow')}
                data-testid="following-search"
                style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 13.5, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
              />
              {query && <span onClick={() => setQuery('')} role="button" aria-label={T('Xoá', 'Clear')} data-testid="following-search-clear" style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 16, lineHeight: 1 }}>×</span>}
            </div>
            <div style={{ fontSize: 11.5, color: ink, opacity: 0.65, margin: '10px 2px 8px' }} data-testid="following-count">
              {T(`${rows.length} tổ chức`, rows.length === 1 ? '1 host' : `${rows.length} hosts`)}
            </div>
            {shown.length === 0 ? (
              <div data-testid="following-no-match" style={{ ...fieldGlass({ padding: 18, textAlign: 'center', borderRadius: 14 }), fontSize: 13, color: ink }}>
                {T(`Không có tổ chức nào khớp "${query.trim()}".`, `No followed hosts match "${query.trim()}".`)}
              </div>
            ) : (
              <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
                {shown.map((h, i, arr) => {
                  const avatar = h.available ? organizerAvatarPublicUrl(h.avatarPath, h.avatarR2Ref, 'card') : '';
                  const monogram = (h.name || '?').trim()[0]?.toUpperCase() || '?';
                  return (
                    <div key={h.organizerId} data-testid={`following-row-${h.organizerId}`} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
                      <div
                        onClick={h.available ? () => openOrganizerProfile(h.organizerId, 'following') : undefined}
                        role={h.available ? 'link' : undefined}
                        tabIndex={h.available ? 0 : undefined}
                        onKeyDown={h.available ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openOrganizerProfile(h.organizerId, 'following'); } } : undefined}
                        aria-label={h.available ? T(`Mở trang của ${h.name}`, `Open ${h.name}'s page`) : undefined}
                        data-testid={`following-open-${h.organizerId}`}
                        style={{ display: 'flex', alignItems: 'center', gap: 12, flex: 1, minWidth: 0, cursor: h.available ? 'pointer' : 'default' }}
                      >
                        {avatar ? (
                          <img src={avatar} alt="" style={{ width: 44, height: 44, borderRadius: 11, objectFit: 'cover', flex: 'none' }} />
                        ) : (
                          <div aria-hidden="true" style={{ width: 44, height: 44, borderRadius: 11, flex: 'none', background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 17, fontWeight: 700 }}>{h.available ? monogram : '–'}</div>
                        )}
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                          <span style={{ fontSize: 14, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                            {h.available ? h.name : T('Tổ chức này không còn khả dụng', 'This host is no longer available')}{h.available && h.verified ? ' ✓' : ''}
                          </span>
                          <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.7 }}>✓ {T('Đang theo dõi', 'Following')}</span>
                        </div>
                      </div>
                      <span
                        onClick={busyId ? undefined : () => setConfirmId(h.organizerId)}
                        role="button"
                        aria-label={T(`Bỏ theo dõi ${h.name || ''}`, `Unfollow ${h.name || 'this host'}`)}
                        data-testid={`following-unfollow-${h.organizerId}`}
                        style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: ink, border: `1px solid ${rule}`, borderRadius: 999, padding: '8px 14px', minHeight: 20, cursor: busyId ? 'default' : 'pointer', opacity: busyId === h.organizerId ? 0.5 : 1 }}
                      >
                        {T('Bỏ theo dõi', 'Unfollow')}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>

      {confirmRow && (
        <div role="dialog" aria-modal="true" aria-label={T('Xác nhận bỏ theo dõi', 'Confirm unfollow')} data-testid="following-confirm"
          onClick={() => !busyId && setConfirmId(null)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 60, padding: 24 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: 16, padding: 22, maxWidth: 340, width: '100%', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <span style={{ ...display(18) }}>{T('Bỏ theo dõi?', 'Unfollow?')}</span>
            <span style={{ fontSize: 13, lineHeight: 1.5, color: ink }}>
              {confirmRow.available
                ? T(`Bạn sẽ không còn thấy ${confirmRow.name} trong danh sách theo dõi, và sẽ không thấy story của họ trên Trang chủ nữa.`, `${confirmRow.name} will leave your Following list and their stories will stop appearing on Home.`)
                : T('Tổ chức này sẽ được xoá khỏi danh sách theo dõi của bạn.', 'This host will be removed from your Following list.')}
            </span>
            <div style={{ display: 'flex', gap: 10 }}>
              <span onClick={() => !busyId && setConfirmId(null)} role="button" data-testid="following-confirm-cancel" style={{ flex: 1, textAlign: 'center', padding: '12px 0', borderRadius: 12, border: `1px solid ${rule}`, fontSize: 13.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</span>
              <span onClick={doUnfollow} role="button" data-testid="following-confirm-ok" style={{ flex: 1, textAlign: 'center', padding: '12px 0', borderRadius: 12, background: ink, fontSize: 13.5, fontWeight: 600, color: paper, cursor: busyId ? 'default' : 'pointer', opacity: busyId ? 0.6 : 1 }}>
                {busyId ? T('Đang xử lý…', 'Working…') : T('Bỏ theo dõi', 'Unfollow')}
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
