#!/bin/bash

SEQ="${1}"
JSON_INPUT="${2}"
USER="${3}" 
WORKINGDIR="${4}"
ACCOUNT="${5}"
STATUS_FILE="${6}"
RUN_ID="${7}"

update_status() {
    echo "${1}" > "${STATUS_FILE}"
}

handle_error() {
    echo "Error occurred: ${1}"
    update_status "failed"
    exit 1
}

trap 'error_code=$?; echo "Debug: Trap caught error ${error_code} at line ${BASH_LINENO[0]}"; if [[ ${error_code} -ne 0 ]]; then handle_error "Error ${error_code} at line ${BASH_LINENO[0]}"; fi' ERR

RUN_DIR="${WORKINGDIR}/run_${RUN_ID}"
INPUT_DIR="${RUN_DIR}/input"
CPU_OUTPUT="${RUN_DIR}/cpu_output"
GPU_OUTPUT="${RUN_DIR}/gpu_output"
STRUCT="${RUN_DIR}/structure"
LOGDIR="${RUN_DIR}/logs/${RUN_ID}"
JSON_DIR="${INPUT_DIR}"

AF3_CONTAINER="/storage/group/u1o/default/wkl2/CONTAINER/alphafold3_241202.sif"
AF3_WEIGHTS="/storage/group/u1o/default/wkl2/CONTAINER/alphafold3_weights"
AF3_DB="/storage/icds/RISE/sw8/alphafold3/alphafold3/databases"

mkdir -p "${INPUT_DIR}" || handle_error "Failed to create input directory"
mkdir -p "${CPU_OUTPUT}" || handle_error "Failed to create CPU output directory"
mkdir -p "${GPU_OUTPUT}" || handle_error "Failed to create GPU output directory"
mkdir -p "${STRUCT}" || handle_error "Failed to create structure directory"
mkdir -p "${LOGDIR}" || handle_error "Failed to create log directory"

FASTA_FILE="${INPUT_DIR}/input.fa"
JSON_FILE="${INPUT_DIR}/input.json"

if [ -n "${SEQ}" ]; then
    echo "Debug: Received FASTA sequence"
    echo "${SEQ}" > "${FASTA_FILE}" || handle_error "Failed to write sequence to FASTA file"

    echo "Debug: Converting FASTA to JSON"
    convert_fasta_to_json() {
        local fasta_file="$1"
        local json_file="$2"

        local name
        name=$(basename "$fasta_file" .fa)
        
        local sequences
        sequences=$(grep -v "^>" "$fasta_file" | tr -d ' \n')
        
        local seq_count
        seq_count=$(grep -c "^>" "$fasta_file")
        
        local chain_ids
        if [ "$seq_count" -gt 1 ]; then
            chain_ids="["
            for i in $(seq 1 "$seq_count"); do
                chain_id=$(printf '%c' $((64 + i)))  
                if [ "$i" -eq 1 ]; then
                    chain_ids="${chain_ids}\"${chain_id}\""
                else
                    chain_ids="${chain_ids}, \"${chain_id}\""
                fi
            done
            chain_ids="${chain_ids}]"
        else
            chain_ids='["A"]'
        fi
        
        cat > "$json_file" <<EOF
{
    "name": "${name}",
    "modelSeeds": [1, 2, 3],
    "sequences": [
        {
            "protein": {
                "id": ${chain_ids},
                "sequence": "${sequences}"
            }
        }
    ],
    "dialect": "alphafold3",
    "version": 1
}
EOF
    }
    convert_fasta_to_json "${FASTA_FILE}" "${JSON_FILE}" || handle_error "Failed to convert FASTA to JSON"

elif [ -n "${JSON_INPUT}" ]; then
    echo "Debug: Received JSON input"
    echo "${JSON_INPUT}" > "${JSON_FILE}" || handle_error "Failed to write JSON input to file"
else
    handle_error "No valid input provided"
fi

echo "Debug: JSON input ready at ${JSON_FILE}"

# Create CPU SLURM script
CPU_SLURM_SCRIPT="${CPU_OUTPUT}/cpu_job_${RUN_ID}.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=1                # Number of tasks (keep as 1 if using multithreading within the task)
#SBATCH --cpus-per-task=32        # Increased CPUs per task for multithreading
#SBATCH --mem=128GB               # Increased memory allocation
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${LOGDIR}/cpu_job_${RUN_ID}.log

