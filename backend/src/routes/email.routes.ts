import { Router } from "express";
import { getLatestGoogleAccount } from "../db/accounts.repo.js";
import { getEmail, listInboxEmails } from "../services/gmail.service.js";

export const emailRoutes = Router();

emailRoutes.get("/emails", async (_request, response, next) => {
  try {
    const account = await getLatestGoogleAccount();

    if (!account) {
      response.status(401).json({ error: "No Gmail account connected." });
      return;
    }

    const emails = await listInboxEmails(account);
    response.json({ emails });
  } catch (error) {
    next(error);
  }
});

emailRoutes.get("/emails/:id", async (request, response, next) => {
  try {
    const account = await getLatestGoogleAccount();

    if (!account) {
      response.status(401).json({ error: "No Gmail account connected." });
      return;
    }

    const email = await getEmail(account, request.params.id);
    response.json({ email });
  } catch (error) {
    next(error);
  }
});
