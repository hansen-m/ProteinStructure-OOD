$(document).ready(function() {
    function updateProteinSequenceField() {
      var sessionType = $('#batch_connect_session_context_session_type').val();
      var useFasta = $('#batch_connect_session_context_use_fasta_af3').is(':checked');
  
      var label = 'Input Sequence';
      var helpText = 'Enter the input sequence.';
      var rows = 5;
  
      if (sessionType === 'AlphaFold 2') {
        label = 'Input Sequence (FASTA format)';
        helpText = 'Input must be in FASTA format for AlphaFold2.';
        rows = 5;
      } else if (sessionType === 'AlphaFold 3') {
        if (useFasta) {
          label = 'Input Sequence (FASTA format)';
          helpText = 'Input must be in FASTA format for AlphaFold3 when "Use FASTA format instead" is checked.';
          rows = 5;
        } else {
          label = 'Input Sequence (JSON format)';
          helpText = 'Input must be in JSON format as prescribed by AlphaFold3. You can find detailed instructions to set up the input in <a href="https://github.com/google-deepmind/alphafold3/blob/main/docs/input.md" target="_blank">AlphaFold3\'s documentation</a>.';
          rows = 15;
        }
      }
  
      var $formGroup = $('#batch_connect_session_context_protein_sequence').closest('.form-group');
      $formGroup.find('label').text(label);
      $formGroup.find('.form-text').html(helpText);
      $('#batch_connect_session_context_protein_sequence').attr('rows', rows);
    }
  
    $('#batch_connect_session_context_session_type').change(updateProteinSequenceField);
    $('#batch_connect_session_context_use_fasta_af3').change(updateProteinSequenceField);
  
    updateProteinSequenceField();
  });