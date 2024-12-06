$(document).ready(function() {
  function updateProteinSequenceField() {
      var sessionType = $('#batch_connect_session_context_session_type').val();

      var label = 'Input Sequence';
      var helpText = 'Enter the input sequence.';
      var rows = 5;

      if (sessionType === 'AlphaFold 2') {
          label = 'Input Sequence (FASTA format)';
          helpText = 'Input must be in FASTA format for AlphaFold2.';
          rows = 5;
      } else if (sessionType === 'AlphaFold 3') {
          label = 'Input Sequence (JSON format)';
          helpText = 'Input must be in JSON format as prescribed by AlphaFold3. You can find detailed instructions to set up the input in <a href="https://github.com/google-deepmind/alphafold3/blob/main/docs/input.md" target="_blank">AlphaFold3\'s documentation</a>.';
          rows = 15;
      }

      var $formGroup = $('#batch_connect_session_context_protein_sequence').closest('.form-group');
      $formGroup.find('label').text(label);
      $formGroup.find('.form-text').html(helpText);
      $('#batch_connect_session_context_protein_sequence').attr('rows', rows);
  }

  function updateFormVisibility() {
      var sessionType = $('#batch_connect_session_context_session_type').val();

      if (sessionType === 'AlphaFold 2') {
          $('#batch_connect_session_context_agree_terms').closest('.form-group').hide();
      } else {
          $('#batch_connect_session_context_agree_terms').closest('.form-group').show();
      }
  }

  function isValidFASTA(sequence) {
      const fastaPattern = /^>.*\n([A-Za-z\n]+)$/;
      return fastaPattern.test(sequence);
  }

  function isValidJSON(sequence) {
    try {
        const json = JSON.parse(sequence);

        if (!(typeof json === 'object' && json !== null)) {
            displayError("JSON input must be an object.");
            return false;
        }

        if (!json.name) {
            displayError("JSON input must contain a 'name' field.");
            return false;
        }
        if (!Array.isArray(json.modelSeeds)) {
            displayError("JSON input must contain a 'modelSeeds' array.");
            return false;
        }
        if (!Array.isArray(json.sequences)) {
            displayError("JSON input must contain a 'sequences' array.");
            return false;
        }

        for (const entity of json.sequences) {
            if (!entity.protein && !entity.dnaSequence && !entity.rnaSequence && !entity.ligand && !entity.ion) {
                displayError("Each sequence must contain at least one of 'protein', 'dnaSequence', 'rnaSequence', 'ligand', or 'ion'.");
                return false;
            }
            if (entity.protein) {
                if (!entity.protein.id || !entity.protein.sequence) {
                    displayError("Each 'protein' must contain 'id' and 'sequence'.");
                    return false;
                }
            }
        }
        return true;
    } catch (e) {
        displayError("Invalid JSON format: " + e.message);
        return false;
    }
}

  const form = $('#new_batch_connect_session_context');
  const errorContainer = $('<div class="alert alert-danger" style="display: none;"></div>');
  form.prepend(errorContainer);

  function displayError(message) {
      errorContainer.text(message).show();
  }

  function validateInput() {
      const sequence = $('#batch_connect_session_context_protein_sequence').val().trim();
      const sessionType = $('#batch_connect_session_context_session_type').val();
      errorContainer.hide();

      if (sessionType === 'AlphaFold 3') {
          if (!isValidJSON(sequence)) {
              displayError("Invalid input: Please enter a valid JSON sequence for AlphaFold 3.");
              return false;
          }
      } else if (sessionType === 'AlphaFold 2') {
          if (!isValidFASTA(sequence)) {
              displayError("Invalid input: Please enter a valid FASTA sequence for AlphaFold 2.");
              return false;
          }
      }
      return true;
  }

  form.on('submit', function(event) {
      if (!validateInput()) {
          event.preventDefault();
          $('input[type="submit"]').prop('disabled', false).removeAttr('data-disable-with');
      }
  });

  $('#batch_connect_session_context_protein_sequence').on('input', function() {
      $('input[type="submit"]').prop('disabled', false).removeAttr('data-disable-with');
  });

  $('#batch_connect_session_context_session_type').change(function() {
      updateProteinSequenceField();
      updateFormVisibility();
  });

  updateProteinSequenceField();
  updateFormVisibility();
});
