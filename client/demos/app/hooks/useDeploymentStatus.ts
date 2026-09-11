"use client";

import { useCallback, useEffect, useState } from "react";

export type StepStatus = "pending" | "running" | "done" | "error" | "skipped";

export type ServiceStatus = {
  key?: string;
  name?: string;
  mode?: string;
  ready?: boolean;
  app_running?: boolean;
  app_failed?: boolean;
  application?: { status?: string; id?: string; subdomain?: string } | null;
};

export type DeploymentStatus = {
  pipeline_ready?: boolean;
  serverless_ready?: boolean;
  bundled_ready?: boolean;
  pipeline_failed?: boolean;
  build_in_progress?: boolean;
  deploy_active?: boolean;
  nim_deploy_mode?: string;
  config?: {
    serverless?: Record<string, unknown>;
    bundled?: Record<string, unknown>;
  };
  secrets_set?: {
    serverless?: { ngc_api_key?: boolean };
    bundled?: { ngc_api_key?: boolean };
  };
  mode_summary?: { headline?: string; detail?: string };
  deployments?: Record<string, ServiceStatus>;
  services?: Record<string, ServiceStatus>;
  build?: {
    error?: string;
    message?: string;
    in_progress?: boolean;
    mode?: string;
    steps?: Array<{ id: string; label: string; status: StepStatus; detail?: string }>;
  };
};

export function useDeploymentStatus({ pollWhilePending = false } = {}) {
  const [status, setStatus] = useState<DeploymentStatus | null>(null);
  const [initialLoading, setInitialLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await fetch("/api/deployment");
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Failed to load status");
      setStatus(data);
      setFetchError(null);
    } catch (err) {
      setFetchError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setInitialLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!pollWhilePending) return;
    if (!status?.deploy_active && !status?.build_in_progress) return;
    const id = setInterval(() => void refresh(), 4000);
    return () => clearInterval(id);
  }, [pollWhilePending, refresh, status?.deploy_active, status?.build_in_progress]);

  return {
    status,
    initialLoading,
    fetchError,
    refresh,
    pipelineReady: Boolean(status?.pipeline_ready),
    serverlessReady: Boolean(status?.serverless_ready),
    bundledReady: Boolean(status?.bundled_ready),
    pipelineFailed: Boolean(status?.pipeline_failed),
    buildInProgress: Boolean(status?.build_in_progress),
    hasPriorBuild: Boolean(status?.build?.steps?.some((s) => s.status === "done")),
  };
}
