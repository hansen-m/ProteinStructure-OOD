#!/usr/bin/python3

"""Singularity/Apptainer launch script for Alphafold."""

def parse_args():
  import argparse

  parser = argparse.ArgumentParser(description='Run AlphaFold structure prediction using SIF image.')

  parser.add_argument(
    '--fasta_paths', required=True,
    help='Paths to FASTA files, each containing a prediction '
    'target that will be folded one after another. If a FASTA file contains '
    'multiple sequences, then it will be folded as a multimer. Paths should be '
    'separated by commas. All FASTA paths must have a unique basename as the '
    'basename is used to name the output directories for each prediction.')

  parser.add_argument(
    '--use_gpu', type=str_to_bool, default=True,
    help='Enable NVIDIA runtime to run with GPUs.')

  import os
  parser.add_argument(
    '--gpu_devices', default=os.environ.get('SGE_GPU', '0'),
    help='Comma separated list GPU identifiers to set environment variable CUDA_VISIBLE_DEVICES.')

  parser.add_argument(
    '--use_gpu_relax', type=str_to_bool, default=True,
    help='Whether to do OpenMM energy minimization using GPU.')

  parser.add_argument('--hhblits_binary_path', default='/storage/icds/RISE/sw8/alphafold/hh-suite/bin/hhblits', help='Path to the HHblits executable')
    
  parser.add_argument(
    '--models_to_relax', default='all',
    help='The models to run the final relaxation step on. If `all`, all models are relaxed, which may be time '
    'consuming. If `best`, only the most confident model is relaxed. If `none`, relaxation is not run. Turning '
    'off relaxation might result in predictions with distracting stereochemical violations but might help '
    'in case you are having issues with the relaxation stage.' )

  parser.add_argument(
    '--output_dir', default='/storage/group/u1o/default/vvm5242/temp',
    help='Path to a directory that will store the results.')

  parser.add_argument(
    '--data_dir', default='/storage/icds/RISE/sw8/alphafold/alphafold_databases',
    help='Path to directory with supporting data: AlphaFold parameters and genetic '
    'and template databases. Set to the target of download_all_databases.sh.')

  parser.add_argument(
    '--mount_data_dir', default='/storage/icds/RISE/sw8/alphafold/alphafold_databases',
    help='Path to directory where databases reside.')

  parser.add_argument(
    '--singularity_image_path', default='/storage/icds/RISE/sw8/alphafold/singularity/alphafold_2.3.2-1.sif',
    help='Path to the AlphaFold singularity image.')

  parser.add_argument(
    '--max_template_date', default='2040-01-01',
    help='Maximum template release date to consider (ISO-8601 format: YYYY-MM-DD). '
    'Important if folding historical test sets.')

  parser.add_argument(
    '--db_preset', default='full_dbs', choices=['full_dbs', 'reduced_dbs'],
    help='Choose preset MSA database configuration - smaller genetic database '
    'config (reduced_dbs) or full genetic database config (full_dbs)')

  parser.add_argument(
    '--model_preset', default='multimer',
    choices=['monomer', 'monomer_casp14', 'monomer_ptm', 'multimer'],
    help='Choose preset model configuration - the monomer model, the monomer model '
    'with extra ensembling, monomer model with pTM head, or multimer model')

  parser.add_argument(
      '--num_multimer_predictions_per_model', default=1,
      help='How many predictions (each with a different random seed) will be '
      'generated per model. E.g. if this is 2 and there are 5 '
      'models then there will be 10 predictions per input. '
      'Note: this FLAG only applies if model_preset=multimer')

  parser.add_argument(
    '--benchmark', default=False,
    help='Run multiple JAX model evaluations to obtain a timing that excludes the '
    'compilation time, which should be more indicative of the time required '
    'for inferencing many proteins.')

  parser.add_argument(
    '--use_precomputed_msas', default=True,
    help='Whether to read MSAs that have been written to disk. WARNING: This will '
    'not check if the sequence, database or configuration have changed.')

  args = parser.parse_args()
  return args

def str_to_bool(v):
    if isinstance(v, bool):
        return v
    if v.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif v.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        import argparse
        raise argparse.ArgumentTypeError('Boolean value expected.')

