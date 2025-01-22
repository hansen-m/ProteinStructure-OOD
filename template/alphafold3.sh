#!/bin/bash

JSON_FILE="${1}"
WORKINGDIR="${2}"
ACCOUNT="${3}"
STATUS_FILE="${4}"

NAME=$(grep -oi '"name": *"[^"]*"' "${JSON_FILE}" | sed 's/"name": *"\([^"]*\)"/\1/I' | tr '[:upper:]' '[:lower:]') || handle_error "Failed to extract 'name' from JSON"
echo "Debug: Name from JSON input: ${NAME}"

CPU_SLURM_SCRIPT="${INPUT_DIR}/af3_cpu_job.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=120GB
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${CPU_LOG_FILE}

singularity exec \\
    --bind ${INPUT_DIR}:/root/af_input \\
    --bind ${STRUCT}:/root/af_output \\
    --bind ${ALPHAFOLD3_WEIGHTS}:/root/models \\
    --bind ${ALPHAFOLD3_DB}:/root/public_databases \\
    ${ALPHAFOLD3_CONTAINER} \\
    python3 /app/alphafold/run_alphafold.py \\
    --json_path=/root/af_input/$(basename "${JSON_FILE}") \\
    --model_dir=/root/models \\
    --db_dir=/root/public_databases \\
    --output_dir=/root/af_output \\
    --run_data_pipeline=true \\
    --run_inference=false \\
    --jackhmmer_n_cpu=32 \\
    --nhmmer_n_cpu=32
EOF

GENERATED_JSON_FILE="/root/af_output/${NAME}/${NAME}_data.json"
echo "Debug: Expected generated JSON file: ${GENERATED_JSON_FILE}"

CPU_JOB_ID=$(sbatch "${CPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit CPU job"
echo "Debug: CPU job submitted with ID: ${CPU_JOB_ID}"

GPU_SLURM_SCRIPT="${INPUT_DIR}/af3_gpu_job.slurm"
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

singularity exec --nv \\
    --bind ${STRUCT}:/root/af_output \\
    --bind ${ALPHAFOLD3_WEIGHTS}:/root/models \\
    --bind ${ALPHAFOLD3_DB}:/root/public_databases \\
    --bind "singularity_af3/app/alphafold/run_alphafold.py:/app/alphafold/run_alphafold.py" \\
    ${ALPHAFOLD3_CONTAINER} \\
    python3 /app/alphafold/run_alphafold.py \\
    --json_path=${GENERATED_JSON_FILE} \\
    --model_dir=/root/models \\
    --db_dir=/root/public_databases \\
    --output_dir=/root/af_output \\
    --run_data_pipeline=false \\
    --run_inference=true
EOF

GPU_JOB_ID=$(sbatch "${GPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: ${GPU_JOB_ID}"

OUTPUT_DIR="${STRUCT}/${NAME}"
TOP_MODEL="${OUTPUT_DIR}/${NAME}_model.cif"
RANKING_FILE="${OUTPUT_DIR}/ranking_scores.csv"

EXPECTED_OUTPUT_FILE="${TOP_MODEL}"

export CPU_JOB_ID GPU_JOB_ID