#!/usr/bin/env node

import { findingId, findingMarker, findingMetadata, priorFinding } from './review-history.mjs';
import { assertReviewCurrent, guardedRequest, ReviewStopped } from './review-lifecycle.mjs';
import { updateChecklist } from './review-checklist.mjs';
import { collectReviewEvidence } from './review-evidence.mjs';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {
    AI_REVIEW_BLOCKING_MARKER,
    AI_REVIEW_ROUND_MARKER,
    assertRequiredEnv,
    githubRequest,
    isCompletedLlmReview,
    paginate,
    parseRepository,
    PR_NUMBER,
    REPOSITORY,
    REVIEW_RESULT_PATH,
} from './github-api.mjs';

export function isSelfReviewRequestChangesError(error) {
    const message = String(error?.message || '');
    return (
        message.includes('GitHub API 422') &&
        message.includes('Review Can not request changes on your own pull request')
    );
}

export function isSelfReviewApproveError(error) {
    const message = String(error?.message || '');
    return message.includes('GitHub API 422') && message.includes('Review Can not approve your own pull request');
}

export function isInlineCommentPermissionError(error) {
    const message = String(error?.message || '');
    return (
        message.includes('GitHub API 403') &&
        message.includes('/pulls/') &&
        message.includes('/comments') &&
        message.includes('Resource not accessible by personal access token')
    );
}

function findingLabel(finding) {
    if (finding.tier) {
        return finding.tier;
    }

    return finding.severity === 'blocking' ? 'blocking' : 'note';
}

function formatInlineComment(finding, marker) {
    const lines = [marker, `[${findingLabel(finding)}] ${finding.message}`, findingMarker(finding)];

    if (finding.symbol) {
        lines.push('', `Symbol: \`${finding.symbol}\``);
    }

    if (finding.why) {
        lines.push('', `Why: ${finding.why}`);
    }

    return lines.join('\n');
}

export function filterAlreadyPublishedFindings(findings, comments, marker) {
    return partitionPublishedFindings(findings, comments, marker).unpublishedFindings;
}

export function partitionPublishedFindings(findings, comments, marker) {
    const byId = new Map(comments.filter((comment) => !comment.in_reply_to_id && String(comment.body || '').includes(marker))
        .map((comment) => [priorFinding(comment).finding_id, comment]));
    const unpublishedFindings = [];
    const alreadyPublishedFindings = [];
    const seen = new Set();
    for (const finding of findings) {
        const id = findingId(finding);
        if (seen.has(id)) continue;
        seen.add(id);
        const existing = byId.get(id);
        // Exact legacy text is safe; location/severity alone cannot identify a concern.
        const legacy = existing || comments.find((comment) => !comment.in_reply_to_id &&
            String(comment.body || '').includes(marker) && comment.path === finding.path &&
            String(comment.body).split('\n')[1] === `[${findingLabel(finding)}] ${finding.message}`);
        if (legacy) alreadyPublishedFindings.push(legacy.html_url ? { ...finding, existing_url: legacy.html_url } : finding);
        else unpublishedFindings.push(finding);
    }
    return { unpublishedFindings, alreadyPublishedFindings };
}

function formatFindingSummary(finding) {
    const location = finding.path && finding.line ? ` (${finding.path}:${finding.line})` : '';
    return `- [${findingLabel(finding)}] ${finding.message}${location}`;
}

export function isInlineFinding(finding) {
    return finding.inline !== false;
}

function buildDetails(title, items) {
    if (items.length === 0) {
        return [];
    }

    return ['', '<details>', `<summary>${title} (${items.length})</summary>`, '', ...items, '', '</details>'];
}

function buildLlmSection(llm) {
    if (!llm) {
        return [];
    }

    if (llm.error) {
        return ['', `**LLM review:** unavailable (${llm.error}).`];
    }

    if (llm.skipped) {
        return ['', `**LLM review:** skipped. ${llm.skipped}`];
    }

    const lines = [];

    if (llm.verdict_reasoning) {
        lines.push('', `**Verdict:** ${llm.verdict_reasoning}`);
    }

    const partialContext = [...(llm.truncated_files ?? []), ...(llm.omitted_files ?? [])];
    if (partialContext.length > 0) {
        lines.push('', `Reviewed with partial context (size budget): ${partialContext.map((path) => `\`${path}\``).join(', ')}.`);
    }

    // Required tests live in the single persistent checklist.

    const designNotes = Array.isArray(llm.design_notes) ? llm.design_notes : [];
    lines.push(
        ...buildDetails(
            'Design notes',
            designNotes.map(
                (note) =>
                    `- **${note.kind}** (${note.worth_doing_now ? 'now' : 'later'}) \`${note.location}\`: ${note.problem} → ${note.direction}`,
            ),
        ),
    );

    const dismissedHints = Array.isArray(llm.dismissed_hints) ? llm.dismissed_hints : [];
    lines.push(
        ...buildDetails(
            'Dismissed heuristic hints',
            dismissedHints.map((hint) => `- \`${hint.rule}\` in \`${hint.path}\`: ${hint.reason}`),
        ),
    );

    const level = llm.effort ? `effort: ${llm.effort}` : `thinking: ${llm.thinking_level}`;
    const duration = typeof llm.duration_seconds === 'number' ? ` in ${Math.round(llm.duration_seconds)}s` : '';
    const cost = typeof llm.cost_usd === 'number' ? `, est. cost $${llm.cost_usd.toFixed(2)}` : '';
    const route = llm.tier ? ` Routed to ${llm.tier}: ${llm.route_reason}` : '';
    lines.push('', `_Reviewed by ${llm.engine} / ${llm.model} (${llm.model_version}, ${level})${duration}${cost}.${route}_`);
    lines.push('', AI_REVIEW_ROUND_MARKER);
    return lines;
}

