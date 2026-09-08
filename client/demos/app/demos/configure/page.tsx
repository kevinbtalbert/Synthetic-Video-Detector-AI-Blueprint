"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import SecretInput from "@/app/components/atoms/SecretInput";
import { useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

type Mode = "BUNDLED" | "SERVERLESS";

const defaultForm = {
  nim_deploy_mode: "BUNDLED" as Mode,
  ngc_api_key: "",
  svd_nvidia_function_id: "847b6e53-0133-452d-ab85-d7acf3ace723",
  nvidia_serverless_grpc_host: "grpc.nvcf.nvidia.com",
  nvidia_serverless_grpc_port: "443",
  detection_threshold: "0.30",
};

export default function ConfigurePage() {
  const { status, refresh, pipelineReady, pipelineFailed, hasPriorBuild } = useDeploymentStatus({
    pollWhilePending: true,
  });
  const [form, setForm] = useState(defaultForm);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (status?.config) {
      setForm((prev) => ({
        ...prev,
        nim_deploy_mode: (status.config!.nim_deploy_mode as Mode) || prev.nim_deploy_mode,
        svd_nvidia_function_id: String(status.config!.svd_nvidia_function_id || prev.svd_nvidia_function_id),
        nvidia_serverless_grpc_host: String(status.config!.nvidia_serverless_grpc_host || prev.nvidia_serverless_grpc_host),
        nvidia_serverless_grpc_port: String(status.config!.nvidia_serverless_grpc_port || prev.nvidia_serverless_grpc_port),
        detection_threshold: String(status.config!.detection_threshold || prev.detection_threshold),
      }));
    }
  }, [status]);

  const post = async (action: string) => {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const res = await fetch("/api/deployment", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, config: form }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || JSON.stringify(data.errors || data));
      if (action === "build") {
        setMessage("Build started — polling status…");
        void refresh();
      } else if (action === "save-config") {
        setMessage("Configuration saved.");
      } else {
        setMessage(data.valid ? "Validation passed." : data.errors?.join("; "));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Request failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-3xl space-y-6 p-6">
        <Card title="Deployment mode">
          <p className="mb-4 text-sm text-neutral-400">{status?.mode_summary?.headline}</p>
          <div className="flex gap-4 mb-4">
            {(["BUNDLED", "SERVERLESS"] as Mode[]).map((mode) => (
              <label key={mode} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  checked={form.nim_deploy_mode === mode}
                  onChange={() => setForm({ ...form, nim_deploy_mode: mode })}
                />
                {mode === "BUNDLED" ? "Bundled NIM (GPU)" : "Serverless NVCF API"}
              </label>
            ))}
          </div>
          <SecretInput
            label="NGC API Key"
            value={form.ngc_api_key}
            onChange={(v) => setForm({ ...form, ngc_api_key: v })}
            placeholder={status?.secrets_set?.ngc_api_key ? "•••••••• (saved)" : "nvapi-…"}
          />
          {form.nim_deploy_mode === "SERVERLESS" && (
            <div className="mt-4 grid gap-3">
              <label className="text-sm">
                NVCF Function ID
                <input
                  className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
                  value={form.svd_nvidia_function_id}
                  onChange={(e) => setForm({ ...form, svd_nvidia_function_id: e.target.value })}
                />
              </label>
              <label className="text-sm">
                gRPC Host
                <input
                  className="mt-1 w-full rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
                  value={form.nvidia_serverless_grpc_host}
                  onChange={(e) => setForm({ ...form, nvidia_serverless_grpc_host: e.target.value })}
                />
              </label>
            </div>
          )}
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              className="rounded bg-neutral-800 px-4 py-2 hover:bg-neutral-700 disabled:opacity-50"
              disabled={busy}
              onClick={() => void post("save-config")}
            >
              Save configuration
            </button>
            <button
              className="rounded bg-neutral-800 px-4 py-2 hover:bg-neutral-700 disabled:opacity-50"
              disabled={busy}
              onClick={() => void post("validate")}
            >
              Validate
            </button>
            <button
              className="rounded bg-[var(--nvidia-green)] px-4 py-2 font-medium text-black hover:opacity-90 disabled:opacity-50"
              disabled={busy || status?.build_in_progress}
              onClick={() => void post("build")}
            >
              Build pipeline
            </button>
          </div>
          {message && <p className="mt-4 text-sm text-green-400">{message}</p>}
          {error && <p className="mt-4 text-sm text-red-400">{error}</p>}
        </Card>

        <Card title="Pipeline status">
          {pipelineReady && (
            <p className="text-green-400 mb-2">
              Ready — <Link href="/demos/detect" className="underline">run detection</Link>
            </p>
          )}
          {pipelineFailed && <p className="text-red-400 mb-2">One or more services failed.</p>}
          {status?.build?.steps?.map((step) => (
            <div key={step.id} className="text-sm py-1">
              {step.status === "done" ? "✓" : step.status === "running" ? "◌" : "○"} {step.label}
              {step.detail ? ` — ${step.detail}` : ""}
            </div>
          ))}
          {!hasPriorBuild && !pipelineReady && (
            <p className="text-neutral-500 text-sm">Save configuration and build the pipeline to begin.</p>
          )}
        </Card>
      </main>
    </div>
  );
}
