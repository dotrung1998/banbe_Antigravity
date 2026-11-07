// Admin "Project hub demo" (note 76, migration 216, switch project_hub_demo). An admin opens the Event Project Hub on
// the built-in sample data (tests/fixtures/project-snapshot.json, the same synthetic evening the tests and iOS use) to
// show it to colleagues. Pure helpers only; the state lives in BanBeContext (openProjectDemo / exitProjectDemo) and
// useEventProject keeps every read and write on the device while `projectDemo` is true.
// iOS twin: the project demo in apps/ios (same fixture, same roles and clock).
import { flagOn } from './featureFlags.js';

/** "View as" choices, in picker order. */
export const DEMO_ROLES = ['host', 'manager', 'finance', 'lane_lead', 'helper'];

/** The viewer's id inside the fixture (the Host) and the member each role is re-cast from. */
export const DEMO_FIXTURE_HOST_ID = '00000000-0000-4000-8000-00000000f1f0';
const DEMO_STAND_IN_HOST_ID = '00000000-0000-4000-8000-0000000001ff';
const DEMO_MEMBER_IDS = {
  manager: '00000000-0000-4000-8000-000000000102',
  lane_lead: '00000000-0000-4000-8000-000000000103',
  helper: '00000000-0000-4000-8000-000000000104',
  finance: '00000000-0000-4000-8000-000000000106',
};

/** Inside the demo only, every project switch counts as on (they stay off for everyone else). */
export const DEMO_PROJECT_FLAGS = Object.freeze({
  event_project_hub: true, project_qr_invite: true, project_delegate_checkin: true, project_delegate_payments: true, project_delegate_refunds: true,
});

/** The demo clock: 11 days before the sample event, or 18:10 on the event day (Day-of live mode and the now line). */
export const DEMO_CLOCK = Object.freeze({ before: '2026-11-03T10:00:00+07:00', eventDay: '2026-11-14T18:10:00+07:00' });

/** Who sees the entry: admins, and only while the switch is on. Missing switch = off. */
export function projectDemoAllowed({ accountType, featureFlags } = {}) {
  return accountType === 'admin' && flagOn(featureFlags || {}, 'project_hub_demo');
}

/**
 * The fixture snapshot as `as` sees it, with the signed-in admin standing in for that person (so "You", permissions and
 * "waiting on you" read right). The Host view keeps the fixture as is; a member view re-casts the Host to a stand-in.
 */
export function buildDemoSnapshot(fixture, { as = 'host', userId } = {}) {
  const me = String(userId || DEMO_FIXTURE_HOST_ID).toLowerCase();
  const role = DEMO_ROLES.includes(as) ? as : 'host';
  let text = JSON.stringify(fixture);
  if (role !== 'host') {
    text = text.split(DEMO_FIXTURE_HOST_ID).join(DEMO_STAND_IN_HOST_ID).replace('"display_name":"Bạn"', '"display_name":"Lan"');
    text = text.split(DEMO_MEMBER_IDS[role]).join(DEMO_FIXTURE_HOST_ID);
  }
  const snap = JSON.parse(text.split(DEMO_FIXTURE_HOST_ID).join(me));
  if (role === 'host') return { ...snap, is_host: true, me: null };
  const mine = snap.members.find(m => String(m.user_id).toLowerCase() === me);
  return { ...snap, is_host: false, me: { member_id: mine.member_id, role: mine.role, lane_id: mine.lane_id, cap_money: mine.cap_money,
    cap_checkin: mine.cap_checkin, grant_expires_at: '2026-11-21T17:00:00+00:00' } };
}

/** Every state key the demo writes, back to its resting value. Used by Exit, by leaving the hub and by sign-out. */
export const PROJECT_DEMO_RESET = Object.freeze({
  projectDemo: false, projectDemoAdmin: false, projectDemoAs: 'host', projectNow: null,
  projectDemoTrash: [], projectDemoReplies: {}, projectDemoInvites: 0,
  projectSnapshot: null, projectEventId: '', projectTab: 'overview', projectNotice: '', projectError: '', projectBusy: false, projectLoading: false,
  projectDayView: 'list', projectInvites: [], projectMoney: null, projectDoor: null, projectPayments: null, projectRefunds: null, projectRosVersion: null,
  projectPostsExhausted: false,
});

/** The state patch that opens the demo hub. */
export function projectDemoState(fixture, { as = 'host', eventDay = false, userId } = {}) {
  const snapshot = buildDemoSnapshot(fixture, { as, userId });
  return {
    ...PROJECT_DEMO_RESET,
    projectDemo: true, projectDemoAdmin: true, projectDemoAs: DEMO_ROLES.includes(as) ? as : 'host',
    projectNow: eventDay ? DEMO_CLOCK.eventDay : DEMO_CLOCK.before,
    projectSnapshot: snapshot, projectEventId: snapshot.event?.id || 'fx_project', projectTab: eventDay ? 'dayof' : 'overview',
    projectBack: 'accountGroup', screen: 'eventProject',
  };
}
