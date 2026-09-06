-- Migration: OTP codes table for send-otp Edge Function

CREATE TABLE IF NOT EXISTS otp_codes (
  phone text PRIMARY KEY,
  code_hash text NOT NULL,
  attempts int NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  last_sent_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_otp_codes_expires_at ON otp_codes (expires_at);

ALTER TABLE otp_codes ENABLE ROW LEVEL SECURITY;
