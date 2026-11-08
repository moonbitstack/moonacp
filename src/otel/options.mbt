// What the wrappers need to know that the protocol itself may not have said.

///|
/// The agent's name and version.
///
/// The wire carries both, in the answer to `initialize`; the agent side reads them there. An
/// editor holds no such answer, so its wrapper is told them instead. Leaving a name empty keeps
/// `gen_ai.agent.name` off the span rather than putting a stand-in on it.
pub(all) struct Options {
  agent_name : String
  agent_version : String
}

///|
/// Names nothing: the spans carry only what the protocol says.
pub let options : Options = { agent_name: "", agent_version: "", }
