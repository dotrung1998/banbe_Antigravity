-- Migration: payment details, invoices, receipts and proof of payment.
--
-- banbe never touches the money — a guest transfers directly to the
-- organizer. What was missing was everything *around* that transfer: the
-- guest had no screen telling them where to send it, and neither side ended
-- up holding a document afterwards. This adds the paperwork, not a payment
-- processor.
--
-- Most of the rails already existed and were simply unused:
--   organizers.bank_name / bank_account_name / bank_account_no /
--   momo_phone / pay_qr_path / pay_note / pay_methods   (001)
--   bookings.total_vnd / code / paid_marked_at / paid_method (002)
--   confirm_payment()                                    (011)
--   the private `pay-qr` bucket, already readable by a confirmed booker (005)
-- so this migration only adds what genuinely has no home yet.
--
-- IMPORTANT, and deliberate: what this issues is a commercial payment
-- document, NOT a Vietnamese VAT e-invoice. A legally valid hoá đơn điện tử
-- under Nghị định 123/2020/NĐ-CP and Thông tư 78/2021/TT-BTC has to be
-- issued through a tax-authority-registered provider and carries a mã của
-- cơ quan thuế, which no application can mint for itself. Every rendered
-- document therefore says so in as many words. The layout still follows the
-- shape a Vietnamese recipient expects (bên bán / bên mua, MST, số chứng
-- từ, bảng đơn giá, số tiền bằng chữ) so it is usable as an internal record
-- and for reimbursement.

-- ---------------------------------------------------------------------------
-- 1. Buyer identity. A document needs an address; profiles had none.
--    Kept separate from display_name/phone because the name on a receipt is
--    frequently a company, not the person whose account it is.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS billing_name text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS billing_address text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS billing_phone text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS billing_tax_code text NOT NULL DEFAULT '';

-- ---------------------------------------------------------------------------
-- 2. Seller identity. The bank columns were already here; the parts a
--    Vietnamese document header needs (registered address, MST) were not.
-- ---------------------------------------------------------------------------
ALTER TABLE public.organizers
  ADD COLUMN IF NOT EXISTS billing_address text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS tax_code text NOT NULL DEFAULT '';

-- ---------------------------------------------------------------------------
-- 3. Proof of payment on the booking itself. One transfer, one booking, so
--    a column beats a side table here. The file lives in the private
--    `pay-proof` bucket created below; only the path is stored.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS proof_path text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS proof_note text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS proof_uploaded_at timestamptz;

