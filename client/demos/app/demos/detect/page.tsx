"use client";

import { useCallback, useState } from "react";
import Link from "next/link";
import { useDropzone } from "react-dropzone";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import DetectionProgress from "@/app/components/atoms/DetectionProgress";
import DetectionResultSummary from "@/app/components/atoms/DetectionResultSummary";
import { useVideoDetection } from "@/app/hooks/useVideoDetection";
import { resolveDeployMode, useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

export default function DetectPage() {
  const { pipelineReady, status } = useDeploymentStatus({});
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const detection = useVideoDetection();

  const onDrop = useCallback(
    (accepted: File[]) => {
      const f = accepted[0];
      if (!f) return;
      setFile(f);
      setPreview(URL.createObjectURL(f));
      detection.reset();
    },
    [detection.reset],
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { "video/mp4": [".mp4"] },
    maxFiles: 1,
    maxSize: 500 * 1024 * 1024,
    disabled: detection.busy,
  });

  const mode = resolveDeployMode(status);

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-4xl space-y-6 p-6">
        {!pipelineReady && (process.env.NEXT_PUBLIC_SVD_APP_ROLE || "launchpad") === "launchpad" && (
          <p className="rounded border border-amber-800 bg-amber-950/40 px-4 py-3 text-sm">
            Deploy a runtime application from the{" "}
            <Link href="/demos/configure" className="underline">
              Launchpad
            </Link>{" "}
            first, then open that app&apos;s URL to run detection.
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
            } ${detection.busy ? "pointer-events-none opacity-60" : ""}`}
          >
            <input {...getInputProps()} />
            {file ? file.name : "Drop MP4 here or click to browse"}
          </div>
          {preview && (
            <video src={preview} controls className="mt-4 w-full max-h-80 rounded bg-black" />
          )}

          <DetectionProgress
            phase={detection.phase}
            message={detection.progressMessage}
            clipsDone={detection.clipsDone}
            totalClips={detection.totalClips}
            elapsedSeconds={detection.elapsedSeconds}
          />

          <button
            className="mt-4 rounded bg-[var(--nvidia-green)] px-4 py-2 font-medium text-black disabled:opacity-50"
            disabled={!file || detection.busy || !pipelineReady}
            onClick={() => file && void detection.runDetection(file)}
          >
            {detection.busy ? "Detection in progress…" : "Run detection"}
          </button>
        </Card>

        {detection.error && <p className="text-red-400">{detection.error}</p>}

        {detection.result && (
          <Card title="Detection summary">
            <DetectionResultSummary result={detection.result} />
            <p className="text-sm text-neutral-500 mt-4">
              Higher scores indicate stronger evidence of AI-generated content. Scores above the
              threshold are classified as synthetic.
            </p>
          </Card>
        )}
      </main>
    </div>
  );
}
