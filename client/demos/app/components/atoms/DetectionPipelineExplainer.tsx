"use client";

const STEPS = [
  {
    title: "Upload & validate",
    body: "Your MP4 is sent securely to the NVIDIA Synthetic Video Detector NIM. Only H.264 MP4 is supported (same constraint as production NIM deployments).",
  },
  {
    title: "Temporal clip analysis",
    body: "The Hiera-based model splits the video into short clips. Each clip gets a raw score (logit) tied to a frame index in the timeline—not a single guess for the whole file.",
  },
  {
    title: "Stream results",
    body: "Scores stream back while inference runs, so you can see progress clip-by-clip. This is the same gRPC API used on build.nvidia.com and in bundled GPU runtimes.",
  },
  {
    title: "Aggregate verdict",
    body: "Clip scores are combined into one synthetic probability. Above 30% threshold → likely AI-generated; below → likely authentic. Use the timeline chart to spot suspicious segments.",
  },
];

export default function DetectionPipelineExplainer({ deployMode }: { deployMode: string }) {
  return (
    <section className="rounded-xl border border-neutral-800 bg-gradient-to-br from-neutral-950 via-neutral-950 to-[#0f140a] p-6">
      <div className="mb-5 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-[var(--nvidia-green)]">
            Why this matters
          </p>
          <h2 className="text-xl font-semibold text-neutral-100">
            Trust signals for synthetic media
          </h2>
        </div>
        <span className="inline-flex w-fit rounded-full border border-neutral-700 bg-neutral-900 px-3 py-1 text-xs text-neutral-400">
          Runtime: {deployMode}
        </span>
      </div>
      <p className="mb-6 max-w-3xl text-sm leading-relaxed text-neutral-400">
        AI-generated video is increasingly realistic. This blueprint runs{" "}
        <strong className="font-medium text-neutral-200">NVIDIA Synthetic Video Detector</strong>{" "}
        on Cloudera AI—either bundled on GPU in your project or via NVIDIA cloud inference—so teams
        can authenticate footage, flag deepfakes in editorial workflows, and audit media before
        publish.
      </p>
      <ol className="grid gap-4 sm:grid-cols-2">
        {STEPS.map((step, i) => (
          <li
            key={step.title}
            className="rounded-lg border border-neutral-800/80 bg-black/40 p-4"
          >
            <div className="mb-2 flex items-center gap-2">
              <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--nvidia-green)]/15 text-xs font-bold text-[var(--nvidia-green)]">
                {i + 1}
              </span>
              <h3 className="text-sm font-medium text-neutral-100">{step.title}</h3>
            </div>
            <p className="text-xs leading-relaxed text-neutral-500">{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
