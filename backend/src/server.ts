import dotenv from "dotenv";
import express from "express";
import cors from "cors";
import { authRoutes } from "./routes/auth.routes.js";
import { emailRoutes } from "./routes/email.routes.js";
import { healthRoutes } from "./routes/health.routes.js";
import { realtimeRoutes } from "./routes/realtime.routes.js";

dotenv.config({ override: true });

const app = express();

app.use(cors());
app.use(express.json({ limit: "40mb" }));

app.use(healthRoutes);
app.use("/auth", authRoutes);
app.use(emailRoutes);
app.use(realtimeRoutes);

const port = Number(process.env.PORT ?? 3000);

app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
  console.error(error);
  response.status(500).json({ error: "Internal server error." });
});

app.listen(port, () => {
  console.log(`ClarityMail API listening on ${port}`);
});
