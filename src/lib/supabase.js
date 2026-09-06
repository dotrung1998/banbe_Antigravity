import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ukchdgdnwytretvqjjqu.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_gHAhltvf1HSNIhuJQujVZA_lvscZwbz';

const authRedirectUrl = import.meta.env.VITE_AUTH_REDIRECT_URL || import.meta.env.VITE_SITE_URL;

export function getAuthRedirectUrl() {
  if (authRedirectUrl) return authRedirectUrl.replace(/\/+$/, '');
  return window.location.origin;
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,   // picks up access_token from magic-link redirect
  },
});
