#!/bin/bash

SEQ="${1}"
USER="${2}" 
WORKINGDIR="${3}"
ACCOUNT="${4}"
STATUS_FILE="${5}"
TIMESTAMP="${6}"

update_status() {
    echo "${1}" > "${STATUS_FILE}"
}

handle_error() {
    echo "Error occurred: ${1}"
    update_status "failed"
    exit 1
}

trap 'error_code=$?; echo "Debug: Trap caught error ${error_code} at line ${BASH_LINENO[0]}"; if [[ ${error_code} -ne 0 ]]; then handle_error "Error ${error_code} at line ${BASH_LINENO[0]}"; fi' ERR

monitor_jobs() {
    local cpu_id=${1}
    local gpu_id=${2}
    
    while true; do
        CPU_STATE=$(squeue -j "${cpu_id}" -h -o %t 2>/dev/null)
        GPU_STATE=$(squeue -j "${gpu_id}" -h -o %t 2>/dev/null)
        
        echo "Debug: CPU Job State: ${CPU_STATE}, GPU Job State: ${GPU_STATE}"

        if [[ "${GPU_STATE}" == "R" ]]; then
            update_status "running"
            sleep 60
            continue
        fi
        
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
            cat "${LOGDIR}/${JOB_NAME}/${JOB_NAME}_cpu_${cpu_id}.log" 2>/dev/null
            cat "${LOGDIR}/${JOB_NAME}/${JOB_NAME}_gpu_${gpu_id}.log" 2>/dev/null
            update_status "failed"
            exit 1
        fi
        
        sleep 60
    done
}

mkdir -p "${WORKINGDIR}" || handle_error "Failed to create working directory"
mkdir -p "${RUN_DIR}" || handle_error "Failed to create run directory"
mkdir -p "${CPU_OUTPUT}" "${GPU_OUTPUT}" "${STRUCT}" "${LOGDIR}/${JOB_NAME}" || handle_error "Failed to create output directories"

echo "Debug: Received sequence: ${SEQ}"
echo "Debug: Received msa: ${MSA}"
echo "Debug: Received USER: ${USER}"

cat <<EOF > "${FASTA_FILE}"
${SEQ}
EOF

echo "Debug: Created FASTA file at ${FASTA_FILE}"
echo "Debug: Contents of FASTA file:"
cat "${FASTA_FILE}"

CPU_SLURM_SCRIPT="${CPU_OUTPUT}/${JOB_NAME}.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=60GB
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${LOGDIR}/${JOB_NAME}/${JOB_NAME}_cpu_%j.log

echo "Debug: Starting CPU job"
echo "Debug: Contents of input FASTA:"
cat ${FASTA_FILE}

time singularity run \
    -B "${ALPHAFOLD_DB}" \
    -B "${WORKINGDIR}" \
    -B "/tmp" \
    -B "${CPU_OUTPUT}" \
    -B "$(dirname "${0}")/singularity/app/alphafold/run_alphafold.py:/app/alphafold/run_alphafold.py" \
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

echo "Debug: Created CPU SLURM script"
echo "CPU job script contents:"
cat "${CPU_SLURM_SCRIPT}"

echo "Debug: Submitting CPU job"
CPU_JOB_ID=$(sbatch "${CPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit CPU job"
echo "Debug: CPU job submitted with ID: ${CPU_JOB_ID}"

GPU_SLURM_SCRIPT="${GPU_OUTPUT}/${JOB_NAME}.slurm"
cat <<EOF > "${GPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --gpus=1
#SBATCH --time=10:00:00
#SBATCH --account=${ACCOUNT}
#SBATCH -p sla-prio
#SBATCH --output=${LOGDIR}/${JOB_NAME}/${JOB_NAME}_gpu_%j.log
#SBATCH --dependency=afterok:${CPU_JOB_ID}

time python3 ${ALPHAFOLD_GPU_SCRIPT} \
    --num_multimer_predictions_per_model=1 \
    --model_preset=multimer \
    --output_dir=${STRUCT} \
    --fasta_paths=${FASTA_FILE}
EOF

echo "Debug: Created GPU SLURM script"
echo "Debug: Submitting GPU job"
GPU_JOB_ID=$(sbatch "${GPU_SLURM_SCRIPT}" | awk '{print $4}') || handle_error "Failed to submit GPU job"
echo "Debug: GPU job submitted with ID: ${GPU_JOB_ID}"

echo "Debug: All jobs submitted successfully"

echo "Debug: Starting job monitoring"
monitor_jobs "${CPU_JOB_ID}" "${GPU_JOB_ID}"

check_job_completion() {
    local job_id=${1}
    local state=$(sacct -j "${job_id}" -n -o State | head -1)
    
    state=$(echo "${state}" | xargs)
    
    if [[ "${state}" == "COMPLETED" ]]; then
        return 0
    elif [[ "${state}" == "FAILED" || "${state}" == "CANCELLED" || "${state}" == "TIMEOUT" ]]; then
        return 1
    else
        return 2  
    fi
}

while true; do
    CPU_STATE=$(squeue -j "${CPU_JOB_ID}" -h -o %t 2>/dev/null)
    GPU_STATE=$(squeue -j "${GPU_JOB_ID}" -h -o %t 2>/dev/null)
    
    echo "Debug: CPU Job State: ${CPU_STATE}, GPU Job State: ${GPU_STATE}"
    
    if [[ -z "${CPU_STATE}" && -z "${GPU_STATE}" ]]; then

        sleep 10
        
        cpu_status=$(check_job_completion "${CPU_JOB_ID}")
        gpu_status=$(check_job_completion "${GPU_JOB_ID}")
        
        echo "Debug: CPU completion status: ${cpu_status}"
        echo "Debug: GPU completion status: ${gpu_status}"
        
        if [[ ${cpu_status} -eq 0 && ${gpu_status} -eq 0 ]]; then
            echo "Both jobs completed successfully"

            if [[ -d "${STRUCT}" && -f "${STRUCT}/ranked_0.pdb" ]]; then
                echo "Output files found in ${STRUCT}"
                update_status "completed"
                exit 0
            else
                echo "Output files not found in ${STRUCT}"
                update_status "failed"
                exit 1
            fi

        elif [[ ${cpu_status} -eq 1 || ${gpu_status} -eq 1 ]]; then
            echo "One or both jobs failed"
            echo "CPU job log:"
            cat "${LOGDIR}/${JOB_NAME}/${JOB_NAME}_cpu_${CPU_JOB_ID}.log" 2>/dev/null
            echo "GPU job log:"
            cat "${LOGDIR}/${JOB_NAME}/${JOB_NAME}_gpu_${GPU_JOB_ID}.log" 2>/dev/null
            update_status "failed"
            exit 1
        fi
    fi
    
    sleep 60
done
