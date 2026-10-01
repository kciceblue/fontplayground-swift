try:
    from fpengine.cli import main
except KeyboardInterrupt:
    raise SystemExit(130) from None

raise SystemExit(main())
