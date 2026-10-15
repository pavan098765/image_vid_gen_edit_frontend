Place on-device inpaint model files here.

- Runtime model: `lama_dilated.tflite` (downloaded from R2 and cached locally)
- No bundled LaMa file is required in this folder.

Source (LaMa family):
- https://github.com/advimman/lama

Notes:
- The app uses `lama_dilated.tflite` for on-device inpaint/erase.
- The model URL/version is read from `tool_config.json` (`onDeviceModelUrl` and related fields).
- Input preprocessing is shape-aware and supports both:
  - single input tensor models (image+mask packed, typically 4 channels)
  - two input tensor models (separate image and mask tensors)
- Mask semantics in app:
  - painted area = remove/inpaint
  - non-painted area = keep
