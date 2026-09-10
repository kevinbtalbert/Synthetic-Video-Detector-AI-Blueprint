"use client";

import { useState } from "react";
import DetectionProgress from "@/app/components/atoms/DetectionProgress";
import DetectionResultSummary from "@/app/components/atoms/DetectionResultSummary";
import { useVideoDetection } from "@/app/hooks/useVideoDetection";

export type SampleVideo = {
  id: string;
  label: string;
  description: string;
  src: string;
  filename: string;
};

type Props = {
  sample: SampleVideo;
  pipelineReady: boolean;
};

export default function SampleDetectionPanel({ sample, pipelineReady }: Props) {
  const detection = useVideoDetection();
  const [loadError, setLoadError] = useState<string | null>(null);

  const runSampleDetection = async () => {
    setLoadError(null);
    const res = await fetch(sample.src);
    if (!res.ok) {
      setLoadError("Sample video not available");
      return;
    }
    const blob = await res.blob();
    const file = new File([blob], sample.filename, { type: "video/mp4" });
    await detection.runDetection(file);
  };

  return (
    <div className="flex flex-col rounded-lg border border-neutral-800 bg-neutral-950 p-4">
      <h3 className="text-base font-medium">{sample.label}</h3>
      <p className="mb-3 text-sm text-neutral-400">{sample.description}</p>

      <video
        src={sample.src}
        controls
        className="w-full max-h-56 rounded bg-black"
        preload="metadata"
      />

      <DetectionProgress
        phase={detection.phase}
        message={detection.progressMessage}
        clipsDone={detection.clipsDone}
        totalClips={detection.totalClips}
        elapsedSeconds={detection.elapsedSeconds}
      />

      <button
        className="mt-4 rounded bg-[var(--nvidia-green)] px-4 py-2 text-sm font-medium text-black disabled:opacity-50"
        disabled={detection.busy || !pipelineReady}
        onClick={() => void runSampleDetection()}
      >
        {detection.busy ? "Detection in progress…" : "Run detection"}
      </button>

      {(loadError || detection.error) && (
        <p className="mt-3 text-sm text-red-400">{loadError || detection.error}</p>
      )}
      {detection.result && <DetectionResultSummary result={detection.result} />}
    </div>
  );
}
