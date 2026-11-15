"""Context compaction (design 6.2): a safety net, the same for every agent in every condition.

The system prompt, the first user message (the brief or the lead's instructions) and the last `keep_last_turns`
assistant turns stay whole; everything between them is replaced by one summary the same model writes. A tool result is
never separated from the assistant message that asked for it.
"""

from collabbench.harness.llm import ChatClient, ChatResult

SUMMARY_PREFIX = "[Summary of your earlier work]"
_SUMMARIZER = ("You compress an agent's work log so it can keep working with less context. Write a dense summary: "
               "what it found (paths, names, values, test results), what it changed, what it promised teammates, "
               "what is left to do. Keep every exact identifier, number and file path. No preamble.")


async def compact(messages: list[dict], client: ChatClient, keep_last_turns: int = 6
                  ) -> tuple[list[dict], ChatResult | None]:
    assistant_at = [i for i, m in enumerate(messages) if i >= 2 and m.get("role") == "assistant"]
    if len(assistant_at) <= keep_last_turns:
        return messages, None
    split = assistant_at[-keep_last_turns]
    middle = messages[2:split]
    if not middle:
        return messages, None
    res = await client.chat([{"role": "system", "content": _SUMMARIZER},
                             {"role": "user", "content": _render(middle)}], [])
    summary = {"role": "user", "content": f"{SUMMARY_PREFIX}\n{res.content.strip()}"}
    return [messages[0], messages[1], summary, *messages[split:]], res


def _render(messages: list[dict], limit: int = 2000) -> str:
    lines = []
    for m in messages:
        role = m.get("role")
        if role == "assistant":
            if m.get("content"):
                lines.append(f"ASSISTANT: {m['content'][:limit]}")
            for c in m.get("tool_calls") or []:
                lines.append(f"CALL {c['function']['name']} {c['function']['arguments'][:limit]}")
        elif role == "tool":
            lines.append(f"RESULT: {str(m.get('content', ''))[:limit]}")
        else:
            lines.append(f"{str(role).upper()}: {str(m.get('content', ''))[:limit]}")
    return "\n".join(lines)
