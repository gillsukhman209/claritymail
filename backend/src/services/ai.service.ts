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
