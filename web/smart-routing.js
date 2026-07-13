/**
 * Smart Routing Demo - minimal standalone page
 *
 * Deliberately simple: one query box, one API call, one result. No session
 * history, no dashboards, no health monitoring. This page exists to teach
 * complexity-based model tiering (Haiku / Sonnet / Opus) in isolation from
 * the more advanced patterns in the main demo.
 */

const apiBaseUrl = 'https://89146f5y80.execute-api.us-east-1.amazonaws.com/Prod'; // Will be configured for API Gateway

const queryInput = document.getElementById('queryInput');
const submitBtn = document.getElementById('submitBtn');
const resultSection = document.getElementById('resultSection');
const errorSection = document.getElementById('errorSection');
const tierBadge = document.getElementById('tierBadge');
const reasonText = document.getElementById('reasonText');
const complexityScore = document.getElementById('complexityScore');
const tokensUsed = document.getElementById('tokensUsed');
const latencyMs = document.getElementById('latencyMs');
const answerText = document.getElementById('answerText');

const TIER_COLORS = {
    haiku: '#2ecc71',
    sonnet: '#3498db',
    opus: '#9b59b6'
};

async function submitQuery() {
    const query = queryInput.value.trim();
    if (!query) {
        return;
    }

    submitBtn.disabled = true;
    submitBtn.textContent = 'Thinking...';
    resultSection.style.display = 'none';
    errorSection.style.display = 'none';

    try {
        const response = await fetch(apiBaseUrl + '/smart-routing', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query: query })
        });

        const result = await response.json();

        if (!response.ok || result.error) {
            const message = (result.error && result.error.message) || 'Request failed';
            throw new Error(message);
        }

        tierBadge.textContent = result.tier.toUpperCase();
        tierBadge.style.backgroundColor = TIER_COLORS[result.tier] || '#888';
        reasonText.textContent = result.reason;
        complexityScore.textContent = result.complexity_score;
        tokensUsed.textContent = result.tokens_used;
        latencyMs.textContent = result.latency_ms;
        answerText.textContent = result.response;

        resultSection.style.display = 'block';
    } catch (error) {
        errorSection.textContent = 'Error: ' + error.message;
        errorSection.style.display = 'block';
    } finally {
        submitBtn.disabled = false;
        submitBtn.textContent = 'Submit Query';
    }
}

submitBtn.addEventListener('click', submitQuery);
queryInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter' && e.ctrlKey) {
        submitQuery();
    }
});
