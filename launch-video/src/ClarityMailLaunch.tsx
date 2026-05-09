import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const fps = 24;
const black = '#030302';
const nearBlack = '#090806';
const ivory = '#f5efe6';
const warmIvory = '#fff7eb';
const muted = '#9d9184';
const dim = '#5e564d';
const amber = '#d47a32';
const deepAmber = '#6f3418';
const green = '#214b3f';
const lineDark = 'rgba(255, 242, 224, 0.09)';
const lineLight = 'rgba(42, 34, 25, 0.14)';

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const ease = Easing.bezier(0.45, 0, 0.55, 1);
const softOut = Easing.bezier(0.16, 1, 0.3, 1);

const t = (seconds: number) => seconds * fps;

const fade = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {...clamp, easing: ease});

const fadeOut = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [1, 0], {...clamp, easing: ease});

const drift = (frame: number, start: number, end: number, from: number, to: number) =>
  interpolate(frame, [start, end], [from, to], {...clamp, easing: ease});

type Theme = 'dark' | 'light';

type Mail = {
  initials: string;
  sender: string;
  subject: string;
  preview: string;
  time: string;
  label?: string;
  important?: boolean;
};

const mail: Mail[] = [
  {
    initials: 'AR',
    sender: 'Amazon Relay',
    subject: 'Invoice ready for review',
    preview: 'Work period Apr 26 - May 2. Review before settlement.',
    time: '11:25 PM',
    label: 'IMPORTANT',
    important: true,
  },
  {
    initials: 'F',
    sender: 'FedEx',
    subject: 'Service disruption',
    preview: 'Weather may affect shipments leaving today.',
    time: '9:20 AM',
    label: 'ACTION',
    important: true,
  },
  {
    initials: 'C',
    sender: 'Chase',
    subject: 'Monthly statement available',
    preview: 'Your statement is ready.',
    time: '8:44 AM',
  },
  {
    initials: 'P',
    sender: 'Plaid',
    subject: 'Product update',
    preview: 'New tools for monitoring fraud signals.',
    time: '8:13 AM',
  },
  {
    initials: 'U',
    sender: 'USPS',
    subject: 'Mail arriving today',
    preview: 'Your informed delivery preview is ready.',
    time: '7:47 AM',
  },
];

const chaosSnippets = [
  '14 unread',
  'delivery update',
  'receipt',
  'new login',
  'promotion',
  'newsletter',
  'statement',
  'reminder',
  'security alert',
  'invoice',
  'follow up',
  'muted',
];

export const ClarityMailLaunch: React.FC = () => {
  return (
    <AbsoluteFill style={{background: black}}>
      <AudioDesign />
      <FilmTexture />

      <Sequence from={0} durationInFrames={t(4)}>
        <ChaosScene />
      </Sequence>

      <Sequence from={t(4)} durationInFrames={t(2)}>
        <ReliefScene />
      </Sequence>

      <Sequence from={t(6)} durationInFrames={t(10)}>
        <ExperienceScene />
      </Sequence>

      <Sequence from={t(16)} durationInFrames={t(3)}>
        <IconicTransition />
      </Sequence>

      <Sequence from={t(19)} durationInFrames={t(3)}>
        <EndFrame />
      </Sequence>
    </AbsoluteFill>
  );
};

const AudioDesign: React.FC = () => {
  return (
    <>
      <Sequence from={0}>
        <Audio
          src={staticFile('audio/notifications.wav')}
          volume={(f) => interpolate(f, [0, t(3.25), t(3.48)], [0.22, 0.82, 0], clamp)}
        />
      </Sequence>
      <Sequence from={t(4)}>
        <Audio
          src={staticFile('audio/ambient.wav')}
          volume={(f) => interpolate(f, [0, t(2), t(16.7), t(18)], [0, 0.42, 0.42, 0], clamp)}
        />
      </Sequence>
      <Sequence from={t(8.8)}>
        <Audio src={staticFile('audio/ui-soft.wav')} volume={0.15} />
      </Sequence>
      <Sequence from={t(15.8)}>
        <Audio src={staticFile('audio/light-shift.wav')} volume={0.24} />
      </Sequence>
    </>
  );
};

