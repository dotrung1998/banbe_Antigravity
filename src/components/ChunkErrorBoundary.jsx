// Catches a failed lazy screen import (an open tab still asking for a chunk an older deploy named, which the
// catch-all rewrite answers with index.html) and any other render error under it, so the user sees a calm
// Reload card instead of a blank white screen. main.jsx's `vite:preloadError` handler reloads first; this is
// the fallback when that reload was skipped (loop guard) or the error was not a preload error.
import { Component } from 'react';
import { ink, ink2 } from '../theme.js';
import { inlineEmptyAction } from './ui/InlineEmpty.jsx';

const CHUNK_ERROR = /ChunkLoadError|Failed to fetch dynamically imported module|Importing a module script failed|error loading dynamically imported module/i;

export function isChunkLoadError(error) {
  return !!error && (error.name === 'ChunkLoadError' || CHUNK_ERROR.test(String(error.message || error)));
}

export default class ChunkErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const T = this.props.T || ((vi, en) => en);
    const chunk = isChunkLoadError(error);
    return (
      <div role="alert" data-testid="chunk-error" style={{
        minHeight: '60dvh', padding: '48px 24px', display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', gap: 8, textAlign: 'center', color: ink,
      }}>
        <div style={{ fontSize: 17, fontWeight: 600 }}>
          {chunk ? T('banbe vừa được cập nhật', 'banbe was just updated') : T('Màn hình này chưa mở được', 'This screen could not open')}
        </div>
        <p style={{ margin: 0, fontSize: 14, lineHeight: 1.45, color: ink2, maxWidth: 320 }}>
          {T('Tải lại để tiếp tục.', 'Reload to carry on.')}
        </p>
        <button type="button" className="bb-press" onClick={() => window.location.reload()} style={{ ...inlineEmptyAction, marginTop: 8 }}>
          {T('Tải lại', 'Reload')}
        </button>
      </div>
    );
  }
}
