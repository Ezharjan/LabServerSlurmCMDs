# How to Upload Files to Google Drive from a Headless Cluster using Rclone

This guide provides a step-by-step process for configuring `rclone` on a headless Linux cluster and authenticating it via a local Windows PC.

## Step 1: Install Rclone Locally (Windows)
You need `rclone` on your local PC to generate the authentication token.
1. Open **PowerShell** on your Windows computer.
2. Run the following command and follow the prompts:
   ```powershell
   winget install Rclone.Rclone
   ```
3. **Close and reopen** PowerShell so the `rclone` command is recognized.

## Step 2: Configure Rclone on the Cluster
1. SSH into the cluster.
2. Start the configuration wizard:
   ```bash
   rclone config
   ```
3. Follow these exact prompts:
   * **`e/n/d/r/c/s/q>`**: `n` (New remote)
   * **`name>`**: `gdrive`
   * **`Storage>`**: `drive`
   * **`client_id>`**: Press **Enter** (leave blank)
   * **`client_secret>`**: Press **Enter** (leave blank)
   * **`scope>`**: `1` (Full access)
   * **`service_account_file>`**: Press **Enter** (leave blank)
   * **`Edit advanced config?`**: `n`
   * **`Use web browser to automatically authenticate rclone with remote?`**: **`n`**
4. The cluster will output an authorization command (e.g., `rclone authorize "drive" "..."`). **Copy this entire line.**

## Step 3: Authenticate on your Local PC
1. Paste the copied `rclone authorize...` command into your **local Windows PowerShell** and press Enter.
2. Your web browser will open. Log into your Google account and click **Allow**.
3. PowerShell will output a large block of code (the token). **Copy the entire token block.**

## Step 4: Finalize Cluster Configuration
1. Go back to your cluster SSH session.
2. Paste the token block where it is waiting for the verification code and press **Enter**.
3. Complete the setup:
   * **`Configure this as a Shared Drive (Team Drive)?`**: `n`
   * **`y/e/d>`**: `y` (Confirm setup)
   * **`e/n/d/r/c/s/q>`**: `q` (Quit configuration)

## Step 5: Upload Files via Autonomous SLURM Batch Job

> **Handling Large Files & Limits:** When syncing massive datasets, you will eventually hit Google Drive's 750 GB daily upload limit. Standard batch jobs will either fail instantly or hang indefinitely, wasting valuable cluster resources. The script below solves this using a self-resubmitting chain logic. It will safely skip already uploaded files, push files up to the limit (allowing oversized files to finish), and gracefully exit. If blocked by the daily limit, it will automatically instruct SLURM to hold the job and resume exactly 24 hours later.

1. Create a file named `upload_gdrive.sh`:
   ```bash
   nano upload_gdrive.sh
   ```
2. Paste the following batch script. *(Note: Ensure you update `~/local_folder_path` and `gdrive:RemoteFolderName` to match your actual environment names.)*
   ```bash
   #!/bin/bash
   #SBATCH --job-name=gdrive_upload
   #SBATCH --partition=cpu
   #SBATCH --nodes=1
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=4
   #SBATCH --mem=8G
   #SBATCH --time=5-00:00:00
   #SBATCH --output=rclone_upload_%j.out
   #SBATCH --error=rclone_upload_%j.err

   echo "Job started on $(hostname) at $(date)"

   # rclone copy skips perfectly matched files on the cloud automatically.
   # --drive-stop-on-upload-limit allows massive files >750GB to finish successfully, 
   # then safely triggers an exit so the script can auto-resubmit for tomorrow.
   rclone copy ~/local_folder_path gdrive:RemoteFolderName \
       -v \
       --stats 60s \
       --transfers 2 \
       --checkers 8 \
       --drive-chunk-size 256M \
       --tpslimit 10 \
       --retries 10 \
       --drive-stop-on-upload-limit

   # Capture the exit code of the rclone command
   EXIT_CODE=$?

   if [ $EXIT_CODE -eq 0 ]; then
       echo "======================================================"
       echo "SUCCESS: rclone finished with 0 errors!"
       echo "All files are perfectly synced to Google Drive."
       echo "======================================================"
   else
       echo "======================================================"
       echo "NOTICE: rclone exited with code $EXIT_CODE."
       echo "This indicates the 750GB daily limit was reached (or a network drop occurred)."
       echo "Auto-resubmitting this script to SLURM to resume in 24 hours..."
       echo "======================================================"
       
       # Resubmit this exact script to the queue, but delay the start time by 24 hours
       sbatch --begin=now+24hour $0
   fi

   echo "Job finished at $(date)"
   ```
3. Submit the job to the cluster:
   ```bash
   sbatch upload_gdrive.sh
   ```

## Monitoring Your Upload
* **Check job status:** Run `squeue -u <your_username>` to view running and queued jobs.
* **View delayed jobs:** If the 750GB limit is hit, your auto-resubmitted job will appear in the queue with a `PD` (Pending) state and a `(BeginTime)` reason until the 24-hour limit resets. No compute resources are wasted while pending.
* **View live progress log:** `tail -f rclone_upload_<JOB_ID>.out`