function buildReviewBody(result, options = {}) {
    const summaryLines = [];
    const findings = Array.isArray(result.findings) ? result.findings : [];
    const summarizedFindings = Array.isArray(options.summarizedFindings) ? options.summarizedFindings : [];

    if (result.verdict === 'request_changes') {
        if (options.inlineCommentsPublished === false) {
            summaryLines.push('Issues found. Inline comments could not be published with this token, so the findings are listed below.');
        } else if (summarizedFindings.length > 0) {
            summaryLines.push('Issues found — see inline comments and summarized findings below.');
        } else {
            summaryLines.push('Issues found — see inline comments.');
        }
    } else if (result.verdict === 'approve') {
        if (options.usedApprovalFallback) {
            summaryLines.push(
                'Automated review completed with no blocking findings. GitHub rejected a formal approval for this PR identity, so this automated review was published as a comment instead.',
            );
        } else {
            summaryLines.push('Automated review complete.');
        }
    } else if (result.verdict === 'wait') {
        summaryLines.push('Automated review complete with no blocking findings; waiting for required checks.');
    }

    if (options.usedRequestChangesFallback) {
        summaryLines[0] =
            'Issues found — see inline comments. GitHub rejected a formal request-changes review for this PR identity, so this automated review was published as a comment instead.';
    }

    if (findings.length > 0 && options.inlineCommentsPublished === false) {
        summaryLines.push('');
        summaryLines.push(...findings.map((finding) => formatFindingSummary(finding)));
    } else {
        if (summarizedFindings.length > 0) {
            summaryLines.push('');
            summaryLines.push(
                'Outstanding findings in existing threads:',
            );
            summaryLines.push(...summarizedFindings.map((finding) => finding.existing_url ? `- [${findingLabel(finding)}] [Existing discussion](${finding.existing_url})` : `- [${findingLabel(finding)}] Existing finding ${findingId(finding)}`));
        }

        const summaryOnlyFindings = findings.filter((finding) => !isInlineFinding(finding) && !summarizedFindings.some((prior) => findingId(prior) === findingId(finding)));
        if (summaryOnlyFindings.length > 0) {
            summaryLines.push('', 'Findings without an inline anchor in the diff:');
            summaryLines.push(...summaryOnlyFindings.map((finding) => formatFindingSummary(finding)));
        }
    }

    if (result.checklist_url) summaryLines.push('', `[Required tests](${result.checklist_url})`);
    summaryLines.push(...buildLlmSection(result.llm));
    if (isCompletedLlmReview(result.llm) && result.llm.blocking) {
        summaryLines.push(AI_REVIEW_BLOCKING_MARKER);
    }
    if (result.publication_key) summaryLines.push('', `<!-- gfrm-review-run:${result.publication_key} -->`);
    summaryLines.push('', result.marker);
    return summaryLines.join('\n');
}

async function loadReviewResult() {
    const raw = await readFile(REVIEW_RESULT_PATH, 'utf8');
    return JSON.parse(raw);
}

export async function publishReviewResult(result, submitReview, options = {}) {
    if (result.verdict === 'request_changes') {
        try {
            await submitReview('REQUEST_CHANGES', buildReviewBody(result, options));
        } catch (error) {
            if (!isSelfReviewRequestChangesError(error)) {
                throw error;
            }

            await submitReview('COMMENT', buildReviewBody(result, {...options, usedRequestChangesFallback: true}));
        }
        return true;
    }

    if (result.verdict === 'approve') {
        try {
            await submitReview('APPROVE', buildReviewBody(result, options));
        } catch (error) {
            if (!isSelfReviewApproveError(error)) {
                throw error;
            }

            await submitReview('COMMENT', buildReviewBody(result, {...options, usedApprovalFallback: true}));
        }
        return true;
    }

    // A completed AI round must leave a review carrying its round marker, or review-pr.mjs would not count it.
    if (result.verdict === 'wait' && isCompletedLlmReview(result.llm)) {
        await submitReview('COMMENT', buildReviewBody(result, options));
        return true;
    }
    return false;
}

