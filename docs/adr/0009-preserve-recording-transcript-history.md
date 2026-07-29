# Preserve recording transcript history

Each successful cloud transcription, local transcription, or translation appends a durable version to the existing recording. Reprocessing does not create a duplicate recording and does not overwrite earlier successful output. The latest version remains projected through the legacy scalar transcript fields until their consumers migrate. Existing scalar-only recordings surface as one legacy history entry, while YouTube source captions remain separate provenance artifacts under ADR 0003.
