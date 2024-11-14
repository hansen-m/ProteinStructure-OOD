
import os
PATH = '/scratch/sld5866/'
os.environ['HF_HOME'] = PATH
os.environ['HF_DATASETS_CACHE'] = PATH
os.environ['TORCH_HOME'] = PATH
import torch
from transformers import AutoTokenizer, EsmForProteinFolding


model_name = "facebook/esmfold_v1"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = EsmForProteinFolding.from_pretrained(model_name, low_cpu_mem_usage=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = model.to(device)


sequence = "NLYIQWLKDGGPSSGRPPPS"

# Multimer prediction can be done with chains separated by ':'

with torch.no_grad():
    output = model.infer_pdb(sequence)

with open("/scratch/sld5866/result.pdb", "w") as f:
    f.write(output)

