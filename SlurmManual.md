# Slurm Cluster Reference Manual

A practical guide to the commands you actually need: checking node availability, picking the right partition, submitting and managing jobs, and diagnosing problems.

---

## 1. Cluster Overview — What's Available?

Before submitting anything, understand the cluster's current state.

- **List all partitions and node states:**
  ```bash
  sinfo
  ```
  Shows partitions, time limits, node counts, and states (`idle`, `mix`, `alloc`, `drain`, `down`, etc.).

- **List GPU types and per-node state (very useful):**
  ```bash
  sinfo -p gpu -o "%N %G %t"
  ```
  Shows which nodes have which GPU model (`v100`, `a100`, `h100`) and current state.

- **Show only idle (free) nodes in a partition:**
  ```bash
  sinfo -p gpu -t idle
  sinfo -p gpu -t idle -o "%N %G"
  ```

- **Compact one-line-per-partition summary:**
  ```bash
  sinfo -s
  ```

- **See the maximum allowed time limit per partition:**
  ```bash
  sinfo -o "%P %l"
  ```
  The `%l` column is the partition's time limit (e.g. `7-00:00:00` = 7 days). Your job's `--time` must not exceed this.

### Node State Meanings (Quick Reference)

| State    | Meaning                                                  |
|----------|----------------------------------------------------------|
| `idle`   | Free, nothing running. Best target.                      |
| `mix`    | Some resources used, some free. Often still schedulable. |
| `alloc`  | Fully allocated. No room.                                |
| `drain`  | Admin marked it to stop accepting jobs.                  |
| `down`   | Not responding / offline.                                |
| `maint`  | Reserved for maintenance.                                |
| `resv`   | Held by a reservation.                                   |

---

## 2. Detailed Node Inspection

When you want to know if a specific node is healthy and what it offers.

- **Full info on one node:**
  ```bash
  scontrol show node gpu050
  ```
  Look for:
  - `State=` — health/availability
  - `Reason=` — if drained or down, says why
  - `Gres=` — GPU type and count (e.g. `gpu:a100:8`)
  - `CfgTRES=` vs `AllocTRES=` — total vs currently in use
  - `RealMemory=`, `CPUTot=` — hardware specs

- **Recent job history on a node (spot flaky hardware):**
  ```bash
  sacct -N gpu050 -S now-7days -o JobID,State,ExitCode,NodeList | head -30
  ```
  Lots of `NODE_FAIL` or `FAILED` exits = suspicious. Mostly `COMPLETED 0:0` = healthy.

- **Show partition configuration in detail:**
  ```bash
  scontrol show partition gpu
  ```
  Reveals `MaxTime`, `DefaultTime`, allowed accounts, etc.

---

## 3. Checking the Queue

- **See all jobs currently in the system:**
  ```bash
  squeue
  ```

- **See only your jobs:**
  ```bash
  squeue -u $USER
  ```

- **See only pending jobs in a partition (jobs ahead of you):**
  ```bash
  squeue -p gpu -t PD --sort=-p,i
  ```

- **Count how many jobs are pending above yours:**
  ```bash
  squeue -p gpu -t PD --sort=-p,i | awk 'NR>1' | wc -l
  ```

- **See pending jobs with priority values:**
  ```bash
  squeue -p gpu -t PD -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R %p" --sort=-p
  ```

- **Estimated start time for a queued job:**
  ```bash
  squeue -j <jobid> --start
  scontrol show job <jobid> | grep -E "StartTime|Reason"
  ```

### Common Pending Reasons

| Reason              | Meaning                                              |
|---------------------|------------------------------------------------------|
| `(Priority)`        | Waiting turn; not enough matching resources free.    |
| `(Resources)`       | Right resources don't exist or aren't free yet.      |
| `(QOSMaxJobsPerUser)` | You've hit a per-user job cap.                     |
| `(AssocGrpCpuLimit)` | Account/group resource cap reached.                |
| `(ReqNodeNotAvail)` | Requested node is down/drained.                      |
| `(Dependency)`      | Waiting on another job (`--dependency`).             |

---

## 4. Submitting Jobs

- **Submit a batch script:**
  ```bash
  sbatch my_script.sh
  ```

- **Submit with command-line overrides:**
  ```bash
  sbatch --time=4:00:00 --gres=gpu:v100:1 my_script.sh
  ```

- **Interactive session (great for testing/debugging):**
  ```bash
  srun --partition=gpu --gres=gpu:v100:1 --cpus-per-task=4 --mem=16G --time=00:30:00 --pty bash
  ```

