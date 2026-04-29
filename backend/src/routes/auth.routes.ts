import { Router } from "express";
import { createGoogleAuthUrl, exchangeGoogleCode } from "../services/googleOAuth.service.js";
import { getLatestGoogleAccount, listGoogleAccounts, saveGoogleAccount } from "../db/accounts.repo.js";

export const authRoutes = Router();

authRoutes.get("/google/url", (_request, response) => {
  response.json({ url: createGoogleAuthUrl() });
});

authRoutes.get("/status", async (_request, response, next) => {
  try {
    const account = await getLatestGoogleAccount();
    response.json({
      isSignedIn: Boolean(account),
      email: account?.email ?? null
    });
  } catch (error) {
    next(error);
  }
});

authRoutes.get("/accounts", async (_request, response, next) => {
  try {
    const accounts = await listGoogleAccounts();
    response.json({ accounts });
  } catch (error) {
    next(error);
  }
});

authRoutes.get("/google/callback", async (request, response, next) => {
  try {
    const code = typeof request.query.code === "string" ? request.query.code : undefined;

    if (!code) {
      response.status(400).send("Missing Google auth code.");
      return;
    }

    const result = await exchangeGoogleCode(code);
    await saveGoogleAccount(result.profile, result.tokens);

    response.send("ClarityMail is connected. You can close this tab.");
  } catch (error) {
    next(error);
  }
});
