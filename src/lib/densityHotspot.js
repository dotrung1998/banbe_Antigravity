// Where the map centers on first load — deliberately NOT the user's GPS
// position (see .claude/notes/11-realtime-map.md): centers on wherever
// events are actually clustered instead, so opening the map for the first
// time shows something happening rather than an empty neighborhood the
// user just happens to be standing in.
//
// Simple grid-binning, not a real clustering library: round each event's
// lat/lng to a coarse grid cell, count events per cell, take the densest
// cell's own centroid (the mean position of the events actually in it, not
// the cell's geometric center — a hotspot should sit where the events are,
// not on a bin boundary). Good enough at city scale (a few dozen events)
// without pulling in a clustering dependency for a one-time calculation.

const DEFAULT_CELL_DEGREES = 0.02; // ~2.2km at HCMC's latitude

/**
 * @param {{lat: number, lng: number}[]} points
 * @param {number} [cellDegrees]
 * @returns {{lat: number, lng: number} | null} the densest cluster's
 *   centroid, or null if `points` has nothing usable.
 */
export function densityHotspot(points, cellDegrees = DEFAULT_CELL_DEGREES) {
  const usable = (points || []).filter(p => p && Number.isFinite(p.lat) && Number.isFinite(p.lng));
  if (usable.length === 0) return null;

  const bins = new Map(); // "cellLat:cellLng" -> { sumLat, sumLng, count }
  for (const p of usable) {
    const cellKey = `${Math.round(p.lat / cellDegrees)}:${Math.round(p.lng / cellDegrees)}`;
    const bin = bins.get(cellKey) || { sumLat: 0, sumLng: 0, count: 0 };
    bin.sumLat += p.lat;
    bin.sumLng += p.lng;
    bin.count += 1;
    bins.set(cellKey, bin);
  }

  let best = null;
  for (const bin of bins.values()) {
    if (!best || bin.count > best.count) best = bin;
  }
  return { lat: best.sumLat / best.count, lng: best.sumLng / best.count };
}
