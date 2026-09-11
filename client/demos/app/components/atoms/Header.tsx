import Link from "next/link";
import { getAppRole } from "@/app/lib/appRole";

export default function Header() {
  const isLaunchpad = getAppRole() === "launchpad";

  return (
    <header className="border-b border-neutral-800 px-6 py-4 flex items-center justify-between">
      <div>
        <h1 className="text-xl font-semibold text-[var(--nvidia-green)]">Synthetic Video Detector</h1>
        <p className="text-sm text-neutral-400">
          {isLaunchpad ? "Launchpad — generate standalone runtime applications" : "NVIDIA NIM Runtime"}
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
