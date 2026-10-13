# Agent Lens

A macOS-native utility that tells you **which AI CLI tools are actually installed, where they came from, and which copy PATH resolves to**. Built in Swift 6 (D-001): an `AgentLensCore` engine plus an `agent-lens` CLI, with a SwiftUI app arriving later.

This repository surfaces the diagnostic that no existing tool answers: when multiple copies of an AI CLI exist on your machine, which one wins — and why. See `AGENT_LENS_SCOPE.md` for the full scope and `DECISIONS.md` for settled design decisions.
