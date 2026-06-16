# Multi-If Combinator

A Factorio 2.0 / Space Age mod that adds a single combinator capable of evaluating **many fully independent `IF` conditions at once**, where **each condition has its own dedicated output**.

This solves a structural limitation of the vanilla Decider Combinator: in 2.0 the decider can hold multiple conditions, but they are all combined (AND/OR) into a *single* boolean that drives *all* outputs together. It cannot express several parallel, unrelated rules in one entity.

The Multi-If Combinator can, for example, do all of this simultaneously:

- `IF iron plate < 500  THEN output iron plate = 500`
- `IF copper plate < 500 THEN output copper plate = 500`
- `IF steel < 200        THEN output steel = 200`

Each row is its own little `IF … THEN …` statement, evaluated and output independently.

## How it works

The placed entity is a reskinned decider combinator, used only for its separate **input** and **output** circuit poles and its visuals (it is tinted orange to stand out).

On placement the mod spawns an **invisible constant combinator** and wires it — with non-editable script wires — to the main entity's **output** poles. Every update the runtime:

1. reads and merges the red + green signals on the **input** poles,
2. evaluates each configured condition row,
3. writes the outputs of the passing rows onto the hidden constant combinator, which emits them on the output network.

Because input and output live on separate circuit networks, outputs never feed back into the conditions.

## Usage

1. Research **Circuit network** (same technology that unlocks the vanilla combinators).
2. Craft and place the **Multi-If Combinator**.
3. Wire your signal source(s) to the **input** side and your consumers to the **output** side, like any combinator.
4. Click the combinator to open the custom panel and **Add condition** rows. Each row is:

   `[input signal] [operator] [constant value OR comparison signal]  →  [output signal] [output value]`

   - Operators: `<`, `>`, `=`, `≥`, `≤`, `≠`.
   - If a **comparison signal** is selected, it is read from the input network and the constant value is ignored.
   - A row only takes effect once it has both an input signal and an output signal.
   - Below each input signal the panel shows the **live amount** of that signal currently on the input network, so you can see at a glance what is lacking.

Configuration is saved per combinator and travels with **blueprints**, **copy-paste** (Shift+right-click / Shift+left-click) and **cloning**.

## Performance (UPS)

- Combinators are bucketed by `unit_number % interval`; only the bucket for the current tick is processed, spreading work evenly across ticks.
- Each combinator caches the signature of its last output and **skips rewriting** the hidden constant combinator when the result is unchanged (the common steady state).
- The update interval is configurable via the **Multi-If update interval** startup setting (default 20 ticks ≈ 3 updates/second).

## Project layout

| Path | Purpose |
| --- | --- |
| `info.json` | Mod metadata (base ≥ 2.0). |
| `settings.lua` | Startup setting for the update interval. |
| `data.lua` + `prototypes/` | Item, recipe and entity prototypes (the main combinator + the hidden output combinator). |
| `control.lua` | Runtime: custom GUI, persistence in `storage`, signal evaluation, scheduling, blueprint/copy-paste/clone support. |
| `locale/en`, `locale/pt-BR` | English and Brazilian Portuguese localization. |
| `scripts/`, `.github/workflows/` | Packaging and CI/CD (develop artifact builds + main releases to GitHub and the Mod Portal). |

## Compatibility

- Factorio 2.0+ (base game). Space Age compatible (no hard dependency).
- Reuses base-game decider combinator sprites/icons, so no extra art assets are shipped.

## Packaging

Set the target release version in `info.json`, then run `./scripts/package.sh` to generate `multi-if-combinator_<version>.zip` containing the folder `multi-if-combinator_<version>/` with all runtime files.

Pushes to `develop` build the same versioned zip as a workflow artifact for local testing. Pushes to `main` build the zip, create the matching GitHub release tag, attach the zip to the GitHub Release, and publish to the Factorio Mod Portal. Configure the GitHub Actions secret `FACTORIO_MOD_PORTAL_TOKEN` with a Mod Portal API token before publishing from `main`.

Maintainer note: whenever `info.json` version changes for a release, append a new section to the top of `changelog.txt` using the Factorio changelog tags (`Features`, `Changes`, `Bugfixes`, `Info`).

## Version History

- `1.0.0` — Initial release: Multi-If Combinator entity/item/recipe, custom per-row GUI, hidden-combinator scripted output, UPS-friendly scheduling, blueprint/copy-paste/clone support, English + Brazilian Portuguese localization.
