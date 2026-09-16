"use client";

import Link from "next/link";
import Header from "@/app/components/atoms/Header";
import LaunchpadDeployBanner from "@/app/components/atoms/LaunchpadDeployBanner";
import NimStartupProgress from "@/app/components/atoms/NimStartupProgress";
import { useAppRole } from "@/app/hooks/useAppRole";
import DetectionPipelineExplainer from "@/app/components/atoms/DetectionPipelineExplainer";
import SampleDetectionPanel, {
  type SampleVideo,
} from "@/app/components/atoms/SampleDetectionPanel";
import { resolveDeployMode, useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

const SAMPLE_VIDEOS: SampleVideo[] = [
  {
    id: "real",
    label: "Real video",
    description:
      "FaceForensics++ original sequence 000 (~5 s) — expected to classify as real.",
    src: "/api/samples/real",
    filename: "real_sample_video.mp4",
  },
  {
    id: "fake",
    label: "Synthetic video",
    description:
      "FaceForensics++ Deepfakes clip 000_003 (~5 s) — expected to classify as synthetic.",
    src: "/api/samples/fake",
    filename: "fake_sample_video.mp4",
  },
];

export default function DemoPage() {
  const { isRuntime } = useAppRole();
  const { pipelineReady, status } = useDeploymentStatus({});
  const mode = resolveDeployMode(status);

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-6xl space-y-6 p-6">
        <LaunchpadDeployBanner pipelineReady={pipelineReady} />
        {isRuntime && ["OPEN", "BUNDLED"].includes(String(mode).toUpperCase()) && <NimStartupProgress />}

        <DetectionPipelineExplainer deployMode={String(mode)} />

        <section className="rounded-xl border border-neutral-800 bg-neutral-950 p-6">
          <h2 className="mb-2 text-lg font-medium">Side-by-side samples</h2>
          <p className="mb-6 text-sm text-neutral-400">
            Run the same pipeline NVIDIA publishes on build.nvidia.com—compare expected real vs
            synthetic outcomes, then inspect the timeline chart for each clip.
          </p>

          <div className="grid gap-6 md:grid-cols-2">
            {SAMPLE_VIDEOS.map((sample) => (
              <SampleDetectionPanel
                key={sample.id}
                sample={sample}
                pipelineReady={pipelineReady}
              />
            ))}
          </div>

          <p className="mt-4 text-xs text-neutral-500">
            Sample videos are from{" "}
            <a
              href="https://github.com/ondyari/FaceForensics"
              className="text-[var(--nvidia-green)] underline"
              target="_blank"
              rel="noreferrer"
            >
              FaceForensics++
            </a>{" "}
            (research use; see{" "}
            <code className="text-neutral-400">assets/SAMPLE_VIDEOS_ATTRIBUTION.md</code> in the
            project repo).
          </p>

          <p className="mt-4 text-sm text-neutral-500">
            To analyze your own file, use the{" "}
            <Link href="/demos/detect" className="text-[var(--nvidia-green)] underline">
              Detect
            </Link>{" "}
            tab.
          </p>
        </section>
      </main>
    </div>
  );
}
