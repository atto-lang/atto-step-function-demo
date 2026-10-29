/**
 * Trusted GitHub Actions evidence adapter for the host-only demo.
 * The caller supplies run ID and SHA as a request, never as evidence.
 * Only independent API responses + configured tenant/repository policy
 * can authorize a memory write. This is not a signed GitHub attestation.
 */
const fail=(code)=>{throw new Error(code)};
const valid=(condition,code)=>{if(!condition)fail(code)};
const hexSha=/^[0-9a-f]{40}(?:[0-9a-f]{24})?$/;
const name=/^[A-Za-z0-9_.-]{1,100}$/;
const repoPattern=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const int=value=>Number.isSafeInteger(value)&&value>0;
const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);
const bounded=(s)=>typeof s==="string"&&s.length<=256&&s.length>0;
const jobSteps=job=>Array.isArray(job.steps)?job.steps:[];

/**
 * reader.readRun(repo, runId) and reader.readJobs(repo, runId, attempt)
 * must obtain data from a separately authenticated, read-only API.
 * tenantRepos maps tenant IDs to exact full owner/repo names.
 */
export function createGitHubEvidenceVerifier({
  reader, tenantRepos, workflowName='Source-free workflow demo checks',
  requiredStep='Run Node tests', maxJobs=100
}={}) {
  valid(reader&&typeof reader.readRun==='function'&&
    typeof reader.readJobs==='function','MISSING_TRUSTED_READER');
  valid(tenantRepos && typeof tenantRepos==='object' &&
    !Array.isArray(tenantRepos),'MISSING_TENANT_POLICY');
  valid(bounded(workflowName)&&bounded(requiredStep) &&
    int(maxJobs)&&maxJobs<=100,'BAD_VERIFIER_POLICY');
  const policy=new Map(Object.entries(tenantRepos));
  for (const [tenant,repo] of policy) {
    valid(name.test(tenant)&&repoPattern.test(repo),'BAD_TENANT_POLICY');
  }
  return async function evidenceVerifier(request) {
    if(!request||!name.test(request.tenantId||'')||
       !name.test(request.eventId||'')||!repoPattern.test(request.repo||'')||
       !hexSha.test(request.sourceSha||'')||
       !int(request.runId)||!int(request.runAttempt)) return null;
    const expectedRepo=policy.get(request.tenantId);
    if(!expectedRepo || request.repo!==expectedRepo) return null;
    let run,jobCollection;
    try {
      run=await reader.readRun(expectedRepo,request.runId);
      jobCollection=await reader.readJobs(expectedRepo,request.runId,
        request.runAttempt);
    } catch {
      return null;
    }
    if(!run||typeof run!=='object'||Array.isArray(run)||
       run.id!==request.runId || run.run_attempt!==request.runAttempt ||
       run.head_sha!==request.sourceSha ||
       run.name!==workflowName || run.status!=='completed' ||
       run.conclusion!=='success' ||
       !['push','pull_request','workflow_dispatch'].includes(run.event) ||
       run.repository?.full_name!==expectedRepo ||
       // Pull requests from a foreign fork require their own admission policy.
       (run.event==='pull_request' &&
        run.head_repository?.full_name!==expectedRepo)) return null;
    const jobs=Array.isArray(jobCollection)?jobCollection:
      jobCollection?.jobs;
    const total=Array.isArray(jobCollection)?jobCollection.length:
      jobCollection?.total_count;
    if(!Array.isArray(jobs)||!Number.isSafeInteger(total) ||
       total!==jobs.length || jobs.length<1 || jobs.length>maxJobs) return null;
    let executed=0,required=false,successfulJobs=0;
    for(const job of jobs) {
      if(!job||job.run_id!==request.runId ||
         job.run_attempt!==request.runAttempt) return null;
      if(job.status==='completed' && job.conclusion==='success')
        successfulJobs++;
      // Each job must have actual positive, successful steps. A queued or
      // skipped job never proves source-code execution.
      if(job.conclusion!=='success' || job.status!=='completed') return null;
      const steps=jobSteps(job);
      if(steps.length===0 || steps.length>100) return null;
      for (const step of steps) {
        if(!step||typeof step.name!=='string' ||
           step.status!=='completed') return null;
        if(step.conclusion==='success') {
          executed++;
          if(step.name===requiredStep) required=true;
        } else if(step.conclusion!=='skipped') {
          return null;
        }
      }
    }
    if(successfulJobs<1||!required||executed===0) return null;
    return Object.freeze({
      tenantId:request.tenantId,eventId:request.eventId,repo:expectedRepo,
      headSha:run.head_sha,conclusion:'success',executedSteps:executed,
      runId:request.runId,runAttempt:request.runAttempt,
      provenance:'github_rest_jobs'
    });
  };
}

/** Create a read-only GitHub REST reader. Token must have explicit read scope. */
export function createGitHubRestReader({token,fetchImpl=globalThis.fetch,apiBase='https://api.github.com'}={}) {
  valid(apiBase==='https://api.github.com','UNTRUSTED_API_ORIGIN');
  valid(typeof token==='string'&&token.length>10&&
    typeof fetchImpl==='function','MISSING_API_CREDENTIALS');
  const read=async path=>{
    const response=await fetchImpl(apiBase+path,{
      method:'GET',redirect:'error',
      headers:{
        Accept:'application/vnd.github+json',
        Authorization:'Bearer '+token,
        'X-GitHub-Api-Version':'2022-11-28'
      }
    });
    if(!response.ok)fail('GITHUB_API_ERROR');
    return response.json();
  };
  const pathFor=(repo,run,attempt)=>{
    valid(repoPattern.test(repo)&&int(run) &&
      (attempt===undefined||int(attempt)),'BAD_API_PATH');
    return '/repos/'+repo+'/actions/runs/'+run;
  };
  return Object.freeze({
    readRun:(repo,run)=>read(pathFor(repo,run)),
    readJobs:(repo,run,attempt)=>read(pathFor(repo,run,attempt)+
      '/attempts/'+attempt+'/jobs?per_page=100')
  });
}
