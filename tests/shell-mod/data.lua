-- Capture the frozen original constructor before vanilla expansion
-- data-updates add new defaults to its parent prototypes (e.g. speaker heat).
-- Factorio resets module caches across data phases; use a unique test-only
-- global rather than reconstructing against already-modified parent defaults.
cc2_shell_original_prototypes=require('original_prototypes')
