#!/bin/bash

module load anaconda
#conda activate /storage/group/RISE/sld5866/envs/chat
conda activate conda_env
#echo $2
#printf $2 > fasta_file
#seq=$(awk 'BEGIN {FS="\n";OFS=""} NR>0 {print ">"$1; $1=""; print}' fasta_file) 
#seq=$(awk 'BEGIN {RS=">";FS="\n";OFS=""} NR>1 {print ">"$1; $1=""; print}' fasta_file) 
#echo $seq
cat <<EOF > exec.py

import os
PATH = '/scratch/$1/'
os.environ['HF_HOME'] = PATH
os.environ['HF_DATASETS_CACHE'] = PATH
os.environ['TORCH_HOME'] = PATH
import torch
#from transformers import AutoTokenizer, EsmForProteinFolding
import esm

model = esm.pretrained.esmfold_v1()
model = model.eval().cuda()
#model_name = "facebook/esmfold_v1"
#tokenizer = AutoTokenizer.from_pretrained(model_name)
#model = EsmForProteinFolding.from_pretrained(model_name, low_cpu_mem_usage=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = model.to(device)

with open("/scratch/$1/sequence.fasta", "r") as f:
    seq=f.readline().rstrip()
#sequence = "$2"

# Multimer prediction can be done with chains separated by ':'

with torch.no_grad():
    output = model.infer_pdb(seq)

with open("/scratch/$1/result.pdb", "w") as f:
    f.write(output)

EOF

python exec.py

