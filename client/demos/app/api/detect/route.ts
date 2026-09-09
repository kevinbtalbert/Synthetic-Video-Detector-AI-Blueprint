import { NextRequest, NextResponse } from "next/server";
import { spawn } from "child_process";
import fs from "fs/promises";
import os from "os";
import path from "path";
import { applyPersistedConfigToProcessEnv, pythonPath, projectRoot } from "../utils/persistedConfig";

export async function POST(request: NextRequest): Promise<NextResponse> {
  applyPersistedConfigToProcessEnv();
  const form = await request.formData();
  const file = form.get("video");
  if (!(file instanceof Blob)) {
    return NextResponse.json({ error: "Missing video file" }, { status: 400 });
  }
  const buffer = Buffer.from(await file.arrayBuffer());
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "svd-"));
  const videoPath = path.join(tmpDir, "input.mp4");
  const jsonPath = path.join(tmpDir, "result.json");
  await fs.writeFile(videoPath, buffer);

  const root = projectRoot();
  const env = { ...process.env, PYTHONPATH: [root, path.join(root, "src")].join(":") };

  return new Promise<NextResponse>((resolve) => {
    const proc = spawn(
      pythonPath(),
      ["-m", "src.svd.cli", "--video-input", videoPath, "--output-json", jsonPath],
      { env, cwd: root },
    );
    let stderr = "";
    proc.stderr.on("data", (d) => (stderr += d.toString()));
    proc.on("close", async (code) => {
      try {
        if (code !== 0) {
          resolve(NextResponse.json({ error: stderr || "Detection failed" }, { status: 500 }));
          return;
        }
        const result = JSON.parse(await fs.readFile(jsonPath, "utf8"));
        resolve(NextResponse.json(result));
      } catch (err) {
        resolve(
          NextResponse.json(
            { error: err instanceof Error ? err.message : "Failed to parse result" },
            { status: 500 },
          ),
        );
      } finally {
        await fs.rm(tmpDir, { recursive: true, force: true });
      }
    });
  });
}
