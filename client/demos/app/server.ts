import { createServer } from "http";
import { parse } from "url";
import next from "next";
import { applyPersistedConfigToProcessEnv } from "./api/utils/persistedConfig";

applyPersistedConfigToProcessEnv();

const port = parseInt(process.env.CDSW_APP_PORT || process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  createServer((req, res) => {
    const parsedUrl = parse(req.url!, true);
    handle(req, res, parsedUrl);
  }).listen(port, "127.0.0.1", () => {
    console.log(`> SVD Launchpad on http://127.0.0.1:${port}`);
  });
});
