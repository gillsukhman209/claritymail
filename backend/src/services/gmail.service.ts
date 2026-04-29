import { google } from "googleapis";

type GmailAccount = {
  refreshToken: string;
};

function getOAuthClient(account: GmailAccount) {
  const oauth2Client = new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );

  oauth2Client.setCredentials({
    refresh_token: account.refreshToken
  });

  return oauth2Client;
}

function getGmailClient(account: GmailAccount) {
  return google.gmail({ version: "v1", auth: getOAuthClient(account) });
}

function headerValue(headers: Array<{ name?: string | null; value?: string | null }> | undefined, name: string) {
  return headers?.find((header) => header.name?.toLowerCase() === name.toLowerCase())?.value ?? "";
}

function decodeBase64Url(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(normalized, "base64").toString("utf8");
}

function stripHtml(value: string) {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, "\"")
    .replace(/\s+/g, " ")
    .trim();
}

function findBodyPart(payload: any, mimeType: string): string | null {
  if (!payload) {
    return null;
  }

  if (payload.mimeType === mimeType && payload.body?.data) {
    return decodeBase64Url(payload.body.data);
  }

  for (const part of payload.parts ?? []) {
    const value = findBodyPart(part, mimeType);
    if (value) {
      return value;
    }
  }

  return null;
}

export async function listInboxEmails(account: GmailAccount) {
  const gmail = getGmailClient(account);

  const listResponse = await gmail.users.messages.list({
    userId: "me",
    labelIds: ["INBOX"],
    maxResults: 20
  });

  const messages = listResponse.data.messages ?? [];

  const emails = await Promise.all(
    messages.map(async (message) => {
      const messageResponse = await gmail.users.messages.get({
        userId: "me",
        id: message.id ?? "",
        format: "metadata",
        metadataHeaders: ["Subject", "From", "Date"]
      });

      const data = messageResponse.data;
      const headers = data.payload?.headers;
      const labelIds = data.labelIds ?? [];

      return {
        id: data.id ?? "",
        threadId: data.threadId ?? "",
        subject: headerValue(headers, "Subject") || "(No subject)",
        sender: headerValue(headers, "From") || "Unknown sender",
        snippet: data.snippet ?? "",
        receivedAt: new Date(Number(data.internalDate ?? Date.now())).toISOString(),
        isRead: !labelIds.includes("UNREAD"),
        isStarred: labelIds.includes("STARRED")
      };
    })
  );

  return emails;
}

export async function getEmail(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);

  const messageResponse = await gmail.users.messages.get({
    userId: "me",
    id,
    format: "full"
  });

  const data = messageResponse.data;
  const headers = data.payload?.headers;
  const labelIds = data.labelIds ?? [];
  const plainText = findBodyPart(data.payload, "text/plain");
  const html = findBodyPart(data.payload, "text/html");
  const body = plainText?.trim() || (html ? stripHtml(html) : data.snippet ?? "");

  return {
    id: data.id ?? "",
    threadId: data.threadId ?? "",
    subject: headerValue(headers, "Subject") || "(No subject)",
    sender: headerValue(headers, "From") || "Unknown sender",
    snippet: data.snippet ?? "",
    receivedAt: new Date(Number(data.internalDate ?? Date.now())).toISOString(),
    isRead: !labelIds.includes("UNREAD"),
    isStarred: labelIds.includes("STARRED"),
    body
  };
}

export async function archiveEmail(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.modify({
    userId: "me",
    id,
    requestBody: {
      removeLabelIds: ["INBOX"]
    }
  });
}

export async function trashEmail(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.trash({
    userId: "me",
    id
  });
}

export async function markEmailRead(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.modify({
    userId: "me",
    id,
    requestBody: {
      removeLabelIds: ["UNREAD"]
    }
  });
}

export async function markEmailUnread(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.modify({
    userId: "me",
    id,
    requestBody: {
      addLabelIds: ["UNREAD"]
    }
  });
}

export async function starEmail(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.modify({
    userId: "me",
    id,
    requestBody: {
      addLabelIds: ["STARRED"]
    }
  });
}

export async function unstarEmail(account: GmailAccount, id: string) {
  const gmail = getGmailClient(account);
  await gmail.users.messages.modify({
    userId: "me",
    id,
    requestBody: {
      removeLabelIds: ["STARRED"]
    }
  });
}
