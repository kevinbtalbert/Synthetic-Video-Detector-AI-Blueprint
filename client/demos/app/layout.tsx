import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Synthetic Video Detector",
  description: "Detect AI-generated video content with NVIDIA NIM",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