- **Quick one-off command on a compute node:**
  ```bash
  srun --partition=gpu --gres=gpu:1 --time=00:05:00 nvidia-smi
  ```

### Example Batch Script (annotated)

```bash
#!/bin/bash
#SBATCH --job-name=run_dgpo            # Shown in squeue
#SBATCH --output=logs/%x_%j.out        # %x=job name, %j=job id
#SBATCH --error=logs/%x_%j.err
#SBATCH --partition=gpu                # Partition to run in
#SBATCH --gres=gpu:v100:1              # 1 V100 GPU (or gpu:a100:1, or gpu:1 for any)
#SBATCH --cpus-per-task=8              # CPU cores
#SBATCH --mem=32G                      # System RAM
#SBATCH --time=08:00:00                # Walltime — must be ≤ partition MaxTime
# #SBATCH --nodelist=gpu010            # Optional: force a specific node
# #SBATCH --exclude=gpu017             # Optional: avoid a known-bad node

mkdir -p logs
nvidia-smi                             # Sanity check in the log
python train.py
```

**Tips:**
- Keep `--time` realistic. Shorter walltimes backfill into gaps and start sooner.
- Only `--exclude` nodes you have a concrete reason to avoid — otherwise it just shrinks your pool.
- Use `--gres=gpu:1` (any GPU) if your code doesn't care about model — broadest scheduling.

---

## 5. Managing Running Jobs

- **Cancel a job:**
  ```bash
  scancel <jobid>
  ```

- **Cancel all your jobs:**
  ```bash
  scancel -u $USER
  ```

- **Cancel only pending jobs:**
  ```bash
  scancel -u $USER -t PENDING
  ```

- **Live job details:**
  ```bash
  scontrol show job <jobid>
  ```

- **Watch your queue update live:**
  ```bash
  watch -n 5 'squeue -u $USER'
  ```

- **Attach to a running job's node for inspection:**
  ```bash
  srun --jobid=<jobid> --pty bash
  ```

- **Tail your job's output:**
  ```bash
  tail -f logs/run_dgpo_<jobid>.out
  ```

---

## 6. Inspecting GPUs (Inside a Job)

`nvidia-smi` only works on a compute node, not the login node. Start an interactive session first.

- **Basic GPU info:**
  ```bash
  nvidia-smi
  ```
  Check: model matches expectation, temp <50°C idle, 0 MiB used, no `ERR!`.

- **Health-focused query:**
  ```bash
  nvidia-smi -q | grep -iE "ECC|Retired|Remapped|Throttle|Temperature"
  ```
  Red flags: non-zero `Retired Pages`, `Uncorrectable ECC Errors`, persistent thermal throttling.

- **Live GPU usage refresh:**
  ```bash
  nvidia-smi -l 1
  ```

- **CUDA version (driver level):**
  ```bash
  nvidia-smi | head -3
  ```

- **CUDA toolkit version:**
  ```bash
  nvcc --version
  ```

- **Quick PyTorch functional test:**
  ```bash
  python -c "
  import torch
  print('CUDA available :', torch.cuda.is_available())
  print('Device         :', torch.cuda.get_device_name(0))
  print('Compute cap.   :', torch.cuda.get_device_capability(0))
  print('Torch version  :', torch.__version__)
  print('Torch CUDA ver :', torch.version.cuda)
  x = torch.randn(8192, 8192, device='cuda')
  y = x @ x; torch.cuda.synchronize()
  print('Matmul OK, norm:', y.norm().item())
  "
  ```

### GPU Hierarchy (Newer = Faster)

| GPU   | Year | Bf16 native | Typical memory | Notes                          |
|-------|------|-------------|----------------|--------------------------------|
| P100  | 2016 | No          | 16 GB          | Old; avoid for modern ML.      |
| V100  | 2017 | No          | 16 / 32 GB     | Use fp16, not bf16.            |
| A100  | 2020 | Yes         | 40 / 80 GB     | Sweet spot for most workloads. |
| H100  | 2022 | Yes (FP8)   | 80 GB          | Fastest widely deployed.       |
| GH200 | 2024 | Yes (FP8)   | 96+ GB         | Hopper + ARM CPU superchip.    |

---

## 7. Job History & Accounting

- **Your jobs in the last day:**
  ```bash
  sacct -S now-1day -o JobID,JobName,State,ExitCode,Elapsed,NodeList
  ```

- **Why did a job fail? Full breakdown:**
  ```bash
  sacct -j <jobid> -o JobID,State,ExitCode,DerivedExitCode,Reason,NodeList
  ```

