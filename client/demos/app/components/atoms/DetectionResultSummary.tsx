import type { DetectionResult } from "@/app/lib/detectionTypes";

export default function DetectionResultSummary({ result }: { result: DetectionResult }) {
  const synthetic = result.is_synthetic;

  return (
    <div className="rounded-lg border border-neutral-700 bg-neutral-900 p-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <span
            className={`flex h-10 w-10 items-center justify-center rounded-full text-lg ${
              synthetic ? "bg-red-500/15 text-red-400" : "bg-[var(--nvidia-green)]/15 text-[var(--nvidia-green)]"
            }`}
            aria-hidden
          >
            {synthetic ? "!" : "✓"}
          </span>
          <div>
            <h3 className="text-lg font-semibold text-neutral-100">
              {synthetic ? "Likely synthetic video" : "Likely real video"}
            </h3>
            <p className="text-sm text-neutral-400">
              {synthetic
                ? "Aggregate score is at or above the detection threshold—treat as potential AI-generated content."
                : "Aggregate score is below the threshold—consistent with authentic footage."}
            </p>
          </div>
        </div>
        <span
          className={`inline-flex shrink-0 rounded-full px-4 py-1.5 text-sm font-semibold ${
            synthetic
              ? "bg-red-500/20 text-red-300"
              : "bg-[var(--nvidia-green)]/20 text-[var(--nvidia-green)]"
          }`}
        >
          Synthetic score: {result.synthetic_score_percent}%
        </span>
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-3 border-t border-neutral-800 pt-4 text-xs sm:grid-cols-4">
        <div>
          <dt className="text-neutral-500">Probability</dt>
          <dd className="font-medium text-neutral-200">{(result.probability * 100).toFixed(1)}%</dd>
        </div>
        <div>
          <dt className="text-neutral-500">Threshold</dt>
          <dd className="font-medium text-neutral-200">{(result.threshold * 100).toFixed(0)}%</dd>
        </div>
        <div>
          <dt className="text-neutral-500">Clips analyzed</dt>
          <dd className="font-medium text-neutral-200">{result.total_clips}</dd>
        </div>
        <div>
          <dt className="text-neutral-500">Model output</dt>
          <dd className="font-medium text-neutral-200">
            {result.logit != null ? `logit ${result.logit.toFixed(3)}` : "aggregated mean"}
          </dd>
        </div>
      </dl>
    </div>
  );
}