const ChaosScene: React.FC = () => {
  const frame = useCurrentFrame();
  const push = drift(frame, 0, t(4), 0, 92);
  const intensity = fade(frame, t(0.2), t(2.9));
  const textIn = fade(frame, t(1.7), t(2.7));
  const blackout = fade(frame, t(3.48), t(3.62));

  return (
    <AbsoluteFill style={{background: black, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          inset: -170,
          transform: `scale(${1 + intensity * 0.08}) translate3d(${-push}px, ${push * 0.35}px, 0)`,
          filter: `blur(${14 - intensity * 4}px)`,
          opacity: 0.32 + intensity * 0.46,
        }}
      >
        {chaosSnippets.map((snippet, index) => {
          const x = 8 + ((index * 29) % 86);
          const y = 8 + ((index * 19) % 84);
          const delay = index * 5;
          const pop = fade(frame, t(0.3) + delay, t(1.8) + delay);
          return (
            <div
              key={snippet}
              style={{
                position: 'absolute',
                left: `${x}%`,
                top: `${y}%`,
                width: 270 + (index % 3) * 90,
                minHeight: 76,
                borderRadius: 18,
                border: '1px solid rgba(255,255,255,0.08)',
                background: 'rgba(255,255,255,0.035)',
                color: 'rgba(255,245,232,0.56)',
                padding: '18px 22px',
                fontSize: 24,
                letterSpacing: 2.8,
                textTransform: 'uppercase',
                opacity: pop,
                boxShadow: '0 30px 80px rgba(0,0,0,0.42)',
              }}
            >
              <div style={{fontWeight: 800}}>{snippet}</div>
              <div style={{height: 9, width: '78%', background: 'rgba(255,255,255,0.08)', marginTop: 14}} />
              <div style={{height: 9, width: '48%', background: 'rgba(255,255,255,0.06)', marginTop: 10}} />
            </div>
          );
        })}
      </div>

      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(circle at 50% 48%, rgba(212,122,50,0.12), transparent 34%), radial-gradient(circle at 50% 50%, transparent 0%, rgba(0,0,0,0.72) 76%)',
        }}
      />

      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          opacity: textIn * fadeOut(frame, t(3.32), t(3.55)),
          transform: `translateY(${drift(frame, t(1.7), t(3.35), 24, 0)}px)`,
        }}
      >
        <SerifText size={72}>Email became noise.</SerifText>
      </div>

      <AbsoluteFill style={{background: black, opacity: blackout}} />
    </AbsoluteFill>
  );
};

const ReliefScene: React.FC = () => {
  const frame = useCurrentFrame();
  const reveal = fade(frame, t(0.55), t(1.8));
  const y = drift(frame, 0, t(2), 36, -8);

  return (
    <AbsoluteFill style={{background: black, overflow: 'hidden'}}>
      <AmberGlow opacity={reveal * 0.7} />
      <div
        style={{
          position: 'absolute',
          left: 102,
          right: 102,
          top: 236 + y,
          opacity: reveal,
          transform: `scale(${drift(frame, 0, t(2), 0.965, 1)})`,
        }}
      >
        <MacWindow theme="dark" crop="hero" />
      </div>
    </AbsoluteFill>
  );
};

