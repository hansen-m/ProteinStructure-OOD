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

    function updateFormVisibility() {
        var sessionType = $('#batch_connect_session_context_session_type').val();
        
        // Handle use_fasta_af3 visibility
        if (sessionType === 'AlphaFold 2') {
            $('#batch_connect_session_context_use_fasta_af3').closest('.form-group').hide();
            $('#batch_connect_session_context_agree_terms').closest('.form-group').hide();
        } else {
            $('#batch_connect_session_context_use_fasta_af3').closest('.form-group').show();
            $('#batch_connect_session_context_agree_terms').closest('.form-group').show();
        }
    }

    // Add new validation functions
    function isValidFASTA(sequence) {
        const fastaPattern = /^>.*\n([A-Za-z\n]+)$/;
        return fastaPattern.test(sequence);
    }

    function isValidJSON(sequence) {
        try {
            const json = JSON.parse(sequence);
            if (!Array.isArray(json) || json.length === 0) return false;
            for (const job of json) {
                if (!job.name || !Array.isArray(job.modelSeeds) || !Array.isArray(job.sequences)) return false;
                for (const entity of job.sequences) {
                    if (!entity.proteinChain && !entity.dnaSequence && !entity.rnaSequence && !entity.ligand && !entity.ion) return false;
                }
            }
            return true;
        } catch (e) {
            return false;
        }
    }

    function convertFASTAToJSON(fasta) {
        const lines = fasta.split("\n");
        const json = [{
            name: "Converted Job",
            modelSeeds: [],
            sequences: [{ proteinChain: { sequence: lines.slice(1).join("") } }]
        }];
        return JSON.stringify(json, null, 2);
    }

    function convertJSONToFASTA(json) {
        const parsed = JSON.parse(json);
        const sequences = parsed[0].sequences;
        let fasta = "";
        for (const entity of sequences) {
            if (entity.proteinChain) {
                fasta += `>Converted Sequence\n${entity.proteinChain.sequence}\n`;
            }
        }
        return fasta.trim();
    }

    // Create error container
    const form = $('#new_batch_connect_session_context');
    const errorContainer = $('<div class="alert alert-danger" style="display: none;"></div>');
    form.prepend(errorContainer);

    function displayError(message) {
        errorContainer.text(message).show();
    }

    function validateInput() {
        const sequence = $('#batch_connect_session_context_protein_sequence').val().trim();
        const sessionType = $('#batch_connect_session_context_session_type').val();
        const useFasta = $('#batch_connect_session_context_use_fasta_af3').is(':checked');
        errorContainer.hide();

        if (sessionType === 'AlphaFold 3') {
            if (useFasta) {
                if (!isValidFASTA(sequence)) {
                    displayError("Invalid input: Please enter a valid FASTA sequence for AlphaFold 3.");
                    return false;
                }
            } else if (!isValidJSON(sequence)) {
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

    // Add form submission handler
    form.on('submit', function(event) {
        if (!validateInput()) {
            event.preventDefault();
            $('input[type="submit"]').prop('disabled', false).removeAttr('data-disable-with');
        }
    });

    // Add input handler
    $('#batch_connect_session_context_protein_sequence').on('input', function() {
        $('input[type="submit"]').prop('disabled', false).removeAttr('data-disable-with');
    });

    // Update event handlers section
    $('#batch_connect_session_context_session_type').change(function() {
        updateProteinSequenceField();
        updateFormVisibility();
    });
    $('#batch_connect_session_context_use_fasta_af3').change(updateProteinSequenceField);

    // Initial setup
    updateProteinSequenceField();
    updateFormVisibility();
});
