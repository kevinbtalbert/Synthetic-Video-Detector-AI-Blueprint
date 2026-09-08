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

export function controlPlaneScript(): string {
  return path.join(projectRoot(), "cai/amp/7_deploy/control_plane_cli.py");
}

export function pythonPath(): string {
  const venv = path.join(projectRoot(), ".venv/bin/python");
  if (fs.existsSync(venv)) return venv;
  return process.env.PYTHON || "python3";
}

export function applyPersistedConfigToProcessEnv(): void {
  const configPath = deploymentConfigPath();
  if (!fs.existsSync(configPath)) return;
  try {
    const data = JSON.parse(fs.readFileSync(configPath, "utf8")) as PersistedConfig;
    for (const [jsonKey, envKey] of Object.entries(ENV_MAP)) {
      const value = data[jsonKey as keyof PersistedConfig];
      if (value) process.env[envKey] = String(value);
    }
  } catch {
    /* ignore */
  }
  const endpointsPath = endpointsEnvPath();
  if (fs.existsSync(endpointsPath)) {
    for (const line of fs.readFileSync(endpointsPath, "utf8").split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
      const eq = trimmed.indexOf("=");
      const key = trimmed.slice(0, eq);
      let val = trimmed.slice(eq + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      process.env[key] = val;
    }
  }
}
