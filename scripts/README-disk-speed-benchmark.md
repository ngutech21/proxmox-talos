`just disk-speed-benchmark` runs an explicit `fio` write/read benchmark against a fresh PVC.

It is intentionally separate from `just baseline-performance` because it creates real write load and changes the storage state during the run.

Default benchmark profiles:

- `seqread`
- `seqwrite`
- `randread4k`
- `randwrite4k`

Example:

```bash
just disk-speed-benchmark
just disk-speed-benchmark longhorn 8Gi 30 talos-wk-02 docker.io/xridge/fio:latest false
just disk-speed-benchmark longhorn 8Gi 30 talos-wk-02 docker.io/xridge/fio:latest false perf-disk 2
```

Arguments are:

1. storage class
2. PVC size
3. runtime per profile in seconds
4. target node (empty string keeps default scheduling)
5. fio image
6. keep resources (`true` or `false`)
7. output root
8. replica count override (empty string keeps the storage class default)

The script uses a separate `1G` test file by default so the PVC itself is not filled completely during the run.
