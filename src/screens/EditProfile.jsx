import { useRef } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, alert, inkButton } from '../theme.js';
import { PROFILE_PALETTES } from '../lib/profileTheme.js';

// TASK D (2026-10-01 UX foundation pass) — the owner's own editable public
// identity: avatar, handle, display name, bio, city, interests, palette.
// Reachable by tapping Account's own profile card (Account.jsx).

export default function EditProfile() {
  const { state, T, backFromEditProfile, set, saveProfileFields, uploadAvatar, removeAvatar, openPublicProfile } = useGoc();
  const s = state;
  const fileRef = useRef(null);

  const onPickAvatar = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    const url = await uploadAvatar(file);
    if (url) await saveProfileFields(url);
  };

  const canSave = s.editProfileHandle.trim().length >= 3 && s.editProfileName.trim().length > 0 && !s.editProfileBusy;
  const monogram = (s.editProfileName || s.user?.name || 'B').trim()[0]?.toUpperCase() || 'B';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Edit profile">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={backFromEditProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Tài khoản', '‹ Account')}</span>
        <span style={{ ...display(18) }}>{T('Chỉnh sửa hồ sơ', 'Edit profile')}</span>
        <span style={{ width: 50 }} />
      </div>

      <div style={{ padding: '22px 20px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
        <div style={{ position: 'relative', width: 84, height: 84 }}>
          {s.user?.avatarUrl ? (
            <img src={s.user.avatarUrl} alt="" style={{ width: 84, height: 84, borderRadius: '50%', objectFit: 'cover' }} />
          ) : (
            <div style={{ width: 84, height: 84, borderRadius: '50%', background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 30, fontWeight: 700 }}>
              {monogram}
            </div>
          )}
        </div>
        <div style={{ display: 'flex', gap: 14 }}>
          <span onClick={() => fileRef.current?.click()} style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }} data-testid="edit-profile-avatar-pick">
            {T('Đổi ảnh', 'Change photo')}
          </span>
          {s.user?.avatarUrl && (
            <span onClick={removeAvatar} style={{ fontSize: 12, color: alert, cursor: 'pointer' }} data-testid="edit-profile-avatar-remove">
              {T('Xoá ảnh', 'Remove photo')}
            </span>
          )}
        </div>
        <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onPickAvatar} data-testid="edit-profile-avatar-input" />
      </div>

      <div style={{ padding: '22px 20px 0', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Field label={T('Tên người dùng (handle)', 'Handle')} prefix="@" value={s.editProfileHandle}
          onChange={(v) => set({ editProfileHandle: v.toLowerCase().replace(/[^a-z0-9_]/g, '') })} testId="edit-profile-handle" />
        <Field label={T('Tên hiển thị', 'Display name')} value={s.editProfileName}
          onChange={(v) => set({ editProfileName: v })} testId="edit-profile-name" />
        <Field label={T('Giới thiệu ngắn', 'Short bio')} value={s.editProfileBio} multiline
          onChange={(v) => set({ editProfileBio: v.slice(0, 280) })} testId="edit-profile-bio" />
        <Field label={T('Khu vực (không bắt buộc)', 'City (optional)')} value={s.editProfileCity}
          onChange={(v) => set({ editProfileCity: v })} testId="edit-profile-city" />
        <Field label={T('Sở thích, cách nhau bởi dấu phẩy (không bắt buộc)', 'Interests, comma-separated (optional)')} value={s.editProfileInterests}
          onChange={(v) => set({ editProfileInterests: v })} testId="edit-profile-interests" />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Bảng màu hồ sơ', 'Profile palette')}</span>
          <div style={{ display: 'flex', gap: 10 }}>
            {PROFILE_PALETTES.map(p => (
              <div key={p.key} onClick={() => set({ editProfileTheme: p.key })} data-testid={`edit-profile-theme-${p.key}`}
                style={{
                  width: 34, height: 34, borderRadius: '50%', background: p.color, cursor: 'pointer',
                  border: s.editProfileTheme === p.key ? `2.5px solid ${ink}` : `1px solid ${rule}`,
                }} />
            ))}
          </div>
        </div>

        {s.editProfileError && <p style={{ fontSize: 12, color: alert, margin: 0 }}>{s.editProfileError}</p>}

        <div onClick={() => canSave && saveProfileFields()} data-testid="edit-profile-save"
          style={{ ...inkButton({ padding: '15px 0', opacity: canSave ? 1 : 0.5, cursor: canSave ? 'pointer' : 'default', marginTop: 4 }) }}>
          {s.editProfileBusy ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
        </div>

        {s.user?.handle && (
          <div onClick={() => openPublicProfile(s.user.handle, 'editProfile')} style={{ textAlign: 'center', fontSize: 12.5, color: ink, opacity: 0.75, cursor: 'pointer', padding: '10px 0 30px' }} data-testid="edit-profile-preview">
            {T('Xem hồ sơ công khai của bạn', 'View your public profile')}
          </div>
        )}
      </div>
    </div>
  );
}

function Field({ label, value, onChange, multiline, prefix, testId }) {
  const Comp = multiline ? 'textarea' : 'input';
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
      <span style={{ fontSize: 11.5, color: ink }}>{label}</span>
      <div style={{ ...fieldGlass({ display: 'flex', alignItems: multiline ? 'flex-start' : 'center', padding: '11px 12px' }) }}>
        {prefix && <span style={{ fontSize: 13, color: ink, opacity: 0.6, marginRight: 2 }}>{prefix}</span>}
        <Comp
          value={value}
          onChange={(e) => onChange(e.target.value)}
          rows={multiline ? 3 : undefined}
          data-testid={testId}
          style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 13, color: ink, fontFamily: 'inherit', resize: 'none' }}
        />
      </div>
    </label>
  );
}
