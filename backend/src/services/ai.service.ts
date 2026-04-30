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
          "You summarize emails for a personal email client. Be concise, factual, and useful. Output 2-4 short bullets. Mention action items clearly if any."
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