-- ---------------------------------------------------------------------------
-- 4. The documents themselves.
--
--    Every party/amount is frozen into jsonb at issue time instead of being
--    joined at read time. This is the whole point of a document: an
--    organizer renaming themselves, editing a price, or correcting their
--    bank details next month must not silently rewrite a receipt somebody
--    already downloaded. Joins would do exactly that.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_doc_kind') THEN
    CREATE TYPE payment_doc_kind AS ENUM ('invoice', 'receipt');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.payment_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  event_id text REFERENCES public.events(id) ON DELETE SET NULL,
  organizer_id text REFERENCES public.organizers(id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  kind payment_doc_kind NOT NULL,
  number text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  seller jsonb NOT NULL DEFAULT '{}'::jsonb,
  buyer jsonb NOT NULL DEFAULT '{}'::jsonb,
  event jsonb NOT NULL DEFAULT '{}'::jsonb,
  lines jsonb NOT NULL DEFAULT '[]'::jsonb,
  total_vnd int NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'VND',
  pay_method text NOT NULL DEFAULT '',
  paid_at timestamptz,
  note text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One invoice and one receipt per booking. Re-issuing is a no-op, which is
-- what makes ensure_payment_document() below safe to call from anywhere.
CREATE UNIQUE INDEX IF NOT EXISTS payment_documents_booking_kind_idx
  ON public.payment_documents (booking_id, kind);
CREATE UNIQUE INDEX IF NOT EXISTS payment_documents_number_idx
  ON public.payment_documents (number);
CREATE INDEX IF NOT EXISTS payment_documents_user_idx
  ON public.payment_documents (user_id, issued_at DESC);
CREATE INDEX IF NOT EXISTS payment_documents_organizer_idx
  ON public.payment_documents (organizer_id, issued_at DESC);

-- ---------------------------------------------------------------------------
-- 5. Number series. Vietnamese practice is a gapless sequential series per
--    issuer per year, per document type — not a random id. A plain sequence
--    would leak gaps on rollback and would be shared across organizers, so
--    this is a counter row bumped inside the issuing transaction.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_document_counters (
  organizer_id text NOT NULL REFERENCES public.organizers(id) ON DELETE CASCADE,
  kind payment_doc_kind NOT NULL,
  year int NOT NULL,
  next_number int NOT NULL DEFAULT 1,
  PRIMARY KEY (organizer_id, kind, year)
);

ALTER TABLE public.payment_document_counters ENABLE ROW LEVEL SECURITY;
-- No policy at all: only the SECURITY DEFINER function below ever touches it.

-- ---------------------------------------------------------------------------
-- 6. RLS. Guests read their own documents, organizers read documents for
--    bookings on their own events. Nobody writes directly — issuing goes
--    through ensure_payment_document(), so a client can neither forge a
--    number nor edit an amount after the fact.
-- ---------------------------------------------------------------------------
ALTER TABLE public.payment_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_documents_select_guest" ON public.payment_documents;
CREATE POLICY "payment_documents_select_guest" ON public.payment_documents
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "payment_documents_select_host" ON public.payment_documents;
CREATE POLICY "payment_documents_select_host" ON public.payment_documents
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.organizers o
      WHERE o.id = payment_documents.organizer_id
        AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- 7. save_billing_details() — the buyer's own block on every future document.
--    Deliberately does not touch display_name: what you are called in the
--    app and what goes on a receipt are different things.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_billing_details(
  p_name text, p_address text, p_phone text DEFAULT '', p_tax_code text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  UPDATE profiles SET
    billing_name     = left(trim(COALESCE(p_name, '')), 160),
    billing_address  = left(trim(COALESCE(p_address, '')), 400),
    billing_phone    = left(trim(COALESCE(p_phone, '')), 40),
    billing_tax_code = left(trim(COALESCE(p_tax_code, '')), 30)
  WHERE id = auth.uid();

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.save_billing_details(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_billing_details(text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. save_organizer_payment() — where guests are told to send the money.
--    Only an owner of that organizer may call it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_organizer_payment(
  p_organizer text,
  p_bank_name text DEFAULT '', p_bank_account_name text DEFAULT '', p_bank_account_no text DEFAULT '',
  p_momo_phone text DEFAULT '', p_pay_note text DEFAULT '',
  p_billing_address text DEFAULT '', p_tax_code text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_methods text[] := '{}';
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM organizers o
    WHERE o.id = p_organizer AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  -- pay_methods is what the guest-facing screen switches on, so it is
  -- derived from what was actually filled in rather than trusted from the
  -- client — an empty bank number can't advertise bank transfer.
  IF trim(COALESCE(p_bank_account_no, '')) <> '' THEN v_methods := array_append(v_methods, 'bank'); END IF;
  IF trim(COALESCE(p_momo_phone, '')) <> '' THEN v_methods := array_append(v_methods, 'momo'); END IF;

  UPDATE organizers SET
    bank_name         = left(trim(COALESCE(p_bank_name, '')), 120),
    bank_account_name = left(trim(COALESCE(p_bank_account_name, '')), 160),
    bank_account_no   = left(trim(COALESCE(p_bank_account_no, '')), 40),
    momo_phone        = left(trim(COALESCE(p_momo_phone, '')), 40),
    pay_note          = left(trim(COALESCE(p_pay_note, '')), 400),
    billing_address   = left(trim(COALESCE(p_billing_address, '')), 400),
    tax_code          = left(trim(COALESCE(p_tax_code, '')), 30),
    pay_methods       = v_methods
  WHERE id = p_organizer;

  RETURN jsonb_build_object('success', true, 'pay_methods', to_jsonb(v_methods));
END;
$$;
REVOKE EXECUTE ON FUNCTION public.save_organizer_payment(text, text, text, text, text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_organizer_payment(text, text, text, text, text, text, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. ensure_payment_document() — issue once, then always return the same row.
--
--    Idempotent on purpose. It is called from three places that can't
--    coordinate: confirm_payment() below, the guest opening their documents
--    list, and the organizer opening theirs. Whoever gets there first mints
--    the number; everyone after that reads it back unchanged.
--
--    'invoice'  = what is owed, issued as soon as anyone asks for it.
--    'receipt'  = proof it was paid, only issuable once the booking is
--                 actually marked paid — a receipt for money that never
--                 arrived is the one thing this must never produce.
-- ---------------------------------------------------------------------------
-- The party blocks, factored out so the "issue it" path and the "refresh an
-- unpaid invoice" path below cannot drift apart. IMMUTABLE-free on purpose:
-- they only reshape the row handed to them.
CREATE OR REPLACE FUNCTION public.build_document_seller(v_org public.organizers)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'name', v_org.name,
    'address', v_org.billing_address,
    'tax_code', v_org.tax_code,
    'bank_name', v_org.bank_name,
    'bank_account_name', v_org.bank_account_name,
    'bank_account_no', v_org.bank_account_no,
    'momo_phone', v_org.momo_phone
  );
$$;

-- Falls back to the account's display name and phone, so a guest who never
-- opened the billing screen still gets a usable document rather than blanks.
CREATE OR REPLACE FUNCTION public.build_document_buyer(v_buyer public.profiles)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'name', COALESCE(NULLIF(v_buyer.billing_name, ''), v_buyer.display_name, ''),
    'address', COALESCE(v_buyer.billing_address, ''),
    'phone', COALESCE(NULLIF(v_buyer.billing_phone, ''), v_buyer.phone, ''),
    'tax_code', COALESCE(v_buyer.billing_tax_code, '')
  );
$$;

CREATE OR REPLACE FUNCTION public.ensure_payment_document(
  p_booking uuid, p_kind payment_doc_kind
)
RETURNS public.payment_documents
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_event   events%ROWTYPE;
  v_org     organizers%ROWTYPE;
  v_buyer   profiles%ROWTYPE;
  v_doc     payment_documents%ROWTYPE;
  v_is_host boolean;
  v_year    int;
  v_seq     int;
  v_number  text;
  v_prefix  text;
  v_unit    int;
  v_paid_at timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking;
  IF NOT FOUND THEN RAISE EXCEPTION 'BOOKING_NOT_FOUND'; END IF;

  SELECT * INTO v_event FROM events WHERE id = v_booking.event_id;
  SELECT * INTO v_org FROM organizers WHERE id = v_event.organizer_id;
  SELECT * INTO v_buyer FROM profiles WHERE id = v_booking.user_id;

  v_is_host := v_org.id IS NOT NULL
    AND (v_org.owner_id = auth.uid() OR v_org.user_id = auth.uid());

  IF v_booking.user_id <> auth.uid() AND NOT v_is_host THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- A receipt asserts money changed hands. Only confirm_payment() can make
  -- that true, so refuse until it has.
  IF p_kind = 'receipt' AND v_booking.paid_marked_at IS NULL
     AND v_booking.status <> 'confirmed' AND v_booking.status <> 'attended' THEN
    RAISE EXCEPTION 'NOT_PAID_YET';
  END IF;

  SELECT * INTO v_doc FROM payment_documents
   WHERE booking_id = p_booking AND kind = p_kind;

  IF FOUND THEN
    -- An UNPAID invoice is not history yet — it is a live request for money,
    -- and it is the document that tells the guest which account to transfer
    -- to. Freezing it at creation meant an invoice raised before the
    -- organizer had filled in their bank details kept an empty payment block
    -- forever, which is worse than useless: it is a bill with nowhere to pay
    -- it. So the parties are re-snapshotted while the booking is unpaid
    -- (the guest may also have added billing details since), and the whole
    -- document goes immutable the moment money is marked received.
    --
    -- The number never changes either way. That is the document's identity.
    IF p_kind = 'invoice' AND v_booking.paid_marked_at IS NULL
       AND v_booking.status NOT IN ('confirmed', 'attended') THEN
      UPDATE payment_documents SET
        seller = build_document_seller(v_org),
        buyer  = build_document_buyer(v_buyer)
      WHERE id = v_doc.id
      RETURNING * INTO v_doc;
    END IF;
    RETURN v_doc;
  END IF;

  IF v_org.id IS NULL THEN RAISE EXCEPTION 'ORGANIZER_NOT_FOUND'; END IF;

  v_year := EXTRACT(YEAR FROM now())::int;
  v_prefix := CASE WHEN p_kind = 'invoice' THEN 'HD' ELSE 'PT' END;

  -- Gapless within committed transactions: the row is locked for the rest
  -- of this one, so two concurrent issues serialise instead of colliding.
  INSERT INTO payment_document_counters (organizer_id, kind, year, next_number)
  VALUES (v_org.id, p_kind, v_year, 1)
  ON CONFLICT (organizer_id, kind, year)
  DO UPDATE SET next_number = payment_document_counters.next_number + 1
  RETURNING next_number INTO v_seq;

  v_number := v_prefix || '-' || upper(v_org.id) || '-' || v_year::text
              || '-' || lpad(v_seq::text, 4, '0');

  v_unit := CASE WHEN COALESCE(v_booking.qty, 0) > 0
                 THEN v_booking.total_vnd / v_booking.qty
                 ELSE v_booking.total_vnd END;

  v_paid_at := CASE WHEN p_kind = 'receipt'
                    THEN COALESCE(v_booking.paid_marked_at, v_booking.confirmed_at, now())
                    ELSE NULL END;

  INSERT INTO payment_documents (
    booking_id, event_id, organizer_id, user_id, kind, number,
    seller, buyer, event, lines, total_vnd, pay_method, paid_at
  ) VALUES (
    p_booking, v_event.id, v_org.id, v_booking.user_id, p_kind, v_number,
    build_document_seller(v_org),
    build_document_buyer(v_buyer),
    jsonb_build_object(
      'id', v_event.id, 'key', v_event.key, 'name', v_event.name,
      'date', v_event.event_date, 'time', v_event.event_time,
      'area', v_event.area, 'booking_code', v_booking.code
    ),
    jsonb_build_array(jsonb_build_object(
      'description', v_event.name,
      'qty', v_booking.qty,
      'unit_vnd', v_unit,
      'amount_vnd', v_booking.total_vnd
    )),
    v_booking.total_vnd,
    COALESCE(v_booking.paid_method, ''),
    v_paid_at
  )
  RETURNING * INTO v_doc;

  RETURN v_doc;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.ensure_payment_document(uuid, payment_doc_kind) FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_payment_document(uuid, payment_doc_kind) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. mark_payment_proof() — the guest says "I've transferred", and attaches
--     the screenshot. It does NOT mark the booking paid: only the organizer,
--     who can actually see their own bank account, may do that.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_payment_proof(
  p_booking uuid, p_path text, p_note text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;
  IF v_booking.user_id <> auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  UPDATE bookings SET
    proof_path = left(trim(COALESCE(p_path, '')), 400),
    proof_note = left(trim(COALESCE(p_note, '')), 400),
    proof_uploaded_at = now()
  WHERE id = p_booking;

  -- Tell the organizer in the place they already look: the event's thread.
  SELECT id INTO v_thread_id FROM threads
   WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;
  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Khách báo đã chuyển khoản ▪︎ Guest reported a transfer for booking '
            || COALESCE(v_booking.code, ''), 'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT COALESCE(o.owner_id, o.user_id), 'payment_proof',
         'Khách báo đã chuyển khoản',
         'Một khách vừa gửi xác nhận chuyển khoản. Kiểm tra và đánh dấu đã thanh toán.',
         jsonb_build_object('booking_id', p_booking, 'event_id', v_booking.event_id)
  FROM events e JOIN organizers o ON o.id = e.organizer_id
  WHERE e.id = v_booking.event_id AND COALESCE(o.owner_id, o.user_id) IS NOT NULL;

  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.mark_payment_proof(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_payment_proof(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. confirm_payment(), re-declared so marking a guest paid also issues the
--     receipt — which is the whole point of the organizer's "mark as paid"
--     action now. Everything else is carried over verbatim from 011.
--
--     The document work sits in its own EXCEPTION block: if numbering ever
--     fails, the payment must still be recorded. A booking marked paid with
--     no receipt yet is recoverable (anyone opening it calls
--     ensure_payment_document again); losing the payment mark is not.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_payment(p_booking uuid, p_method text DEFAULT 'momo')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_is_authorized boolean;
  v_thread_id uuid;
  v_receipt payment_documents%ROWTYPE;
  v_receipt_number text := NULL;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT b.* INTO v_booking FROM bookings b WHERE b.id = p_booking;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_FOUND');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM events e
    JOIN organizers o ON o.id = e.organizer_id
    WHERE e.id = v_booking.event_id
      AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) INTO v_is_authorized;

  IF NOT v_is_authorized THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_booking.status <> 'pending' AND v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'BOOKING_NOT_PENDING');
  END IF;

  UPDATE bookings
  SET status = 'confirmed',
      paid_marked_at = now(),
      paid_method = p_method,
      paid_marked_by = auth.uid(),
      confirmed_at = now()
  WHERE id = p_booking;

  -- Documents. The invoice is issued first so a paid booking is never left
  -- holding a receipt for an invoice that was never raised.
  BEGIN
    PERFORM ensure_payment_document(p_booking, 'invoice');
    v_receipt := ensure_payment_document(p_booking, 'receipt');
    v_receipt_number := v_receipt.number;
  EXCEPTION WHEN OTHERS THEN
    v_receipt_number := NULL;
  END;

  SELECT id INTO v_thread_id
  FROM threads
  WHERE event_id = v_booking.event_id AND guest_id = v_booking.user_id;

  IF v_thread_id IS NOT NULL THEN
    INSERT INTO messages (thread_id, sender_id, body, kind)
    VALUES (v_thread_id, auth.uid(),
            'Host marked payment received via ' || COALESCE(p_method, 'direct transfer') || '.'
            || COALESCE(' Biên nhận ▪︎ Receipt ' || v_receipt_number, ''), 'system');
  END IF;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  VALUES (v_booking.user_id, 'payment_confirmed',
          'Đã nhận thanh toán',
          'Người tổ chức xác nhận đã nhận thanh toán của bạn. Biên nhận đã sẵn sàng trong Tài khoản.',
          jsonb_build_object('booking_id', p_booking, 'event_id', v_booking.event_id,
                             'receipt_number', v_receipt_number));

  RETURN jsonb_build_object('success', true, 'booking_id', p_booking,
                            'receipt_number', v_receipt_number);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_payment(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. Proof-of-payment storage. Private, small, images and PDF only. Paths
--     are `<booking_id>/<filename>`, which is what both policies split on —
--     it ties every object to exactly one booking and therefore to exactly
--     one guest and one organizer.
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('pay-proof', 'pay-proof', false, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "pay_proof_guest_insert" ON storage.objects;
CREATE POLICY "pay_proof_guest_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'pay-proof' AND EXISTS (
    SELECT 1 FROM public.bookings b
    WHERE b.id::text = split_part((objects).name, '/', 1)
      AND b.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "pay_proof_read" ON storage.objects;
CREATE POLICY "pay_proof_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'pay-proof' AND EXISTS (
    SELECT 1 FROM public.bookings b
    JOIN public.events e ON e.id = b.event_id
    LEFT JOIN public.organizers o ON o.id = e.organizer_id
    WHERE b.id::text = split_part((objects).name, '/', 1)
      AND (b.user_id = auth.uid() OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
  )
);
