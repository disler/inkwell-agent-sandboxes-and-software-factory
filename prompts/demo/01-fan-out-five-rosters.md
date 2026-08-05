Run the redesign in prompts/06-redesign-quiet-room.md five times — once per agent config in
adws/adw_sssf_config/ (default, frontier, deepestseek, open-weights, top-speed), each in its own
sandbox. Use the name of the config in the name of the sandbox.
Use the agent-mediated kickoff path: delegate to the orchestrator agent inside each box
and have IT launch the full adw_simple_sdlc workflow (plan → build → test → review → document)
with its roster. Mount five boxes, command the five in-box agents, report the five run ids and
URLs. Do not tear anything down.
