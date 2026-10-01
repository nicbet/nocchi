import Foundation
import Testing
@testable import NocchiCodex

/// Lines shaped like Codex CLI 0.159 rollouts.
@Suite struct CodexRolloutTests {
    func parse(_ json: String) -> CodexRolloutEvent? { CodexRolloutEvent.parse(Data(json.utf8)) }
    func item(_ json: String) -> CodexRolloutEvent? {
        parse(#"{"timestamp":"t","type":"event_msg","payload":{"type":"item_completed","thread_id":"x","item":\#(json)}}"#)
    }

    @Test func sessionAndTurns() {
        #expect(parse(#"{"type":"session_meta","payload":{"session_id":"01a0","cwd":"/r/app"}}"#) == .session(id: "01a0", cwd: "/r/app"))
        #expect(parse(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#) == .turnStarted)
        #expect(parse(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"**Done.** All tests pass.\n\nDetails…"}}"#)
            == .turnCompleted(lastMessage: "Done. All tests pass."))
        #expect(parse(#"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#) == .turnAborted)
        #expect(parse(#"{"type":"event_msg","payload":{"type":"token_count"}}"#) == nil)
        #expect(parse("nope") == nil)
    }

    @Test func stepsFromCompletedItems() {
        #expect(item(#"{"type":"CommandExecution","command":["/bin/zsh","-lc","rg --files"],"parsed_cmd":[{"type":"read","cmd":"sed -n 1,80p main.go","name":"main.go"}]}"#)
            == .step("Reading main.go"))
        #expect(item(#"{"type":"CommandExecution","command":["/bin/zsh","-lc","pwd && rg --files -g '!vendor'"],"parsed_cmd":[{"type":"unknown","cmd":"pwd && rg --files"}]}"#)
            == .step("Running pwd && rg --files"))
        #expect(item(#"{"type":"CommandExecution","command":["/bin/zsh","-lc","make test"]}"#) == .step("Running make test"))
        #expect(item(#"{"type":"FileChange","changes":{"/r/app/main.go":{"type":"update"},"/r/app/util.go":{"type":"update"}}}"#)
            == .step("Editing main.go and 1 more"))
        #expect(item(#"{"type":"FileChange","changes":{"/r/app/new.go":{"type":"add"}}}"#) == .step("Creating new.go"))
        #expect(item(#"{"type":"McpToolCall","server":"xpo","tool":"add_note"}"#) == .step("xpo: add note"))
        #expect(item(#"{"type":"Extension","kind":"web.search","query":"swift testing exit tests"}"#) == .step("Searching the web for “swift testing exit tests”"))
        #expect(item(#"{"type":"AgentMessage","content":[{"type":"Text","text":"Hello!"}],"phase":"final_answer"}"#) == .message("Hello!"))
        #expect(item(#"{"type":"Reasoning","summary_text":[]}"#) == nil)
    }
}
