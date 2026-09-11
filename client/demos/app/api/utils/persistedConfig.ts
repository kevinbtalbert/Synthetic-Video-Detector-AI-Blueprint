import path from "path";
import fs from "fs";

export type PersistedConfig = {
  nim_deploy_mode?: string;
  svd_nvidia_function_id?: string;
  nvidia_serverless_grpc_host?: string;
  nvidia_serverless_grpc_port?: string;
  detection_threshold?: string;
  ngc_api_key?: string;
};

const ENV_MAP: Record<string, string> = {
  nim_deploy_mode: "NIM_DEPLOY_MODE",
  svd_nvidia_function_id: "SVD_NVIDIA_FUNCTION_ID",
  nvidia_serverless_grpc_host: "NVIDIA_SERVERLESS_GRPC_HOST",
  nvidia_serverless_grpc_port: "NVIDIA_SERVERLESS_GRPC_PORT",
  detection_threshold: "SVD_DETECTION_THRESHOLD",
  ngc_api_key: "NGC_API_KEY",
};

function projectRoot(): string {
  return process.env.CDSW_PROJECT_DIR || path.resolve(process.cwd(), "../..");
}

export { projectRoot };

export function deploymentConfigPath(): string {
  return path.join(projectRoot(), "cai/config/deployment_config.json");
}

export function endpointsEnvPath(): string {
  return path.join(projectRoot(), "cai/config/runtime_endpoints.env");
}

export function appEnvironmentPath(): string {
  return path.join(projectRoot(), "cai/config/app_environment.env");
}

function applyDotenvFile(targetPath: string, env: NodeJS.ProcessEnv): void {
  if (!fs.existsSync(targetPath)) return;
  for (const line of fs.readFileSync(targetPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const eq = trimmed.indexOf("=");
    const key = trimmed.slice(0, eq);
    let val = trimmed.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
}

function applyDeploymentJson(env: NodeJS.ProcessEnv): void {
  const configPath = deploymentConfigPath();
  if (!fs.existsSync(configPath)) return;
  try {
    const raw = JSON.parse(fs.readFileSync(configPath, "utf8")) as Record<string, unknown>;
    const mode = String(env.NIM_DEPLOY_MODE || raw.nim_deploy_mode || "BUNDLED").toUpperCase();
    let data: PersistedConfig;
    if (raw.serverless || raw.bundled) {
      const section =
        mode === "SERVERLESS"
          ? (raw.serverless as PersistedConfig)
          : (raw.bundled as PersistedConfig);
      data = { ...section, nim_deploy_mode: mode };
    } else {
      data = raw as PersistedConfig;
    }
    for (const [jsonKey, envKey] of Object.entries(ENV_MAP)) {
      const value = data[jsonKey as keyof PersistedConfig];
      if (value) env[envKey] = String(value);
    }
  } catch {
    /* ignore */
  }
}

/** Merge env for detect API. Runtime apps use CML-baked env only; Launchpad reads saved config. */
export function buildDetectProcessEnv(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env };
  applyDotenvFile(endpointsEnvPath(), env);
  const role = String(env.SVD_APP_ROLE || "launchpad");
  if (role === "launchpad") {
    applyDotenvFile(appEnvironmentPath(), env);
    applyDeploymentJson(env);
  }

  const mode = String(env.NIM_DEPLOY_MODE || "BUNDLED").toUpperCase();
  if (mode === "SERVERLESS" && role === "launchpad") {
    const server = String(env.SVD_SERVER || "");
    const host = server.split(":")[0]?.toLowerCase() || "";
    if (host === "127.0.0.1" || host === "localhost") {
      delete env.SVD_SERVER;
    }
  }
  return env;
}

export function validateDetectEnv(env: NodeJS.ProcessEnv): string | null {
  const mode = String(env.NIM_DEPLOY_MODE || "BUNDLED").toUpperCase();
  const role = String(env.SVD_APP_ROLE || "runtime");
  if (mode === "SERVERLESS") {
    if (!env.NGC_API_KEY?.trim()) {
      return "NGC API key is not configured. Save serverless configuration on the Launchpad and redeploy.";
    }
    return null;
  }
  const server = String(env.SVD_SERVER || "");
  if (!server) {
    return "Bundled NIM endpoints are not configured. Wait for the app to finish starting NIM.";
  }
  if (role === "launchpad") {
    const host = server.split(":")[0]?.toLowerCase() || "";
    if (host === "127.0.0.1" || host === "localhost") {
      return "Open the deployed Bundled app URL from the Launchpad to run detection.";
    }
  }
  return null;
}

export function controlPlaneScript(): string {
  return path.join(projectRoot(), "cai/amp/7_deploy/control_plane_cli.py");
}

export function pythonPath(): string {
  const venv = path.join(projectRoot(), ".venv/bin/python");
  if (fs.existsSync(venv)) return venv;
  return process.env.PYTHON || "python3";
}

export function applyPersistedConfigToProcessEnv(): void {
  const merged = buildDetectProcessEnv();
  for (const [key, value] of Object.entries(merged)) {
    if (value !== undefined) process.env[key] = value;
  }
}