const ExperienceScene: React.FC = () => {
  const frame = useCurrentFrame();
  const cameraX = drift(frame, 0, t(10), -22, 28);
  const cameraY = drift(frame, 0, t(10), 20, -24);
  const zoom = drift(frame, 0, t(10), 1.015, 1.065);
  const light = fade(frame, t(7.1), t(8.7)) * fadeOut(frame, t(9.3), t(10));

  return (
    <AbsoluteFill style={{background: black, overflow: 'hidden'}}>
      <AmberGlow opacity={0.62} />
      <Dust />
      <div
        style={{
          position: 'absolute',
          left: 88,
          right: 88,
          top: 214,
          transform: `translate3d(${cameraX}px, ${cameraY}px, 0) scale(${zoom})`,
        }}
      >
        <MacWindow theme={light > 0.5 ? 'light' : 'dark'} progress={frame} />
      </div>

      <FloatingWord word="Calm." start={t(1.2)} end={t(2.9)} />
      <FloatingWord word="Focused." start={t(4.1)} end={t(5.8)} />
      <FloatingWord word="Readable." start={t(6.5)} end={t(8.15)} />

      <CursorMotion />
      <EmailOpenOverlay />
      <ComposeGlow />
    </AbsoluteFill>
  );
};

const IconicTransition: React.FC = () => {
  const frame = useCurrentFrame();
  const p = fade(frame, 0, t(3));
  const lightOpacity = fadeOut(frame, t(0.1), t(2.35));
  const darkOpacity = fade(frame, t(0.65), t(2.55));

  return (
    <AbsoluteFill style={{background: black, overflow: 'hidden'}}>
      <div style={{position: 'absolute', inset: 0, background: ivory, opacity: lightOpacity}} />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: darkOpacity,
          background:
            'radial-gradient(circle at 50% 38%, rgba(212,122,50,0.28), transparent 34%), linear-gradient(180deg, #100906, #030302 68%)',
        }}
      />
      <Dust strong />
      <div
        style={{
          position: 'absolute',
          left: 76,
          right: 76,
          top: 250,
          transform: `scale(${interpolate(p, [0, 1], [0.99, 1.045], clamp)}) translateY(${interpolate(p, [0, 1], [24, -34], clamp)}px)`,
          opacity: interpolate(p, [0, 0.2, 1], [0, 1, 1], clamp),
          filter: `drop-shadow(0 0 ${24 + p * 54}px rgba(212,122,50,${0.13 + p * 0.17}))`,
        }}
      >
        <MacWindow theme={p < 0.47 ? 'light' : 'dark'} transitionGlow={p} />
      </div>
    </AbsoluteFill>
  );
};

const EndFrame: React.FC = () => {
  const frame = useCurrentFrame();
  const first = fade(frame, t(0.2), t(1.05)) * fadeOut(frame, t(1.68), t(2.1));
  const brand = fade(frame, t(1.7), t(2.45));

  return (
    <AbsoluteFill style={{background: black, alignItems: 'center', justifyContent: 'center'}}>
      <AmberGlow opacity={0.18 * brand} />
      <div
        style={{
          position: 'absolute',
          top: 760,
          left: 90,
          right: 90,
          textAlign: 'center',
          opacity: first,
        }}
      >
        <SerifText size={50}>Email was never designed for humans.</SerifText>
      </div>
      <div
        style={{
          position: 'absolute',
          top: 884,
          left: 0,
          right: 0,
          textAlign: 'center',
          opacity: brand,
          filter: 'drop-shadow(0 0 36px rgba(212,122,50,0.25))',
        }}
      >
        <SerifText size={72}>ClarityMail</SerifText>
      </div>
    </AbsoluteFill>
  );
};

