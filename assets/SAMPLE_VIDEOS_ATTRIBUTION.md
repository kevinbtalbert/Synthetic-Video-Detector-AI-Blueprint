# Demo sample videos — attribution

The Launchpad **Demo** tab serves two **independent** ~5 second MP4 clips (different subjects/scenes—not a before/after pair of the same take).

| File | Label | Source clip | Duration |
|------|--------|-------------|----------|
| `real_sample_video.mp4` | Authentic | [SDFVD](https://huggingface.co/datasets/Hemgg/SDFVD-video-dataset) `Real/v38.mp4` (720p stock; original footage from **Pexels**) | 5.0 s |
| `fake_sample_video.mp4` | Synthetic (face-swap) | [SDFVD](https://huggingface.co/datasets/Hemgg/SDFVD-video-dataset) `Fake/vs22.mp4` (Remaker AI face-swap on a **different** real clip, `v22`); first 5.0 s retained for the demo bundle | 5.0 s |

## Licenses (permissive use)

- **Real footage:** The SDFVD authors sourced originals from [Pexels](https://www.pexels.com/). Pexels content is free to use under the [Pexels License](https://www.pexels.com/license/) (including commercial use; attribution appreciated but not required).
- **Synthetic clip:** Distributed as part of the public **SDFVD** research dataset on Hugging Face. The same clips are also aggregated in [belkhir-nacim/deepfake-videos](https://huggingface.co/datasets/belkhir-nacim/deepfake-videos) under **CC BY 4.0** (with permission from contributing dataset authors). This blueprint redistributes only these two files for demo purposes.

## Citation

If you reference the sample clips in documentation or research:

```text
Hemgg. SDFVD video dataset. Hugging Face, 2025.
https://huggingface.co/datasets/Hemgg/SDFVD-video-dataset
```

Optional (unified mirror):

```bibtex
@misc{unified-deepfake-2024,
  title={Unified Deepfake Video Dataset},
  author={belkhir-nacim},
  year={2024},
  publisher={Hugging Face},
  url={https://huggingface.co/datasets/belkhir-nacim/deepfake-videos}
}
```

## Replacing the samples

1. Overwrite `real_sample_video.mp4` and/or `fake_sample_video.mp4`.
2. Update this file with source URLs, license, and citation.
3. Rebuild or redeploy the UI if your runtime image embeds `assets/` at build time.
