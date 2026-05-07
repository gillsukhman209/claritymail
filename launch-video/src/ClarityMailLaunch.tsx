import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Sequence,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const cream = '#f5efe6';
const paper = '#fffaf1';
const ink = '#11100e';
const muted = '#81796f';
const line = '#ded5ca';
const orange = '#d9581f';
const green = '#275f4f';

type Email = {
  initials: string;
  sender: string;
  subject: string;
  preview: string;
  time: string;
  tag?: string;
  color?: string;
};

const emails: Email[] = [
  {
    initials: 'AR',
    sender: 'Amazon Relay',
    subject: 'New invoice is available for work period',
    preview: 'Your Relay invoice statement is available. Review charges before noon.',
    time: '11:25 PM',
    tag: 'IMPORTANT SENDER',
    color: green,
  },
  {
    initials: 'T',
    sender: 'TikTok',
    subject: 'You have 1 new like',
    preview: 'You did it again. New likes on TikTok.',
    time: '9:38 AM',
    tag: 'MUTED SENDER',
    color: green,
  },
  {
    initials: 'F',
    sender: 'FedEx',
    subject: 'National service disruption',
    preview: 'Weather disruptions may impact package delivery in your region.',
    time: '9:20 AM',
    color: ink,
  },
  {
    initials: 'C',
    sender: 'Chase',
    subject: 'Refer friends to Chase',
    preview: 'Share your referral link and earn rewards.',
    time: '9:12 AM',
    color: '#ffffff',
  },
  {
    initials: 'P',
    sender: 'Plaid',
    subject: 'Fight fraud in real time',
    preview: 'Check out 20+ product updates.',
    time: '8:13 AM',
    tag: 'MUTED SENDER',
    color: '#08242f',
  },
  {
    initials: 'U',
    sender: 'USPS Informed Delivery',
    subject: 'Your mail is arriving today',
    preview: 'See what is coming to your mailbox.',
    time: '7:47 AM',
    color: '#756240',
  },
];

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const fade = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, end], [0, 1], {...clamp, easing: ease});

const slideUp = (frame: number, start: number, end: number, distance = 70) =>
  interpolate(frame, [start, end], [distance, 0], {...clamp, easing: ease});

const SceneText: React.FC<{
  kicker?: string;
  title: string;
  body?: string;
  start?: number;
  size?: 'large' | 'medium';
}> = ({kicker, title, body, start = 0}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, start, start + 18);
  const y = slideUp(frame, start, start + 22, 52);

  return (
    <div
      style={{
        opacity,
        transform: `translateY(${y}px)`,
        padding: '0 74px',
        color: ink,
      }}
    >
      {kicker ? <div style={styles.kicker}>{kicker}</div> : null}
      <div style={styles.title}>{title}</div>
      {body ? <div style={styles.body}>{body}</div> : null}
    </div>
  );
};

const BottomCaption: React.FC<{text: string}> = ({text}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, 0, 18);
  const y = slideUp(frame, 0, 20, 28);

  return (
    <div
      style={{
        position: 'absolute',
        left: 72,
        right: 72,
        bottom: 82,
        opacity,
        transform: `translateY(${y}px)`,
        background: 'rgba(255, 250, 241, 0.94)',
        border: `2px solid ${line}`,
        borderRadius: 18,
        padding: '24px 28px',
        fontFamily: 'Georgia, serif',
        fontSize: 42,
        fontWeight: 900,
        lineHeight: 1.05,
        boxShadow: '0 18px 45px rgba(55, 42, 28, 0.16)',
      }}
    >
      {text}
    </div>
  );
};

const PhoneShell: React.FC<{
  children: React.ReactNode;
  scale?: number;
  y?: number;
}> = ({children, scale = 1, y = 0}) => {
  return (
    <div
      style={{
        width: 780,
        height: 1380,
        borderRadius: 72,
        background: '#0f0e0c',
        padding: 18,
        boxShadow: '0 34px 90px rgba(17, 16, 14, 0.28)',
        transform: `scale(${scale}) translateY(${y}px)`,
        transformOrigin: 'center top',
      }}
    >
      <div
        style={{
          height: '100%',
          borderRadius: 56,
          overflow: 'hidden',
          background: cream,
          position: 'relative',
        }}
      >
        {children}
      </div>
    </div>
  );
};

