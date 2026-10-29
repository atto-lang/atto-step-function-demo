#!/usr/bin/env node
/**
 * Read-only GitHub Actions evidence check. Requires a read-scoped GITHUB_TOKEN.
 * This tool validates API metadata; it does not issue a signed attestation.
 * Tenant -> repository mapping comes from the operator CLI, never an agent payload.
 */
import {createGitHubEvidenceVerifier,createGitHubRestReader} from '../src/github-evidence.mjs';

const [tenantId,repo,runText,attemptText,sourceSha,eventId]=process.argv.slice(2);
if(!tenantId||!repo||!runText||!attemptText||!sourceSha||!eventId) {
  console.error('Usage: GITHUB_TOKEN=... GITHUB_WORKFLOW_ID=... node scripts/verify-github-run.mjs TENANT owner/repo RUN_ID ATTEMPT SHA EVENT_ID');
  process.exitCode=2;
} else {
  try {
    const reader=createGitHubRestReader({token:process.env.GITHUB_TOKEN});
    const verify=createGitHubEvidenceVerifier({
      reader,tenantRepos:{[tenantId]:repo},
      expectedWorkflowId:Number(process.env.GITHUB_WORKFLOW_ID),
      workflowName:'Source-free workflow demo checks',
      requiredStep:'Run Node tests'
    });
    const attested=await verify({tenantId,repo,
      runId:Number(runText),runAttempt:Number(attemptText),sourceSha,eventId});
    if(!attested) {
      console.error('UNVERIFIED: no matching successful, executed exact-head job');
      process.exitCode=1;
    } else {
      console.log(JSON.stringify({status:'VERIFIED_GITHUB_REST_METADATA',
        ...attested},null,2));
    }
  } catch (err) {
    // Never print token, response body or raw error containing secrets.
    console.error('UNVERIFIED: API reader or policy unavailable');
    process.exitCode=1;
  }
}
