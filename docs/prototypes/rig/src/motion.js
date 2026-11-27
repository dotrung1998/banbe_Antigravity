import { interpolate, Easing } from 'remotion';

/** Decelerating push-in: the move a still photo needs to feel filmed. */
export const push = (frame, duration) =>
  interpolate(frame, [0, duration], [1.0, 1.07], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.22, 1, 0.36, 1),
  });

/** Slow horizontal drift, for a tall screen that has more content than frame. */
export const panLeft = (frame, duration, distance = 4) =>
  interpolate(frame, [0, duration], [0, -distance], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.4, 0, 0.2, 1),
  });

/** Settle: arrives slightly large, comes to rest. Reads as "the page landed". */
export const settle = (frame, duration) =>
  interpolate(frame, [0, Math.round(duration * 0.55)], [1.04, 1.0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

/** Caption rise: one line, under the device, never over the content. */
export const captionRise = (frame, duration) =>
  interpolate(frame, [0, Math.round(duration * 0.35)], [14, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.22, 1, 0.36, 1),
  });

/** Cross-fade in/out with a short hold, so two shots never both read as "new". */
export const shotOpacity = (frame, duration, fade = 8) => {
  const enter = interpolate(frame, [0, fade], [0, 1], { extrapolateRight: 'clamp' });
  const exit = interpolate(frame, [duration - fade, duration], [1, 0], { extrapolateLeft: 'clamp' });
  return Math.min(enter, exit);
};

export const camera = (move, frame, duration) => {
  if (move === 'pan-left') return { scale: 1.04, x: panLeft(frame, duration) + '%', y: 0 };
  if (move === 'settle') return { scale: settle(frame, duration), x: 0, y: 0 };
  return { scale: push(frame, duration), x: 0, y: 0 };
};