const InboxScreen: React.FC<{dimLowPriority?: boolean}> = ({dimLowPriority}) => {
  return (
    <div style={{height: '100%', padding: '60px 48px', background: cream}}>
      <div style={{fontFamily: 'Georgia, serif', fontSize: 92, fontStyle: 'italic', fontWeight: 800}}>
        Inbox
      </div>
      <div style={{...styles.kicker, marginTop: 20}}>41 UNREAD OF 50 - @SUKHMANSINGH1603</div>
      <div style={{display: 'flex', gap: 32, marginTop: 34, fontSize: 21, fontWeight: 900, letterSpacing: 5}}>
        <span style={{color: muted}}>PRIORITY</span>
        <span>INBOX</span>
        <span style={{color: muted}}>SENT</span>
      </div>
      <div
        style={{
          marginTop: 32,
          height: 58,
          border: `2px solid ${line}`,
          borderRadius: 12,
          display: 'flex',
          alignItems: 'center',
          padding: '0 22px',
          color: muted,
          fontSize: 24,
        }}
      >
        Filter inbox
      </div>
      <div style={{marginTop: 28}}>
        {emails.map((email, index) => {
          const low = index > 0;
          return (
            <EmailRow
              key={email.sender}
              email={email}
              index={index}
              opacity={dimLowPriority && low ? 0.24 : 1}
              highlight={index === 0}
            />
          );
        })}
      </div>
      <button
        style={{
          position: 'absolute',
          right: 42,
          bottom: 40,
          background: ink,
          color: paper,
          border: 0,
          borderRadius: 10,
          fontSize: 26,
          fontFamily: 'Georgia, serif',
          fontWeight: 800,
          padding: '22px 34px',
        }}
      >
        Compose -&gt;
      </button>
    </div>
  );
};

const EmailRow: React.FC<{
  email: Email;
  index: number;
  opacity: number;
  highlight: boolean;
}> = ({email, index, opacity, highlight}) => {
  const frame = useCurrentFrame();
  const rowIn = fade(frame, 118 + index * 8, 142 + index * 8);
  const y = slideUp(frame, 118 + index * 8, 142 + index * 8, 26);

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '64px 1fr 126px',
        gap: 20,
        alignItems: 'start',
        borderTop: `1px solid ${line}`,
        minHeight: 122,
        padding: '22px 0',
        opacity: rowIn * opacity,
        transform: `translateY(${y}px)`,
        background: highlight ? '#fff3e9' : 'transparent',
      }}
    >
      <div
        style={{
          width: 58,
          height: 58,
          borderRadius: 7,
          background: email.color ?? green,
          color: email.sender === 'Chase' ? '#0062b2' : paper,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'Georgia, serif',
          fontSize: 24,
          fontWeight: 900,
        }}
      >
        {email.initials}
      </div>
      <div>
        <div style={{fontSize: 25, fontWeight: 900}}>{email.sender}</div>
        <div style={{fontFamily: 'Georgia, serif', fontSize: 27, fontWeight: 900, lineHeight: 1.08}}>
          {email.subject}
        </div>
        <div style={{fontSize: 21, color: muted, marginTop: 6, whiteSpace: 'nowrap', overflow: 'hidden'}}>
          {email.preview}
        </div>
        {email.tag ? <span style={styles.tag}>{email.tag}</span> : null}
      </div>
      <div style={{fontSize: 15, letterSpacing: 3, fontWeight: 900, color: muted, paddingTop: 8}}>
        TODAY<br />{email.time}
      </div>
    </div>
  );
};

const MorningBrief: React.FC = () => {
  const frame = useCurrentFrame();
  const cardIn = spring({frame: frame - 34, fps: 30, config: {damping: 18, stiffness: 95}});
  const scale = interpolate(cardIn, [0, 1], [0.92, 1], clamp);
  const opacity = interpolate(cardIn, [0, 1], [0, 1], clamp);

  return (
    <div style={{height: '100%', padding: '74px 54px', background: cream}}>
      <div style={styles.kicker}>9:00 AM MORNING BRIEF</div>
      <div style={{fontFamily: 'Georgia, serif', fontSize: 72, fontStyle: 'italic', fontWeight: 900, marginTop: 18}}>
        7 PM - 9 AM
      </div>
      <div style={{fontSize: 26, color: muted, marginTop: 16}}>Unread overnight emails, ranked by what matters.</div>
      <div
        style={{
          opacity,
          transform: `scale(${scale})`,
          transformOrigin: 'center top',
          background: paper,
          border: `2px solid ${line}`,
          borderRadius: 22,
          marginTop: 42,
          padding: 30,
          boxShadow: '0 24px 55px rgba(55, 42, 28, 0.13)',
        }}
      >
        <BriefSection
          delay={72}
          label="IMPORTANT"
          title="Amazon Relay invoice needs review"
          detail="New invoice is ready for the Apr 26 - May 2 work period."
          accent={orange}
        />
        <BriefSection
          delay={118}
          label="NEEDS ACTION"
          title="Check FedEx disruption"
          detail="Weather may affect shipments. Review anything going out today."
          accent={green}
        />
        <BriefSection
          delay={164}
          label="CAN WAIT"
          title="18 low-priority emails skipped"
          detail="Likes, product updates, referrals, promos, and routine notices."
          accent={muted}
        />
      </div>
    </div>
  );
};

const BriefSection: React.FC<{
  delay: number;
  label: string;
  title: string;
  detail: string;
  accent: string;
}> = ({delay, label, title, detail, accent}) => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, delay, delay + 22);
  const y = slideUp(frame, delay, delay + 24, 22);

  return (
    <div
      style={{
        opacity,
        transform: `translateY(${y}px)`,
        borderTop: `1px solid ${line}`,
        padding: '24px 0',
      }}
    >
      <div style={{...styles.kicker, color: accent}}>{label}</div>
      <div style={{fontFamily: 'Georgia, serif', fontWeight: 900, fontSize: 35, lineHeight: 1.05, marginTop: 8}}>
        {title}
      </div>
      <div style={{fontSize: 24, color: muted, lineHeight: 1.32, marginTop: 10}}>{detail}</div>
    </div>
  );
};

const NotificationScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pulse = interpolate(Math.sin(frame / 9), [-1, 1], [0.96, 1.02]);

  return (
    <AbsoluteFill style={{background: ink, color: paper, justifyContent: 'center', alignItems: 'center'}}>
      <div style={{width: 840, transform: `scale(${pulse})`}}>
        <div style={{fontSize: 26, letterSpacing: 5, color: '#b9ab9b', fontWeight: 900}}>CLARITYMAIL</div>
        <div style={{fontFamily: 'Georgia, serif', fontSize: 82, fontWeight: 900, lineHeight: 1.05, marginTop: 28}}>
          Morning Brief ready.
        </div>
        <div style={{fontSize: 38, lineHeight: 1.25, marginTop: 34, color: '#e7ded2'}}>
          3 important emails. 2 need action. 18 can wait.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CTA: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = fade(frame, 0, 24);

  return (
    <AbsoluteFill style={{background: cream, opacity, padding: 78, justifyContent: 'center'}}>
      <div style={{...styles.kicker, color: orange}}>BUILDING IN PUBLIC</div>
      <div style={{fontFamily: 'Georgia, serif', fontSize: 104, fontStyle: 'italic', fontWeight: 900, lineHeight: 0.96, marginTop: 26}}>
        I want email to feel calm again.
      </div>
      <div style={{fontSize: 38, color: muted, lineHeight: 1.25, marginTop: 42}}>
        Want early access to ClarityMail?
      </div>
      <div
        style={{
          marginTop: 54,
          background: ink,
          color: paper,
          width: 'fit-content',
          borderRadius: 14,
          padding: '28px 38px',
          fontFamily: 'Georgia, serif',
          fontSize: 42,
          fontWeight: 900,
        }}
      >
        Reply "Clarity"
      </div>
    </AbsoluteFill>
  );
};

export const ClarityMailLaunch: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const phoneY = interpolate(frame, [5 * fps, 7 * fps], [110, 0], {...clamp, easing: ease});
  const phoneOpacity = fade(frame, 140, 178);

  return (
    <AbsoluteFill style={{background: cream, fontFamily: 'Inter, Arial, sans-serif', overflow: 'hidden'}}>
      <Sequence from={0} durationInFrames={150}>
        <AbsoluteFill style={{justifyContent: 'center'}}>
          <SceneText
            kicker="EVERY MORNING"
            title="I wake up to 41 unread emails."
            body="But only a few actually matter."
          />
        </AbsoluteFill>
      </Sequence>

      <Sequence from={145} durationInFrames={385}>
        <AbsoluteFill style={{alignItems: 'center', paddingTop: 238, opacity: phoneOpacity}}>
          <PhoneShell scale={0.93} y={phoneY}>
            <InboxScreen />
          </PhoneShell>
        </AbsoluteFill>
      </Sequence>

      <Sequence from={340} durationInFrames={150}>
        <AbsoluteFill>
          <BottomCaption text="Most of it is noise. One email actually matters." />
        </AbsoluteFill>
      </Sequence>

      <Sequence from={530} durationInFrames={380}>
        <AbsoluteFill style={{alignItems: 'center', paddingTop: 122}}>
          <PhoneShell scale={0.96}>
            <MorningBrief />
          </PhoneShell>
        </AbsoluteFill>
      </Sequence>

      <Sequence from={805} durationInFrames={170}>
        <AbsoluteFill style={{justifyContent: 'flex-end', paddingBottom: 90}}>
          <SceneText
            kicker="SO I BUILT"
            title="An AI email client that gives me the brief first."
            body="Important. Needs action. Can wait."
            start={0}
          />
        </AbsoluteFill>
      </Sequence>

      <Sequence from={980} durationInFrames={190}>
        <NotificationScene />
      </Sequence>

      <Sequence from={1145} durationInFrames={295}>
        <CTA />
      </Sequence>
    </AbsoluteFill>
  );
};

const styles = {
  kicker: {
    fontSize: 24,
    letterSpacing: 7,
    fontWeight: 900,
    color: muted,
  },
  title: {
    fontFamily: 'Georgia, serif',
    fontSize: 92,
    fontWeight: 900,
    fontStyle: 'italic',
    lineHeight: 0.98,
    letterSpacing: 0,
  },
  body: {
    fontSize: 36,
    lineHeight: 1.22,
    color: muted,
    marginTop: 32,
    maxWidth: 820,
  },
  tag: {
    display: 'inline-block',
    marginTop: 10,
    border: `2px solid ${orange}`,
    color: orange,
    fontSize: 14,
    letterSpacing: 3,
    fontWeight: 900,
    padding: '3px 7px',
  },
} satisfies Record<string, React.CSSProperties>;
