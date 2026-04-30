import { google } from "googleapis";

type GmailAccount = {
  id?: string;
  email?: string;
  refreshToken: string;
  lastHistoryId?: string | null;
};

export type MailboxFolder = "inbox" | "sent" | "archive" | "trash";

export type EmailAttachment = {
  filename: string;
  mimeType: string;
  data: string;
};

type SendInput = {
  to: string;
  subject?: string;
  body: string;
  attachments?: EmailAttachment[];
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

function encodeBase64Url(value: string | Buffer) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function encodeHeader(value: string) {
  if (/^[\x00-\x7F]*$/.test(value)) {
    return value;
  }

  return `=?UTF-8?B?${Buffer.from(value, "utf8").toString("base64")}?=`;
}

function escapeMimeValue(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
}

function chunkBase64(value: string) {
  return value.match(/.{1,76}/g)?.join("\r\n") ?? "";
}

function buildRawEmail(input: SendInput) {
  const subject = input.subject ?? "";
  const attachments = input.attachments ?? [];

  if (attachments.length === 0) {
    const lines = [
      `To: ${input.to}`,
      `Subject: ${encodeHeader(subject)}`,
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      input.body
    ];

    return encodeBase64Url(lines.join("\r\n"));
  }

  const boundary = `claritymail-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const lines = [
    `To: ${input.to}`,
    `Subject: ${encodeHeader(subject)}`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: 8bit",
    "",
    input.body,
    ""
  ];

  for (const attachment of attachments) {
    const filename = escapeMimeValue(attachment.filename);
    const mimeType = attachment.mimeType || "application/octet-stream";
    lines.push(
      `--${boundary}`,
      `Content-Type: ${mimeType}; name="${filename}"`,
      `Content-Disposition: attachment; filename="${filename}"`,
      "Content-Transfer-Encoding: base64",
      "",
      chunkBase64(attachment.data),
      ""
    );
  }

  lines.push(`--${boundary}--`);

  return encodeBase64Url(lines.join("\r\n"));
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

function findAttachments(payload: any): Array<{ id: string; filename: string; mimeType: string; size: number }> {
  if (!payload) {
    return [];
  }

  const current =
    payload.filename && payload.body?.attachmentId
      ? [
          {
            id: payload.body.attachmentId,
            filename: payload.filename,
            mimeType: payload.mimeType ?? "application/octet-stream",
            size: Number(payload.body.size ?? 0)
          }
        ]
      : [];

  return current.concat((payload.parts ?? []).flatMap((part: any) => findAttachments(part)));
}

function mailboxListOptions(folder: MailboxFolder, query?: string) {
  const trimmedQuery = query?.trim();

  switch (folder) {
    case "sent":
      return { labelIds: ["SENT"], q: trimmedQuery || undefined };
    case "trash":
      return { labelIds: ["TRASH"], q: trimmedQuery || undefined };
    case "archive":
      return {
        labelIds: undefined,
        q: ["-in:inbox", "-in:sent", "-in:trash", "-in:drafts", trimmedQuery].filter(Boolean).join(" ")
      };
    case "inbox":
    default:
      return { labelIds: ["INBOX"], q: trimmedQuery || undefined };
  }
}

export async function listMailboxEmails(
  account: GmailAccount,
  options: { query?: string; folder?: MailboxFolder } = {}
) {
  const gmail = getGmailClient(account);
  const listOptions = mailboxListOptions(options.folder ?? "inbox", options.query);

  const listResponse = await gmail.users.messages.list({
    userId: "me",
    labelIds: listOptions.labelIds,
    maxResults: 30,
    q: listOptions.q
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
        accountId: account.id ?? "",
        accountEmail: account.email ?? "",
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
  const attachments = findAttachments(data.payload);

  return {
    accountId: account.id ?? "",
    accountEmail: account.email ?? "",
    id: data.id ?? "",
    threadId: data.threadId ?? "",
    subject: headerValue(headers, "Subject") || "(No subject)",
    sender: headerValue(headers, "From") || "Unknown sender",
    snippet: data.snippet ?? "",
    receivedAt: new Date(Number(data.internalDate ?? Date.now())).toISOString(),
    isRead: !labelIds.includes("UNREAD"),
    isStarred: labelIds.includes("STARRED"),
    body,
    htmlBody: html?.trim() || null,
    attachments
  };
}

export async function getEmailAttachment(account: GmailAccount, messageId: string, attachmentId: string) {
  const gmail = getGmailClient(account);
  const result = await gmail.users.messages.attachments.get({
    userId: "me",
    messageId,
    id: attachmentId
  });

  return {
    data: result.data.data ?? "",
    size: result.data.size ?? 0
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

export async function blockSenderInGmail(account: GmailAccount, senderEmail: string) {
  const gmail = getGmailClient(account);

  const filtersResponse = await gmail.users.settings.filters.list({
    userId: "me"
  });

  const existingFilter = (filtersResponse.data.filter ?? []).find(
    (filter) => filter.criteria?.from?.toLowerCase() === senderEmail.toLowerCase()
  );

  if (!existingFilter) {
    await gmail.users.settings.filters.create({
      userId: "me",
      requestBody: {
        criteria: {
          from: senderEmail
        },
        action: {
          removeLabelIds: ["INBOX"],
          addLabelIds: ["TRASH"]
        }
      }
    });
  }

  const matchingMessages = await gmail.users.messages.list({
    userId: "me",
    q: `from:${senderEmail}`,
    maxResults: 100
  });

  await Promise.all(
    (matchingMessages.data.messages ?? []).map((message) =>
      message.id
        ? gmail.users.messages.trash({
            userId: "me",
            id: message.id
          })
        : Promise.resolve()
    )
  );
}

export async function unblockSenderInGmail(account: GmailAccount, senderEmail: string) {
  const gmail = getGmailClient(account);

  const filtersResponse = await gmail.users.settings.filters.list({
    userId: "me"
  });

  const matchingFilters = (filtersResponse.data.filter ?? []).filter(
    (filter) => filter.id && filter.criteria?.from?.toLowerCase() === senderEmail.toLowerCase()
  );

  await Promise.all(
    matchingFilters.map((filter) =>
      gmail.users.settings.filters.delete({
        userId: "me",
        id: filter.id ?? ""
      })
    )
  );
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

export async function sendEmail(account: GmailAccount, input: SendInput) {
  const gmail = getGmailClient(account);
  const result = await gmail.users.messages.send({
    userId: "me",
    requestBody: {
      raw: buildRawEmail(input)
    }
  });

  return {
    id: result.data.id,
    threadId: result.data.threadId
  };
}

export async function replyToEmail(account: GmailAccount, input: SendInput & { threadId: string }) {
  const gmail = getGmailClient(account);
  const subject = (input.subject ?? "").toLowerCase().startsWith("re:") ? (input.subject ?? "") : `Re: ${input.subject ?? ""}`;
  const result = await gmail.users.messages.send({
    userId: "me",
    requestBody: {
      raw: buildRawEmail({
        to: input.to,
        subject,
        body: input.body,
        attachments: input.attachments
      }),
      threadId: input.threadId
    }
  });

  return {
    id: result.data.id,
    threadId: result.data.threadId
  };
}

export async function startGmailWatch(account: GmailAccount) {
  const topicName = process.env.GMAIL_PUBSUB_TOPIC;

  if (!topicName) {
    throw new Error("Missing GMAIL_PUBSUB_TOPIC.");
  }

  const gmail = getGmailClient(account);
  const result = await gmail.users.watch({
    userId: "me",
    requestBody: {
      topicName,
      labelIds: ["INBOX"]
    }
  });

  return {
    historyId: result.data.historyId ?? "",
    expiration: result.data.expiration ?? null
  };
}

export async function listGmailHistory(account: GmailAccount, startHistoryId: string) {
  const gmail = getGmailClient(account);
  const result = await gmail.users.history.list({
    userId: "me",
    startHistoryId,
    historyTypes: ["messageAdded", "labelAdded", "labelRemoved"]
  });

  const history = result.data.history ?? [];
  const messageIds = new Set<string>();

  for (const item of history) {
    for (const added of item.messagesAdded ?? []) {
      if (added.message?.id) messageIds.add(added.message.id);
    }

    for (const labelAdded of item.labelsAdded ?? []) {
      if (labelAdded.message?.id) messageIds.add(labelAdded.message.id);
    }

    for (const labelRemoved of item.labelsRemoved ?? []) {
      if (labelRemoved.message?.id) messageIds.add(labelRemoved.message.id);
    }
  }

  return {
    historyId: result.data.historyId ?? startHistoryId,
    messageIds: Array.from(messageIds)
  };
}
