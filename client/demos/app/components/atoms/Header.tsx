import Link from "next/link";

export default function Header() {
  return (
    <header className="border-b border-neutral-800 px-6 py-4 flex items-center justify-between">
      <div>
        <h1 className="text-xl font-semibold text-[var(--nvidia-green)]">Synthetic Video Detector</h1>
        <p className="text-sm text-neutral-400">NVIDIA NIM Blueprint</p>
      </div>
      <nav className="flex gap-4 text-sm">
        <Link href="/demos/detect" className="hover:text-[var(--nvidia-green)]">
          Detect
        </Link>
        <Link href="/demos/demo" className="hover:text-[var(--nvidia-green)]">
          Demo
        </Link>
        <Link href="/demos/configure" className="hover:text-[var(--nvidia-green)]">
          Configure
        </Link>
      </nav>
    </header>
  );
}
