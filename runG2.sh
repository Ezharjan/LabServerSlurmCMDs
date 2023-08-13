#!/usr/bin/env bash

#SBATCH --mem-per-gpu=9G
#SBATCH --partition=gpu_batch
#SBATCH --job-name=PROJECT_NAME
#SBATCH --output=logs/slurm-%j.out
#SBATCH --gres=gpu:8
#SBATCH --nodelist=gpu02
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=64
#SBATCH --time=48:00:00

set -x

sh base_cmd.sh
