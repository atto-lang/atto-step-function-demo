import test from 'node:test';
import assert from 'node:assert/strict';
import {createGitHubEvidenceVerifier,createGitHubRestReader} from '../src/github-evidence.mjs';

const request=()=>({tenantId:'tenant_a',eventId:'evt_1',
  repo:'ores-truffle-oreslang/oreslang-step-function-demo',
  sourceSha:'a'.repeat(40),runId:111,runAttempt:2});
const run=()=>({id:111,run_attempt:2,head_sha:'a'.repeat(40),
  name:'Source-free workflow demo checks',path:'.github/workflows/demo.yml',
  workflow_id:400176040,status:'completed',conclusion:'success',
  event:'push',repository:{full_name:'ores-truffle-oreslang/oreslang-step-function-demo'},
  head_repository:{full_name:'ores-truffle-oreslang/oreslang-step-function-demo'}});
const jobs=()=>({total_count:1,jobs:[{name:'node-contract',run_id:111,run_attempt:2,
  status:'completed',conclusion:'success',steps:[
    {name:'Set up job',status:'completed',conclusion:'success'},
    {name:'Run Node tests',status:'completed',conclusion:'success'},
    {name:'Complete job',status:'completed',conclusion:'success'}
  ]}]});
const make=(r=run(),j=jobs(), policy={tenant_a:request().repo})=>
  createGitHubEvidenceVerifier({reader:{
    readRun:async()=>r,readJobs:async()=>j
  },tenantRepos:policy});

test('reader-derived run and real executed test step grant scoped evidence',async()=>{
  const response=await make()(request());
  assert.equal(response.tenantId,'tenant_a');
  assert.equal(response.headSha,request().sourceSha);
  assert.equal(response.executedSteps,3);
  assert.equal(response.runId,111);
  assert.equal(response.runAttempt,2);
});
test('tenant binding rejects a repo outside its exact configured scope',async()=>{
  assert.equal(await make()( {...request(),repo:'attacker/repo'}),null);
  assert.equal(await make()( {...request(),tenantId:'other'}),null);
});
test('wrong HEAD SHA, workflow name, event, or run identity reject',async()=>{
  for(const bad of [
    {...run(),head_sha:'b'.repeat(40)},
    {...run(),name:'untrusted-other-workflow'},
    {...run(),path:'.github/workflows/attacker.yml'},
    {...run(),workflow_id:null},
    {...run(),event:'schedule'},
    {...run(),id:222},
    {...run(),run_attempt:1},
    {...run(),repository:{full_name:'attacker/repo'}},
    {...run(),status:'queued'}
  ]) assert.equal(await make(bad)(request()),null);
});
test('cross-repository pull request and failed run cannot establish evidence',async()=>{
  assert.equal(await make({...run(),event:'pull_request',
    head_repository:{full_name:'attacker/repo'}})(request()),null);
  assert.equal(await make({...run(),conclusion:'failure'})(request()),null);
});
test('zero-step jobs, skipped test step, pagination mismatch and wrong run attempt reject',async()=>{
  for(const invalid of [
    {total_count:1,jobs:[{...jobs().jobs[0],steps:null}]},
    {total_count:1,jobs:[{...jobs().jobs[0],steps:[]}]},
    {total_count:2,jobs:jobs().jobs},
    {total_count:1,jobs:[{...jobs().jobs[0],run_attempt:1}]},
    {total_count:1,jobs:[{...jobs().jobs[0],steps:jobs().jobs[0].steps.map(s=>
      s.name==='Run Node tests'?{...s,conclusion:'skipped'}:s)}]}
  ])assert.equal(await make(run(),invalid)(request()),null);
});
test('failed or unexecuted jobs cannot be laundered by successful neighboring jobs',async()=>{
  const j=jobs();
  j.jobs.push({...j.jobs[0],conclusion:'failure',steps:[]});
  j.total_count=2;
  assert.equal(await make(run(),j)(request()),null);
});
test('API reader failures return no evidence and no private credentials in errors',async()=>{
  const verify=createGitHubEvidenceVerifier({
    reader:{readRun:async()=>{throw Error('secret:123')},
      readJobs:async()=>jobs()},tenantRepos:{tenant_a:request().repo}
  });
  assert.equal(await verify(request()),null);
});
test('GitHub REST reader binds URL and token to a fixed HTTPS API origin',async()=>{
  const urls=[];
  const reader=createGitHubRestReader({token:'not-a-real-token-demo',fetchImpl:async (url,options)=>{
    urls.push({url,method:options.method,hasBearer:options.headers.Authorization.startsWith('Bearer ')});
    return {ok:true,json:async()=>({status:'completed'})};
  }});
  await reader.readRun(request().repo,111);
  await reader.readJobs(request().repo,111,2);
  assert.equal(urls.length,2);
  assert.match(urls[0].url,/^https:\/\/api\.github\.com\/repos\/ores-truffle-oreslang\/oreslang-step-function-demo\/actions\/runs\/111$/);
  assert.match(urls[1].url,/\/attempts\/2\/jobs\?per_page=100$/);
  assert.equal(urls[0].method,'GET');
  assert.equal(urls[0].hasBearer,true);
  assert.throws(()=>createGitHubRestReader({token:'not-a-real-token-demo',apiBase:'https://attacker.example'}),/UNTRUSTED_API_ORIGIN/);
});

test('a similarly named test step in another job cannot spoof required job',async()=>{
  const untrusted=jobs();
  untrusted.jobs[0].name='other-job';
  assert.equal(await make(run(),untrusted)(request()),null);
});
test('reject changed workflow path even with successful run and passing steps',async()=>{
  const mismatched={...run(),path:'.github/workflows/other.yml'};
  assert.equal(await make(mismatched)(request()),null);
});
