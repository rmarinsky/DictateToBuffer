# Preserve generated transcripts and source captions separately

Diduny will persist the generated transcript and extracted source captions as separate artifacts, each with explicit provenance. The generated transcript remains the primary recording result; captions are companion artifacts rather than content merged into that transcript. If either artifact fails, the successful artifact remains persisted and a retry targets only the missing or failed artifact, preserving useful partial results without ambiguity or data loss.
