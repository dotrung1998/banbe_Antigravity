import React from 'react';
import { Composition } from 'remotion';
import { OnboardingScreens, totalFrames } from './OnboardingScreens.jsx';
import { FPS, SHOTS } from './shots.js';

export const RemotionRoot = () => (
  <>
    <Composition
      id="OnboardingWide"
      component={OnboardingScreens}
      durationInFrames={totalFrames()}
      fps={FPS}
      width={1440}
      height={900}
      defaultProps={{ shots: SHOTS }}
    />
    <Composition
      id="OnboardingPhone"
      component={OnboardingScreens}
      durationInFrames={totalFrames()}
      fps={FPS}
      width={390}
      height={844}
      defaultProps={{ shots: SHOTS }}
    />
  </>
);
