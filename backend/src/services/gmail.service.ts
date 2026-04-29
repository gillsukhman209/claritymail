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

function headerValue(headers: Array<{ name?: string | null; value?: string | null }> | undefined, name: string) {
  return headers?.find((header) => header.name?.toLowerCase() === name.toLowerCase())?.value ?? "";
}

export async function listInboxEmails(account: GmailAccount) {
  const auth = getOAuthClient(account);
  const gmail = google.gmail({ version: "v1", auth });

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