echo "Debug: Starting AlphaFold 3 CPU job"


singularity exec \
    --bind ${JSON_DIR}:/root/af_input \
    --bind ${STRUCT}:/root/af_output \
    --bind ${AF3_WEIGHTS}:/root/models \
    --bind ${AF3_DB}:/root/public_databases \
    ${AF3_CONTAINER} \
    python3 /app/alphafold/run_alphafold.py \
    --json_path=/root/af_input/$(basename "${JSON_FILE}") \
    --model_dir=/root/models \
    --db_dir=/root/public_databases \
    --output_dir=/root/af_output \
    --run_data_pipeline=true \
    --run_inference=false \
    --jackhmmer_n_cpu=32 \
    --nhmmer_n_cpu=32

EOF

echo "Debug: Created CPU SLURM script"

CPU_JOB_ID=$(sbatch "${CPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit CPU job"
echo "Debug: CPU job submitted with ID: ${CPU_JOB_ID}"

# Create GPU SLURM script
GPU_SLURM_SCRIPT="${GPU_OUTPUT}/gpu_job_${RUN_ID}.slurm"
cat <<EOF > "${GPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --gpus=1
#SBATCH --time=10:00:00
#SBATCH --account=${ACCOUNT}
#SBATCH --partition=sla-prio
#SBATCH --output=${LOGDIR}/gpu_job_${RUN_ID}.log
#SBATCH --dependency=afterok:${CPU_JOB_ID}

echo "Debug: Starting AlphaFold 3 GPU job"

singularity exec --nv \
    --bind ${STRUCT}:/root/af_output \
    --bind ${AF3_WEIGHTS}:/root/models \
    --bind ${AF3_DB}:/root/public_databases \
    ${AF3_CONTAINER} \
    python3 /app/alphafold/run_alphafold.py \
    --json_path=/root/af_output/$(basename "${JSON_FILE}" .json)_data.json \
    --model_dir=/root/models \
    --db_dir=/root/public_databases \
    --output_dir=/root/af_output \
    --run_data_pipeline=false \
    --run_inference=true

kill \$vmstat_pid
kill \$nvidia_smi_pid
end_time=\$(date +%s)

EOF

echo "Debug: Created GPU SLURM script"

GPU_JOB_ID=$(sbatch "${GPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: ${GPU_JOB_ID}"

monitor_jobs() {
    local cpu_id=${1}
    local gpu_id=${2}
    
    while true; do
        CPU_STATE=$(squeue -j "${cpu_id}" -h -o %t 2>/dev/null)
        GPU_STATE=$(squeue -j "${gpu_id}" -h -o %t 2>/dev/null)
        
        echo "Debug: CPU Job State: ${CPU_STATE}, GPU Job State: ${GPU_STATE}"
        
        if [[ -z "${CPU_STATE}" && -z "${GPU_STATE}" ]]; then
            sleep 10

            cpu_status=$(sacct -j "${cpu_id}" --format=State -n | head -1 | tr -d ' ')
            gpu_status=$(sacct -j "${gpu_id}" --format=State -n | head -1 | tr -d ' ')

            echo "Debug: Final CPU status: ${cpu_status}"
            echo "Debug: Final GPU status: ${gpu_status}"

            if [[ "${cpu_status}" == "COMPLETED" && "${gpu_status}" == "COMPLETED" ]]; then
                if [[ -d "${STRUCT}" && -f "${STRUCT}/ranked_0.pdb" ]]; then
                    update_status "completed"
                    exit 0
                fi
            fi

            echo "Debug: Job completion check failed"
            echo "Debug: Checking logs..."
            cat "${LOGDIR}/cpu_job_${RUN_ID}.log" 2>/dev/null
            cat "${LOGDIR}/gpu_job_${RUN_ID}.log" 2>/dev/null
            update_status "failed"
            exit 1
        fi

        sleep 60
    done
}

echo "Debug: Starting job monitoring"
monitor_jobs "${CPU_JOB_ID}" "${GPU_JOB_ID}"