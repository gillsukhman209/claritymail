import OpenAI from "openai";

let client: OpenAI | null = null;

function getOpenAIClient() {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  client ??= new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
  });

  return client;
}

export async function summarizeEmail(input: {
  subject: string;
  sender: string;
  body: string;
}) {
  const openai = getOpenAIClient();
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  const body = input.body.slice(0, 12000);

  const completion = await openai.chat.completions.create({
    model,
    messages: [
      {
        role: "system",
        content:
          [
            "You summarize emails for a personal email client.",
            "Return plain text only. No markdown, no bullets, no asterisks.",
            "Use exactly this format:",
            "Summary: one short sentence, max 22 words.",
            "Action: one short sentence only if the user must do something important soon; otherwise write Action: None.",
            "Ignore marketing fluff, tracking text, unsubscribe text, and repeated footer content."
          ].join(" ")
      },
      {
        role: "user",
        content: `Subject: ${input.subject}\nFrom: ${input.sender}\n\nEmail:\n${body}`
      }
    ],
    max_completion_tokens: 220
  });

  return completion.choices[0]?.message?.content?.trim() || "No summary available.";
}

export type MorningBriefEmail = {
  id: string;
  accountEmail?: string;
  sender: string;
  subject: string;
  snippet: string;
  body?: string;
  receivedAt: string;
};

export type MorningBriefItem = {
  id: string;
  sender: string;
  subject: string;
  summary: string;
  action?: string | null;
};

export type MorningBriefSummary = {
  important: MorningBriefItem[];
  needsAction: MorningBriefItem[];
  deadlines: MorningBriefItem[];
  fyi: MorningBriefItem[];
  ignored: MorningBriefItem[];
};

function emptyMorningBriefSummary(): MorningBriefSummary {
  return {
    important: [],
    needsAction: [],
    deadlines: [],
    fyi: [],
    ignored: []
  };
}

function parseMorningBriefJSON(value: string): MorningBriefSummary {
  const jsonStart = value.indexOf("{");
  const jsonEnd = value.lastIndexOf("}");
  if (jsonStart === -1 || jsonEnd === -1 || jsonEnd <= jsonStart) {
    return emptyMorningBriefSummary();
  }

  try {
    const parsed = JSON.parse(value.slice(jsonStart, jsonEnd + 1));
    return {
      important: Array.isArray(parsed.important) ? parsed.important : [],
      needsAction: Array.isArray(parsed.needsAction) ? parsed.needsAction : [],
      deadlines: Array.isArray(parsed.deadlines) ? parsed.deadlines : [],
      fyi: Array.isArray(parsed.fyi) ? parsed.fyi : [],
      ignored: Array.isArray(parsed.ignored) ? parsed.ignored : []
    };
  } catch {
    return emptyMorningBriefSummary();
  }
}

export async function summarizeMorningBrief(input: {
  emails: MorningBriefEmail[];
  windowStart: string;
  windowEnd: string;
  includeNewsletters: boolean;
}): Promise<MorningBriefSummary> {
  if (input.emails.length === 0) {
    return emptyMorningBriefSummary();
  }

  const openai = getOpenAIClient();
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  const emails = input.emails.slice(0, 40).map((email) => ({
    id: email.id,
    accountEmail: email.accountEmail,
    sender: email.sender,
    subject: email.subject,
    receivedAt: email.receivedAt,
    snippet: email.snippet,
    body: (email.body ?? "").slice(0, 1800)
  }));

  const completion = await openai.chat.completions.create({
    model,
    messages: [
      {
        role: "system",
        content: [
          "You create a morning email brief for a personal email client.",
          "Only classify emails from the provided list.",
          "Return valid JSON only. No markdown.",
          "Schema: {\"important\":[],\"needsAction\":[],\"deadlines\":[],\"fyi\":[],\"ignored\":[]}.",
          "Each item must be {\"id\":\"email id\",\"sender\":\"sender\",\"subject\":\"subject\",\"summary\":\"short plain-English summary\",\"action\":\"optional short action or null\"}.",
          "Be strict. Most emails are not important.",
          "Important means personal, financial, legal, medical, security, account access, work, family, appointment, travel, delivery problem, bill, claim, or anything that could cost money/time if missed.",
          "NeedsAction means the user clearly needs to reply, decide, pay, review, sign, attend, call, fix, or follow up.",
          "Deadlines means real appointments, due dates, expirations, scheduled events, payment dates, or time-sensitive required actions.",
          "FYI means useful non-promotional information, but not urgent.",
          "Ignore discounts, coupons, deals, rewards offers, promo codes, sales, marketing, newsletters, recruiting ads, gig-work availability, app engagement emails, social updates, and forwarded promotions.",
          "Do not mark a discount, coupon, deal, or promo as important just because it expires soon.",
          "Do not create an action item for optional shopping, optional signup, optional app usage, optional gig work, or optional promo redemption.",
          "Forwarded promotional emails should still be ignored unless the user's own written message asks for something.",
          input.includeNewsletters
            ? "Newsletters can be included if useful."
            : "Put newsletters, promotions, receipts, ads, tracking, automated updates, and low-value messages in ignored unless clearly important under the strict rules above.",
          "Keep summaries short. Do not duplicate the same email across categories unless it truly has both action and deadline."
        ].join(" ")
      },
      {
        role: "user",
        content: JSON.stringify({
          windowStart: input.windowStart,
          windowEnd: input.windowEnd,
          emails
        })
      }
    ],
    max_completion_tokens: 1800,
    response_format: { type: "json_object" }
  });

  return parseMorningBriefJSON(completion.choices[0]?.message?.content ?? "");
}