- **Resource efficiency report (CPU/RAM utilization):**
  ```bash
  seff <jobid>
  ```
  Useful for right-sizing `--mem` and `--cpus-per-task` next time.

- **Detailed accounting fields:**
  ```bash
  sacct -j <jobid> --format=JobID,Elapsed,MaxRSS,MaxVMSize,ReqMem,AllocCPUS,State
  ```

---

## 8. Versions & Environment

- **Slurm version:**
  ```bash
  sinfo -V
  ```

- **Your active conda environment:**
  ```bash
  conda env list
  conda list | head
  ```

- **Loaded environment modules (if cluster uses `module`):**
  ```bash
  module list
  module avail
  module load cuda/12.1
  ```

- **Python version inside a job:**
  ```bash
  python --version
  which python
  ```

---

## 9. Limits, Quotas, and Time Caps

- **Max time allowed in each partition:**
  ```bash
  sinfo -o "%P %l"
  ```

- **Your account's limits (QoS, fairshare, etc.):**
  ```bash
  sacctmgr show association user=$USER format=Account,Partition,QOS,MaxJobs,MaxSubmit,GrpTRES
  ```

- **QoS definitions on the cluster:**
  ```bash
  sacctmgr show qos format=Name,MaxWall,MaxTRES,MaxJobsPU
  ```

- **Fairshare (your scheduling priority weight):**
  ```bash
  sshare -U
  ```

---

## 10. Common Workflows

### "I want to run now — what's free?"
```bash
sinfo -p gpu -t idle -o "%N %G"        # See idle GPU nodes + types
sinfo -p gpu -o "%N %G %t"             # Full GPU picture
```
Pick a GPU type with idle nodes, submit with that `--gres`.

### "How long is my wait?"
```bash
squeue -p gpu -t PD --sort=-p,i        # Pending jobs in partition
squeue -j <jobid> --start              # Estimated start time
scontrol show job <jobid>              # Full reason
```

### "Is this node healthy?"
```bash
scontrol show node gpu050              # State, Reason, GRES
sacct -N gpu050 -S now-7days -o JobID,State,ExitCode | head -30
```

### "What time limit can I use?"
```bash
sinfo -o "%P %l"                       # Per-partition max walltime
```
Set `--time` ≤ that value. Use the smallest realistic walltime — short jobs backfill better.

### "Submit, watch, debug, kill"
```bash
sbatch run_dgpo.sh                     # Submit
squeue -u $USER                        # See state
tail -f logs/run_dgpo_<jobid>.out      # Watch output
scancel <jobid>                        # Kill if needed
seff <jobid>                           # Post-mortem efficiency
```

---

## 11. Troubleshooting Quick Hits

| Symptom                                | Likely cause / fix                                          |
|----------------------------------------|-------------------------------------------------------------|
| Job stuck on `(Priority)` with idle nodes | Resource mismatch — you asked for a GPU type that isn't free. Check `sinfo -p gpu -o "%N %G %t"`. |
| `(ReqNodeNotAvail, UnavailableNodes:...)` | You requested a node that's `down`/`drain`. Remove `--nodelist` or `--exclude` adjustments. |
| `Invalid time specification`           | `--time` exceeds partition `MaxTime`. Check with `sinfo -o "%P %l"`. |
| Job dies instantly                     | Check `logs/*.err`. Usually env/import error or OOM.        |
| `nvidia-smi: command not found`        | You're on the login node. Use `srun ... --pty bash` first.  |
| `scancle: command not found`           | Typo — the command is `scancel`.                            |
| `CUDA out of memory`                   | Lower batch size, enable gradient checkpointing, or request a bigger GPU. |
| Job runs but is very slow              | Inside the job, run `nvidia-smi` — confirm GPU is actually being used and not throttled. |

---

## 12. Style Tips for Reliable Jobs

- Always log `hostname`, `nvidia-smi`, and `nvcc --version` at the top of your script — invaluable when debugging later.
- Use `%x_%j` in output filenames so logs are self-identifying.
- Right-size memory with `seff` after a successful run; over-requesting `--mem` slows scheduling.
- Checkpoint long jobs every N steps so a node failure isn't catastrophic.
- Prefer `--gres=gpu:1` over pinning to a specific model unless your code truly needs it — wider scheduling pool, faster start.

--- 

## 13. Get the maximum time allowed for each GPUs on the cluster:

Get the availability and the GPU information through:
```
sinfo -p gpu -N -o "%15N %25G %25f %15l %15T"
```
