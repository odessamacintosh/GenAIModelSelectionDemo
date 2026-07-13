# How This Demo Works: Provider-Agnostic GenAI Architecture

This guide walks through what happens when you submit a query in the demo,
from your browser all the way to the AI model that answers it.

## The big idea

Three different AI companies build the models behind this demo: Anthropic
(Claude), OpenAI (GPT-OSS), and Amazon (Nova). Normally, talking to each of
these providers means learning a different API, a different request format,
and a different response format for each one.

This demo shows a pattern for avoiding that: write your application once,
and let the backend decide which provider actually answers. The app code
never needs to know or care which one it's talking to.

## The journey of one query

```
 You type a question and click Submit
              |
              v
     [ Browser: index.html + app.js ]
              |
              |  Sends one HTTP POST request to /query
              |  with just your question text
              v
     [ API Gateway ]
              |
              |  Public entry point, routes the request
              |  to the backend function
              v
     [ Lambda function: lambda_handler.py ]
              |
              |  Reads your request, kicks off routing
              v
     [ router.py : "which model should answer this?" ]
              |
              |  Picks Claude, GPT-OSS, or Nova based on
              |  health, load, and strategy
              v
     [ bedrock_adapter.py : "call whichever model was picked" ]
              |
              |  Uses AWS Bedrock's Converse API - one
              |  consistent format for every provider
              v
     [ AWS Bedrock ]
              |
              v
     [ Claude  /  GPT-OSS  /  Nova ]
              |
              |  Answer flows back up through the same path
              v
     Your browser displays the response
```

## The one thing to take away

Look at the code your browser runs to submit a query:

```javascript
async function submitQuery(query) {
    const response = await fetch(API_URL + '/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            query: query,
            sessionId: generateSessionId()
        })
    });

    const result = await response.json();

    // Response format is identical for ALL providers
    console.log('Provider:', result.metadata.provider);  // anthropic, openai, or nova
    console.log('Response:', result.response);
    console.log('Tokens:', result.metadata.tokensUsed);

    return result;
}
```

Notice what's **not** here: no `if (provider === 'anthropic')`, no
provider-specific SDK, no special-casing. This function is exactly the same
whether Claude, GPT-OSS, or Nova ends up answering. The `result.metadata.provider`
field only tells you *after the fact* which one responded - the client never
requests a specific provider.

That's only possible because of two things working together:

1. **AWS Bedrock's Converse API** gives every provider the same request and
   response shape, even though the underlying models are built completely
   differently by different companies.
2. **A router on the backend** (`router.py`) is the only piece of code in the
   whole system that actually decides which provider to use. Everything else -
   the browser, the API, the Bedrock adapter - just passes requests through
   without caring about that decision.

## Why this matters

If you build applications by calling each AI provider's SDK directly, your
code becomes locked to that provider. Switching providers, adding a new one,
or failing over automatically when one is down means rewriting application
logic.

If you build against a stable abstraction layer instead (like Bedrock's
Converse API, or a similar pattern you build yourself), your application code
stays stable while the routing/provider logic evolves independently behind it.
That's the core architectural pattern this demo exists to show.

## Terms you'll see in the demo UI

- **Provider** - which company's model answered (Anthropic, OpenAI, or Amazon Nova).
- **Routing strategy** - the rule the backend uses to pick a model (e.g. balance
  cost vs. speed vs. quality).
- **Health status** - whether a given model is currently responding normally.
- **Circuit breaker** - a safety mechanism that temporarily stops sending
  requests to a model that's failing, so the system can fail over to a
  healthy one instead of repeatedly hitting a broken one.
