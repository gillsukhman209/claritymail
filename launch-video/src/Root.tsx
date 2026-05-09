import {Composition} from 'remotion';
import {ClarityMailLaunch} from './ClarityMailLaunch';

export const RemotionRoot = () => {
  return (
    <Composition
      id="ClarityMailLaunch"
      component={ClarityMailLaunch}
      durationInFrames={528}
      fps={24}
      width={1080}
      height={1920}
    />
  );
};
