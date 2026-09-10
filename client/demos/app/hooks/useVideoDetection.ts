"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { DetectPhase } from "@/app/components/atoms/DetectionProgress";

export type DetectionResult = {
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

export function useVideoDetection() {
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<DetectPhase>("idle");
  const [progressMessage, setProgressMessage] = useState("");
  const [clipsDone, setClipsDone] = useState(0);
  const [totalClips, setTotalClips] = useState<number | null>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [result, setResult] = useState<DetectionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

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

  const reset = useCallback(() => {
    setResult(null);
    setError(null);
    setPhase("idle");
    setClipsDone(0);
    setTotalClips(null);
    setProgressMessage("");
  }, []);

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

  const runDetection = useCallback(async (file: File) => {
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
        const data = (await res.json()) as DetectionResult;
        setPhase("done");
        setProgressMessage("Detection complete");
        setResult(data);
        return;
      }

      const reader = res.body.getReader();
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
  }, []);

  return {
    busy,
    phase,
    progressMessage,
    clipsDone,
    totalClips,
    elapsedSeconds,
    result,
    error,
    reset,
    runDetection,
  };
}
