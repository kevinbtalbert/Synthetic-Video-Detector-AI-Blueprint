import { NextRequest, NextResponse } from "next/server";
import { spawn } from "child_process";
import fs from "fs";
import path from "path";
import { controlPlaneScript, pythonPath } from "../utils/persistedConfig";

export async function GET() {
  return new Promise((resolve) => {
    const proc = spawn(pythonPath(), [controlPlaneScript(), "status"]);
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));
    proc.on("close", (code) => {
      if (code !== 0) {
        resolve(NextResponse.json({ error: stderr || "status failed" }, { status: 500 }));
        return;
      }
      resolve(NextResponse.json(JSON.parse(stdout)));
    });
  });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const action = body.action as string;
  const config = body.config;

  if (action === "save-config") {
    return runCli(["save-config", "--config-json", JSON.stringify(config)]);
  }
  if (action === "validate") {
    return runCli(["validate", "--config-json", JSON.stringify(config || {})]);
  }
  if (action === "build") {
    const logDir = path.join(process.env.CDSW_PROJECT_DIR || path.resolve(process.cwd(), "../.."), "cai/config");
    fs.mkdirSync(logDir, { recursive: true });
    const logPath = path.join(logDir, "build_worker.log");
    const out = fs.openSync(logPath, "a");
    const proc = spawn(pythonPath(), [controlPlaneScript(), "build"], {
      detached: true,
      stdio: ["ignore", out, out],
    });
    proc.unref();
    return NextResponse.json({ started: true, log: logPath });
  }
  return NextResponse.json({ error: "Unknown action" }, { status: 400 });
}

function runCli(args: string[]): Promise<NextResponse> {
  return new Promise((resolve) => {
    const proc = spawn(pythonPath(), [controlPlaneScript(), ...args]);
    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));
    proc.on("close", (code) => {
      const payload = stdout ? JSON.parse(stdout) : { error: stderr };
      resolve(NextResponse.json(payload, { status: code === 0 ? 200 : 400 }));
    });
  });
}
