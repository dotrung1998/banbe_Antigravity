// Event Project Hub permissions (note 76): who may do what in an event's private team project.
// iOS twin: apps/ios/BanbeApp/Lib/ProjectPermissions.swift. Shared vectors: tests/fixtures/project-permissions.json,
// run under BOTH Host definitions (see below). The server enforces the same rules (migrations 210-214); this copy only
// decides what the UI offers.
//
// Two different "host" checks, on purpose:
// - projectIsHost: the Host of the PROJECT. v1 = either organizer account (owner_id or user_id), exactly like
//   is_event_host() today. Mirrors the server helper project_is_host(), the one place to change if the Host ever
//   becomes owner_id only (hostDef 'owner_only').
// - organizerAccount: the check the EXISTING money and door RPCs already make (confirm_payment, check_in_guest,
//   mark_refund_sent: owner_id or user_id). Delegation only ever ADDS people on top of it, so changing the project
//   Host can never take money or door rights away from anyone who has them today. Event cancellation and the payout
//   account are not project actions at all and are not modelled here.
//
// Roles stored on a member: manager ("Quản lý"), finance, lane_lead, helper. The Host is never a stored role.
import LIMITS from '../data/projectLimits.json' with { type: 'json' };
import { flagOn } from './featureFlags.js';

export const PROJECT_LIMITS = LIMITS;
export const PROJECT_ROLES = ['manager', 'finance', 'lane_lead', 'helper'];
/** Which roles each inviter may preset on an invite. */
export const INVITABLE_ROLES = { host: ['manager', 'finance', 'lane_lead', 'helper'], manager: ['lane_lead', 'helper'] };

/** Every action this module answers; anything else is refused. */
export const PROJECT_ACTIONS = [
  'project.read', 'project.start', 'channels.open',
  'task.status', 'task.manage',
  'post.question', 'post.update', 'post.vote', 'post.seen', 'post.reply', 'post.proposal', 'post.decision',
  'post.resolve', 'post.edit', 'post.delete',
  'invite.create', 'invite.revoke', 'member.manage',
  'lane.manage', 'channels.edit', 'change.propose', 'change.review',
  'ros.edit', 'ros.tick', 'trash.restore', 'trash.purge',
  'refund.approval.set', 'grants.extend',
  'checkin', 'money.view', 'money.confirm', 'money.reject', 'proof.open',
  'refund.request', 'refund.markSent', 'refund.approve',
];

const HOST_ONLY_WRITES = new Set(['member.manage', 'lane.manage', 'channels.edit', 'change.review', 'refund.approval.set', 'grants.extend', 'trash.purge']);
const ANY_MEMBER_WRITES = new Set(['post.question', 'post.update', 'post.vote', 'post.seen', 'post.reply', 'ros.tick']);

const ms = v => (v === null || v === undefined ? null : typeof v === 'number' ? v : Date.parse(v));

/** The existing RPCs' own check: either organizer account. */
export function organizerAccount(userId, organizer) {
  return !!userId && !!organizer && (userId === organizer.ownerId || userId === organizer.userId);
}

/** project_is_host(): v1 'either' (both organizer accounts); 'owner_only' is the one-line alternative. */
export function projectIsHost(userId, organizer, hostDef = 'either') {
  if (!userId || !organizer) return false;
  return hostDef === 'owner_only' ? userId === organizer.ownerId : organizerAccount(userId, organizer);
}

/** Finance always holds both capabilities; anyone else holds what the Host granted. */
export function memberCaps(member) {
  if (!member) return { money: false, checkin: false };
  if (member.role === 'finance') return { money: true, checkin: true };
  return { money: member.caps?.money === true, checkin: member.caps?.checkin === true };
}

