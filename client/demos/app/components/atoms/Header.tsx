"use client";

import Link from "next/link";
import { useAppRole } from "@/app/hooks/useAppRole";

export default function Header() {
  const { isLaunchpad } = useAppRole();

  return (
    <header className="flex items-center justify-between border-b border-neutral-800 bg-neutral-950/80 px-6 py-4 backdrop-blur-sm">
      <div>
        <p className="text-[10px] font-semibold uppercase tracking-[0.2em] text-neutral-500">
          NVIDIA NIM · Cloudera AI Blueprint
        </p>
        <h1 className="text-xl font-semibold text-[var(--nvidia-green)]">Synthetic Video Detector</h1>
        <p className="text-sm text-neutral-400">
          {isLaunchpad
            ? "Deploy bundled GPU or serverless inference apps for your project"
            : "Clip-level AI detection for media integrity & forensics"}
        </p>
      </div>
      <nav className="flex gap-4 text-sm">
        {isLaunchpad ? (
          <Link href="/demos/configure" className="hover:text-[var(--nvidia-green)]">
            Deploy
          </Link>
        ) : (
          <>
            <Link href="/demos/detect" className="hover:text-[var(--nvidia-green)]">
              Detect
            </Link>
            <Link href="/demos/demo" className="hover:text-[var(--nvidia-green)]">
              Demo
            </Link>
          </>
        )}
      </nav>
    </header>
  );
}
