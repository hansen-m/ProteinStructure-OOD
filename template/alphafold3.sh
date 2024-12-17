#!/bin/bash

echo "Debug: alphafold3.sh script started"

export SESSIONDIR="$PWD"

JSON_INPUT_FILE="${1}"
USER="${2}"
WORKINGDIR="${3}"
ACCOUNT="${4}"
STATUS_FILE="${5}"
TIMESTAMP="${6}"

source "${SESSIONDIR}/alphafold_env.sh" || { echo "Failed to source alphafold_env.sh"; exit 1; }
source "${SESSIONDIR}/before.sh" || { echo "Failed to source before.sh"; exit 1; }

echo "Debug: Received JSON input file at ${JSON_INPUT_FILE}"

JSON_FILE="${INPUT_DIR}/input.json"

echo "Debug: JSON input ready at ${JSON_FILE}"

NAME=$(grep -oi '"name": *"[^"]*"' "${JSON_FILE}" | sed 's/"name": *"\([^"]*\)"/\1/I') || handle_error "Failed to extract 'name' from JSON"
echo "Debug: Extracted name from JSON input: ${NAME}"

NAME_LOWER=$(echo "${NAME}" | tr '[:upper:]' '[:lower:]')
echo "Debug: Lowercase name: ${NAME_LOWER}"

GENERATED_JSON_FILE="/root/af_output/${NAME_LOWER}/${NAME_LOWER}_data.json"
echo "Debug: Expected generated JSON file: ${GENERATED_JSON_FILE}"

CPU_SLURM_SCRIPT="${CPU_OUTPUT}/cpu_job_${TIMESTAMP}.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128GB
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${LOGDIR}/cpu_job_${TIMESTAMP}.log

echo "Debug: Starting AlphaFold 3 CPU job"

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

echo "Debug: Created CPU SLURM script"

CPU_JOB_ID=$(sbatch "${CPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit CPU job"
echo "Debug: CPU job submitted with ID: ${CPU_JOB_ID}"

GPU_SLURM_SCRIPT="${GPU_OUTPUT}/gpu_job_${TIMESTAMP}.slurm"
cat <<EOF > "${GPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --gpus=1
#SBATCH --time=10:00:00
#SBATCH --account=${ACCOUNT}
#SBATCH --partition=sla-prio
#SBATCH --output=${LOGDIR}/gpu_job_${TIMESTAMP}.log
#SBATCH --dependency=afterok:${CPU_JOB_ID}

echo "Debug: Starting AlphaFold 3 GPU job"

singularity exec --nv \\
    --bind ${STRUCT}:/root/af_output \\
    --bind ${ALPHAFOLD3_WEIGHTS}:/root/models \\
    --bind ${ALPHAFOLD3_DB}:/root/public_databases \\
    --bind "${SESSIONDIR}/singularity_af3/app/alphafold/run_alphafold.py:/app/alphafold/run_alphafold.py" \\
    ${ALPHAFOLD3_CONTAINER} \\
    python3 /app/alphafold/run_alphafold.py \\
    --json_path=${GENERATED_JSON_FILE} \\
    --model_dir=/root/models \\
    --db_dir=/root/public_databases \\
    --output_dir=/root/af_output \\
    --run_data_pipeline=false \\
    --run_inference=true
EOF

echo "Debug: Created GPU SLURM script"

GPU_JOB_ID=$(sbatch "${GPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: ${GPU_JOB_ID}"

OUTPUT_DIR="${STRUCT}/${NAME_LOWER}"
TOP_MODEL="${OUTPUT_DIR}/${NAME_LOWER}_model.cif"
RANKING_FILE="${OUTPUT_DIR}/ranking_scores.csv"

EXPECTED_OUTPUT_FILE="${TOP_MODEL}"

echo "Debug: Starting job monitoring"
monitor_jobs "${CPU_JOB_ID}" "${GPU_JOB_ID}"