const MacWindow: React.FC<{
  theme: Theme;
  crop?: 'hero';
  progress?: number;
  transitionGlow?: number;
}> = ({theme, crop, progress = 0, transitionGlow = 0}) => {
  const dark = theme === 'dark';
  const bg = dark ? '#0b0907' : '#f5efe6';
  const text = dark ? ivory : black;
  const sub = dark ? '#9c9185' : '#766f66';
  const divider = dark ? lineDark : lineLight;
  const rowBg = dark ? 'rgba(255,246,233,0.035)' : 'rgba(255, 238, 222, 0.56)';
  const scroll = progress ? drift(progress, t(1.5), t(5.9), 0, -106) : 0;

  return (
    <div
      style={{
        width: 936,
        height: crop === 'hero' ? 990 : 1280,
        borderRadius: 42,
        overflow: 'hidden',
        background: bg,
        color: text,
        border: `1px solid ${dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.1)'}`,
        boxShadow: `${dark ? '0 70px 160px rgba(0,0,0,0.72)' : '0 70px 150px rgba(48,38,28,0.32)'}, inset 0 1px 0 rgba(255,255,255,${dark ? 0.08 : 0.65})`,
        position: 'relative',
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: dark
            ? `radial-gradient(circle at 76% 0%, rgba(212,122,50,${0.14 + transitionGlow * 0.22}), transparent 34%)`
            : `radial-gradient(circle at 75% 0%, rgba(212,122,50,${0.12 + transitionGlow * 0.18}), transparent 38%)`,
          pointerEvents: 'none',
        }}
      />
      <WindowChrome dark={dark} />
      <div style={{padding: '82px 64px 56px'}}>
        <div
          style={{
            fontFamily: 'Georgia, Times New Roman, serif',
            fontSize: 102,
            fontStyle: 'italic',
            fontWeight: 900,
            letterSpacing: -1,
            lineHeight: 0.92,
          }}
        >
          Inbox
        </div>
        <div style={{marginTop: 34, color: sub, fontSize: 19, letterSpacing: 5.5, fontWeight: 800}}>
          41 UNREAD OF 50 - CLARITY
        </div>
        <div style={{display: 'flex', gap: 34, marginTop: 42, fontSize: 21, letterSpacing: 5, fontWeight: 900}}>
          {['PRIORITY', 'INBOX', 'SENT', 'DRAFTS'].map((item) => (
            <span key={item} style={{color: item === 'INBOX' ? text : sub}}>
              {item}
            </span>
          ))}
        </div>
        <div
          style={{
            marginTop: 34,
            height: 70,
            borderRadius: 13,
            border: `1px solid ${divider}`,
            color: sub,
            display: 'flex',
            alignItems: 'center',
            padding: '0 24px',
            fontSize: 24,
            background: dark ? 'rgba(255,255,255,0.018)' : 'rgba(255,255,255,0.42)',
          }}
        >
          Filter inbox
          <span style={{marginLeft: 'auto', letterSpacing: 4, fontSize: 16, color: dark ? '#c7b8a7' : sub}}>
            ALL INBOXES
          </span>
        </div>

        <div style={{marginTop: 32, height: crop === 'hero' ? 620 : 790, overflow: 'hidden'}}>
          <div style={{transform: `translateY(${scroll}px)`}}>
            {mail.map((item, index) => (
              <MailRow
                key={item.sender}
                mail={item}
                index={index}
                text={text}
                sub={sub}
                divider={divider}
                rowBg={index === 0 ? rowBg : 'transparent'}
                dark={dark}
              />
            ))}
          </div>
        </div>
      </div>
      <button
        style={{
          position: 'absolute',
          right: 42,
          bottom: 34,
          border: 0,
          borderRadius: 13,
          background: dark ? warmIvory : black,
          color: dark ? black : warmIvory,
          padding: '22px 34px',
          fontFamily: 'Georgia, Times New Roman, serif',
          fontWeight: 900,
          fontSize: 27,
          boxShadow: transitionGlow
            ? `0 0 ${26 + transitionGlow * 28}px rgba(212,122,50,0.32)`
            : '0 22px 48px rgba(0,0,0,0.25)',
        }}
      >
        Compose
      </button>
    </div>
  );
};

const WindowChrome: React.FC<{dark: boolean}> = ({dark}) => (
  <div
    style={{
      position: 'absolute',
      top: 18,
      left: 0,
      right: 0,
      height: 34,
      display: 'flex',
      alignItems: 'center',
      paddingLeft: 28,
      gap: 13,
      opacity: 0.88,
      color: dark ? '#ded0c1' : '#645a50',
      fontSize: 16,
      fontWeight: 800,
    }}
  >
    <span style={{width: 18, height: 18, borderRadius: 99, background: '#d95d54'}} />
    <span style={{width: 18, height: 18, borderRadius: 99, background: '#d8ae2f'}} />
    <span style={{width: 18, height: 18, borderRadius: 99, background: '#37a86b'}} />
    <span style={{marginLeft: 22}}>ClarityMail</span>
  </div>
);

