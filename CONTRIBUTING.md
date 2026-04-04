# Contributing

Thanks for wanting to improve vibe-friend!

## Getting started

```bash
git clone https://github.com/Matribuk/vibe-friend
cd vibe-friend
./build_app.sh
open VibeFriend.app
```

## Adding a new agent

In `ClaudeDetector.swift`, add the CLI process name to the `targets` set:

```swift
private let targets: Set<String> = [
    "claude",
    "your-agent-name-here",
    ...
]
```

The name must match exactly what appears in `ps -eo comm` when the tool runs.

## Adding sprites

Drop PNG files (transparent background) into `Sources/VibeFriend/Resources/` and reference them by name (without extension) in `PetInstance.swift`.

Sprites are expected at **187×366 px** with the character bottom-aligned. The hue recoloring targets orange-red pixels (h < 10% or h > 90%, s > 30%, v > 20%) — keep that range for your sprite's main color if you want per-session tinting to work.

## Submitting changes

1. Fork the repo
2. Create a branch (`git checkout -b my-feature`)
3. Commit your changes
4. Open a pull request

Please keep PRs focused — one feature or fix per PR.
