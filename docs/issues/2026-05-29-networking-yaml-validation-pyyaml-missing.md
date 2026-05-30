# Networking YAML validation: PyYAML missing

## What I tested

Validated `argocd/applications/networking.yaml` after removing the redundant `directory.recurse: false` block.

## Attempted command

```bash
python3 -c "import yaml; yaml.safe_load(open('argocd/applications/networking.yaml'))"
```

## Actual output

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import yaml; yaml.safe_load(open('argocd/applications/networking.yaml'))
    ^^^^^^^^^^^
ModuleNotFoundError: No module named 'yaml'
```

## Root cause

The environment does not have `PyYAML` installed, so the spec-required validation command could not run.

## Follow-up

Validated the file with Ruby's built-in YAML parser instead:

```bash
ruby -e "require 'yaml'; YAML.load_file('argocd/applications/networking.yaml')"
```

That completed without output.
