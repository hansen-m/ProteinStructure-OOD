#!/bin/bash
cat <<EOF | sbatch
#!/bin/bash                
#SBATCH -A icds_internal_use 
#SBATCH -p sla-prio
#SBATCH --ntasks-per-node 8  
#SBATCH --time=02:00:00 
time python run_alphafold-msa_2.3.1.py --model_preset=multimer --fasta_paths=97_aa.fa
EOF
