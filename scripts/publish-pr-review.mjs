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

function formatInlineComment(finding, marker) {
    const prefix = finding.severity === 'blocking' ? '[blocking]' : '[note]';
    return `${marker}\n${prefix} ${finding.message}`;
}

function formatFindingSummary(finding) {
    const severity = finding.severity === 'blocking' ? 'blocking' : 'note';
    const location = finding.path && finding.line ? ` (${finding.path}:${finding.line})` : '';
    return `- [${severity}] ${finding.message}${location}`;
}

function buildReviewBody(result, options = {}) {
    const summaryLines = [];
    const findings = Array.isArray(result.findings) ? result.findings : [];

    if (result.verdict === 'request_changes') {
        if (options.inlineCommentsPublished === false) {
            summaryLines.push('Issues found. Inline comments could not be published with this token, so the findings are listed below.');
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
    }

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

async function removePreviousInlineComments(owner, repo, marker) {
    const comments = await paginate(`/repos/${owner}/${repo}/pulls/${PR_NUMBER}/comments`);
    const deletableComments = comments.filter((comment) => String(comment.body || '').includes(marker));

    for (const comment of deletableComments) {
        await githubRequest(`/repos/${owner}/${repo}/pulls/comments/${comment.id}`, {
            method: 'DELETE',
        });
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

    try {
        await removePreviousInlineComments(owner, repo, result.marker);
    } catch (error) {
        if (!isInlineCommentPermissionError(error)) {
            throw error;
        }

        inlineCommentsPublished = false;
    }

    if (inlineCommentsPublished) {
        for (const finding of result.findings) {
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
        {inlineCommentsPublished},
    );
}

if (process.argv[1] && fileURLToPath(import.meta.url) == process.argv[1]) {
    main().catch((error) => {
        console.error(error);
        process.exit(1);
    });
}