/**
 * ctx: {
 *   actor: { userId, member?: { role, laneId, caps: { money, checkin }, status, grantExpiresAt } },
 *   organizer: { ownerId, userId }, hostDef: 'either' | 'owner_only', flags, now,
 *   project: { readOnlyAt, refundApproval: 'host' | 'finance_alone' },
 *   target: { laneId, assigneeId, authorId, addresseeId, createdBy, type, state, quiet, role, awaitingVerification, refundClaimId },
 *   disputeGrants: [{ userId, refundClaimId, until, disputeOpen }]
 * }
 */
export function canProject(action, ctx = {}) {
  const { actor = {}, organizer = null, hostDef = 'either', flags = {}, target = {}, project = {}, disputeGrants = [] } = ctx;
  const now = ms(ctx.now) ?? Date.now();
  const uid = actor.userId ?? null;
  const host = projectIsHost(uid, organizer, hostDef);
  const org = organizerAccount(uid, organizer);
  const m = actor.member && actor.member.status === 'active' ? actor.member : null;
  const role = m?.role ?? null;
  const hub = flagOn(flags, 'event_project_hub');
  const readOnly = project.readOnlyAt != null && now >= ms(project.readOnlyAt);
  const inProject = hub && (host || !!m);
  const write = inProject && !readOnly;
  const manager = role === 'manager';
  const leadOk = role === 'lane_lead' && (target.laneId == null || m.laneId === target.laneId);
  const mine = id => !!uid && id === uid;
  const caps = memberCaps(m);
  const grantLive = !!m && (m.grantExpiresAt == null || now < ms(m.grantExpiresAt)) && !readOnly;
  const delegate = (flag, cap) => hub && flagOn(flags, flag) && grantLive && caps[cap];
  const disputeOk = hub && flagOn(flags, 'project_delegate_refunds') && target.refundClaimId != null &&
    (disputeGrants || []).some(g => g.userId === uid && g.refundClaimId === target.refundClaimId && g.disputeOpen === true && now < ms(g.until));

  if (HOST_ONLY_WRITES.has(action)) return write && host;
  if (ANY_MEMBER_WRITES.has(action)) return write;
  switch (action) {
    case 'project.read':
    case 'channels.open':
      return inProject;
    case 'project.start':
      return hub && host && !readOnly;
    case 'task.status':
      return write && (host || manager || leadOk || mine(target.assigneeId));
    case 'task.manage':
      return write && (host || manager || leadOk);
    case 'post.proposal':
      return write && (host || manager || role === 'finance' || role === 'lane_lead');
    case 'post.decision':
      return write && (host || manager || leadOk);
    case 'post.resolve':
      return write && target.state === 'open' && target.type !== 'update' &&
        (host || manager || leadOk || mine(target.authorId) || mine(target.addresseeId));
    case 'post.edit':
      return write && mine(target.authorId) && target.state === 'open' && target.type !== 'decision' && target.quiet === true;
    case 'post.delete':
      return write && (host || manager || (mine(target.authorId) && target.state === 'open' && target.quiet === true));
    case 'invite.create':
      return write && ((host && INVITABLE_ROLES.host.includes(target.role)) || (manager && INVITABLE_ROLES.manager.includes(target.role)));
    case 'invite.revoke':
      return write && (host || (manager && mine(target.createdBy)));
    case 'change.propose':
      return write && manager;
    case 'ros.edit':
    case 'trash.restore':
      return write && (host || manager);
    // Money and door: the existing check, plus delegation behind its own switch (migrations 212-214).
    case 'checkin':
      return org || delegate('project_delegate_checkin', 'checkin');
    case 'money.view':
    case 'money.confirm':
      return org || delegate('project_delegate_payments', 'money');
    case 'proof.open':
      return org || (delegate('project_delegate_payments', 'money') && target.awaitingVerification === true);
    case 'money.reject':
      return org; // reject_pending_guest cancels a seat: not delegated
    case 'refund.request':
      return !org && (delegate('project_delegate_refunds', 'money') || disputeOk);
    case 'refund.markSent':
      return org || (project.refundApproval === 'finance_alone' && (delegate('project_delegate_refunds', 'money') || disputeOk));
    case 'refund.approve':
      return org;
    default:
      return false;
  }
}
