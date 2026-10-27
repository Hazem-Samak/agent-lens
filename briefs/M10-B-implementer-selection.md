# M10-B implementer selection

Date: 2026-10-27, Africa/Cairo. Surface: T3 Code. This selection supplements the frozen [M10-B brief](M10-B-npm-latest.md); it does not change its bytes, scope, acceptance criteria or file authority.

The user selected:

- Primary: Nemotron 3.5 Super VL through OpenRouter. Use the existing T3 Pi route `pi` / `openrouter/nvidia/nemotron-3.5-super-vl:free`, keeping the implementer on the same Pi surface as the selected fallback. This Pi surface choice resolves the unspecified CLI using the available route; it does not substitute a model/provider. T3 advertises this model as available for child tasks.
- Authorized fallback for provider/model issues or quota limits: DeepSeek V4.1 Flash through WorkBuddy Pi, `pi` / `workbuddy/deepseek-v4.1-flash`. Do not substitute the River 1017 council model or OpenCode's similarly named model.
- No effort level was selected in this instruction. Preserve the provider's advertised default unless the user sets one before dispatch; do not import the council's high effort or Qwen's prompt-only maximum request.

Fallback handling: record the concrete primary failure/quota evidence; stop/cancel the primary run before starting the fallback. Keep one product writer on `codex/m10-npm-management`, preserve the current candidate and raw failure evidence, and hand the fallback the frozen brief plus current changes/findings rather than starting a divergent implementation. A genuine implementation defect goes through the brief's numbered correction/review process; the fallback instruction does not expand scope or skip acceptance.

This turn records implementer selection. Implementation dispatch, baseline gates and fixture/native-host readiness remain pending. No implementer child task, model smoke call or product edit was started merely to verify the catalog. The next explicit implementation instruction can use these selected routes without asking the user to choose them again.

## User-authorized replacement after both provider failures

The user selected “qwen 3.8 flash from qoder cli max effort available”. Current implementer: T3 `acpRegistry_qoder_cli` / `qfmodel` (Qwen3.8-Flash). The catalog exposes no effort option; maximum-effort reasoning is requested in the prompt, with no provider-enforced effort claim. This is Flash, not `qmodel_38max` (the expensive planning reviewer). Product implementation remains authorized by the prior “implement !”. Both failed Pi tasks were stopped; this replacement is the sole writer. Frozen scope and acceptance are unchanged.
