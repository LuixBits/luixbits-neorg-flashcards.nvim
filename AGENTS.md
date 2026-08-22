# Repository instructions

## Graphify knowledge graph

- `graphify-out/graph.json` is a generated local code index and is ignored by
  Git. Use the Graphify MCP tools before broad cross-file, architecture, call
  path, or change-impact exploration when the graph exists.
- Pass this repository's absolute root as `project_path`, then verify relevant
  Lua or TypeScript source before editing.
- Graphify 0.9.48 does not index Nix. Inspect Nix files normally instead of
  assuming the graph represents the complete repository.
- After changing supported source, refresh the graph with
  `graphify-project update .` before handoff.
