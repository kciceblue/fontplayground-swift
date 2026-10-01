# Font fixtures policy

- Never commit Apple, Microsoft or other proprietary font files. Tests build
  synthetic fonts at runtime, or read installed system fonts in place in the
  opt-in `apple_fonts` suite.
- Open-licence fonts may be committed here only if they are at most 200 KB and
  listed below with their licence.
- Conformance fixtures are generated, never edited by hand. Their generator
  records its inputs and the `fpengine` version in each file's header object.

| File | Licence | Source | Size |
|---|---|---|---|
