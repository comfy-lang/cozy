# cozy

**cozy** is the official CLI tool for the [comfy language](https://github.com/comfy-lang/comfy).

It wraps the comfy compiler with helpful commands for building and running code. In the future, it will also serve as the package manager and project scaffolding tool for comfy projects.

## Features

* Compile comfy source files
* Run comfy programs directly
* Generate new comfy project structures
* Download the latest comfy compiler binary
* (Planned) Manage compiler versions
* (Planned) Package management
* (Planned) Testing cli

## Usage

```bash
cozy new my-project             # Create a new comfy project
cozy build                      # Compile the current project
cozy run src/main.fy            # Build and run a file
cozy get-compiler               # Download the latest comfy compiler binary
cozy get-compiler --path <path> # Download to a custom folder
```

## Compiler Binary Management

The `cozy get-compiler` command downloads the latest version of the comfy compiler binary.

* By default, it installs to a standard location:

  * Linux/macOS: `$HOME/.cozy/bin`
  * Windows: (not supported yet)
* You can override the target location using `--path <folder>`
* Versioning support is planned for the future

## Installation

Coming soon. You will be able to install cozy via binary downloads or build it from source.

## Project Structure

cozy generates a simple comfy project layout:

```
my-project/
├── project.comfx         # Project config
├── src/
│   └── main.fy
└── build/
    └── output
└── tests/                # (Planned for testing)
    └── new-feature.tfy
```

---

Stay comfy :3
