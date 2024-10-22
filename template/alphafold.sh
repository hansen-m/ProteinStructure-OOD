#!/bin/bash

seq="$1"
msa="$2"
USER="$3"
WORKINGDIR="$4"
rc_account="$5"

export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

STORAGE_BASE="/storage"
ICDS_BASE="Insert ICDS Base Here"
GROUP_BASE="Insert Group Base Here"

CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")
RUN_DIR="$WORKINGDIR/run_${CURRENT_DATE}"

CPU_OUTPUT="$RUN_DIR/CPU-SLURM"
GPU_OUTPUT="$RUN_DIR/GPU-SLURM"
STRUCT="$RUN_DIR/DESIGN-ESM"
LOGDIR="$RUN_DIR/logs"

UNIREF90_PATH="$ICDS_BASE/uniref90/uniref90.fasta"
MGNIFY_PATH="$ICDS_BASE/mgnify/mgy_clusters_2022_05.fa"
TEMPLATE_MMCIF_PATH="$ICDS_BASE/pdb_mmcif/mmcif_files"
OBSOLETE_PDBS_PATH="$ICDS_BASE/pdb_mmcif/obsolete.dat"
UNIPROT_PATH="$ICDS_BASE/uniprot/uniprot.fasta"
PDB_SEQRES_PATH="$ICDS_BASE/pdb_seqres/pdb_seqres.txt"
UNIREF30_PATH="$ICDS_BASE/uniref30/UniRef30_2021_03"
BFD_PATH="$ICDS_BASE/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt"

ALPHAFOLD_CONTAINER="$GROUP_BASE/CONTAINER/alphafold-msa_2.3.1"
ALPHAFOLD_GPU_SCRIPT="$GROUP_BASE/design_tools/run_alphafold-gpu_2.3.2.py"

JOB_NAME="alphafold_job_${USER}"
FASTA_FILE="$CPU_OUTPUT/input.fasta"

mkdir -p "$WORKINGDIR"
mkdir -p "$RUN_DIR"
mkdir -p "$CPU_OUTPUT" "$GPU_OUTPUT" "$STRUCT" "$LOGDIR/$JOB_NAME"

echo "Debug: Received sequence: $seq"
echo "Debug: Received msa: $msa"
echo "Debug: Received USER: $USER"

cat <<EOF > "$FASTA_FILE"
$seq
EOF

echo "Debug: Created FASTA file at $FASTA_FILE"
echo "Debug: Contents of FASTA file:"
cat "$FASTA_FILE"

CPU_SLURM_SCRIPT="$CPU_OUTPUT/$JOB_NAME.slurm"
cat <<EOF > "$CPU_SLURM_SCRIPT"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=60GB
#SBATCH --time=6:00:00
#SBATCH --account=$msa
#SBATCH --output=$LOGDIR/$JOB_NAME/${JOB_NAME}_cpu_%j.log

echo "Debug: Starting CPU job"
echo "Debug: Contents of input FASTA:"
cat $FASTA_FILE

time singularity run -B "$ICDS_BASE" -B "$WORKINGDIR" -B "/tmp" -B "$CPU_OUTPUT" \
    --env CUDA_VISIBLE_DEVICES=0,NVIDIA_VISIBLE_DEVICES=0,TF_FORCE_UNIFIED_MEMORY=1,XLA_PYTHON_CLIENT_MEM_FRACTION=4.0 \
    $ALPHAFOLD_CONTAINER \
    --fasta_paths=$FASTA_FILE \
    --uniref90_database_path=$UNIREF90_PATH \
    --mgnify_database_path=$MGNIFY_PATH \
    --template_mmcif_dir=$TEMPLATE_MMCIF_PATH \
    --obsolete_pdbs_path=$OBSOLETE_PDBS_PATH \
    --uniprot_database_path=$UNIPROT_PATH \
    --pdb_seqres_database_path=$PDB_SEQRES_PATH \
    --uniref30_database_path=$UNIREF30_PATH \
    --bfd_database_path=$BFD_PATH \
    --output_dir=$STRUCT \
    --max_template_date=2040-01-01 \
    --db_preset=full_dbs \
    --model_preset=multimer \
    --use_precomputed_msas=True \
    --logtostderr
EOF

echo "Debug: Created CPU SLURM script"
echo "CPU job script contents:"
cat "$CPU_SLURM_SCRIPT"

echo "Debug: Submitting CPU job"
CPU_JOB_ID=$(sbatch "$CPU_SLURM_SCRIPT" | awk '{print $4}')
echo "Debug: CPU job submitted with ID: $CPU_JOB_ID"

GPU_SLURM_SCRIPT="$GPU_OUTPUT/$JOB_NAME.slurm"
cat <<EOF > "$GPU_SLURM_SCRIPT"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --gpus=1
#SBATCH --time=8:00:00
#SBATCH --account=$rc_account
#SBATCH -p sla-prio,burst
#SBATCH -q burst4x
#SBATCH --exclude=p-gc-3024
#SBATCH --output=$LOGDIR/$JOB_NAME/${JOB_NAME}_gpu_%j.log
#SBATCH --dependency=afterok:$CPU_JOB_ID

time python $ALPHAFOLD_GPU_SCRIPT \
    --num_multimer_predictions_per_model=1 \
    --model_preset=multimer \
    --output_dir=$STRUCT \
    --fasta_paths=$FASTA_FILE
EOF

echo "Debug: Created GPU SLURM script"
echo "Debug: Submitting GPU job"
GPU_JOB_ID=$(sbatch "$GPU_SLURM_SCRIPT" | awk '{print $4}')
echo "Debug: GPU job submitted with ID: $GPU_JOB_ID"

echo "Debug: All jobs submitted successfully"