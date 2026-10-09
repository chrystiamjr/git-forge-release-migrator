#!/usr/bin/env node

import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {
    assertRequiredEnv,
    githubRequest,
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
    const lines = [marker, `[${findingLabel(finding)}] ${finding.message}`];

    if (finding.symbol) {
        lines.push('', `Symbol: \`${finding.symbol}\``);
    }

    if (finding.why) {
        lines.push('', `Why: ${finding.why}`);
    }

    return lines.join('\n');
}

function inlineCommentSignature(path, line, body) {
    return `${path ?? ''}\0${line ?? ''}\0${body ?? ''}`;
}

export function filterAlreadyPublishedFindings(findings, comments, marker) {
    return partitionPublishedFindings(findings, comments, marker).unpublishedFindings;
}

function commentLabel(body) {
    return String(body).split('\n')[1]?.match(/^\[([a-z_]+)\]/)?.[1] ?? null;
}

// LLM wording changes between runs, so tiered findings match an existing comment by path + line + tier;
// deterministic findings keep exact-text matching.
function findingSignature(finding, marker) {
    const body = finding.tier ? `tier:${finding.tier}` : formatInlineComment(finding, marker);
    return inlineCommentSignature(finding.path, finding.line, body);
}

export function partitionPublishedFindings(findings, comments, marker) {
    const existingCommentSignatures = new Set();

    for (const comment of comments) {
        if (!String(comment.body || '').includes(marker)) {
            continue;
        }

        existingCommentSignatures.add(inlineCommentSignature(comment.path, comment.line, comment.body));
        const label = commentLabel(comment.body);
        if (label) {
            existingCommentSignatures.add(inlineCommentSignature(comment.path, comment.line, `tier:${label}`));
        }
    }

    const unpublishedFindings = [];
    const alreadyPublishedFindings = [];

    for (const finding of findings) {
        const isAlreadyPublished = existingCommentSignatures.has(findingSignature(finding, marker));

        if (isAlreadyPublished) {
            alreadyPublishedFindings.push(finding);
        } else {
            unpublishedFindings.push(finding);
        }
    }

    return {unpublishedFindings, alreadyPublishedFindings};
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

    // Secondary detail stays collapsed so the inline comments remain the main read.
    const testsNeeded = Array.isArray(llm.tests_needed) ? llm.tests_needed : [];
    lines.push(...buildDetails('Tests needed', testsNeeded.map((test) => `- ${test}`)));

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
                'These findings matched existing automated inline comments and are repeated here so the review is self-contained:',
            );
            summaryLines.push(...summarizedFindings.map((finding) => formatFindingSummary(finding)));
        }

        const summaryOnlyFindings = findings.filter((finding) => !isInlineFinding(finding));
        if (summaryOnlyFindings.length > 0) {
            summaryLines.push('', 'Findings without an inline anchor in the diff:');
            summaryLines.push(...summaryOnlyFindings.map((finding) => formatFindingSummary(finding)));
        }
    }

    summaryLines.push(...buildLlmSection(result.llm));
    summaryLines.push('', result.marker);
    return summaryLines.join('\n');
}

async function dismissPreviousReviews(owner, repo, marker) {
    const reviews = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews`);
    const dismissableReviews = reviews.filter(
        (review) =>
            String(review.body || '').includes(marker) &&
            (review.state === 'CHANGES_REQUESTED' || review.state === 'APPROVED'),
    );

    for (const review of dismissableReviews) {
        try {
            await githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews/${review.id}/dismissals`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    message: 'Superseded by new automated review run.',
                }),
            });
        } catch {
            // Best-effort: dismiss may fail if token lacks permission or review was already dismissed.
        }
    }
}

async function postInlineFinding(owner, repo, headSha, finding, marker) {
    await githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/comments`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            body: formatInlineComment(finding, marker),
            commit_id: headSha,
            path: finding.path,
            line: finding.line,
            side: 'RIGHT',
        }),
    });
}

async function submitReview(owner, repo, event, body) {
    await githubRequest(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/reviews`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            event,
            body,
        }),
    });
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
        return;
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
    }
}

async function main() {
    assertRequiredEnv();

    const result = await loadReviewResult();
    const {owner, repo} = parseRepository(REPOSITORY);
    let inlineCommentsPublished = true;

    await dismissPreviousReviews(owner, repo, result.marker);
    let existingComments = [];

    try {
        existingComments = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/comments`);
    } catch (error) {
        if (!isInlineCommentPermissionError(error)) {
            throw error;
        }

        inlineCommentsPublished = false;
    }

    const findings = Array.isArray(result.findings) ? result.findings : [];
    const {unpublishedFindings, alreadyPublishedFindings} = partitionPublishedFindings(
        findings.filter(isInlineFinding),
        existingComments,
        result.marker,
    );

    if (inlineCommentsPublished) {
        for (const finding of unpublishedFindings) {
            try {
                await postInlineFinding(owner, repo, result.head_sha, finding, result.marker);
            } catch (error) {
                if (!isInlineCommentPermissionError(error)) {
                    throw error;
                }

                inlineCommentsPublished = false;
                break;
            }
        }
    }

    await publishReviewResult(
        result,
        (event, body) => submitReview(owner, repo, event, body),
        {inlineCommentsPublished, summarizedFindings: alreadyPublishedFindings},
    );
}

if (process.argv[1] && fileURLToPath(import.meta.url) == process.argv[1]) {
    main().catch((error) => {
        console.error(error);
        process.exit(1);
    });
}
