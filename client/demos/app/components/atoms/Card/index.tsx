export default function Card({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-neutral-800 bg-neutral-950 p-6">
      {title ? <h2 className="mb-4 text-lg font-medium">{title}</h2> : null}
      {children}
    </section>
  );
}
