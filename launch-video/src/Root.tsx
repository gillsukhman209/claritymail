import {Composition} from 'remotion';
import {ClarityMailLaunch} from './ClarityMailLaunch';

export const RemotionRoot = () => {
  return (
    <Composition
      id="ClarityMailLaunch"
      component={ClarityMailLaunch}
      durationInFrames={1440}
      fps={30}
      width={1080}
      height={1920}
    />
  );
};
