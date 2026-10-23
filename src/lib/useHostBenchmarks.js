// Host benchmarks + audience demand for event creation (note 50, migration 186).
// One request per category+city+currency per session (module cache), debounced while the host is still typing.
// Currency (migration 195): `p_currency` is sent ONLY for USD, so a VND form keeps calling the two-argument
// signature every server has; a USD answer that is not labelled USD is dropped (never compare across currencies).
// Best-effort by design: no session, a missing function or an error all resolve to `null`, which the
// recipe treats exactly like a cold start (tips only, no numbers). Never throws into the form.
import { useEffect, useState } from 'react';
import { supabase } from './supabase.js';

const benchCache = new Map();
const demandCache = new Map();

async function fetchBenchmarks(cat, city, currency) {
  const usd = currency === 'USD';
  const key = `${cat}|${city}|${usd ? 'USD' : 'VND'}`;
  if (!benchCache.has(key)) {
    const args = usd ? { p_cat_key: cat, p_city: city, p_currency: 'USD' } : { p_cat_key: cat, p_city: city };
    benchCache.set(key, supabase.rpc('get_host_benchmarks', args)
      .then(({ data, error }) => (error || !data || data.success === false || (usd && data.currency !== 'USD') ? null : data))
      .catch(() => null));
  }
  return benchCache.get(key);
}

async function fetchDemand(cat) {
  if (!demandCache.has(cat)) {
    demandCache.set(cat, supabase.rpc('get_audience_demand', { p_cat_key: cat })
      .then(({ data, error }) => (error || !data ? null : (data.interested_people ?? null)))
      .catch(() => null));
  }
  return demandCache.get(cat);
}

export function useHostBenchmarks(catKey, city, enabled = true, currency = 'VND') {
  const [benchmarks, setBenchmarks] = useState(null);
  const [demand, setDemand] = useState(null);
  const cat = (catKey || '').trim().toLowerCase();
  const town = (city || '').trim().toLowerCase();
  useEffect(() => {
    if (!enabled) return undefined;
    let live = true;
    const t = setTimeout(() => {
      fetchBenchmarks(cat, town, currency).then(b => { if (live) setBenchmarks(b); });
      if (cat) fetchDemand(cat).then(d => { if (live) setDemand(d); });
      else setDemand(null);
    }, 350);
    return () => { live = false; clearTimeout(t); };
  }, [cat, town, enabled, currency]);
  return { benchmarks, demand };
}
