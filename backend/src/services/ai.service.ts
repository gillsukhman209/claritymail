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

export type PriorityClassificationInput = {
  id: string;
  sender: string;
  subject: string;
  snippet: string;
  body?: string;
  receivedAt: string;
};

export type PriorityClassification = {
  id: string;
  status: "important" | "normal" | "ignored";
  reason: string;
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

function parsePriorityJSON(value: string, fallbackIds: string[]): PriorityClassification[] {
  const jsonStart = value.indexOf("{");
  const jsonEnd = value.lastIndexOf("}");
  if (jsonStart === -1 || jsonEnd === -1 || jsonEnd <= jsonStart) {
    return fallbackIds.map((id) => ({ id, status: "normal", reason: "" }));
  }

  try {
    const parsed = JSON.parse(value.slice(jsonStart, jsonEnd + 1));
    const items = Array.isArray(parsed.emails) ? parsed.emails : [];
    return fallbackIds.map((id) => {
      const item = items.find((candidate: any) => String(candidate.id) === id);
      const status =
        item?.status === "important" || item?.status === "ignored" || item?.status === "normal"
          ? item.status
          : "normal";
      return {
        id,
        status,
        reason: String(item?.reason ?? "").slice(0, 90)
      };
    });
  } catch {
    return fallbackIds.map((id) => ({ id, status: "normal", reason: "" }));
  }
}

export async function classifyEmailPriorityBatch(input: { emails: PriorityClassificationInput[] }) {
  if (input.emails.length === 0) return [];

  const openai = getOpenAIClient();
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  const emails = input.emails.slice(0, 30).map((email) => ({
    id: email.id,
    sender: email.sender,
    subject: email.subject,
    receivedAt: email.receivedAt,
    snippet: email.snippet,
    body: (email.body ?? "").slice(0, 900)
  }));

  const completion = await openai.chat.completions.create({
    model,
    messages: [
      {
        role: "system",
        content: [
          "You classify emails for a personal email client Priority Mode.",
          "Return valid JSON only. No markdown.",
          "Schema: {\"emails\":[{\"id\":\"email id\",\"status\":\"important|normal|ignored\",\"reason\":\"short reason\"}]}",
          "Be strict. Most emails are normal or ignored, not important.",
          "Important means the user likely loses money, misses an appointment, misses a required action, or misses a direct personal/work/client/legal/medical/security/insurance/billing issue.",
          "Financial is important only for real account activity, fraud/security, due payments, failed payments, direct deposits, bills, claims, or required review.",
          "Security or fraud content is important only when it is about the user's own account, login, password, card, identity, transaction, or required action.",
          "Security/fraud marketing is ignored, including reports, guides, research, tools, shared intel, webinars, and downloads.",
          "Financial marketing is ignored, including card offers, money-saving features, rewards, free credits, pre-qualification, car finance ads, loans, promos, discounts, and shopping suggestions.",
          "Ignored means: discounts, coupons, promo codes, sales, newsletters, marketing, rewards offers, social/app engagement, gig-work availability, optional waitlists, optional recruiting ads, generic receipts, automated low-value updates, and optional shopping/car listings.",
          "Normal means useful but not urgent enough for Priority.",
          "Do not mark a promo, discount, deal, optional signup, optional gig-work offer, newsletter, or forwarded promotion as important just because it expires soon.",
          "Do not mark an email important just because it contains the words reply, confirmation, account, finance, fraud, claim, expires, credits, report, waitlist, or review.",
          "Reasons must be short and user-facing, like 'Appointment today', 'Needs reply', 'Payment issue', or empty for ignored/normal."
        ].join(" ")
      },
      {
        role: "user",
        content: JSON.stringify({ emails })
      }
    ],
    max_completion_tokens: 1200,
    response_format: { type: "json_object" }
  });

  return parsePriorityJSON(completion.choices[0]?.message?.content ?? "", emails.map((email) => email.id));
}
