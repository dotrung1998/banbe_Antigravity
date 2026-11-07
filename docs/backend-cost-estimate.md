# banbe backend cost estimate — Vietnam and US markets

Written 2026-10-09, revised to a single architecture: the **hybrid** (Supabase for database, auth, realtime and private files; Cloudflare R2 for public photos). Scope: the services the backend actually uses today (found in the repo), priced at four growth stages. Every price is labelled **[Fact]** (read from the vendor's page on 2026-10-09, source in section 9) or **[Estimate]** (my assumption or a number I could not verify). Traffic per user is an estimate, not a measurement: the project's per-file download logs were unavailable (see note 22) and the Supabase project is currently blocked.

Exchange rate used: **26,100 VND/USD** [Fact: Vietcombank selling rate, 10 Sep 2026; check the current rate]. All USD prices exclude VAT/GST/local taxes (the vendors state this); see section 7.

## 1. TL;DR

| Stage | MAU (monthly active users) | Monthly cost, local VN SMS | ≈ VND | Same, if SMS goes through Twilio |
|---|---|---|---|---|
| A. Pilot | 500 | **≈ $70** | 1.8 M | ≈ $140 |
| B. Local traction (one city) | 5,000 | **≈ $130–180** | 3.4–4.7 M | ≈ $720–750 |
| C. Citywide | 25,000 | **≈ $435–545** | 11–14 M | ≈ $2,800–2,900 |
| D. Multi-city / national | 100,000 | **≈ $1,300–1,700** | 34–44 M | ≈ $9,300–9,700 |

1. **The floor is about $55 a month**: Supabase Pro $25 + Vercel Pro $20 + Apple Developer $8.25 + a domain. The free plans are not an option for a commercial launch (section 3).
2. **The biggest swing is phone-OTP SMS, not infrastructure.** Twilio charges $0.2852 per SMS to Vietnam [Fact]. A Vietnamese brandname-SMS provider charges 450–790 VND (≈ $0.017–0.030) per SMS [Fact: SpeedSMS price list, incl. VAT] plus a registered sender name, roughly 10–15× cheaper than Twilio (section 6b). The app requires phone verification, so this single decision outweighs everything else from Stage B onward.
3. **The hybrid keeps photo traffic off Supabase from day one.** Public event and organizer photos are served from Cloudflare R2, whose egress is free [Fact]. Supabase then only serves private files (chat, payment proofs, stories) and the database, which stays inside Pro's 250 GB egress until about Stage D. R2's own cost is close to zero at every stage (section 5); the price of the hybrid is a one-off setup plus a domain.
4. **Replace Gmail SMTP before launch.** It is a personal mailbox with low daily send limits and no domain authentication; Resend Free covers 3,000 emails a month [Fact].
5. **No separate auth provider is needed for phone codes.** Supabase Auth creates and checks the code; it only needs an SMS delivery provider behind it, and it adds no fee of its own (section 6a). Raise its default 30-SMS-per-hour cap as you grow.

## 1a. Abbreviations and terms used in this document

| Term | Meaning |
|---|---|
| **MAU** | Monthly Active Users: distinct people who open the app at least once in a month. Used to size each growth stage. |
| **VN / US** | Vietnam / United States, the two target markets. |
| **VND / USD** | Vietnamese dong / US dollar. All prices are in USD unless marked VND; **M** after a VND figure means million (3.2 M = 3,200,000 VND). |
| **k, GB, MB, TB** | Thousand; gigabyte, megabyte, terabyte (1 TB = 1,000 GB). |
| **SMS** | Short Message Service: a text message. |
| **OTP** | One-Time Password: the short code sent by SMS to verify a phone number at signup. |
| **SMTP** | Simple Mail Transfer Protocol: the standard way a program sends email. "Gmail SMTP" means sending the app's email through a Gmail mailbox. |
| **API** | Application Programming Interface: the server endpoints the web and iOS apps call (the 12 functions under `api/`). |
| **CDN** | Content Delivery Network: servers around the world that cache and serve files (photos, the web app) close to users. |
| **Egress** | Data leaving a service to users (downloads). Providers bill or cap it. **Cached egress** is served from the provider's CDN cache (mostly public files); **uncached egress** comes straight from the database or storage. |
| **R2** | Cloudflare R2: file storage with free egress, used in the hybrid for public photos (note 28). |
| **Class A / Class B operations** | R2's request types: Class A are writes and listings (uploads), Class B are reads (downloads). |
| **Compute (Micro / Small / Medium / Large)** | The size of the Supabase database server; larger sizes cost more and handle more load. |
| **Seat** | One paid team member on a Vercel plan. |
| **Hybrid** | The chosen architecture: Supabase for database, auth, realtime and private files; Cloudflare R2 for public photos. |
| **Hobby / Pro / Team** | The vendors' plan tiers. Hobby and Free are the no-cost tiers; Vercel Hobby is restricted to non-commercial use. |
| **Spend cap** | A Supabase Pro setting that stops usage at the included quota instead of billing overage. |
| **PITR** | Point-In-Time Recovery: an optional paid Supabase add-on that restores the database to any moment, not just the last daily backup. |
| **APNs** | Apple Push Notification service: delivers iOS push notifications (free). |
| **Wallet pass** | An Apple Wallet ticket, which needs the Apple Developer account's certificate. |
| **A2P 10DLC** | Application-to-Person, 10-Digit Long Code: the US registration that carriers require before an app can send SMS from a normal phone number. It has one-off and monthly fees. |
| **VAT / GST** | Value-Added Tax / Goods and Services Tax: consumption taxes that vendors add on top of listed prices depending on billing country. |
| **VietQR** | The Vietnamese bank-transfer QR standard used for ticket payments. **SePay, payOS, Casso** are services that notify the app when a transfer arrives (bank-webhook reconciliation). |
| **Stripe direct charge** | A payment taken on the host's own Stripe account, so banbe never holds the money. |
| **MFA** | Multi-Factor Authentication: a second proof of identity at login. Supabase's *Phone MFA* is a separate paid add-on that this app does not use. |
| **Send SMS hook** | A Supabase setting that hands each login code to your own HTTP endpoint, so any SMS provider (or Zalo, WhatsApp) can deliver it. |
| **Brandname** | A sender name (for example "BANBE") that Vietnamese carriers require to be registered before SMS can show it. |
| **[Fact] / [Estimate]** | Labels: **[Fact]** was read from the vendor's page on 2026-10-09; **[Estimate]** is my assumption or an unverified number. |
| **TL;DR** | "Too long; didn't read": the one-screen summary at the top. |

## 1b. Architecture this estimate assumes (hybrid)

| Data | Where it lives | Why |
|---|---|---|
| Database, auth, realtime, business logic | Supabase | Already built on it |
| **Public** media: event photos of public events, organizer profile photos | **Cloudflare R2** behind a custom domain (for example `media.<domain>`) | Free egress; these are the photos shown to everyone on Home and event pages, the bulk of downloads |
| **Private** media: chat and dispute attachments, payment and refund proofs, stories, invite-only and draft event photos, QR codes | Supabase Storage (signed links) | Needs row-level access control; low traffic |
| Web app and serverless API | Vercel | Already built on it |

Original Supabase copies of migrated photos are kept, so old app builds keep working while the apps move to R2 (note 28). Setup steps are in the answer I gave on 2026-10-09; the migration and compression scripts are `scripts/migrate-media-to-r2.mjs` and `scripts/compress-supabase-media.mjs`.

## 2. What the backend consists of (from the repo)

| Piece | What it is | Where |
|---|---|---|
| Database, auth, realtime, private file storage | Supabase | `supabase/`, `src/lib/supabase.js`, iOS `SupabaseService` |
| Web app + serverless API (12 functions) + 4 cron jobs | Vercel (`vercel.json`) | `api/`, `vercel.json` |
| Public photo storage and delivery (chosen; built, not yet configured) | Cloudflare R2 | `api/media.js`, note 28 |
| Transactional email | Gmail SMTP via nodemailer | `api/_lib/email.js` |
| Phone OTP | Supabase Auth SMS provider (Twilio configured in `config.toml`) | `supabase/config.toml` |
| Push | Apple APNs | `api/_lib/apns.js` |
| Apple Wallet passes | Apple Developer account certificate | `api/wallet.js` |
| Maps | MapLibre + OpenFreeMap tiles; geocoding via public Nominatim | `src/`, iOS |
| Payments | Not held by banbe: VietQR bank transfers reconciled by webhook (VN), host-side Stripe planned (US) | `docs/payment-research.md` |

## 3. Plans and what they include (all [Fact])

- **Supabase**: Free $0 (500 MB database, 1 GB storage, 5 GB cached egress, 5 GB uncached, 50k MAU, projects pause after a week idle). **Pro $25/month**: 8 GB database, 100 GB storage, **250 GB cached + 250 GB uncached egress**, 100k MAU, $10 compute credit (covers a Micro instance), spend cap on by default. Overage: database $0.125/GB, storage $0.0213/GB, uncached egress $0.09/GB, extra MAU $0.00325. Compute add-ons: Micro ~$10, Small ~$15, Medium ~$60, Large ~$110, XL ~$210. Team plan is $599.
- **Vercel**: Hobby $0 but **"for personal, non-commercial use"**; Pro **$20/month per seat** with 1 TB fast data transfer and usage-based functions/CPU. Image optimisation on Pro from $0.05 per 1,000 transformations.
- **Cloudflare R2**: storage $0.015/GB-month (first 10 GB free), Class A $4.50 per million (1M free), Class B $0.36 per million (10M free), **egress free**.
- **Resend**: Free 3,000 emails/month (100/day); Pro $20 for 50,000 or $35 for 100,000, overage $0.90 per 1,000.
- **Apple Developer Program**: $99/year [Fact via several 2026 guides].

## 4. Assumptions per stage [Estimate]

| | A. Pilot | B. Traction | C. Citywide | D. National |
|---|---|---|---|---|
| MAU | 500 | 5,000 | 25,000 | 100,000 |
| New signups per month | 200 | 1,500 | 6,000 | 20,000 |
| Phone-OTP SMS (1.5 per signup, resends) | 300 | 2,250 | 9,000 | 30,000 |
| Emails (≈3 per MAU: verification, tickets, notices) | 1,500 | 15,000 | 75,000 | 300,000 |
| Supabase compute | Micro (in credit) | Small | Medium | Large |
| Public photo traffic, served by R2 (≈40 MB per MAU per month, compressed) | 20 GB | 200 GB | 1 TB | 4 TB |
| Private-file traffic, served by Supabase (≈4 MB per MAU per month) | 2 GB | 20 GB | 100 GB | 400 GB |

## 5. Monthly cost by stage (USD) [Fact prices × Estimate volumes]

| Line | A | B | C | D |
|---|---|---|---|---|
| Supabase Pro base | 25 | 25 | 25 | 25 |
| Supabase compute above the $10 credit | 0 | 5 | 50 | 100 |
| Supabase disk / extras | 0 | 0 | 5 | 20 |
| Supabase egress overage (private files above 250 GB at $0.09/GB, worst case) | 0 | 0 | 0 | 14 |
| Vercel Pro (seats + usage) | 20 | 20 | 60 | 160 |
| Email (Resend) | 0 | 20 | 35 | 215 |
| **Phone OTP — local VN provider** (590 VND ≈ $0.0226/SMS + $7.7/month sender name [Fact]) | 15 | 59 | 211 | 686 |
| Phone OTP — Twilio VN ($0.2852/SMS [Fact]) | 86 | 642 | 2,567 | 8,556 |
| **R2: public photo storage + operations** (egress free; free tier covers the first 10 GB) | 0 | 2 | 5 | 20 |
| Maps geocoding / tiles at scale (public Nominatim is not for heavy use) | 0 | 0–25 | 50 | 150 |
| Monitoring / error tracking | 0 | 0 | 26 | 50 |
| Apple Developer ($99 / 12) | 8.25 | 8.25 | 8.25 | 8.25 |
| Domain (≈ $12/year [Estimate]) | 1 | 1 | 1 | 1 |
| **Total, local VN SMS** | **≈ 69** | **≈ 140–165** | **≈ 476** | **≈ 1,449** |
| **Total, Twilio SMS** | ≈ 140 | ≈ 723–748 | ≈ 2,832 | ≈ 9,319 |

Cost per MAU (local SMS): A $0.14, B $0.028–0.033, C $0.019, D $0.014 (R2 setup is included in these figures at its running cost; the one-off setup time is not). Fixed costs dominate at small scale, which is normal.

## 6. Market differences

### Vietnam
- **SMS**: Twilio VN $0.2852 [Fact]. Vietnamese brandname providers are far cheaper; see the provider comparison in section 6b. Domestic OTP needs a registered brandname with the carriers (3–5 business days).
- **Using a local SMS provider** means Supabase's **Send SMS hook** [Fact: Supabase docs], an HTTP endpoint that receives the OTP and calls the provider's API. Supabase's built-in providers are Twilio, Twilio Verify, MessageBird, Vonage and Textlocal. The hook is a small engineering task.
- **Payments**: banbe does not hold money (`docs/payment-research.md`). VietQR + bank-webhook reconciliation (SePay / payOS / Casso) is paid by the host, if at all. Gateway fees are not in the table above.
- **Latency**: pick the Supabase region nearest the users (Singapore is closest to Vietnam). I could not see which region this project uses; changing it later means migrating.

### US
- **SMS**: Twilio US $0.0083 per segment plus carrier fees of about $0.0035–$0.005 [Fact], so ≈ $0.013 per SMS. At the stage volumes that is about $4 / $29 / $117 / $390 a month: close to the Vietnamese local-provider price. US A2P 10DLC registration has onboarding fees that Twilio's page does not list [Estimate: budget a one-time $50–100 and a small monthly campaign fee; verify].
- **Payments**: Stripe direct-charge on the host's account (fees borne by the host, per `docs/payment-research.md`, which labels the 2.9% + 30¢ figure as an estimate). I could not read Stripe's US pricing page this session. No platform cost unless an application fee is introduced.
- **Sales tax / VAT** on subscriptions: see section 7.

## 6a. Phone OTP: what Supabase does and what it does not

**Short answer: Supabase alone is enough for the login logic, but it does not send SMS itself. You still need one SMS delivery provider, and you do not need a second login/auth service (Firebase, Auth0, Clerk).**

| Job | Who does it | Extra cost |
|---|---|---|
| Generate the 6-digit code, expire it (1 hour), check it, rate-limit it, create the session | **Supabase Auth** [Fact: Supabase docs] | Included in Pro (100k MAU) |
| **Deliver** the code as a text message | A third-party SMS provider: Twilio, Twilio Verify, MessageBird/Bird, Vonage or Textlocal built in; anything else through the **Send SMS hook** [Fact: Supabase docs: "You must configure a third-party SMS provider"; "Supabase does not send SMS itself"] | Per-SMS price from section 6b |
| Email codes (sign-up, login) | Already independent of Supabase: the repo sends them from its own API (`api/auth`, Gmail SMTP today) and only the verification calls Supabase (`verifyOtp`) | Resend or similar (section 5) |

How this app uses it (from the code):
- **Phone verification gate**: `auth.updateUser({ phone })` then `verifyOtp({ type: 'phone_change' })` (web `src/lib/accountGate.js`, iOS `AuthViewModel+Gate.swift`). This is the flow that needs SMS delivery. A web phone sign-in path also exists (`signInWithOtp({ phone })`).
- **Not used:** Phone MFA, a separate paid add-on at **$75/month for the first project** [Fact: Supabase docs]. The app's phone step is verification, not MFA, so this cost does not apply. Do not switch it on by accident.
- `supabase/config.toml` has Twilio **disabled** and SMS signup off, but that file is the local-development config. **I could not see the production setting** (Dashboard, Authentication, Providers, Phone). Check which provider, if any, is configured there.

Why not add Firebase/Auth0/Clerk for phone login: it would add per-user fees and a user migration for no benefit, because Supabase already does the code logic. Firebase Phone Auth is only a cheaper SMS channel (about $0.01 in the US, Vietnam price not listed), and it would not integrate with Supabase sessions without custom work.

Limits and safeguards [Fact: Supabase docs]:
- **30 SMS per hour for the whole project** by default, configurable. At Stage C (9,000 SMS a month, ≈ 12 an hour on average) bursts such as an event launch can exceed it, so real users may be blocked: raise the limit as you grow. It is also a built-in ceiling on pumping fraud (30 × $0.2852 ≈ $8.56 an hour on Twilio VN).
- One OTP request per user every **60 seconds**; verification attempts **30 per 5 minutes per IP**.
- Supabase's docs advise adjusting these limits and configuring CAPTCHA to control SMS cost. The rate-limit page I read did not mention CAPTCHA, so confirm in the Dashboard (Authentication, Attack Protection) that hCaptcha or Turnstile is available on your plan.
- **Development and tests:** local config supports fixed test numbers (`[auth.sms.test_otp]`), and this repo has a server-controlled test-account exemption (note 32).

**What this changes in the cost model:** nothing. The SMS price already in sections 5 and 6b is the whole phone-verification cost; Supabase adds $0 on top, and no extra auth provider fee exists.

Ways to need fewer SMS (each is a product choice, not a cost I have priced):
1. Verify the phone only when someone first books or hosts, not at signup. Most browsers then never trigger an SMS.
2. Offer Zalo (ZNS) or email as the first channel in Vietnam, with SMS as fallback, through the Send SMS hook.
3. Skip re-verification on a returning device.

## 6b. OTP text-message providers compared

Phone verification is the largest swing item, so this compares the realistic options. Price per SMS in USD; Vietnamese prices converted at 26,100 VND/USD.

### Vietnam (numbers starting +84)

| Provider | Price per SMS | Notes |
|---|---|---|
| **SpeedSMS (local, brandname "CSKH")** | **450 VND ≈ $0.017** (Gmobile and priority sectors) to **590 VND ≈ $0.023** (e-commerce / social) to **790 VND ≈ $0.030** (general, finance); Vietnamobile 1,500 VND ≈ $0.057 | [Fact: speedsms.vn price list, incl. 10% VAT]. Brandname setup 200,000 VND (≈ $7.7) once + 200,000 VND/month (≈ $7.7). Needs carrier approval (3–5 business days). API in PHP/Java/C#/Node. |
| eSMS.vn, Stringee, VNPT, Viettel, Vihat (local) | Price pages not readable this session; "contact sales" | [Estimate: same order as SpeedSMS]. Get written quotes. All need a registered brandname. |
| Zalo ZNS (OTP template) | Custom notification ≈ 200 VND ≈ $0.008 | [Estimate: from a search snippet; OTP template pricing not confirmed]. Only reaches people who use Zalo; usable as the first channel with SMS as fallback. |
| Plivo | $0.0687 (Beeline/GTEL), $0.1297 (VinaPhone), $0.1380 (MobiFone), **$0.1934 (Viettel)**, up to $0.2280 | [Fact: plivo.com]. Blended ≈ $0.157 [Estimate: my carrier mix]. Viettel has the largest share, so the cheap route rarely applies. |
| Bird (MessageBird) | ≈ $0.1553 | [Fact via an aggregator, July 2026, base rate excluding carrier surcharges]. Built into Supabase. |
| Twilio | **$0.2852** | [Fact: twilio.com, one rate for all carriers]. An aggregator lists $0.1552 base excluding surcharges; I used Twilio's own page. Built into Supabase. |
| Firebase Phone Auth | Not listed for Vietnam in what I could read | $0.01 in the US [Fact via search]; other regions up to $0.46; Blaze billing plan required. |

### United States (numbers starting +1)

| Provider | Cost per OTP SMS | Notes |
|---|---|---|
| **Telnyx** | **≈ $0.008** ($0.004 + carrier fee $0.0035–0.0045) | [Fact: telnyx.com]. Not built into Supabase; use the Send SMS hook. |
| Plivo | $0.008–0.013, no per-verification fee | [Fact via aggregator, Aug 2026]. |
| Sinch | $0.0078+ | [Fact via aggregator]. |
| MSG91 | $0.0065 | [Fact via aggregator]. |
| Firebase Phone Auth | $0.01 | [Fact via search]. Free allowance of about 10 SMS a day. |
| Twilio (plain SMS) | ≈ $0.013 ($0.0083 + carrier fee $0.0035–0.005) | [Fact: twilio.com]. Built into Supabase. |
| AWS end-user messaging | ≈ $0.02 all-in | [Fact via aggregator]. No fraud protection included. |
| **Twilio Verify** | **$0.05 per successful verification + the SMS (≈ $0.063–0.07 total)** | [Fact: twilio.com]. Includes SMS-pumping fraud protection; the fee is about 6× the SMS itself. Built into Supabase. |
| Vonage Verify | ≈ $0.057–0.061 per verification + SMS (≈ $0.07) | [Fact via aggregator]. Built into Supabase. |

### What each stage would cost for phone verification alone (USD per month)

Volumes from section 4 (300 / 2,250 / 9,000 / 30,000 SMS; 200 / 1,500 / 6,000 / 20,000 signups).

| Scenario | A | B | C | D |
|---|---|---|---|---|
| **VN: SpeedSMS at 450 VND** (best case) | 13 | 47 | 163 | 525 |
| **VN: SpeedSMS at 590 VND** (base case used above) | 15 | 59 | 211 | 686 |
| VN: SpeedSMS at 790 VND (worst local case) | 17 | 76 | 280 | 916 |
| VN: Plivo (blended ≈ $0.157) | 47 | 353 | 1,413 | 4,710 |
| VN: Twilio ($0.2852) | 86 | 642 | 2,567 | 8,556 |
| US: Telnyx (≈ $0.008) | 2 | 18 | 72 | 240 |
| US: Twilio plain SMS (≈ $0.013) | 4 | 29 | 117 | 390 |
| US: Twilio Verify (≈ $0.07 per signup) | 14 | 104 | 417 | 1,390 |

### Extra scenarios

- **Mixed market, 70% Vietnam / 30% US** (base cases: SpeedSMS 590 VND + Telnyx): about $11 / $46 / $169 / $552 a month for stages A–D. With Twilio for both: about $61 / $458 / $1,832 / $6,106.
- **SMS-pumping attack** (bots trigger 5,000 OTP requests to Vietnamese numbers in a day): about $1,426 on Twilio VN, about $785 on Plivo, about $113 on SpeedSMS (590 VND). The same attack costs about $65 against Twilio US. This is why Supabase's docs tell you to set rate limits and add CAPTCHA; with a Send SMS hook you also add your own per-phone, per-IP and per-country limits.
- **Spend ceilings:** a prepaid local account (top-up balance) caps the loss at the balance; Twilio and Plivo support usage limits or alerts, but check they are switched on.

### Recommendation
1. **+84 numbers:** SpeedSMS or another Vietnamese brandname provider via the Send SMS hook (roughly 10–15× cheaper than Twilio), with Zalo ZNS as a possible first channel later.
2. **+1 numbers:** Telnyx or Plivo for lowest cost; Twilio plain SMS is a fine default because it is already built into Supabase. Avoid Twilio Verify unless you want its fraud protection included, since its flat fee exceeds the SMS cost.
3. **Whatever you choose:** rate limits, CAPTCHA and a country allow-list from day one.

## 7. What is not in these numbers
- **Taxes**: vendors quote prices without VAT. Whether Vietnamese VAT or foreign-contractor tax applies to the Supabase/Vercel/Cloudflare invoices depends on how the company is registered. Ask an accountant.
- **Payment gateway fees** (host-side), **chargebacks/refunds**, **customer support tools**, **legal/registration costs**, **marketing**, **developer salaries**.
- **Data-residency rules**: Vietnam's data-localisation requirements for certain categories of user data could affect where the database may sit. This is a legal question, not a price. Ask counsel before committing to a region.
- **Hybrid caveats**: app builds released before the R2-aware version keep downloading from the Supabase copy; the link-preview endpoint (`api/photo-share.js`) should be switched to prefer the R2 address so shared photos do not hit Supabase; private files are unaffected by R2 and still count against Supabase egress.
- **Supabase point-in-time recovery** (optional paid add-on) and **read replicas**. Daily backups come with Pro [Estimate; confirm retention on the plan page].
- **A second developer seat on Vercel** (+$20) is included only from Stage C on.

## 8. What I would do, in order
1. **Upgrade Supabase to Pro now** ($25). It also fixes the current outage on the same day; you can downgrade after a month if needed (section 3).
2. **Move to Vercel Pro ($20) before launching commercially**; Hobby is non-commercial.
3. **Decide the SMS provider before building volume.** Use a Vietnamese brandname provider for +84 numbers and a low-cost US provider for +1 numbers, routed through the Send SMS hook (section 6b). Ask for a written quote; the saving is large from ~1,500 signups a month.
4. **Replace Gmail SMTP with Resend** (free until ~3,000 emails a month).
5. **Set up the hybrid before launch, not after growth.** Run `scripts/compress-supabase-media.mjs` first (3–5× smaller photos; the R2 migration then copies the smaller files), then configure Cloudflare R2 and run `scripts/migrate-media-to-r2.mjs`. One-off cost: a domain (~$12/year), a card on file at Cloudflare, and roughly a day of work plus one pass of downloading ~100 MB of existing photos from Supabase.
6. **Review costs each month in four dashboards**: Supabase Reports (private-file egress), Cloudflare R2 (storage and operations), Vercel Usage, and the SMS provider's balance. SMS spend can spike with abuse; keep the existing per-hour OTP limit (`sms_sent = 30` in `config.toml`) and add per-phone/per-IP limits.

## 9. Sources (read 2026-10-09)
- Supabase pricing: https://supabase.com/pricing · compute: https://supabase.com/docs/guides/platform/compute-and-disk
- Vercel: https://vercel.com/pricing · https://vercel.com/docs/pricing 
- Cloudflare R2: https://developers.cloudflare.com/r2/pricing/
- Resend: https://resend.com/pricing
- Twilio SMS Vietnam: https://www.twilio.com/en-us/sms/pricing/vn · United States: https://www.twilio.com/en-us/sms/pricing/us · Twilio Verify: https://www.twilio.com/en-us/verify/pricing
- Plivo Vietnam: https://www.plivo.com/sms/pricing/vn/ · Telnyx: https://telnyx.com/pricing/messaging · SpeedSMS CSKH price list: https://speedsms.vn/bang-gia-dich-vu-tin-nhan-thuong-hieu-cskh/
- Provider comparisons (aggregators, Aug 2026): https://www.authgear.com/post/best-otp-service-providers/ · https://www.authgear.com/tools/sms-cost-calculator/
- Supabase phone login, Send SMS hook, phone MFA and rate limits: https://supabase.com/docs/guides/auth/phone-login · https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook · https://supabase.com/docs/guides/auth/auth-mfa/phone · https://supabase.com/docs/guides/auth/rate-limits
- Other Vietnamese providers (prices not readable): https://esms.vn · https://stringee.com
- Apple Developer Program fee: https://developer.apple.com/programs/ (confirmed via 2026 guides, e.g. https://magora-systems.com/apple-developer-fee/)
- Exchange rate: https://webgia.com/ty-gia/vietcombank/10-09-2026.html
