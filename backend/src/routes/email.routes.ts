import { Router } from "express";
import { getLatestGoogleAccount } from "../db/accounts.repo.js";
import {
  archiveEmail,
  getEmail,
  listInboxEmails,
  markEmailRead,
  markEmailUnread,
  starEmail,
  trashEmail,
  unstarEmail
} from "../services/gmail.service.js";

export const emailRoutes = Router();

async function requireAccount(response: import("express").Response) {
  const account = await getLatestGoogleAccount();

  if (!account) {
    response.status(401).json({ error: "No Gmail account connected." });
    return null;
  }

  return account;
}

emailRoutes.get("/emails", async (_request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    const emails = await listInboxEmails(account);
    response.json({ emails });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/emails/:id", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    const email = await getEmail(account, request.params.id);
    response.json({ email });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/archive", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await archiveEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/trash", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await trashEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/read", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await markEmailRead(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/unread", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await markEmailUnread(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/star", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await starEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

emailRoutes.post("/emails/:id/unstar", async (request, response, next) => {
  try {
    const account = await requireAccount(response);
    if (!account) return;

    await unstarEmail(account, request.params.id);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});
