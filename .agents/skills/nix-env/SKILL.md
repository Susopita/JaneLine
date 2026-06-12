---
name: nix-env
description: Governs how to run any command-line tool or shell operation in this project. Always use this skill whenever you are about to run any command (make, iverilog, vvp, git, hx, or any other tool) — especially when the command involves building, compiling, simulating, or using development tools in the ProyArqui project. This skill defines whether to wrap the command in nix-shell and what to do when a tool is not yet available in the Nix environment.
---

# Nix Environment — Command Execution Rules

This project uses [Nix](https://nixos.org/) to manage its development environment. The environment is defined in `shell.nix` at the project root. **All commands that require project tools must run through this environment.**

## Tools Available in the Current Environment

The following tools are currently declared in `shell.nix` under `buildInputs`:

| Tool          | Nix package  | Commands exposed  |
|---------------|--------------|-------------------|
| Git           | `git`        | `git`             |
| GNU Make      | `gnumake`    | `make`            |
| Icarus Verilog| `iverilog`   | `iverilog`, `vvp` |
| Helix editor  | `helix`      | `hx`              |

If you need to use any of these tools, wrap the command inside `nix-shell --run`:

```bash
nix-shell --run "<your command here>"
```

**Examples:**
```bash
# Correct — compile and simulate via Make
nix-shell --run "make run"

# Correct — run iverilog manually
nix-shell --run "iverilog -o build/sim.out src/top.v"

# Correct — run git status
nix-shell --run "git status"
```

> Never run project tools directly (e.g., bare `iverilog`, bare `make`) — they may not exist on the host system. Always go through `nix-shell --run`.

---

## When a Tool Is NOT in shell.nix

If you need a tool that is **not listed in the table above**, do NOT add it to `shell.nix` yourself. Instead:

1. **Stop and tell the user** which tool you need and why, using this format:

   > 🔧 **Tool needed:** `<tool-name>`
   > 
   > I need `<tool-name>` to <reason>. This tool is not currently in `shell.nix`.
   > Would you like me to add it? The Nix package name is likely `<nix-package-name>`.

2. **Wait for explicit confirmation** before making any changes to `shell.nix`.

3. Once confirmed, add the package to `buildInputs` in `shell.nix` and update the tool table in this skill file.

### How to find the right Nix package name

If you are unsure of the Nix package name, you can suggest searching for it:
```bash
nix-shell --run "nix search nixpkgs <tool-name>"
```
Or direct the user to [search.nixos.org](https://search.nixos.org/packages).

---

## Adding a New Tool (After User Confirmation)

Once the user confirms, add the package to `shell.nix`:

```nix
buildInputs = with pkgs; [
  git
  gnumake
  iverilog
  helix
  <new-package>  # ← add here
];
```

Then update the tool table in this SKILL.md to keep it in sync.

---

## Summary: Decision Flow

```
Need to run a command?
        │
        ▼
Is the tool in shell.nix?
   YES → wrap in: nix-shell --run "..."
    NO → tell the user, propose adding it, WAIT for confirmation
```