def main():

  args = parse_args()

  # You can individually override the following paths if you have placed the
  # data in locations other than the parser.data_dir.

  # Path to the Uniref90 database for use by JackHMMER.
  import os.path
  uniref90_database_path = os.path.join(
      args.data_dir, 'uniref90', 'uniref90.fasta')

  # Path to the Uniprot database for use by JackHMMER.
  uniprot_database_path = os.path.join(
      args.data_dir, 'uniprot', 'uniprot.fasta')

  # Path to the MGnify database for use by JackHMMER.
  mgnify_database_path = os.path.join(
      args.data_dir, 'mgnify', 'mgy_clusters_2022_05.fa')

  # Path to the BFD database for use by HHblits.
  bfd_database_path = os.path.join(
      args.data_dir, 'bfd',
      'bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt')

  # Path to the Small BFD database for use by JackHMMER.
  small_bfd_database_path = os.path.join(
      args.data_dir, 'small_bfd', 'bfd-first_non_consensus_sequences.fasta')

  # Path to the Uniref30 database for use by HHblits.
  uniref30_database_path = os.path.join(
      args.data_dir, 'uniref30', 'UniRef30_2021_03')

  # Path to the PDB70 database for use by HHsearch.
  pdb70_database_path = os.path.join(args.data_dir, 'pdb70', 'pdb70')

  # Path to the PDB seqres database for use by hmmsearch.
  pdb_seqres_database_path = os.path.join(
      args.data_dir, 'pdb_seqres', 'pdb_seqres.txt')

  # Path to a directory with template mmCIF structures, each named <pdb_id>.cif.
  template_mmcif_dir = os.path.join(args.data_dir, 'pdb_mmcif', 'mmcif_files')

  # Path to a file mapping obsolete PDB IDs to their replacements.
  obsolete_pdbs_path = os.path.join(args.data_dir, 'pdb_mmcif', 'obsolete.dat')

  mounts = []
  command_args = []

  # FASTA paths
  command_args.append(f'--fasta_paths={args.fasta_paths}')

  database_paths = [
      ('uniref90_database_path', uniref90_database_path),
      ('mgnify_database_path', mgnify_database_path),
      ('data_dir', args.data_dir),
      ('template_mmcif_dir', template_mmcif_dir),
      ('obsolete_pdbs_path', obsolete_pdbs_path),
  ]

  if args.model_preset == 'multimer':
    database_paths.append(('uniprot_database_path', uniprot_database_path))
    database_paths.append(('pdb_seqres_database_path',
                           pdb_seqres_database_path))
  else:
    database_paths.append(('pdb70_database_path', pdb70_database_path))

  if args.db_preset == 'reduced_dbs':
    database_paths.append(('small_bfd_database_path', small_bfd_database_path))
  else:
    database_paths.append(('uniref30_database_path', uniref30_database_path))
    database_paths.append(('bfd_database_path', bfd_database_path))

  for name, path in database_paths:
    if path:
      command_args.append(f'--{name}={path}')

  command_args.extend([
      f'--output_dir={args.output_dir}',
      f'--hhblits_binary_path={args.hhblits_binary_path}',
      f'--max_template_date={args.max_template_date}',
      f'--db_preset={args.db_preset}',
      f'--model_preset={args.model_preset}',
      f'--num_multimer_predictions_per_model={args.num_multimer_predictions_per_model}',
      f'--use_gpu_relax={args.use_gpu_relax}',
      f'--models_to_relax={args.models_to_relax}',
      f'--benchmark={args.benchmark}',
      f'--use_precomputed_msas={args.use_precomputed_msas}',
      '--logtostderr',
  ])

  env_vars = {
          'CUDA_VISIBLE_DEVICES': args.gpu_devices,
          'NVIDIA_VISIBLE_DEVICES': args.gpu_devices,
          # The following flags allow us to make predictions on proteins that
          # would typically be too long to fit into GPU memory.
          'TF_FORCE_UNIFIED_MEMORY': '1',
          'XLA_PYTHON_CLIENT_MEM_FRACTION': '4.0',
          }
  env_vals = ','.join('%s=%s' % (key,value) for key,value in env_vars.items())

  # AlphaFold uses Python tempfile which uses TMPDIR env variable
  # which is /scratch/job-id-string on wynton.  Otherwise Python will use /tmp
  # which is only 4-8 GB on wynton and will cause write errors on large sequences.
  import os
  tempdir = os.environ.get('TMPDIR', '/tmp')

  args = ['singularity',
          'run',
          '--nv',  # Use Nvidia container library to use CUDA
          '-B "%s"' % args.mount_data_dir,    # Mount AlphaFold databases
          '-B "%s"' % os.getcwd(),	# Mount current directory for sequence
          '-B "%s"' % tempdir,		# Mount scratch directory
          '--env %s' % env_vals, 
          args.singularity_image_path
        ] + command_args
  cmd = ' '.join(args)
  print (cmd)

  from subprocess import run
  import sys
  run(cmd,
      stdout = sys.stdout, stderr = sys.stderr,
      shell = True,
      executable = '/bin/csh',
      check = True)

if __name__ == '__main__':
  main()
