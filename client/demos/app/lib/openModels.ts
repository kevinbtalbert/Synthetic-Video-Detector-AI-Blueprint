export type OpenModelPresetMoreInfo = {
  what_it_offers?: string;
  best_for?: string;
  limitations?: string;
  highlights?: string[];
};

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
  more_info?: OpenModelPresetMoreInfo;
};

export type OpenModelCatalog = {
  default_preset_id: string;
  presets: OpenModelPreset[];
};

export function presetById(catalog: OpenModelCatalog, id: string): OpenModelPreset | undefined {
  return catalog.presets.find((p) => p.id === id);
}
