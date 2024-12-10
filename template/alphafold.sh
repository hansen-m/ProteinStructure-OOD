#!/bin/bash

SEQ="${1}"
USER="${2}" 
WORKINGDIR="${3}"
ACCOUNT="${4}"
STATUS_FILE="${5}"
TIMESTAMP="${6}"

trap 'error_code=$?; echo "Debug: Trap caught error ${error_code} at line ${BASH_LINENO[0]}"; if [[ ${error_code} -ne 0 ]]; then handle_error "Error ${error_code} at line ${BASH_LINENO[0]}"; fi' ERR

echo "Debug: Received sequence: ${SEQ}"
echo "Debug: Received msa: ${MSA}"
echo "Debug: Received USER: ${USER}"

cat <<EOF > "${FASTA_FILE}"
${SEQ}
EOF

echo "Debug: Created FASTA file at ${FASTA_FILE}"
echo "Debug: Contents of FASTA file:"
cat "${FASTA_FILE}"

CPU_SLURM_SCRIPT="${CPU_OUTPUT}/cpu_job.slurm"
cat <<EOF > "${CPU_SLURM_SCRIPT}"
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=60GB
#SBATCH --time=6:00:00
#SBATCH --partition=open
#SBATCH --output=${LOGDIR}/cpu_job.log

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
#SBATCH --output=${LOGDIR}/gpu_job.log
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
            cat "${LOGDIR}/cpu_job.log" 2>/dev/null
            cat "${LOGDIR}/gpu_job.log" 2>/dev/null
            update_status "failed"
            exit 1
        fi
        
        sleep 60
    done
}

echo "Debug: Starting job monitoring"
monitor_jobs "${CPU_JOB_ID}" "${GPU_JOB_ID}"
