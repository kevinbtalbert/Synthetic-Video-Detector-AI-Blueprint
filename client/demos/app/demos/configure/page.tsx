"use client";

import { useEffect, useRef, useState } from "react";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import SecretInput from "@/app/components/atoms/SecretInput";
import { useDeploymentStatus, type ServiceStatus } from "@/app/hooks/useDeploymentStatus";

type DeployMode = "SERVERLESS" | "BUNDLED";

type ModeForm = {
  ngc_api_key: string;
  svd_nvidia_function_id: string;
  nvidia_serverless_grpc_host: string;
  nvidia_serverless_grpc_port: string;
  detection_threshold: string;
};

const defaultServerless: ModeForm = {
  ngc_api_key: "",
  svd_nvidia_function_id: "847b6e53-0133-452d-ab85-d7acf3ace723",
  nvidia_serverless_grpc_host: "grpc.nvcf.nvidia.com",
  nvidia_serverless_grpc_port: "443",
  detection_threshold: "0.30",
};

const defaultBundled: ModeForm = {
  ngc_api_key: "",
  svd_nvidia_function_id: "",
  nvidia_serverless_grpc_host: "",
  nvidia_serverless_grpc_port: "",
  detection_threshold: "0.30",
};

function appUrl(subdomain?: string): string | null {
  if (!subdomain) return null;
  if (typeof window === "undefined") return null;
  const host = window.location.host.replace(/^[^.]+\./, `${subdomain}.`);
  return `${window.location.protocol}//${host}`;
}

function DeploySection({
  mode,
  title,
  description,
  form,
  onChange,
  deployment,
  secretsSet,
  busy,
  onSave,
  onValidate,
  onDeploy,
  children,
}: {
  mode: DeployMode;
  title: string;
  description: string;
  form: ModeForm;
  onChange: (patch: Partial<ModeForm>) => void;
  deployment?: ServiceStatus;
  secretsSet?: boolean;
  busy: boolean;
  onSave: () => void;
  onValidate: () => void;
  onDeploy: () => void;
  children?: React.ReactNode;
}) {
  const app = deployment?.application;
  const status = app?.status || "not deployed";
  const url = appUrl(app?.subdomain);
  const ready = Boolean(deployment?.ready);
  const running = Boolean(deployment?.app_running);
  const failed = Boolean(deployment?.app_failed);

  return (
    <Card title={title}>
      <p className="mb-4 text-sm text-neutral-400">{description}</p>
      <SecretInput
        label="NGC API Key"
        value={form.ngc_api_key}
        onChange={(v) => onChange({ ngc_api_key: v })}
        placeholder={secretsSet ? "•••••••• (saved)" : "nvapi-…"}
      />
      {children}
      <label className="mt-4 block text-sm">
        Detection threshold
        <input
          className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
          value={form.detection_threshold}
          onChange={(e) => onChange({ detection_threshold: e.target.value })}
        />
      </label>
      <div className="mt-6 flex flex-wrap gap-3">
        <button
          className="rounded bg-neutral-800 px-4 py-2 hover:bg-neutral-700 disabled:opacity-50"
          disabled={busy}
          onClick={onSave}
        >
          Save
        </button>
        <button
          className="rounded bg-neutral-800 px-4 py-2 hover:bg-neutral-700 disabled:opacity-50"
          disabled={busy}
          onClick={onValidate}
        >
          Validate
        </button>
        <button
          className="rounded bg-[var(--nvidia-green)] px-4 py-2 font-medium text-black hover:opacity-90 disabled:opacity-50"
          disabled={busy}
          onClick={onDeploy}
        >
          {running || ready ? "Redeploy" : "Deploy"}
        </button>
      </div>
      <div className="mt-4 space-y-1 text-sm">
        <p>
          Application: <strong>{deployment?.name || title}</strong> —{" "}
          <span className={failed ? "text-red-400" : ready ? "text-green-400" : "text-neutral-300"}>
            {status}
          </span>
        </p>
        {url && (
          <p>
            Open app:{" "}
            <a href={url} target="_blank" rel="noreferrer" className="text-[var(--nvidia-green)] underline">
              {url}
            </a>
          </p>
        )}
        {ready && url && (
          <p className="text-green-400">Ready — use the app URL above for Detect and Demo.</p>
        )}
        {mode === "BUNDLED" && running && !ready && (
          <p className="text-amber-400">NIM is starting inside the app (first run can take 15–30+ minutes).</p>
        )}
      </div>
    </Card>
  );
}

