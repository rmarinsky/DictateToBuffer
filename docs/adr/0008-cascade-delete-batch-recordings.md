# Cascade-delete recordings with their batch

Deleting a transcription batch will delete every recording referenced by that batch, including recordings that were added from the Library or shared with another batch. Those recordings are removed from the Library and from every other batch, so completed batch membership and counts may change. The UI must explicitly confirm the affected recording count and warn about shared recordings. This favors a simple ownership experience over preserving shared material and accepts the resulting data-loss risk as an intentional product decision.
