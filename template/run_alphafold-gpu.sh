#!/bin/bash

for file in 97-*.fa 255-*.fa\
       	   493-*.fa 985-*.fa
do
#[! -d $file ] && mkdir $file
cat <<EOF > $file.slurm
#!/bin/bash
#SBATCH --nodes=1
#SBATCH -G 1
#SBATCH --ntasks=8
#SBATCH --mem=60GB
#SBATCH --begin=now+2hour
#SBATCH --time=20:00:00
#SBATCH -A dml129-engagement_gpu
#SBATCH -p sla-prio,burst
#SBATCH -q burst4x
    
time python run_alphafold-gpu_2.3.1.py --model_preset=multimer --fasta_paths=$file
echo $file
EOF

sbatch $file.slurm
done





