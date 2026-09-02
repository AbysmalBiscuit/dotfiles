# Vendored dependencies

## tomlkit

Version: 0.15.1. Pure Python, MIT-licensed (see `tomlkit/LICENSE`).

Vendored because no `.chezmoiscripts` hook installs anything with pip or uv,
and a `chezmoi apply` that depends on a package index is a `chezmoi apply`
that fails on a plane.

To regenerate:

```bash
SRC="$SCRATCHPAD/tomlkit-src"
mkdir -p .agentcfg/vendor "$SRC"
uvx --from pip pip download tomlkit --no-deps --no-binary :all: -d "$SRC"
python3 -c "import glob,sys,tarfile; tarfile.open(glob.glob(sys.argv[1])[0]).extractall(sys.argv[2], filter='data')" "$SRC/tomlkit-*.tar.gz" "$SRC"
cp -r "$SRC"/tomlkit-*/tomlkit .agentcfg/vendor/tomlkit
cp "$SRC"/tomlkit-*/LICENSE .agentcfg/vendor/tomlkit/LICENSE
```

Verify the copy imports standalone and reports its version from package
metadata:

```bash
cd .agentcfg && python3 -c "import sys; sys.path.insert(0, 'vendor'); import tomlkit; print(tomlkit.__version__)"
```

After regenerating, check the vendored tree for the literal marker chezmoi's
`modifyTemplateRx` looks for (the string that opts a modify script's stdout
into template processing) — it must not appear anywhere under `.agentcfg/`,
vendored code included.
