// Account deletion: remove media that belongs ONLY to the deleting user and is not part of anyone
// else's ticket / payment / dispute record. Runs BEFORE auth.admin.deleteUser (afterwards the
// owner link is nulled and we could no longer tell whose it was).
//
// Removed:  stories + organizer profile photo (legacy bucket and R2) of organizers this user alone
//           owns (no other owner, no accepted team member).
// RETAINED on purpose: event photos (events stay for ticket holders), pay-proof, payment-documents,
//           refund-proof/QR, chat and dispute attachments — financial / dispute records with their
//           own retention rules. Those are policy decisions, listed in note 28.
import { unpublishAsset } from './media.js';

async function soleOwnedOrganizerIds(admin, userId) {
  const { data: orgs, error } = await admin.from('organizers').select('id, owner_id, user_id').or(`owner_id.eq.${userId},user_id.eq.${userId}`);
  if (error) throw new Error(error.message);
  const candidates = (orgs || []).filter((o) => (!o.owner_id || o.owner_id === userId) && (!o.user_id || o.user_id === userId)).map((o) => o.id);
  if (!candidates.length) return [];
  const { data: members, error: mErr } = await admin.from('organizer_members').select('organizer_id, user_id, status').in('organizer_id', candidates).eq('status', 'accepted');
  if (mErr) throw new Error(mErr.message);
  const shared = new Set((members || []).filter((m) => m.user_id !== userId).map((m) => m.organizer_id));
  return candidates.filter((id) => !shared.has(id));
}

/** @param mediaCtx optional ctx from buildMediaCtx(); without it (or without R2 configured) R2 objects are only reported, not removed. */
export async function cleanupOwnedMedia(admin, userId, mediaCtx = null) {
  const out = { organizers: 0, stories: 0, organizerPhotos: 0, r2Assets: 0, r2Skipped: 0 };
  const orgIds = await soleOwnedOrganizerIds(admin, userId);
  out.organizers = orgIds.length;
  for (const orgId of orgIds) {
    const { data: stories, error: sErr } = await admin.from('stories').select('id, media_path').eq('organizer_id', orgId);
    if (sErr) throw new Error(sErr.message);
    const paths = (stories || []).map((s) => s.media_path).filter(Boolean);
    if (paths.length) { const { error } = await admin.storage.from('stories').remove(paths); if (error) throw new Error(error.message); }
    if (stories?.length) { const { error } = await admin.from('stories').delete().in('id', stories.map((s) => s.id)); if (error) throw new Error(error.message); }
    out.stories += stories?.length || 0;

    const { data: files } = await admin.storage.from('organizer-photos').list(orgId);
    if (files?.length) {
      const { error } = await admin.storage.from('organizer-photos').remove(files.map((f) => `${orgId}/${f.name}`));
      if (error) throw new Error(error.message);
      out.organizerPhotos += files.length;
    }
    await admin.from('organizers').update({ avatar_path: '' }).eq('id', orgId);   // never leave a dangling link
  }
  // R2 profile photos uploaded by this user for organizers they solely own
  if (orgIds.length) {
    const { data: assets } = await admin.from('media_assets').select('*').in('organizer_id', orgIds).eq('kind', 'organizer_avatar').neq('status', 'deleted');
    for (const a of assets || []) {
      if (mediaCtx?.r2?.configured) { await unpublishAsset(mediaCtx, a, { demote: false }); out.r2Assets++; }
      else out.r2Skipped++;
    }
  }
  return out;
}
