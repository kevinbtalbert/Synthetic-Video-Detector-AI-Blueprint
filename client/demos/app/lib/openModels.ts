export type OpenModelPreset = {
  id: string;
  name: string;
  subtitle: string;
  hf_model_id: string;
  kind: "image" | "videomae";
  recommended?: boolean;
  vram_gb?: number;
  tags?: string[];
  summary: string;
  metrics_hint?: string;
  hf_url: string;
};

export type OpenModelCatalog = {
  default_preset_id: string;
  presets: OpenModelPreset[];
};

export function presetById(catalog: OpenModelCatalog, id: string): OpenModelPreset | undefined {
  return catalog.presets.find((p) => p.id === id);
}
