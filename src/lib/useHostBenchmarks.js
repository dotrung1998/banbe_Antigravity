// Host benchmarks + audience demand for event creation (note 50, migration 186).
// One request per category+city per session (module cache), debounced while the host is still typing.
// Best-effort by design: no session, a missing function or an error all resolve to `null`, which the
// recipe treats exactly like a cold start (tips only, no numbers). Never throws into the form.
import { useEffect, useState } from 'react';
import { supabase } from './supabase.js';

const benchCache = new Map();
const demandCache = new Map();

async function fetchBenchmarks(cat, city) {
  const key = `${cat}|${city}`;
  if (!benchCache.has(key)) {
    benchCache.set(key, supabase.rpc('get_host_benchmarks', { p_cat_key: cat, p_city: city })
      .then(({ data, error }) => (error || !data || data.success === false ? null : data))
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

export function useHostBenchmarks(catKey, city, enabled = true) {
  const [benchmarks, setBenchmarks] = useState(null);
  const [demand, setDemand] = useState(null);
  const cat = (catKey || '').trim().toLowerCase();
  const town = (city || '').trim().toLowerCase();
  useEffect(() => {
    if (!enabled) return undefined;
    let live = true;
    const t = setTimeout(() => {
      fetchBenchmarks(cat, town).then(b => { if (live) setBenchmarks(b); });
      if (cat) fetchDemand(cat).then(d => { if (live) setDemand(d); });
      else setDemand(null);
    }, 350);
    return () => { live = false; clearTimeout(t); };
  }, [cat, town, enabled]);
  return { benchmarks, demand };
}
