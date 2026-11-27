import React from 'react';
import { AbsoluteFill, Img, Sequence, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { SHOTS, FRAMES_PER_SHOT } from './shots.js';
import { camera, captionRise, shotOpacity } from './motion.js';

/**
 * A motion study, not a mockup. Each shot is a screenshot that exists on disk;
 * a shot whose `src` is null becomes a visible capture request instead.
 */
const Shot = ({ shot, duration }) => {
  const frame = useCurrentFrame();
  const { scale, x, y } = camera(shot.move, frame, duration);
  const opacity = shotOpacity(frame, duration);
  const rise = captionRise(frame, duration);

  return (
    <AbsoluteFill style={{ opacity, alignItems: 'center', justifyContent: 'center' }}>
      <div
        style={{
          transform: `translate(${x}, ${y}) scale(${scale})`,
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {shot.src && shot.ready ? (
          <Img
            src={staticFile(shot.src)}
            style={{ maxHeight: '78%', maxWidth: '72%', borderRadius: 28, boxShadow: '0 40px 80px rgba(0,0,0,.45)' }}
          />
        ) : (
          <div
            style={{
              width: 420,
              height: 700,
              borderRadius: 32,
              border: '2px dashed rgba(247,244,236,.45)',
              color: '#F7F4EC',
              fontFamily: 'ui-sans-serif, system-ui, sans-serif',
              fontSize: 20,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 14,
              padding: 32,
              textAlign: 'center',
              background: 'rgba(247,244,236,.05)',
            }}
          >
            <strong style={{ fontSize: 24 }}>Capture: {shot.id}</strong>
            <span style={{ opacity: 0.75 }}>{shot.capture}</span>
            <span style={{ opacity: 0.5, fontSize: 16 }}>public/{shot.src || 'screens/…'} · ready: false</span>
          </div>
        )}
      </div>

      <div
        style={{
          position: 'absolute',
          bottom: 40,
          left: 0,
          right: 0,
          textAlign: 'center',
          transform: `translateY(${rise}px)`,
          color: '#F7F4EC',
          fontFamily: 'ui-serif, Georgia, serif',
          fontSize: 34,
          letterSpacing: 0.4,
          opacity: 0.92,
        }}
      >
        {shot.label}
      </div>
    </AbsoluteFill>
  );
};

export const OnboardingScreens = ({ shots = SHOTS }) => {
  const { fps } = useVideoConfig();
  let from = 0;

  return (
    <AbsoluteFill style={{ background: 'radial-gradient(circle at 50% 40%, #2A2A28 0%, #141412 70%)' }}>
      {shots.map((shot) => {
        const duration = FRAMES_PER_SHOT(shot);
        const start = from;
        from += duration;
        return (
          <Sequence key={shot.id} from={start} durationInFrames={duration} name={shot.id}>
            <Shot shot={shot} duration={duration} fps={fps} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

export const totalFrames = (shots = SHOTS) => shots.reduce((sum, shot) => sum + FRAMES_PER_SHOT(shot), 0);
