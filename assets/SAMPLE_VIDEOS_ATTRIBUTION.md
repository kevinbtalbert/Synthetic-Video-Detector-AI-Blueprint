# Demo sample videos — attribution

The side-by-side clips in the Launchpad **Demo** tab are short MP4s from the public research dataset **FaceForensics++**, bundled in this repo for offline smoke tests only.

| File | Label | Source in FaceForensics++ | Duration |
|------|--------|---------------------------|----------|
| `real_sample_video.mp4` | Authentic | Original YouTube sequence **000** (H.264 **c23** compression) | ~4.9 s |
| `fake_sample_video.mp4` | Synthetic (manipulated) | **Deepfakes** manipulation **000_003** (swap using donor sequence **003** on base **000**, c23) | ~4.9 s |

## Citation

If you use these samples in a paper or report, cite FaceForensics++:

```bibtex
@inproceedings{rossler2019faceforensics++,
  title={FaceForensics++: Learning to Detect Manipulated Facial Images},
  author={R{\"o}ssler, Andreas and Coelho, Davi and K{\"o}pfer, Nicolas and Cozzolino, Dario and Nie{\ss}ner, Matthias},
  booktitle={Proceedings of the IEEE/CVF International Conference on Computer Vision (ICCV)},
  year={2019}
}
```

## Where the files came from

- **Dataset home:** [ondyari/FaceForensics](https://github.com/ondyari/FaceForensics) (FaceForensics++ download requires accepting the authors’ [dataset terms](https://github.com/ondyari/FaceForensics/tree/master/dataset)).
- **Copies in this repo:** Retrieved from the Hugging Face mirror [TonyStark03/deepfake](https://huggingface.co/datasets/TonyStark03/deepfake) (`000.mp4` and `000_003.mp4`, renamed for the blueprint). That mirror is a convenience for small research clips; the canonical distribution remains the FaceForensics++ release.

## License and use

FaceForensics++ is intended for **non-commercial research and education**. Do not use these clips to imply endorsement by the dataset authors, YouTube, or Cloudera. For production or commercial demos, replace the files under `assets/` with media you own or that is licensed for your use, and update this document.

## Replacing the samples

1. Overwrite `real_sample_video.mp4` and/or `fake_sample_video.mp4` in this directory.
2. Update this file with source, license, and citation.
3. Rebuild or redeploy the UI if your runtime image embeds `assets/` at build time.
