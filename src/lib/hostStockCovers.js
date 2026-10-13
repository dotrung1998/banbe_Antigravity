// Built-in cover designs for the host profile (no photo licensing, no assets to ship):
// soft two-stop gradients with a light bloom, drawn on a canvas. Picking one renders it to a
// real image file that goes through the normal organizer-avatar upload.

export const HOST_STOCK_COVERS = [
  { id: 'dawn',  vi: 'Bình minh', en: 'Dawn',  a: '#F6DDB5', b: '#E7A488', glow: '#FFF3DB' },
  { id: 'moss',  vi: 'Rêu',       en: 'Moss',  a: '#B4C2A4', b: '#4E6B52', glow: '#E4EBD8' },
  { id: 'sea',   vi: 'Biển',      en: 'Sea',   a: '#A5CBCD', b: '#2F5D6B', glow: '#DDF0EF' },
  { id: 'honey', vi: 'Mật ong',   en: 'Honey', a: '#F4D885', b: '#C58519', glow: '#FFF1C4' },
  { id: 'rose',  vi: 'Hồng phấn', en: 'Rose',  a: '#EBBEBE', b: '#A4566B', glow: '#FFE6E6' },
  { id: 'clay',  vi: 'Đất nung',  en: 'Clay',  a: '#D89E7E', b: '#8A4C38', glow: '#F7D9C6' },
  { id: 'dusk',  vi: 'Hoàng hôn', en: 'Dusk',  a: '#7B6BA3', b: '#2E294A', glow: '#C9BFE6' },
  { id: 'ink',   vi: 'Mực',       en: 'Ink',   a: '#47423B', b: '#14120E', glow: '#8A7F6B' },
];

export function drawStockCover(ctx, size, cover) {
  const g = ctx.createLinearGradient(0, 0, size, size);
  g.addColorStop(0, cover.a);
  g.addColorStop(1, cover.b);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  const bloom = (x, y, r, alpha) => {
    const rg = ctx.createRadialGradient(x * size, y * size, 0, x * size, y * size, r * size);
    rg.addColorStop(0, cover.glow);
    rg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.globalAlpha = alpha;
    ctx.fillStyle = rg;
    ctx.fillRect(0, 0, size, size);
    ctx.globalAlpha = 1;
  };
  bloom(0.28, 0.22, 0.75, 0.75);
  bloom(0.82, 0.88, 0.55, 0.35);
}

/** Small data URL for a swatch/preview. Null where canvas is unavailable. */
export function stockCoverDataUrl(cover, size = 160) {
  if (typeof document === 'undefined') return null;
  try {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d');
    if (!ctx) return null;
    drawStockCover(ctx, size, cover);
    return c.toDataURL('image/jpeg', 0.9);
  } catch { return null; }
}

/** Full-size File for the avatar upload (JPEG, ~640px). */
export function stockCoverFile(cover, size = 640) {
  return new Promise((resolve, reject) => {
    try {
      const c = document.createElement('canvas');
      c.width = c.height = size;
      const ctx = c.getContext('2d');
      drawStockCover(ctx, size, cover);
      c.toBlob(blob => (blob ? resolve(new File([blob], `cover-${cover.id}.jpg`, { type: 'image/jpeg' })) : reject(new Error('COVER_RENDER_FAILED'))), 'image/jpeg', 0.92);
    } catch (e) { reject(e); }
  });
}
