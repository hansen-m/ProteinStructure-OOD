# ICDS-Roar-OOD Protein Structure Prediction

## Description
This project provides a web-based interface for running protein structure prediction jobs using AlphaFold on the ICDS Roar cluster via Open OnDemand v3. The app simplifies the process of submitting and monitoring AlphaFold jobs by providing a user-friendly interface and automated job management.

## Features
- **AlphaFold Integration**: 
  - Supports AlphaFold v2.3.2 for protein structure prediction
  - Handles both monomer and multimer predictions
  - Uses full database configuration for maximum accuracy
  - Automated MSA generation and template search
  
- **Job Management**:
  - Two-phase execution (CPU phase for MSA/templates, GPU phase for prediction set as a dependency)
  - Real-time job status monitoring
  - Detailed progress tracking for both phases
  - Automatic error handling and recovery
  
- **User Interface**:
  - Simple FASTA sequence input
  - GPU allocation selection
  - Working directory customization
  - Real-time progress visualization
  - Direct access to output files
  
- **Output Files**:
  - PDB structure files (ranked by confidence)
  - Multiple Sequence Alignment (MSA) files
  - Detailed prediction metrics and confidence scores
  - Comprehensive log files

## Prerequisites

### Database Setup
AlphaFold requires several genetic databases. These must be downloaded and set up before using the app. Download databases using the script from AlphaFold repository: https://github.com/google-deepmind/alphafold

### Singularity Container
The app uses a Singularity container for AlphaFold execution:

Download from Sylabs (https://cloud.sylabs.io/library/prehensilecode/alphafold_singularity/alphafold)

## Installation

1. Clone this repository into your Open OnDemand apps directory.
2. Configure paths in `template/alphafold_env.sh`

## Usage

1. Access the Open OnDemand dashboard
2. Navigate to "Interactive Apps"
3. Select "Protein Structure Prediction"
4. Fill out the form:
   - Enter protein sequence in FASTA format
   - Select GPU allocation
   - Choose working directory
5. Submit the job

### Input Format
The app accepts protein sequences in FASTA format.

### Output Files
The app generates the following output structure:

working_directory/
└── run_YYYYMMDD_HHMMSS/
├── input/
│ ├── ranked_.pdb # Predicted structures
│ ├── result_model_.pkl # Detailed predictions
│ └── msas/ # Multiple sequence alignments
├── logs/ # Job logs
├── CPU-SLURM/ # CPU phase files
└── GPU-SLURM/ # GPU phase files


- PDB structures (ranked_0.pdb being the highest-confidence model)
- MSA files
- result_model_*.pkl files containing detailed output and confidence scores

## Monitoring Jobs
The app provides real-time monitoring of:
- MSA generation progress
- Template search status
- Structure prediction progress
- Model relaxation status

## Troubleshooting
Common issues and solutions:
1. Job fails in CPU phase:
   - Check available disk space
   - Verify database paths
   - Examine CPU phase logs

2. GPU phase errors:
   - Verify GPU allocation
   - Check memory requirements
   - Review GPU phase logs

## License
This project is licensed under the MIT License.

## Acknowledgements
- AlphaFold by DeepMind Technologies Limited
- Singularity container by prehensilecode
- ​The research project is generously funded by Cornell University BRC Epigenomics Core Facility (RRID:SCR_021287), Penn State Institute for Computational and Data Sciences (RRID:SCR_025154) and Penn State University Center for Applications of Artificial Intelligence and Machine Learning to Industry Core Facility (RRID:SCR_022867)

## Contact
For questions or issues, please contact:
- Technical support: vinaysmathew@psu.edu
- ICDS support: icds@psu.edu
