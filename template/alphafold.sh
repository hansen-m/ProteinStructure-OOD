#!/bin/bash

FASTA_FILE="${1}"
WORKINGDIR="${2}"
ACCOUNT="${3}"
STATUS_FILE="${4}"

CPU_SLURM_SCRIPT="${INPUT_DIR}/af_cpu_job.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=60GB
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${CPU_LOG_FILE}

singularity run \
    -B "${ALPHAFOLD_DB}" \
    -B "${WORKINGDIR}" \
    -B "/tmp" \
    -B "${INPUT_DIR}" \
    -B "singularity/app/alphafold/run_alphafold.py:/app/alphafold/run_alphafold.py" \
    --env CUDA_VISIBLE_DEVICES=0,NVIDIA_VISIBLE_DEVICES=0,TF_FORCE_UNIFIED_MEMORY=1,XLA_PYTHON_CLIENT_MEM_FRACTION=4.0 \
    ${ALPHAFOLD_CONTAINER} \
    --fasta_paths=${FASTA_FILE} \
    --uniref90_database_path=${UNIREF90_PATH} \
    --mgnify_database_path=${MGNIFY_PATH} \
    --template_mmcif_dir=${TEMPLATE_MMCIF_PATH} \
    --obsolete_pdbs_path=${OBSOLETE_PDBS_PATH} \
    --uniprot_database_path=${UNIPROT_PATH} \
    --pdb_seqres_database_path=${PDB_SEQRES_PATH} \
    --uniref30_database_path=${UNIREF30_PATH} \
    --bfd_database_path=${BFD_PATH} \
    --output_dir=${STRUCT} \
    --max_template_date=2040-01-01 \
    --db_preset=full_dbs \
    --model_preset=multimer \
    --use_precomputed_msas=True \
    --hhblits_binary_path=${HHBLITS_BINARY_PATH} \
    --logtostderr
EOF

CPU_JOB_ID=$(sbatch "${CPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit CPU job"
echo "Debug: CPU job submitted with ID: ${CPU_JOB_ID}"

GPU_SLURM_SCRIPT="${INPUT_DIR}/af_gpu_job.slurm"
cat <<EOF > "${GPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --gpus=1
#SBATCH --time=10:00:00
#SBATCH --account=${ACCOUNT}
#SBATCH --partition=sla-prio
#SBATCH --output=${GPU_LOG_FILE}
#SBATCH --dependency=afterok:${CPU_JOB_ID}

python3 ${ALPHAFOLD_GPU_SCRIPT} \
    --num_multimer_predictions_per_model=1 \
    --model_preset=multimer \
    --output_dir=${STRUCT} \
    --fasta_paths=${FASTA_FILE}
EOF

GPU_JOB_ID=$(sbatch "${GPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: ${GPU_JOB_ID}"

EXPECTED_OUTPUT_FILE="${STRUCT}/ranked_0.pdb"

export CPU_JOB_ID GPU_JOB_ID