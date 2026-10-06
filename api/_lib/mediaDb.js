// Service-role data access for api/media. Everything here BYPASSES RLS, so the
// authorization decisions live in media.js, never here.
export function makeMediaDb(admin) {
  const one = async (q) => { const { data, error } = await q; if (error) throw new Error(error.message); return data; };
  const count = async (q) => { const { count: n, error } = await q; if (error) throw new Error(error.message); return n || 0; };
  const A = () => admin.from('media_assets');
  return {
    async getEvent(id) { return one(admin.from('events').select('id, status, visibility, organizer_id, cover_image').eq('id', id).maybeSingle()); },
    async getOrganizer(id) { return one(admin.from('organizers').select('id, owner_id, user_id').eq('id', id).maybeSingle()); },
    async isAdmin(userId) { const p = await one(admin.from('profiles').select('role').eq('id', userId).maybeSingle()); return p?.role === 'admin'; },

    countRecentAssets: (userId, sinceIso) => count(A().select('id', { count: 'exact', head: true }).eq('owner_user_id', userId).gte('created_at', sinceIso)),
    countPendingAssets: (userId) => count(A().select('id', { count: 'exact', head: true }).eq('owner_user_id', userId).eq('status', 'pending')),
    findAssetByIdem: (userId, key) => one(A().select('*').eq('owner_user_id', userId).eq('idempotency_key', key).maybeSingle()),
    getAsset: (id) => one(A().select('*').eq('id', id).maybeSingle()),
    async getAssetByRef(ref) {
      const m = /^r2:([A-Za-z0-9_-]+)\/([0-9a-f-]{36})\.(jpg|png|webp)$/.exec(ref || '');
      return m ? one(A().select('*').eq('id', m[2]).eq('scope', m[1]).maybeSingle()) : null;
    },
    insertAsset: (row) => one(A().insert(row).select('*').single()),
    async updateAsset(id, patch) { await one(A().update(patch).eq('id', id)); },

    findEventPhotoByRef: (ref) => one(admin.from('event_photos').select('id').eq('r2_ref', ref).maybeSingle()),
    async insertEventPhoto(row) { await one(admin.from('event_photos').insert(row)); },
    async setEventCoverRef(eventId, ref) { await one(admin.from('events').update({ cover_r2_ref: ref }).eq('id', eventId)); },
    async getOrganizerAvatarRef(orgId) { return (await one(admin.from('organizers').select('avatar_r2_ref').eq('id', orgId).maybeSingle()))?.avatar_r2_ref || null; },
    async setOrganizerAvatarRef(orgId, ref) { await one(admin.from('organizers').update({ avatar_r2_ref: ref }).eq('id', orgId)); },

    listEventPhotosByRef: async (ref) => (await one(admin.from('event_photos').select('id, storage_path').eq('r2_ref', ref))) || [],
    // storagePath === null: drop only the R2 pointer (a legacy copy remains); otherwise repoint the row at a private path.
    async clearEventPhotoRef(rowId, storagePath) {
      await one(admin.from('event_photos').update(storagePath ? { r2_ref: null, storage_path: storagePath } : { r2_ref: null }).eq('id', rowId));
    },
    async clearRefs(kind, ref) {
      if (kind === 'organizer_avatar') await one(admin.from('organizers').update({ avatar_r2_ref: null }).eq('avatar_r2_ref', ref));
      else await one(admin.from('event_photos').delete().eq('r2_ref', ref).eq('storage_path', ref));        // R2-only row: nothing left to show
      if (kind !== 'organizer_avatar') await one(admin.from('event_photos').update({ r2_ref: null }).eq('r2_ref', ref));
    },
    async clearCoverRef(eventId, ref) { if (eventId) await one(admin.from('events').update({ cover_r2_ref: null }).eq('id', eventId).eq('cover_r2_ref', ref)); },
    async replaceCoverPath(eventId, fromRef, toPath) { if (eventId) await one(admin.from('events').update({ cover_image: toPath }).eq('id', eventId).eq('cover_image', fromRef)); },
    async uploadPrivateEventPhoto(path, bytes, contentType) {
      const { error } = await admin.storage.from('event-photos-private').upload(path, bytes, { contentType, upsert: false });
      if (error && !/exists|Duplicate/i.test(error.message)) throw new Error(error.message);
    },

    // legacy invite-only photo demotion (Supabase Storage only)
    async listLegacyPublicPhotosOfInviteEvents(eventId) {
      let q = admin.from('event_photos').select('id, event_id, storage_path, events!inner(visibility)')
        .eq('events.visibility', 'invite').like('storage_path', 'event-photos/%').limit(200);
      if (eventId) q = q.eq('event_id', eventId);
      return (await one(q)) || [];
    },
    async downloadLegacyEventPhoto(rel) {
      const { data, error } = await admin.storage.from('event-photos').download(rel);
      if (error || !data) return null;
      return Buffer.from(await data.arrayBuffer());
    },
    async repointEventPhoto(rowId, storagePath) { await one(admin.from('event_photos').update({ storage_path: storagePath }).eq('id', rowId)); },
    async removeLegacyEventPhotos(rels) { const { error } = await admin.storage.from('event-photos').remove(rels); if (error) throw new Error(error.message); },
    // expired stories
    listExpiredStories: async (limit) => (await one(admin.from('stories').select('id, media_path').lte('expires_at', new Date().toISOString()).limit(limit))) || [],
    async removeStoryObjects(paths) { const { error } = await admin.storage.from('stories').remove(paths); if (error) throw new Error(error.message); },
    async deleteStories(ids) { await one(admin.from('stories').delete().in('id', ids)); },

    listStalePending: async (beforeIso) => (await one(A().select('*').eq('status', 'pending').lt('created_at', beforeIso).limit(200))) || [],
    listPublishedEventAssets: async () => (await one(A().select('*').eq('status', 'published').eq('kind', 'event_photo').limit(1000))) || [],
    listPublishedEventAssetsForEvent: async (eventId) => (await one(A().select('*').eq('status', 'published').eq('kind', 'event_photo').eq('event_id', eventId))) || [],
    async listOrphanedPublishedAssets() {
      const assets = (await one(A().select('*').eq('status', 'published').is('deleted_at', null).limit(500))) || [];
      const refOf = (a) => `r2:${a.scope}/${a.id}.${a.ext}`;
      const orphans = [];
      const avatars = assets.filter((a) => a.kind === 'organizer_avatar');
      if (avatars.length) {
        const orgs = (await one(admin.from('organizers').select('id, avatar_r2_ref').in('id', [...new Set(avatars.map((a) => a.organizer_id))]))) || [];
        const cur = new Map(orgs.map((o) => [o.id, o.avatar_r2_ref]));
        for (const a of avatars) if (cur.get(a.organizer_id) !== refOf(a)) orphans.push(a);
      }
      const photos = assets.filter((a) => a.kind === 'event_photo');
      if (photos.length) {
        const rows = (await one(admin.from('event_photos').select('r2_ref').in('r2_ref', photos.map(refOf)))) || [];
        const live = new Set(rows.map((r) => r.r2_ref));
        for (const a of photos) if (!live.has(refOf(a))) orphans.push(a);
      }
      return orphans;
    },
    listDeletionIntents: async () => (await one(A().select('*').not('deleted_at', 'is', null).neq('status', 'deleted').limit(200))) || [],
  };
}
