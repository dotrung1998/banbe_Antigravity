import { useEffect, useRef } from 'react';
import { useGoc } from '../state/GocContext.jsx';

// TASK 1 (dock "+" menu pass) — the story photo/camera picker + Retake/Use
// Photo preview, mounted ONCE, globally (Shell/App.jsx, next to
// DockCreateButton) instead of living inside Account.jsx only. Both
// Account.jsx's own "▪︎ Đăng story" menu and the dock "+" menu
// (DockCreateButton.jsx — a different, always-mounted component, not a
// child of Account) drive the SAME `s.storyLibraryPickerOpen`/
// `s.storyCameraPickerOpen`/`s.storyCreatePreview` state (GocContext) —
// one upload pipeline, reachable from any screen. `position: fixed` (not
// Account's old `position: absolute` relative to its own screen div) since
// this can now open while a different screen is mounted underneath.
export default function StoryCreateOverlay() {
  const { state, T, pickStoryFile, cancelStoryCreate, publishStory, openStoryCameraPicker, closeStoryPickerRequests } = useGoc();
  const s = state;
  const libraryRef = useRef(null);
  const cameraRef = useRef(null);

  useEffect(() => {
    if (s.storyLibraryPickerOpen) {
      libraryRef.current?.click();
      closeStoryPickerRequests();
    }
  }, [s.storyLibraryPickerOpen, closeStoryPickerRequests]);
  useEffect(() => {
    if (s.storyCameraPickerOpen) {
      cameraRef.current?.click();
      closeStoryPickerRequests();
    }
  }, [s.storyCameraPickerOpen, closeStoryPickerRequests]);

  const onPickFile = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) pickStoryFile(file);
  };

  return (
    <>
      <input ref={libraryRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={onPickFile} data-testid="story-file-input" />
      <input ref={cameraRef} type="file" accept="image/*" capture="environment" style={{ display: 'none' }} onChange={onPickFile} data-testid="story-camera-input" />

      {s.storyCreatePreview && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 70, background: '#000', display: 'flex', flexDirection: 'column' }} data-testid="story-create-preview">
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
            <img src={s.storyCreatePreview.url} alt="" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
          </div>
          <div style={{ padding: '16px 22px 34px', display: 'flex', gap: 10 }}>
            <div
              onClick={s.storyCreateBusy ? undefined : () => { cancelStoryCreate(); openStoryCameraPicker(); }}
              data-testid="story-retake"
              style={{ flex: 1, textAlign: 'center', padding: '13px', borderRadius: 12, border: '1px solid rgba(255,255,255,0.35)', color: '#fff', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}
            >
              {T('Chụp lại', 'Retake')}
            </div>
            <div
              onClick={s.storyCreateBusy ? undefined : () => { publishStory(); }}
              data-testid="story-use-photo"
              style={{ flex: 1, textAlign: 'center', padding: '13px', borderRadius: 12, background: '#fff', color: '#000', fontSize: 13.5, fontWeight: 600, cursor: 'pointer', opacity: s.storyCreateBusy ? 0.6 : 1 }}
            >
              {s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('Dùng ảnh', 'Use photo')}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
