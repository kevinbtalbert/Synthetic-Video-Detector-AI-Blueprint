import type { DetectionResult } from "@/app/hooks/useVideoDetection";

export default function DetectionResultSummary({ result }: { result: DetectionResult }) {
  return (
    <div className="mt-4 rounded border border-neutral-800 bg-neutral-900/40 p-4">
      <div
        className={`text-lg font-semibold mb-1 ${
          result.is_synthetic ? "text-red-400" : "text-green-400"
        }`}
      >
        {result.is_synthetic ? "Likely synthetic" : "Likely real"}
      </div>
      <p>
        Synthetic score: <strong>{result.synthetic_score_percent}%</strong>
      </p>
      <p className="text-sm text-neutral-400 mt-1">
        Threshold: {(result.threshold * 100).toFixed(0)}% — {result.total_clips} clips analyzed
      </p>
    </div>
  );
}
