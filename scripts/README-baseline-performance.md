`just baseline-performance` writes a timestamped snapshot under `perf-baseline/`.

It captures:

- cluster state (`nodes`, `pods`, `events`, `storageclasses`, `PVC/PV`)
- Longhorn state (`volumes`, `replicas`, `settings`)
- Prometheus-backed baseline metrics (node CPU, free memory, load, disk busy, top pods by CPU and memory)

Use the same command before and after each change and compare the generated `summary.md` files.
