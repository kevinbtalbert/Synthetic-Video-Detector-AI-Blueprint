"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useDropzone } from "react-dropzone";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import DetectionProgress, { type DetectPhase } from "@/app/components/atoms/DetectionProgress";
import { useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

type Result = {
  probability: number;
  synthetic_score_percent: number;
  is_synthetic: boolean;
  total_clips: number;
  threshold: number;
};

type StreamEvent = {
  type?: string;
  phase?: string;
  message?: string;
  clips_done?: number;
  total_clips?: number;
  index?: number;
  error?: string;
  synthetic_score_percent?: number;
  is_synthetic?: boolean;
  probability?: number;
  threshold?: number;
};

export default function DetectPage() {
  const { pipelineReady, status } = useDeploymentStatus({});
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<DetectPhase>("idle");
  const [progressMessage, setProgressMessage] = useState("");
  const [clipsDone, setClipsDone] = useState(0);
  const [totalClips, setTotalClips] = useState<number | null>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const onDrop = useCallback((accepted: File[]) => {
    const f = accepted[0];
    if (!f) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
    setResult(null);
    setError(null);
    setPhase("idle");
    setClipsDone(0);
    setTotalClips(null);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { "video/mp4": [".mp4"] },
    maxFiles: 1,
    maxSize: 500 * 1024 * 1024,
    disabled: busy,
  });

  useEffect(() => {
    if (!busy) {
      if (timerRef.current) clearInterval(timerRef.current);
      return;
    }
    setElapsedSeconds(0);
    timerRef.current = setInterval(() => setElapsedSeconds((s) => s + 1), 1000);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [busy]);

  const applyStreamEvent = (event: StreamEvent) => {
    if (event.type === "phase" && event.phase) {
      setPhase(event.phase as DetectPhase);
      if (event.message) setProgressMessage(event.message);
      if (typeof event.total_clips === "number") setTotalClips(event.total_clips);
    }
    if (event.type === "clip") {
      setPhase("analyzing");
      if (typeof event.clips_done === "number") setClipsDone(event.clips_done);
      else if (typeof event.index === "number") setClipsDone(event.index + 1);
      setProgressMessage("Analyzing video clips…");
    }
    if (event.type === "done" || event.type === "result") {
      setPhase("done");
      setProgressMessage("Detection complete");
      if (typeof event.total_clips === "number") setTotalClips(event.total_clips);
      setResult({
        probability: Number(event.probability ?? 0),
        synthetic_score_percent: Number(event.synthetic_score_percent ?? 0),
        is_synthetic: Boolean(event.is_synthetic),
        total_clips: Number(event.total_clips ?? 0),
        threshold: Number(event.threshold ?? 0.3),
      });
    }
    if (event.type === "error") {
      setPhase("error");
      setError(event.error || "Detection failed");
    }
  };

  const runDetection = async () => {
    if (!file) return;
    setBusy(true);
    setError(null);
    setResult(null);
    setClipsDone(0);
    setTotalClips(null);
    setPhase("uploading");
    setProgressMessage("Uploading video…");

    const form = new FormData();
    form.append("video", file);

    try {
      let res = await fetch("/api/detect?stream=1", { method: "POST", body: form });
      if (!res.ok && res.headers.get("content-type")?.includes("json")) {
        const data = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(data.error || "Detection failed");
      }
      if (!res.ok || !res.body) {
        setPhase("analyzing");
        setProgressMessage("Analyzing video (legacy API)…");
        res = await fetch("/api/detect", { method: "POST", body: form });
        if (!res.ok) {
          const data = (await res.json().catch(() => ({}))) as { error?: string };
          throw new Error(data.error || "Detection failed");
        }
        const data = (await res.json()) as Result;
        setPhase("done");
        setProgressMessage("Detection complete");
        setResult(data);
        return;
      }
      const reader = res.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.trim()) continue;
          applyStreamEvent(JSON.parse(line) as StreamEvent);
        }
      }
      if (buffer.trim()) {
        applyStreamEvent(JSON.parse(buffer) as StreamEvent);
      }
    } catch (err) {
      setPhase("error");
      setError(err instanceof Error ? err.message : "Detection failed");
    } finally {
      setBusy(false);
    }
  };

  const mode = status?.nim_deploy_mode || status?.config?.nim_deploy_mode || "unknown";

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-4xl space-y-6 p-6">
        {!pipelineReady && (
          <p className="rounded border border-amber-800 bg-amber-950/40 px-4 py-3 text-sm">
            Pipeline not ready —{" "}
            <Link href="/demos/configure" className="underline">
              configure and build
            </Link>{" "}
            first (serverless mode wires endpoints immediately after build).
          </p>
        )}

        <Card title="Upload video">
          <p className="text-sm text-neutral-400 mb-4">
            H.264 MP4 only, max 500 MB. Mode: <strong>{String(mode)}</strong>
          </p>
          <div
            {...getRootProps()}
            className={`cursor-pointer rounded border-2 border-dashed p-10 text-center ${
              isDragActive ? "border-[var(--nvidia-green)]" : "border-neutral-700"
            } ${busy ? "pointer-events-none opacity-60" : ""}`}
          >
            <input {...getInputProps()} />
            {file ? file.name : "Drop MP4 here or click to browse"}
          </div>
          {preview && (
            <video src={preview} controls className="mt-4 w-full max-h-80 rounded bg-black" />
          )}

          <DetectionProgress
            phase={phase}
            message={progressMessage}
            clipsDone={clipsDone}
            totalClips={totalClips}
            elapsedSeconds={elapsedSeconds}
          />

          <button
            className="mt-4 rounded bg-[var(--nvidia-green)] px-4 py-2 font-medium text-black disabled:opacity-50"
            disabled={!file || busy || !pipelineReady}
            onClick={() => void runDetection()}
          >
            {busy ? "Detection in progress…" : "Run detection"}
          </button>
        </Card>

        {error && <p className="text-red-400">{error}</p>}

        {result && (
          <Card title="Detection summary">
            <div
              className={`text-2xl font-semibold mb-2 ${
                result.is_synthetic ? "text-red-400" : "text-green-400"
              }`}
            >
              {result.is_synthetic ? "Likely synthetic" : "Likely real"}
            </div>
            <p className="text-lg">
              Synthetic score: <strong>{result.synthetic_score_percent}%</strong>
            </p>
            <p className="text-sm text-neutral-400 mt-2">
              Threshold: {(result.threshold * 100).toFixed(0)}% — {result.total_clips} clips analyzed
            </p>
            <p className="text-sm text-neutral-500 mt-4">
              Higher scores indicate stronger evidence of AI-generated content. Scores above the threshold
              are classified as synthetic.
            </p>
          </Card>
        )}
      </main>
    </div>
  );
}
