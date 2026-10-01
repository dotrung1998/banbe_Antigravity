// Real-backend integration check for the "published survey story invisible
// to a non-follower" report — same sanctioned pattern as
// tests/e2e/setup.mjs/dispute-flow-e2e.spec.js (service-role ONLY to seed
// throwaway rows + an anon-key client mirroring the real app's own auth
// path for every actual assertion). Run explicitly:
//   node tests/e2e/survey-story-visibility.integration.mjs
// Prints a plain pass/fail report, never raw secrets. Cleans up everything
// it creates, best-effort, even on failure.
import { hasServiceRole, adminClient, anonClient, createTestUser, signIn, cleanup } from './setup.mjs';

async function main() {
  if (!hasServiceRole()) {
    console.log('SKIP: no SUPABASE_SERVICE_ROLE_KEY/URL/ANON_KEY in env — cannot run.');
    process.exitCode = 1;
    return;
  }
  const admin = adminClient();
  const created = { userIds: [], organizerId: null };
  let surveyId = null;
  let storyId = null;
  const report = [];
  const check = (label, pass, detail) => {
    report.push(`[${pass ? 'PASS' : 'FAIL'}] ${label}${detail ? ' — ' + detail : ''}`);
  };

  try {
    // ---- Seed: a throwaway host (owns a throwaway organizer) and a
    // throwaway viewer who never follows that organizer. ----
    const host = await createTestUser(admin, 'survey-host');
    const viewer = await createTestUser(admin, 'survey-viewer');
    created.userIds.push(host.userId, viewer.userId);
    const organizerId = `e2e-survey-org-${Date.now().toString(36)}`;
    const { error: orgErr } = await admin.from('organizers').insert({
      id: organizerId, owner_id: host.userId, name: 'E2E Survey Host', verified: true,
    });
    if (orgErr) throw new Error('organizer seed failed: ' + orgErr.message);
    created.organizerId = organizerId;

    // ---- Step 1: sign in as HOST through the real anon-key path (mirrors
    // the app's own supabase client), then create+publish a survey and
    // share it to a story via the REAL RPCs the UI calls — never a raw
    // admin insert for these, so a schema/RPC drift would be caught here
    // exactly like it would in the app. ----
    const { client: hostClient } = await signIn(host.email, host.password);
    const now = new Date();
    const closes = new Date(now.getTime() + 7 * 86400000);
    const { data: created_survey, error: createErr } = await hostClient.rpc('create_survey', {
      p_organizer_id: organizerId, p_title: 'E2E visibility survey', p_description: 'test',
      p_opens_at: now.toISOString(), p_closes_at: closes.toISOString(), p_timezone: 'Asia/Ho_Chi_Minh',
      p_config: { date_options: [], location_options: [], budget_options: [], activity_options: [], group_size_min: 1, group_size_max: 10, required: {} },
    });
    check('create_survey RPC exists and succeeded', !createErr && !!created_survey, createErr?.message);
    if (createErr || !created_survey) throw new Error('cannot continue without a survey');
    surveyId = created_survey.id;

    const { data: published, error: pubErr } = await hostClient.rpc('publish_survey', { p_survey_id: surveyId });
    check('publish_survey succeeded, status=active', !pubErr && published?.status === 'active', pubErr?.message || `status=${published?.status}`);

    const { data: story, error: shareErr } = await hostClient.rpc('create_survey_share_story', { p_survey_id: surveyId });
    // A 42883 (function does not exist) or PGRST202 here means migration
    // 117 was never actually deployed — distinguished explicitly, not
    // assumed from the file existing in this repo.
    const migrationNotDeployed = shareErr && /does not exist|PGRST202|42883/i.test(shareErr.message + (shareErr.code || ''));
    check('migration 117 is deployed (create_survey_share_story exists)', !migrationNotDeployed, shareErr ? `${shareErr.code}: ${shareErr.message}` : 'ok');
    check('create_survey_share_story succeeded', !shareErr && !!story, shareErr?.message);
    if (shareErr || !story) throw new Error('cannot continue without a published story');
    storyId = story.id;
    check('story row has kind=survey_share, survey_id set, media_path empty', story.kind === 'survey_share' && story.survey_id === surveyId && story.media_path === '', JSON.stringify({ kind: story.kind, survey_id: story.survey_id, media_path: story.media_path }));

    // ---- Step 2: as the HOST's own session, confirm get_host's own survey
    // is still host-readable directly (sanity — not the bug under test). ----
    const { data: hostOwnSurveyRead } = await hostClient.from('surveys').select('id').eq('id', surveyId).maybeSingle();
    check('host can read own surveys row directly (sanity)', !!hostOwnSurveyRead);

    // ---- Step 3: sign in as VIEWER (a real session, never service-role),
    // who owns no organizer and never followed this one — exactly the
    // "non-owner, non-admin, non-follower" scenario the report describes.
    // Reproduce the EXACT client query loadHomeStories() issues. ----
    const { client: viewerClient } = await signIn(viewer.email, viewer.password);

    const { data: viewerSurveyRead, error: viewerSurveyErr } = await viewerClient
      .from('surveys').select('id').eq('id', surveyId).maybeSingle();
    check(
      'DIAGNOSIS: viewer can read the surveys row directly (expected: NO — surveys_select_host is host/admin-only)',
      !viewerSurveyRead,
      viewerSurveyErr ? viewerSurveyErr.message : JSON.stringify(viewerSurveyRead)
    );

    const { data: viewerStories, error: viewerStoriesErr } = await viewerClient
      .from('stories')
      .select('id, organizer_id, author_id, media_path, media_type, width, height, created_at, expires_at, kind, event_id, survey_id')
      .order('created_at', { ascending: true });
    if (viewerStoriesErr) {
      check('viewer stories query did not error', false, viewerStoriesErr.message);
    } else {
      const found = (viewerStories || []).find(r => r.id === storyId);
      check(
        'ROOT-CAUSE CHECK: viewer (non-owner/non-follower) sees the published survey_share story row via stories SELECT',
        !!found,
        found ? 'found' : `not found among ${viewerStories?.length ?? 0} visible rows`
      );
    }

    const { data: card, error: cardErr } = await viewerClient.rpc('get_survey_card', { p_survey_id: surveyId });
    check('viewer get_survey_card() succeeds with success:true', !cardErr && card?.success === true, cardErr?.message || JSON.stringify(card));
  } catch (e) {
    report.push(`[ERROR] unexpected failure: ${e.message || e}`);
  } finally {
    try {
      if (storyId) await adminClient().from('stories').delete().eq('id', storyId);
      if (surveyId) await adminClient().from('surveys').delete().eq('id', surveyId);
    } catch (e) { console.warn('extra cleanup failed (non-fatal):', e.message); }
    await cleanup(admin, created);
  }

  console.log('\n==== survey-story-visibility report ====');
  report.forEach(line => console.log(line));
  console.log('=========================================\n');
  process.exitCode = report.some(l => l.startsWith('[FAIL]') || l.startsWith('[ERROR]')) ? 1 : 0;
}

main();
