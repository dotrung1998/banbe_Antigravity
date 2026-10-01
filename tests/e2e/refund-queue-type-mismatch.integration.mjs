// Real-backend check for "Could not load the refund queue" — same
// sanctioned pattern as tests/e2e/setup.mjs (service-role ONLY to seed a
// throwaway host/organizer/event/booking/refund claim, an anon-key client
// mirroring the real app's own auth path for the actual RPC call). Run:
//   node tests/e2e/refund-queue-type-mismatch.integration.mjs
import { hasServiceRole, adminClient, signIn, createTestUser, cleanup } from './setup.mjs';

async function main() {
  if (!hasServiceRole()) {
    console.log('SKIP: no SUPABASE_SERVICE_ROLE_KEY/URL/ANON_KEY in env — cannot run.');
    process.exitCode = 1;
    return;
  }
  const admin = adminClient();
  const created = { userIds: [] };
  const report = [];
  const check = (label, pass, detail) => report.push(`[${pass ? 'PASS' : 'FAIL'}] ${label}${detail ? ' — ' + detail : ''}`);

  let organizerId = null;
  let eventId = null;
  let bookingId = null;
  let claimId = null;

  try {
    const host = await createTestUser(admin, 'refund-rpc-host');
    created.userIds.push(host.userId);
    organizerId = `e2e-refundrpc-org-${Date.now().toString(36)}`;
    const { error: orgErr } = await admin.from('organizers').insert({ id: organizerId, owner_id: host.userId, name: 'E2E Refund RPC Host', verified: true });
    if (orgErr) throw new Error('organizer seed failed: ' + orgErr.message);

    eventId = `e2e-refundrpc-event-${Date.now().toString(36)}`;
    const { error: evErr } = await admin.from('events').insert({
      id: eventId, key: eventId, slug: eventId, organizer_id: organizerId,
      name: 'E2E refund RPC test event', price_vnd: 100000, capacity: 5, seats_remaining: 5,
      hold_minutes: 30, status: 'live', approval: 'instant', visibility: 'public',
    });
    if (evErr) throw new Error('event seed failed: ' + evErr.message);

    const { data: bookingRow, error: bookErr } = await admin.from('bookings').insert({
      event_id: eventId, user_id: host.userId, qty: 1, status: 'cancelled',
      total_vnd: 100000, payment_state: 'confirmed',
    }).select('id').single();
    if (bookErr) throw new Error('booking seed failed: ' + bookErr.message);
    bookingId = bookingRow.id;

    const { data: claimRow, error: claimErr } = await admin.from('refund_claims').insert({
      booking_id: bookingId, reservation_id: bookingId, amount_vnd: 100000, reason: 'guest_cancelled', status: 'owed',
    }).select('id').single();
    if (claimErr) throw new Error('refund_claims seed failed: ' + claimErr.message);
    claimId = claimRow.id;

    const { client: hostClient } = await signIn(host.email, host.password);

    // ---- The EXACT call loadRefundQueue() makes (account-wide, p_event_id: null) ----
    const { data: nullResult, error: nullErr } = await hostClient.rpc('get_host_refund_claims', { p_event_id: null });
    check(
      'get_host_refund_claims(p_event_id: null) succeeds (loadRefundQueue path)',
      !nullErr && nullResult?.success === true,
      nullErr ? `code=${nullErr.code} message=${nullErr.message} details=${nullErr.details || ''} hint=${nullErr.hint || ''}` : JSON.stringify(nullResult).slice(0, 200)
    );
    if (nullErr) {
      const isTypeMismatch = /operator does not exist.*text.*uuid|text = uuid|uuid = text/i.test(nullErr.message || '');
      check('HYPOTHESIS CONFIRMED: failure is the text/uuid operator mismatch (e.id = p_event_id)', isTypeMismatch, nullErr.message);
    }

    // ---- The EXACT call loadRefundCenter() makes (per-event, p_event_id: <text event id>) ----
    const { data: evResult, error: evRpcErr } = await hostClient.rpc('get_host_refund_claims', { p_event_id: eventId });
    check(
      'get_host_refund_claims(p_event_id: <text event id>) succeeds (loadRefundCenter path)',
      !evRpcErr && evResult?.success === true,
      evRpcErr ? `code=${evRpcErr.code} message=${evRpcErr.message}` : JSON.stringify(evResult).slice(0, 200)
    );
    if (!nullErr && nullResult?.success) {
      const found = (nullResult.claims || []).find(c => c.id === claimId);
      check('self-booking claim (guest == host) is returned, not silently excluded', !!found, found ? 'found' : `claims=${JSON.stringify(nullResult.claims)}`);
    }
  } catch (e) {
    report.push(`[ERROR] unexpected failure: ${e.message || e}`);
  } finally {
    try {
      if (claimId) await adminClient().from('refund_claims').delete().eq('id', claimId);
      if (bookingId) await adminClient().from('bookings').delete().eq('id', bookingId);
      if (eventId) await adminClient().from('events').delete().eq('id', eventId);
      if (organizerId) await adminClient().from('organizers').delete().eq('id', organizerId);
    } catch (e) { console.warn('extra cleanup failed (non-fatal):', e.message); }
    await cleanup(admin, created);
  }

  console.log('\n==== refund-queue-type-mismatch report ====');
  report.forEach(line => console.log(line));
  console.log('============================================\n');
  process.exitCode = report.some(l => l.startsWith('[FAIL]') || l.startsWith('[ERROR]')) ? 1 : 0;
}

main();