export default function LaunchpadPage() {
  const { status, refresh, buildInProgress } = useDeploymentStatus({ pollWhilePending: true });
  const [serverlessForm, setServerlessForm] = useState(defaultServerless);
  const [bundledForm, setBundledForm] = useState(defaultBundled);
  const [dirty, setDirty] = useState({ serverless: false, bundled: false });
  const hydrated = useRef(false);
  const [busy, setBusy] = useState<DeployMode | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!status?.config || hydrated.current) return;
    hydrated.current = true;
    const sl = status.config.serverless as Record<string, unknown> | undefined;
    const bd = status.config.bundled as Record<string, unknown> | undefined;
    if (sl) {
      setServerlessForm((prev) => ({
        ...prev,
        svd_nvidia_function_id: String(sl.svd_nvidia_function_id || prev.svd_nvidia_function_id),
        nvidia_serverless_grpc_host: String(sl.nvidia_serverless_grpc_host || prev.nvidia_serverless_grpc_host),
        nvidia_serverless_grpc_port: String(sl.nvidia_serverless_grpc_port || prev.nvidia_serverless_grpc_port),
        detection_threshold: String(sl.detection_threshold || prev.detection_threshold),
      }));
    }
    if (bd) {
      setBundledForm((prev) => ({
        ...prev,
        detection_threshold: String(bd.detection_threshold || prev.detection_threshold),
      }));
    }
  }, [status]);

  const post = async (mode: DeployMode, action: "save-config" | "validate" | "deploy") => {
    setBusy(mode);
    setError(null);
    setMessage(null);
    const config = mode === "SERVERLESS" ? serverlessForm : bundledForm;
    try {
      if (action === "deploy") {
        const saveRes = await fetch("/api/deployment", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "save-config", mode, config }),
        });
        const saveData = await saveRes.json();
        if (!saveRes.ok) throw new Error(saveData.error || "Save before deploy failed");
      }
      const res = await fetch("/api/deployment", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, mode, config }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || JSON.stringify(data.errors || data));
      if (action === "deploy") {
        setMessage(`${mode} deployment started — polling status…`);
        setDirty((d) => ({ ...d, [mode.toLowerCase() as "serverless" | "bundled"]: false }));
        void refresh();
      } else if (action === "save-config") {
        setMessage(`${mode} configuration saved.`);
        setDirty((d) => ({ ...d, [mode.toLowerCase() as "serverless" | "bundled"]: false }));
      } else {
        setMessage(data.valid ? `${mode} validation passed.` : data.errors?.join("; "));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Request failed");
    } finally {
      setBusy(null);
    }
  };

  const deployments = status?.deployments || status?.services || {};
  const slSecrets = status?.secrets_set?.serverless?.ngc_api_key;
  const bdSecrets = status?.secrets_set?.bundled?.ngc_api_key;

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-4xl space-y-6 p-6">
        <Card title="Launchpad">
          <p className="text-sm text-neutral-300">{status?.mode_summary?.headline}</p>
          <p className="mt-2 text-sm text-neutral-500">{status?.mode_summary?.detail}</p>
          {buildInProgress && (
            <p className="mt-3 text-sm text-amber-400">
              Deployment in progress… {status?.build?.message || ""}
            </p>
          )}
          {status?.build?.error && <p className="mt-2 text-sm text-red-400">{status.build.error}</p>}
          {message && <p className="mt-3 text-sm text-green-400">{message}</p>}
          {error && <p className="mt-3 text-sm text-red-400">{error}</p>}
        </Card>

        <DeploySection
          mode="SERVERLESS"
          title="Deploy Serverless (NVCF)"
          description="Creates an all-in-one CPU application that calls the NVIDIA Cloud Functions gRPC API for inference."
          form={serverlessForm}
          onChange={(patch) => {
            setDirty((d) => ({ ...d, serverless: true }));
            setServerlessForm((prev) => ({ ...prev, ...patch }));
          }}
          deployment={deployments.serverless as ServiceStatus | undefined}
          secretsSet={slSecrets}
          busy={busy !== null}
          onSave={() => void post("SERVERLESS", "save-config")}
          onValidate={() => void post("SERVERLESS", "validate")}
          onDeploy={() => void post("SERVERLESS", "deploy")}
        >
          <div className="mt-4 grid gap-3">
            <label className="text-sm">
              NVCF Function ID
              <input
                className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
                value={serverlessForm.svd_nvidia_function_id}
                onChange={(e) => {
                  setDirty((d) => ({ ...d, serverless: true }));
                  setServerlessForm((prev) => ({ ...prev, svd_nvidia_function_id: e.target.value }));
                }}
              />
            </label>
            <label className="text-sm">
              gRPC Host
              <input
                className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
                value={serverlessForm.nvidia_serverless_grpc_host}
                onChange={(e) => {
                  setDirty((d) => ({ ...d, serverless: true }));
                  setServerlessForm((prev) => ({ ...prev, nvidia_serverless_grpc_host: e.target.value }));
                }}
              />
            </label>
            <label className="text-sm">
              gRPC Port
              <input
                className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
                value={serverlessForm.nvidia_serverless_grpc_port}
                onChange={(e) => {
                  setDirty((d) => ({ ...d, serverless: true }));
                  setServerlessForm((prev) => ({ ...prev, nvidia_serverless_grpc_port: e.target.value }));
                }}
              />
            </label>
          </div>
        </DeploySection>

        <DeploySection
          mode="BUNDLED"
          title="Deploy Bundled NIM (GPU)"
          description="Creates an all-in-one GPU application. Bundled NIM runs inside the same pod as the detection UI."
          form={bundledForm}
          onChange={(patch) => {
            setDirty((d) => ({ ...d, bundled: true }));
            setBundledForm((prev) => ({ ...prev, ...patch }));
          }}
          deployment={deployments.bundled as ServiceStatus | undefined}
          secretsSet={bdSecrets}
          busy={busy !== null}
          onSave={() => void post("BUNDLED", "save-config")}
          onValidate={() => void post("BUNDLED", "validate")}
          onDeploy={() => void post("BUNDLED", "deploy")}
        />
      </main>
    </div>
  );
}
