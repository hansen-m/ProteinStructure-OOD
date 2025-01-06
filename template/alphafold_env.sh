#!/bin/bash

export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

export RUN_DIR="${WORKINGDIR}/pp${CREATED_AT}"
export STATUS_FILE="status.json"

export INPUT_DIR="${RUN_DIR}/input"
export STRUCT="${RUN_DIR}/structure"
export LOGDIR="${RUN_DIR}/logs"
export CPU_LOG_FILE="${LOGDIR}/cpu_job.log"
export GPU_LOG_FILE="${LOGDIR}/gpu_job.log"

export ALPHAFOLD_BASE="/storage/icds/RISE/sw8/alphafold"
export ALPHAFOLD_DB="${ALPHAFOLD_BASE}/alphafold_databases"

export UNIREF90_PATH="${ALPHAFOLD_DB}/uniref90/uniref90.fasta"
export MGNIFY_PATH="${ALPHAFOLD_DB}/mgnify/mgy_clusters_2022_05.fa"
export TEMPLATE_MMCIF_PATH="${ALPHAFOLD_DB}/pdb_mmcif/mmcif_files"
export OBSOLETE_PDBS_PATH="${ALPHAFOLD_DB}/pdb_mmcif/obsolete.dat"
export UNIPROT_PATH="${ALPHAFOLD_DB}/uniprot/uniprot.fasta"
export PDB_SEQRES_PATH="${ALPHAFOLD_DB}/pdb_seqres/pdb_seqres.txt"
export UNIREF30_PATH="${ALPHAFOLD_DB}/uniref30/UniRef30_2021_03"
export BFD_PATH="${ALPHAFOLD_DB}/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt"

export ALPHAFOLD_CONTAINER="${ALPHAFOLD_BASE}/singularity/alphafold_2.3.2-1.sif"
export ALPHAFOLD_GPU_SCRIPT="${SESSIONDIR}/run_alphafold-gpu_2.3.2.py"

export HHBLITS_BINARY_PATH="${ALPHAFOLD_BASE}/hh-suite/bin/hhblits"

export FASTA_FILE="${INPUT_DIR}/input.fasta"
export JSON_FILE="${INPUT_DIR}/input.json"

export ALPHAFOLD3_BASE="/storage/icds/RISE/sw8/alphafold3"
export ALPHAFOLD3_DB="${ALPHAFOLD3_BASE}/alphafold3/databases"
export ALPHAFOLD3_WEIGHTS="${ALPHAFOLD3_BASE}/alphafold3_weights"
export ALPHAFOLD3_CONTAINER="${ALPHAFOLD3_BASE}/singularity/alphafold3_241202.sif"

export OOD_BASE="https://portal.hpc.psu.edu"