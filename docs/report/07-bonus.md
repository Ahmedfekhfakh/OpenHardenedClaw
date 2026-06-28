# 7. Bonus: Egress-Through-Approved-Domain Attack Class

## The Problem

Traditional egress control focuses on blocking connections to unauthorized destinations. A firewall allowlist permits traffic to "good" domains and blocks everything else. This model fails for agentic AI systems because of a subtle but fundamental property: **an allowlist is a capability grant, not a destination filter.**

Consider a deployment where the agent must call a remote LLM provider API (e.g., `api.openai.com`). The allowlist permits HTTPS traffic to that domain. The agent, whether compromised by prompt injection or acting on a direct user instruction, can now exfiltrate arbitrary data by encoding it in API requests to the permitted domain:

- **URL path encoding:** `GET /v1/chat/completions?metadata=BASE64_ENCODED_SECRET`
- **HTTP header injection:** Custom headers containing sensitive data
- **Request body embedding:** The "system prompt" or "user message" field of a chat completion request can carry arbitrary text, including secrets, credentials, or internal file contents
- **Model name or parameter fields:** Any string field in the API schema can carry a covert payload

From the network layer's perspective, this is a legitimate HTTPS request to an allowed domain. A firewall, proxy, or DNS filter cannot distinguish it from a normal API call without deep content inspection. Even a TLS-intercepting proxy faces challenges: the payload is semantically embedded in the API protocol, not in a suspicious header or URL pattern.

This is the **egress-through-approved-domain** class. It applies to any deployment where the agent has both (a) read access to sensitive data and (b) permitted network egress to any endpoint, even a trusted one.

## Why This Is Especially Dangerous for Agentic Systems

In a traditional application, the developer controls what data enters API calls. In an agentic system, the **model** composes API calls autonomously. A compromised or misbehaving model can embed arbitrary data in any field of any permitted API request. The developer cannot enumerate all possible exfiltration encodings because the model has full control over the request content.

Anthropic's containment guidance makes this explicit: every permitted egress path is a capability the agent can abuse. An allowlist does not "filter out bad traffic" -- it positively grants the ability to send data to specific destinations.

## The Fix: Local Model + Network Isolation

This deployment eliminates the egress-through-approved-domain class entirely by removing both prerequisites:

1. **Local model serving (llama.cpp).** The `.gguf` model runs locally inside the `llamacpp-server` container on the internal Docker network. There is no remote LLM provider API. No API key enters the deployment. The `baseUrl` in `openclaw.json` points to `http://llamacpp-server:8080/v1` -- a container-local address with no internet route.

2. **No internet route (`internal: true`).** The Docker network has no default gateway to the host network. Even if the agent constructs a request to an external domain, the connection fails at the network layer. The sandbox container goes further with `network_mode: none` (no network interfaces at all).

With no external endpoint reachable and no API key to steal, the egress-through-approved-domain class is structurally impossible. The attack has no viable channel.

## Fallback: Inspecting Proxy for Partial Egress

In deployments where some external egress is unavoidable (e.g., the agent must fetch documentation from the internet, or a remote model API is the only option), the following mitigations apply:

1. **TLS-intercepting (MITM) proxy.** Route all egress through a forward proxy that terminates TLS, inspects request content, and re-encrypts. This allows content-level inspection of API calls, not just destination filtering.

2. **Request-body auditing.** Log and audit the content of API request bodies, not just URLs and headers. Flag requests where the body contains data that does not match the expected schema (e.g., a chat completion request whose "user message" contains what looks like a private key or credentials).

3. **Egress budget.** Rate-limit and size-limit outbound requests. A data-exfiltration attempt typically requires more bandwidth or more requests than normal operation.

4. **Treat the allowlist as a capability review.** Every domain on the allowlist should be reviewed as a capability grant: "Are we comfortable with this agent being able to send arbitrary data to this domain?" If the answer is "no," the domain should not be on the allowlist, or the agent should not have read access to the data in question.

These mitigations reduce but do not eliminate the risk. The local-model approach is strictly superior for deployments where it is feasible, because it removes the channel entirely rather than trying to inspect its contents.

## Connection to Project Architecture

This project's three-container topology was designed with the egress-through-approved-domain class in mind:

- `llamacpp-server` is the only "API endpoint" reachable from the gateway, and it is local (no internet path, no real API key, no data leaves the host).
- `openclaw-internal` network has `internal: true` -- the Docker daemon does not create a NAT route to the host network.
- `openclaw-sandbox` has `network_mode: none` -- no network interfaces at all.
- Credentials are unmounted -- even if egress existed, there would be nothing sensitive to exfiltrate from `~/.openclaw/credentials/`.

The result is defense in depth: even if one layer fails (e.g., a future configuration change adds an external endpoint), the other layers (unmounted credentials, read-only config preventing endpoint redirection) still limit the blast radius.
