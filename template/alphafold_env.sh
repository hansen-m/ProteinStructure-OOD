export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

ALPHAFOLD_BASE="/storage/icds/RISE/sw8/alphafold"
ALPHAFOLD_DB="${ALPHAFOLD_BASE}/alphafold_2.3_db"

CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")
RUN_DIR="${WORKINGDIR}/run_${CURRENT_DATE}"

CPU_OUTPUT="${RUN_DIR}/CPU-SLURM"
GPU_OUTPUT="${RUN_DIR}/GPU-SLURM"
STRUCT="${RUN_DIR}/DESIGN-ESM"
LOGDIR="${RUN_DIR}/logs"

UNIREF90_PATH="${ALPHAFOLD_DB}/uniref90/uniref90.fasta"
MGNIFY_PATH="${ALPHAFOLD_DB}/mgnify/mgy_clusters_2022_05.fa"
TEMPLATE_MMCIF_PATH="${ALPHAFOLD_DB}/pdb_mmcif/mmcif_files"
OBSOLETE_PDBS_PATH="${ALPHAFOLD_DB}/pdb_mmcif/obsolete.dat"
UNIPROT_PATH="${ALPHAFOLD_DB}/uniprot/uniprot.fasta"
PDB_SEQRES_PATH="${ALPHAFOLD_DB}/pdb_seqres/pdb_seqres.txt"
UNIREF30_PATH="${ALPHAFOLD_DB}/uniref30/UniRef30_2021_03"
BFD_PATH="${ALPHAFOLD_DB}/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt"

ALPHAFOLD_CONTAINER="${ALPHAFOLD_BASE}/singularity/alphafold_2.3.2-1.sif"
ALPHAFOLD_GPU_SCRIPT="${ALPHAFOLD_BASE}/scripts/run/run_alphafold-gpu_2.3.2.py"

HHBLITS_BINARY_PATH="${ALPHAFOLD_BASE}/hh-suite/bin/hhblits"

JOB_NAME="alphafold_job_${USER}"
FASTA_FILE="${CPU_OUTPUT}/input.fasta"