#!/bin/bash

seq="$1"
USER="$2" 
WORKINGDIR="$3"
rc_account="$4"
STATUS_FILE="$5"

# Function to update status
update_status() {
    echo "$1" > "$STATUS_FILE"
}

# Function to handle errors
handle_error() {
    echo "Error occurred: $1"
    update_status "failed"
    exit 1
}

# Set error trap
trap 'handle_error "Unexpected error occurred"' ERR

export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python


STORAGE_BASE="/storage"
ICDS_BASE="$STORAGE_BASE/icds/RISE/sw8/alphafold/alphafold_2.3_db"

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

ALPHAFOLD_CONTAINER="/storage/icds/RISE/sw8/alphafold/singularity/alphafold_2.3.2-1.sif"
ALPHAFOLD_GPU_SCRIPT="/storage/icds/RISE/sw8/alphafold/scripts/run/run_alphafold-gpu_2.3.2.py"

JOB_NAME="alphafold_job_${USER}"
FASTA_FILE="$CPU_OUTPUT/input.fasta"

mkdir -p "$WORKINGDIR" || handle_error "Failed to create working directory"
mkdir -p "$RUN_DIR" || handle_error "Failed to create run directory"
mkdir -p "$CPU_OUTPUT" "$GPU_OUTPUT" "$STRUCT" "$LOGDIR/$JOB_NAME" || handle_error "Failed to create output directories"

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
#SBATCH --partition=open
#SBATCH --output=$LOGDIR/$JOB_NAME/${JOB_NAME}_cpu_%j.log

echo "Debug: Starting CPU job"
echo "Debug: Contents of input FASTA:"
cat $FASTA_FILE


time singularity run \
    -B "$ICDS_BASE" \
    -B "$WORKINGDIR" \
    -B "/tmp" \
    -B "$CPU_OUTPUT" \
    -B "$(dirname "$0")/singularity/app/alphafold/run_alphafold.py:/app/alphafold/run_alphafold.py" \
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
    --hhblits_binary_path=/storage/icds/RISE/sw8/alphafold/hh-suite/bin/hhblits \
    --logtostderr
EOF

echo "Debug: Created CPU SLURM script"
echo "CPU job script contents:"
cat "$CPU_SLURM_SCRIPT"

echo "Debug: Submitting CPU job"
CPU_JOB_ID=$(sbatch "$CPU_SLURM_SCRIPT" | awk '{print $4}') || handle_error "Failed to submit CPU job"
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
GPU_JOB_ID=$(sbatch "$GPU_SLURM_SCRIPT" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: $GPU_JOB_ID"

echo "Debug: All jobs submitted successfully"

while true; do
    CPU_STATE=$(squeue -j "$CPU_JOB_ID" -h -o %t 2>/dev/null)
    GPU_STATE=$(squeue -j "$GPU_JOB_ID" -h -o %t 2>/dev/null)
    
    if [[ -z "$CPU_STATE" && -z "$GPU_STATE" ]]; then
        CPU_EXIT=$(sacct -j "$CPU_JOB_ID" -n -o State | head -1)
        GPU_EXIT=$(sacct -j "$GPU_JOB_ID" -n -o State | head -1)
        
        if [[ "$CPU_EXIT" == *"COMPLETED"* && "$GPU_EXIT" == *"COMPLETED"* ]]; then
            echo "Both jobs completed successfully"
            update_status "completed"
            exit 0
        else
            echo "One or both jobs failed. CPU: $CPU_EXIT, GPU: $GPU_EXIT"
            update_status "failed"
            exit 1
        fi
    fi
    
    sleep 60  
done