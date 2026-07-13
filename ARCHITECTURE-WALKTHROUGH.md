# Architecture Walkthrough: How a Query Flows Through the System

This doc traces exactly what happens between a student clicking "Submit Query" in
the browser and getting an answer back, file by file. Use this as the reference
when explaining the demo, or when deciding what to simplify/skip for class.

## The full chain

```
web/index.html
    |  (loads app.js, renders the query box + Submit button)
    v
web/app.js  ->  submitQuery()
    |  fetch(API_URL + '/query', { method: 'POST', body: { query, sessionId } })
    v
API Gateway
    |  public HTTPS endpoint, routes POST /query to the Lambda function
    v
lambda/lambda_handler.py  ->  lambda_handler()
    |  entry point AWS actually invokes; parses/validates the request body
    v
lambda/lambda_handler.py  ->  handle_query_request()
    |  orchestrates the two steps below
    v
lambda/router.py  ->  router.route_query()
    |  DECIDES which model/provider should answer (Claude, GPT-OSS, or Nova)
    |  based on strategy, health checks, and load - the client never picks this
    v
lambda/bedrock_adapter.py  ->  adapter.converse()
    |  takes whatever model_id the router chose and calls Bedrock with it
    |  does NOT decide which model to use, just executes the call
    v
AWS Bedrock Converse API
    |  normalizes the request into whatever the underlying provider needs
    v
Actual model (Anthropic Claude / OpenAI GPT-OSS / Amazon Nova)
```

## Where each file lives once deployed

| File | Deployed to | How it gets there |
|---|---|---|
| `web/index.html`, `web/app.js`, `web/styles.css` | S3 bucket, served via CloudFront | `aws s3 sync web/ s3://...` in `deploy-sam.sh` |
| `web/smart-routing.html`, `web/smart-routing.js`, `web/smart-routing-styles.css` | Same S3 bucket/CloudFront | Same `aws s3 sync`, no script changes needed |
| `lambda/*.py` | Lambda function `genai-model-selection-demo-router` | `sam build` + `sam deploy` zips and uploads it |

The browser only ever talks to one URL: the CloudFront website URL for the page
itself, and the API Gateway URL for `/query`. It never talks to Bedrock, and it
never talks to Anthropic/OpenAI/Amazon directly.

## The one teaching point that actually matters

The frontend code (`submitQuery()`) is identical no matter which provider answers.
It doesn't branch on provider, doesn't import provider-specific SDKs, doesn't
change its request shape. The **only** place in the entire codebase that decides
"use Claude vs GPT-OSS vs Nova" is `router.route_query()` in `lambda/router.py`.
Everything else - the adapter, the frontend, API Gateway - is just plumbing that
stays the same regardless of that decision.

If you only have time to make one thing land with students, make it this one.

## A note on complexity for a first-module demo

This codebase implements a lot more than the core teaching point above:
circuit breakers, health monitoring with caching, load balancing, failure
simulation, routing strategies, session history, live metrics dashboards. All of
that is real, working code, but none of it is necessary to demonstrate
"provider-agnostic architecture" to students seeing this for the first time.

For a first module, consider walking through only:

1. `web/app.js` -> `submitQuery()` (or even just the simplified snippet in the
   "View Code" modal) - the client makes one call, no provider awareness.
2. `lambda/router.py` -> `route_query()` - this is where the decision happens.
3. `lambda/bedrock_adapter.py` -> `converse()` - this is what makes the decision
   *possible*, because Bedrock gives every provider the same request/response
   shape.

That's a 3-file, 3-concept story. Everything else in the UI (health monitoring
panels, failure simulation controls, routing strategy dropdowns, metrics
dashboards) is supporting detail that's more appropriate for a later module on
reliability/observability, and will likely generate off-topic questions if shown
in module one.

Options if you want to reduce surface area before class:
- Present only the "Query Interface" and "Provider Status" panels, and skip or
  hide the "Instructor Controls" (failure simulation) and metrics dashboard for
  the first session.
- Or, before class, do a screen-share walkthrough of just the 3 files above
  instead of clicking through the live web UI - keeps the discussion anchored to
  code rather than UI widgets students will want to poke at.

## The second demo: `/smart-routing`

Because the main demo above ended up carrying a lot of supporting complexity
(circuit breakers, load balancing, failure simulation, metrics dashboards),
there's a second, deliberately minimal demo at `web/smart-routing.html` that
teaches exactly one additional idea: **routing by query complexity, within a
single model family.**

Where it's linked from: the main demo's header has a "Next demo" link pointing
to `smart-routing.html`.

### The chain for this demo

```
web/smart-routing.html
    |  (loads smart-routing.js, renders a single query box)
    v
web/smart-routing.js  ->  submitQuery()
    |  fetch(apiBaseUrl + '/smart-routing', { method: 'POST', body: { query } })
    v
API Gateway
    |  routes POST /smart-routing to the SAME Lambda function as the main demo
    v
lambda/lambda_handler.py  ->  lambda_handler()
    |  sees path == '/smart-routing', routes to the handler below
    v
lambda/lambda_handler.py  ->  handle_smart_routing_request()
    |  calls the two small functions below, then calls the adapter directly
    |  (no router.py, no health monitor, no circuit breaker involved)
    v
lambda/lambda_handler.py  ->  estimate_query_complexity() + select_model_tier()
    |  scores the query 0.0-1.0 by length + a small reasoning-keyword check,
    |  then maps that score to Haiku (<0.3), Sonnet (0.3-0.7), or Opus (>0.7)
    v
lambda/bedrock_adapter.py  ->  adapter.converse()
    |  same adapter as the main demo, just called with a Claude tier model_id
    v
AWS Bedrock Converse API
    v
Claude Haiku / Sonnet / Opus (whichever tier was selected)
```

### Why this is a separate, simpler path

This demo reuses `bedrock_adapter.py` (the Bedrock abstraction) but
deliberately does **not** go through `router.py`. There's no load balancer, no
circuit breaker, no health monitoring cache involved - `handle_smart_routing_request()`
calls the adapter directly. That's intentional: the whole routing decision fits
in two small functions (`estimate_query_complexity` and `select_model_tier` in
`lambda_handler.py`), so it can be read top to bottom in a couple of minutes
without needing to first understand the more advanced reliability patterns in
the main demo.

### The teaching point for this demo

Same model family (Claude), three cost/capability tiers. Cheap/fast models are
good enough for simple queries; expensive/powerful models are worth the cost
only when the query actually needs the extra reasoning. The `complexity_score`
and `reason` fields returned by the API make the "why" of each routing decision
visible to students in real time.
