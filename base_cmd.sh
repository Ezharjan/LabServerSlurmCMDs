#!/bin/bash

eval "$(conda shell.bash hook)"
conda activate ENV_NAME

srun -p gpu_batch --gres=gpu:4 python main.py