const MailRow: React.FC<{
  mail: Mail;
  index: number;
  text: string;
  sub: string;
  divider: string;
  rowBg: string;
  dark: boolean;
}> = ({mail: item, index, text, sub, divider, rowBg, dark}) => {
  const frame = useCurrentFrame();
  const hover = index === 1 ? fade(frame, t(8.8), t(9.45)) * fadeOut(frame, t(10.6), t(11.3)) : 0;

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '64px 1fr 116px',
        gap: 22,
        minHeight: 134,
        padding: '24px 10px',
        borderTop: `1px solid ${divider}`,
        background: hover ? (dark ? 'rgba(255,247,234,0.07)' : 'rgba(255,232,211,0.76)') : rowBg,
        transform: `translateX(${hover * 8}px)`,
        transition: 'none',
      }}
    >
      <div
        style={{
          width: 58,
          height: 58,
          borderRadius: 9,
          background: item.important ? green : dark ? '#191510' : '#fff9ef',
          border: `1px solid ${divider}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'Georgia, serif',
          fontSize: 23,
          fontWeight: 900,
          color: item.important ? warmIvory : text,
        }}
      >
        {item.initials}
      </div>
      <div>
        <div style={{fontSize: 25, fontWeight: 900}}>{item.sender}</div>
        <div style={{fontFamily: 'Georgia, serif', fontSize: 29, fontWeight: 900, lineHeight: 1.05, marginTop: 2}}>
          {item.subject}
        </div>
        <div style={{fontSize: 22, color: sub, marginTop: 8, whiteSpace: 'nowrap', overflow: 'hidden'}}>
          {item.preview}
        </div>
        {item.label ? (
          <span
            style={{
              display: 'inline-block',
              marginTop: 12,
              border: `1px solid ${amber}`,
              color: amber,
              fontSize: 14,
              letterSpacing: 3,
              fontWeight: 900,
              padding: '4px 8px',
            }}
          >
            {item.label}
          </span>
        ) : null}
      </div>
      <div style={{fontSize: 15, letterSpacing: 3, fontWeight: 900, color: sub, paddingTop: 7, textAlign: 'right'}}>
        TODAY
        <br />
        {item.time}
      </div>
    </div>
  );
};

const FloatingWord: React.FC<{word: string; start: number; end: number}> = ({word, start, end}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, start, start + t(0.55)) * fadeOut(frame, end - t(0.55), end);
  const y = drift(frame, start, end, 18, -10);

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 155,
        textAlign: 'center',
        opacity,
        transform: `translateY(${y}px)`,
      }}
    >
      <SerifText size={58}>{word}</SerifText>
    </div>
  );
};

const CursorMotion: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, t(2.2), t(2.9)) * fadeOut(frame, t(6.1), t(7));
  const x = drift(frame, t(2.2), t(6), 730, 610);
  const y = drift(frame, t(2.2), t(6), 1048, 842);

  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        width: 22,
        height: 22,
        opacity,
        transform: 'rotate(-18deg)',
        filter: 'drop-shadow(0 10px 18px rgba(0,0,0,0.42))',
      }}
    >
      <div
        style={{
          width: 0,
          height: 0,
          borderLeft: '11px solid transparent',
          borderRight: '11px solid transparent',
          borderBottom: `31px solid ${warmIvory}`,
        }}
      />
    </div>
  );
};

const EmailOpenOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, t(4.9), t(5.8)) * fadeOut(frame, t(7.1), t(8));
  const y = drift(frame, t(4.9), t(7.4), 44, -4);

  return (
    <div
      style={{
        position: 'absolute',
        left: 176,
        right: 176,
        top: 598 + y,
        opacity,
        borderRadius: 24,
        background: 'rgba(12,10,8,0.88)',
        border: '1px solid rgba(255,242,224,0.13)',
        color: ivory,
        padding: 34,
        boxShadow: '0 44px 100px rgba(0,0,0,0.52)',
        backdropFilter: 'blur(18px)',
      }}
    >
      <div style={{fontSize: 16, letterSpacing: 5, color: amber, fontWeight: 900}}>SUMMARY</div>
      <div style={{fontFamily: 'Georgia, serif', fontSize: 38, fontWeight: 900, lineHeight: 1.04, marginTop: 14}}>
        Review invoice and shipment disruption before noon.
      </div>
      <div style={{fontSize: 22, lineHeight: 1.35, color: '#bfb3a5', marginTop: 18}}>
        Two emails need attention. Everything else can wait.
      </div>
    </div>
  );
};

const ComposeGlow: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, t(3.1), t(3.7)) * fadeOut(frame, t(4.4), t(5.1));
  return (
    <div
      style={{
        position: 'absolute',
        right: 132,
        top: 1432,
        width: 240,
        height: 92,
        borderRadius: 28,
        opacity,
        background: 'radial-gradient(circle, rgba(212,122,50,0.24), transparent 68%)',
        filter: 'blur(4px)',
      }}
    />
  );
};

const SerifText: React.FC<{children: React.ReactNode; size: number}> = ({children, size}) => (
  <div
    style={{
      color: ivory,
      fontFamily: 'Georgia, Times New Roman, serif',
      fontSize: size,
      fontWeight: 500,
      letterSpacing: -0.5,
      lineHeight: 1.04,
      textShadow: '0 0 34px rgba(245,239,230,0.12)',
    }}
  >
    {children}
  </div>
);

const AmberGlow: React.FC<{opacity: number}> = ({opacity}) => (
  <div
    style={{
      position: 'absolute',
      inset: 0,
      opacity,
      background:
        'radial-gradient(circle at 50% 33%, rgba(212,122,50,0.28), transparent 28%), radial-gradient(circle at 50% 66%, rgba(111,52,24,0.17), transparent 38%)',
      filter: 'blur(2px)',
    }}
  />
);

const Dust: React.FC<{strong?: boolean}> = ({strong}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{position: 'absolute', inset: 0, opacity: strong ? 0.45 : 0.27}}>
      {Array.from({length: strong ? 40 : 28}).map((_, index) => {
        const x = (index * 37) % 100;
        const y = (index * 61) % 100;
        const move = Math.sin((frame + index * 11) / 38) * 10;
        return (
          <span
            key={index}
            style={{
              position: 'absolute',
              left: `${x}%`,
              top: `calc(${y}% + ${move}px)`,
              width: index % 5 === 0 ? 3 : 2,
              height: index % 5 === 0 ? 3 : 2,
              borderRadius: 99,
              background: 'rgba(255,235,205,0.42)',
              filter: 'blur(0.7px)',
            }}
          />
        );
      })}
    </div>
  );
};

const FilmTexture: React.FC = () => {
  const frame = useCurrentFrame();
  const grainX = (frame % 7) * -9;
  const grainY = (frame % 5) * -11;

  return (
    <>
      <div
        style={{
          position: 'absolute',
          inset: -80,
          pointerEvents: 'none',
          opacity: 0.07,
          transform: `translate(${grainX}px, ${grainY}px)`,
          backgroundImage:
            'repeating-radial-gradient(circle at 17% 23%, rgba(255,255,255,0.9) 0 1px, transparent 1px 4px), repeating-radial-gradient(circle at 77% 63%, rgba(255,255,255,0.55) 0 1px, transparent 1px 5px)',
          mixBlendMode: 'screen',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          pointerEvents: 'none',
          background: 'radial-gradient(circle at 50% 45%, transparent 44%, rgba(0,0,0,0.62) 100%)',
        }}
      />
    </>
  );
};