export async function publishResult(result, {
    repository = REPOSITORY, number = PR_NUMBER, botLogin = process.env.REVIEW_BOT_LOGIN,
    request = githubRequest, evidenceLoader = collectReviewEvidence,
} = {}) {
    if (result.verdict === 'skip') return;
    if (!botLogin) throw new Error('Verified review bot identity required');
    const head = result.head_sha;
    if (!head) throw new Error('Refusing to publish an analysis without a reviewed head');
    await assertReviewCurrent(repository, number, head, request);
    const write = guardedRequest(repository, number, head, request);
    const base = `/repos/${repository}/pulls/${number}`;
    const evidence = await evidenceLoader(repository, number, head, request);
    result.checklist_url = await updateChecklist({ repository, number, head, botLogin, llm: result.llm, evidence, request });
    const comments = (await paginate(`${base}/comments`, request)).filter((comment) => comment.user?.login === botLogin);
    const reviews = await paginate(`${base}/reviews`, request);
    if (result.publication_key && reviews.some((review) => review.user?.login === botLogin &&
        review.body?.includes(`<!-- gfrm-review-run:${result.publication_key} -->`))) return;
    const previousReviews = reviews.filter((review) =>
        review.user?.login === botLogin && review.body?.includes(result.marker) && ['CHANGES_REQUESTED', 'APPROVED'].includes(review.state));
    const findings = Array.isArray(result.findings) ? result.findings : [];
    const { unpublishedFindings, alreadyPublishedFindings } = partitionPublishedFindings(findings, comments, result.marker);
    let inlineCommentsPublished = true;
    for (const finding of unpublishedFindings.filter(isInlineFinding)) {
        try {
            await write(`${base}/comments`, { method: 'POST', body: JSON.stringify({
                body: formatInlineComment(finding, result.marker), commit_id: head,
                path: finding.path, line: finding.line, side: 'RIGHT',
            }) });
        } catch (error) {
            if (!isInlineCommentPermissionError(error)) throw error;
            inlineCommentsPublished = false;
            break;
        }
    }
    for (const assessment of result.llm?.prior_assessments || []) {
        const prior = result.prior_comments?.find((item) => item.finding_id === assessment.finding_id);
        if (!prior) continue;
        const threadComments = comments.filter((comment) => comment.id === prior.comment_id || comment.in_reply_to_id === prior.comment_id);
        const latest = threadComments.filter((comment) => findingMetadata(comment.body)).at(-1);
        const previous = findingMetadata(latest?.body) || { state: 'applicable', tier: prior.tier };
        const finding = findings.find((item) => findingId(item) === prior.finding_id);
        const tier = finding?.tier || prior.tier;
        if (previous.state === assessment.state && previous.tier === tier) continue;
        const state = { finding_id: prior.finding_id, tier, message: assessment.reason };
        await write(`${base}/comments/${prior.comment_id}/replies`, { method: 'POST', body: JSON.stringify({
            body: `${findingMarker(state, assessment.state)}\n${assessment.state}: ${assessment.reason}\n\nVerified against \`${head}\`.`,
        }) });
    }
    const published = await publishReviewResult(result, (event, body) => write(`${base}/reviews`, {
        method: 'POST', body: JSON.stringify({ event, body, commit_id: head }),
    }), { inlineCommentsPublished, summarizedFindings: alreadyPublishedFindings });
    // Replace the verdict before dismissing its predecessor; cancellation must not erase the only blocker.
    for (const review of published ? previousReviews : []) {
        try { await write(`${base}/reviews/${review.id}/dismissals`, { method: 'PUT', body: JSON.stringify({ message: 'Superseded by new automated review run.' }) }); }
        catch (error) { if (error instanceof ReviewStopped) throw error; console.warn(`Could not dismiss review ${review.id}`); }
    }
    if (result.consume_extra_round_label) {
        await write(`/repos/${repository}/issues/${number}/labels/ai-review`, { method: 'DELETE' });
    }
}

async function main() {
    assertRequiredEnv();
    try { await publishResult(await loadReviewResult()); }
    catch (error) { if (error instanceof ReviewStopped) console.log(error.message); else throw error; }
}

if (process.argv[1] && fileURLToPath(import.meta.url) == process.argv[1]) {
    main().catch((error) => {
        console.error(error);
        process.exit(1);
    });
}
