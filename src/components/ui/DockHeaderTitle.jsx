// Note 53 (owner report): the banbe logo + section title at the top of every dock tab (Home, Schedule, Messages,
// Account; Map has its own search header). One component and one set of numbers — logo size, gap, title size, row
// height, page padding — so switching tabs never makes the logo or the title jump. iOS twin: `DockHeaderTitle` in
// apps/ios/BanbeApp/Views/Components.swift (same rule; its numbers follow iOS's own type scale).
import { display } from '../../theme.js';

export const DOCK_HEADER = {
  // Space above the row. A real phone already has its own status bar / safe area (App.jsx pads for it), so this is a small
  // gap (14px); only the desktop phone frame, whose mock status bar sits above the screen, keeps 62px (index.css).
  top: 'var(--bb-dock-top, 14px)',
  side: 20,       // page gutter, each side
  rowHeight: 52,  // every dock header row is this tall, whatever controls sit on its right
  wordmark: 96,
  gap: 10,
  title: 27,
};

/** Logo + title. `wordmark`/`showTitle` only change on Home's narrow-phone fallbacks. */
export default function DockHeaderTitle({ title, testId, wordmark = DOCK_HEADER.wordmark, showTitle = true, as: Tag = 'span' }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: DOCK_HEADER.gap, minWidth: 0 }}>
      {wordmark > 0 && <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: wordmark, height: 'auto', display: 'block', flex: 'none' }} />}
      {showTitle && (
        <Tag data-testid={testId} style={{ ...display(DOCK_HEADER.title), margin: 0, lineHeight: 1.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 }}>
          {title}
        </Tag>
      )}
    </div>
  );
}
