"use client";

import Link from "next/link";
import Header from "@/app/components/atoms/Header";
import Card from "@/app/components/atoms/Card";
import SampleDetectionPanel, {
  type SampleVideo,
} from "@/app/components/atoms/SampleDetectionPanel";
import { useDeploymentStatus } from "@/app/hooks/useDeploymentStatus";

const SAMPLE_VIDEOS: SampleVideo[] = [
  {
    id: "real",
    label: "Real video",
    description: "Authentic footage — expected to classify as real.",
    src: "/api/samples/real",
    filename: "real_sample_video.mp4",
  },
  {
    id: "fake",
    label: "Synthetic video",
    description: "AI-generated example — expected to classify as synthetic.",
    src: "/api/samples/fake",
    filename: "fake_sample_video.mp4",
  },
];

export default function DemoPage() {
  const { pipelineReady, status } = useDeploymentStatus({});
  const mode = status?.nim_deploy_mode || status?.config?.nim_deploy_mode || "unknown";

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-6xl space-y-6 p-6">
        {!pipelineReady && (
          <p className="rounded border border-amber-800 bg-amber-950/40 px-4 py-3 text-sm">
            Pipeline not ready —{" "}
            <Link href="/demos/configure" className="underline">
              configure and build
            </Link>{" "}
            first.
          </p>
        )}

        <Card title="Demo">
          <p className="mb-6 text-sm text-neutral-400">
            Compare detection on bundled real and synthetic sample videos. Mode:{" "}
            <strong>{String(mode)}</strong>
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

          <p className="mt-6 text-sm text-neutral-500">
            To analyze your own file, use the{" "}
            <Link href="/demos/detect" className="text-[var(--nvidia-green)] underline">
              Detect
            </Link>{" "}
            tab.
          </p>
        </Card>
      </main>
    </div>
  );
}
