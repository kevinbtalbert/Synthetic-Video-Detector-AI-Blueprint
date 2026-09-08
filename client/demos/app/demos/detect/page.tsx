"use client";

import { useCallback, useState } from "react";
import Link from "next/link";
import { useDropzone } from "react-dropzone";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import { useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

type Result = {
  probability: number;
  synthetic_score_percent: number;
  is_synthetic: boolean;
  total_clips: number;
  threshold: number;
};

export default function DetectPage() {
  const { pipelineReady, status } = useDeploymentStatus({});
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);

  const onDrop = useCallback((accepted: File[]) => {
    const f = accepted[0];
    if (!f) return;
    setFile(f);
    setPreview(URL.createObjectURL(f));
    setResult(null);
    setError(null);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { "video/mp4": [".mp4"] },
    maxFiles: 1,
    maxSize: 500 * 1024 * 1024,
  });

  const runDetection = async () => {
    if (!file) return;
    setBusy(true);
    setError(null);
    const form = new FormData();
    form.append("video", file);
    try {
      const res = await fetch("/api/detect", { method: "POST", body: form });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Detection failed");
      setResult(data);
    } catch (err) {
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
            }`}
          >
            <input {...getInputProps()} />
            {file ? file.name : "Drop MP4 here or click to browse"}
          </div>
          {preview && (
            <video src={preview} controls className="mt-4 w-full max-h-80 rounded bg-black" />
          )}
          <button
            className="mt-4 rounded bg-[var(--nvidia-green)] px-4 py-2 font-medium text-black disabled:opacity-50"
            disabled={!file || busy}
            onClick={() => void runDetection()}
          >
            {busy ? "Analyzing…" : "Run detection"}
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
